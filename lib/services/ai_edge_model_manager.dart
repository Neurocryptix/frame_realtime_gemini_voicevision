import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:crypto/crypto.dart';
import '../models/model_metadata.dart';
import 'model_download_service.dart';
import 'huggingface_auth_service.dart';

/// AI Edge Model Manager - Consolidated model management using modern services
/// Integrates with Google AI Edge Gallery patterns for model download and validation
class AIEdgeModelManager {
  static const String _modelDownloadedKey = 'ai_edge_model_downloaded';
  static const String _modelVersionKey = 'ai_edge_model_version';
  static const String _currentModelVersion = '2.0.0'; // Updated for consolidated system
  static const String _gemmaModelName = 'gemma-2b-it-q4_0.gguf'; // Legacy compatibility
  static const String _modelChecksumKey = 'ai_edge_model_checksum'; // Legacy compatibility
  
  final void Function(String msg) _emit;
  final void Function(double progress) _onProgress;
  
  late final ModelDownloadService _downloadService;
  late final HuggingFaceAuthService _authService;
  
  bool _isDownloading = false;
  String? _modelPath;

  AIEdgeModelManager({
    void Function(String msg)? logger,
    void Function(double progress)? onProgress,
  })  : _emit = logger ?? ((_) {}),
        _onProgress = onProgress ?? ((_) {}) {
    _authService = HuggingFaceAuthService(logger: logger);
    _downloadService = ModelDownloadService(authService: _authService, logger: logger);
  }

  /// Check if model needs to be downloaded on app startup
  Future<bool> needsModelDownload() async {
    try {
      // Check if we have any models downloaded using the new system
      final downloadedModels = await _downloadService.getDownloadedModels();
      
      if (downloadedModels.isEmpty) {
        _emit('🔍 No AI Edge models found - download needed');
        return true;
      }
      
      // Check if we have a recommended model
      final defaultModel = ModelAllowlist.getDefaultModel();
      if (defaultModel != null) {
        final hasDefaultModel = downloadedModels.contains(defaultModel.modelId);
        if (!hasDefaultModel) {
          _emit('🔍 Recommended model not found - download needed');
          return true;
        }
        
        // Verify model integrity
        final isValid = await _downloadService.verifyModelIntegrity(defaultModel.modelId);
        if (!isValid) {
          _emit('🔍 Model integrity check failed - redownload needed');
          return true;
        }
        
        _modelPath = await _downloadService.getModelPath(defaultModel.modelId);
        _emit('✅ AI Edge model ready: ${defaultModel.displayName}');
        return false;
      }
      
      _emit('✅ ${downloadedModels.length} AI Edge model(s) available');
      return false;
    } catch (e) {
      _emit('❌ Error checking model status: $e');
      return true; // Safe fallback - attempt download
    }
  }

  /// Download model automatically with progress tracking
  Future<bool> downloadModelAutomatically({
    ModelMetadata? specificModel,
    bool showProgress = true,
  }) async {
    if (_isDownloading) {
      _emit('⏳ Model download already in progress...');
      return false;
    }

    try {
      _isDownloading = true;
      
      // Get the model to download (specific or default)
      final modelToDownload = specificModel ?? ModelAllowlist.getDefaultModel();
      if (modelToDownload == null) {
        _emit('❌ No model available for download');
        return false;
      }
      
      _emit('🚀 Starting ${modelToDownload.displayName} download...');
      
      // Check authentication if model requires it
      if (modelToDownload.requiresAuth) {
        final isAuthenticated = await _authService.isAuthenticated();
        if (!isAuthenticated) {
          _emit('❌ Authentication required for ${modelToDownload.displayName}');
          _emit('💡 Please authenticate with HuggingFace first');
          return false;
        }
      }

      // Setup progress tracking
      StreamSubscription<ModelDownloadProgress>? progressSubscription;
      if (showProgress) {
        progressSubscription = _downloadService
          .getDownloadProgress(modelToDownload.modelId)
          .listen((progress) {
            _onProgress(progress.progress);
            if (progress.progress > 0) {
              final percent = (progress.progress * 100).toStringAsFixed(1);
              _emit('📥 Downloading: $percent%');
            }
          });
      }

      try {
        // Download using the consolidated service
        final success = await _downloadService.downloadModel(modelToDownload);
        
        if (success) {
          _modelPath = await _downloadService.getModelPath(modelToDownload.modelId);
          
          // Mark as downloaded in legacy system
          await _markModelAsDownloaded();
          
          _emit('✅ Model download completed successfully!');
          _emit('📁 Model ready: ${modelToDownload.displayName}');
          return true;
        } else {
          _emit('❌ Model download failed');
          return false;
        }
      } finally {
        await progressSubscription?.cancel();
      }

    } catch (e) {
      _emit('❌ Automatic download error: $e');
      return false;
    } finally {
      _isDownloading = false;
    }
  }

  /// Download model from Kaggle using API credentials
  Future<bool> downloadModelFromKaggle({
    required String username,
    required String apiKey,
    bool showProgress = true,
  }) async {
    if (_isDownloading) {
      _emit('⏳ Model download already in progress...');
      return false;
    }

    try {
      _isDownloading = true;
      _emit('🔑 Starting Kaggle API authentication...');
      
      // Validate credentials
      if (username.isEmpty || apiKey.isEmpty) {
        _emit('❌ Invalid Kaggle credentials provided');
        return false;
      }

      // Create model directory if needed
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${appDir.path}/ai_edge_models');
      await modelDir.create(recursive: true);
      
      _modelPath = '${modelDir.path}/$_gemmaModelName';
      final tempPath = '$_modelPath.tmp';

      _emit('🔍 Finding Gemma 3 model on Kaggle...');

      // Get model download URL from Kaggle API
      final downloadUrl = await _getKaggleModelUrl(username, apiKey);
      if (downloadUrl == null) {
        _emit('❌ Could not get model download URL from Kaggle');
        _emit('💡 Please check your credentials and model access');
        return false;
      }

      _emit('📥 Downloading from Kaggle: ${_truncateUrl(downloadUrl)}');
      _emit('💾 Saving to: $_modelPath');

      // Download with Kaggle authentication
      final success = await _downloadFromKaggleWithAuth(
        downloadUrl,
        tempPath,
        username,
        apiKey,
      );
      
      if (success) {
        // Move from temp to final location
        final tempFile = File(tempPath);
        await tempFile.rename(_modelPath!);
        
        // Mark as downloaded and save version
        await _markModelAsDownloaded();
        
        _emit('✅ Kaggle model download completed successfully!');
        _emit('📁 Model ready at: $_modelPath');
        return true;
      } else {
        _emit('❌ Kaggle model download failed');
        return false;
      }

    } catch (e) {
      _emit('❌ Kaggle download error: $e');
      return false;
    } finally {
      _isDownloading = false;
    }
  }

  /// Get Kaggle model download URL using API
  Future<String?> _getKaggleModelUrl(String username, String apiKey) async {
    try {
      // Kaggle API endpoint for model details
      const modelOwner = 'google';
      const modelName = 'gemma-3';
      const framework = 'gguf';
      const variation = 'gemma-3n-2b-it-int4';
      
      const apiUrl = 'https://www.kaggle.com/api/v1/models/$modelOwner/$modelName/$framework/$variation';
      
      // Create basic auth header
      final credentials = base64Encode(utf8.encode('$username:$apiKey'));
      final headers = {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      };

      _emit('🌐 Calling Kaggle API: $apiUrl');
      
      final response = await http.get(Uri.parse(apiUrl), headers: headers);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        // Look for download URL in response
        if (data.containsKey('files')) {
          final files = data['files'] as List<dynamic>;
          for (final file in files) {
            if (file is Map<String, dynamic> && 
                file['name'] == _gemmaModelName) {
              final downloadUrl = file['downloadUrl'] as String?;
              if (downloadUrl != null) {
                _emit('✅ Found model download URL');
                return downloadUrl;
              }
            }
          }
        }
        
        _emit('❌ Model file not found in Kaggle response');
        _emit('💡 Available files: ${data.keys.join(', ')}');
        return null;
        
      } else if (response.statusCode == 401) {
        _emit('❌ Kaggle authentication failed - check username and API key');
        return null;
      } else if (response.statusCode == 403) {
        _emit('❌ Access denied - you may need to accept the model terms on Kaggle');
        return null;
      } else {
        _emit('❌ Kaggle API error: ${response.statusCode}');
        _emit('   Response: ${response.body}');
        return null;
      }
    } catch (e) {
      _emit('❌ Failed to get Kaggle model URL: $e');
      return null;
    }
  }

  /// Download from Kaggle with authentication
  Future<bool> _downloadFromKaggleWithAuth(
    String url,
    String savePath,
    String username,
    String apiKey,
  ) async {
    try {
      // Create auth header
      final credentials = base64Encode(utf8.encode('$username:$apiKey'));
      final headers = {
        'Authorization': 'Basic $credentials',
        'User-Agent': 'Frame-AI-Edge/1.0',
      };

      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(headers);
      
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        _emit('❌ Download failed: HTTP ${response.statusCode}');
        if (response.statusCode == 401) {
          _emit('🔑 Authentication failed - check your credentials');
        } else if (response.statusCode == 403) {
          _emit('🚫 Access denied - accept model terms on Kaggle first');
        }
        return false;
      }

      final contentLength = response.contentLength ?? 0;
      final file = File(savePath);
      final sink = file.openWrite();
      
      int downloadedBytes = 0;
      
      _emit('📊 Model size: ${_formatBytes(contentLength)}');

      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          
          if (contentLength > 0) {
            final progress = downloadedBytes / contentLength;
            _onProgress(progress);
            
            if (downloadedBytes % (1024 * 1024 * 10) == 0) { // Every 10MB
              final progressPercent = (progress * 100).toStringAsFixed(1);
              final downloaded = _formatBytes(downloadedBytes);
              final total = _formatBytes(contentLength);
              _emit('📥 Progress: $progressPercent% ($downloaded / $total)');
            }
          }
        },
        onDone: () async {
          await sink.close();
          _onProgress(1.0);
          _emit('✅ Kaggle download completed: ${_formatBytes(downloadedBytes)}');
        },
        onError: (error) async {
          await sink.close();
          _emit('❌ Download stream error: $error');
        },
      ).asFuture();

      return true;
    } catch (e) {
      _emit('❌ Kaggle download error: $e');
      return false;
    }
  }


  /// Mark model as successfully downloaded
  Future<void> _markModelAsDownloaded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_modelDownloadedKey, true);
      await prefs.setString(_modelVersionKey, _currentModelVersion);
      await prefs.setString('ai_edge_model_path', _modelPath!);
      
      // Calculate and store checksum for integrity checking
      if (_modelPath != null) {
        final checksum = await _calculateFileChecksum(_modelPath!);
        await prefs.setString(_modelChecksumKey, checksum);
      }
      
      _emit('💾 Model status saved to preferences');
    } catch (e) {
      _emit('⚠️ Failed to save model status: $e');
    }
  }

  /// Calculate file checksum for integrity verification
  Future<String> _calculateFileChecksum(String filePath) async {
    try {
      final file = File(filePath);
      final stream = file.openRead();
      final hash = await sha256.bind(stream).first;
      return hash.toString();
    } catch (e) {
      _emit('❌ Error calculating checksum: $e');
      return 'unknown';
    }
  }

  /// Verify model integrity
  Future<bool> verifyModelIntegrity() async {
    try {
      if (_modelPath == null) return false;
      
      final file = File(_modelPath!);
      if (!await file.exists()) return false;
      
      final prefs = await SharedPreferences.getInstance();
      final storedChecksum = prefs.getString(_modelChecksumKey);
      
      if (storedChecksum == null) return true; // No checksum stored, assume OK
      
      final currentChecksum = await _calculateFileChecksum(_modelPath!);
      final isValid = currentChecksum == storedChecksum;
      
      if (!isValid) {
        _emit('⚠️ Model integrity check failed - may need redownload');
      }
      
      return isValid;
    } catch (e) {
      _emit('❌ Model integrity check error: $e');
      return false;
    }
  }

  /// Get model path if downloaded
  Future<String?> getModelPath() async {
    if (_modelPath != null) return _modelPath;
    
    final prefs = await SharedPreferences.getInstance();
    _modelPath = prefs.getString('ai_edge_model_path');
    return _modelPath;
  }

  /// Check available storage space
  Future<bool> hasEnoughStorage({int requiredMB = 500}) async {
    try {
      final freeSpace = await DiskSpacePlus().getFreeDiskSpace;
      if (freeSpace == null) {
        _emit('⚠️ Could not determine free disk space. Assuming enough space.');
        return true; // Fail open
      }
      
      final freeMB = freeSpace;
      _emit('📱 Available storage: ${freeMB.toStringAsFixed(2)} MB');
      
      return freeMB >= requiredMB;
    } catch (e) {
      _emit('⚠️ Could not check storage: $e');
      return true; // Assume we have space if we can't check
    }
  }

  /// Clean up old model versions
  Future<void> cleanupOldModels() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${appDir.path}/ai_edge_models');
      
      if (!await modelDir.exists()) return;
      
      await for (final entity in modelDir.list()) {
        if (entity is File) {
          final fileName = entity.path.split('/').last;
          // Keep current model, remove others
          if (fileName != _gemmaModelName && fileName.endsWith('.bin')) {
            await entity.delete();
            _emit('🗑️ Removed old model: $fileName');
          }
        }
      }
    } catch (e) {
      _emit('⚠️ Cleanup error: $e');
    }
  }

  /// Save model URL to preferences for future use
  Future<void> saveModelUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_edge_model_url', url);
      _emit('💾 Model URL saved for automatic download');
    } catch (e) {
      _emit('❌ Failed to save model URL: $e');
    }
  }

  /// Reset model download state (for testing/debugging)
  Future<void> resetModelState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_modelDownloadedKey);
      await prefs.remove(_modelVersionKey);
      await prefs.remove(_modelChecksumKey);
      await prefs.remove('ai_edge_model_path');
      
      if (_modelPath != null) {
        final file = File(_modelPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      
      _emit('🔄 Model state reset - will download on next launch');
    } catch (e) {
      _emit('❌ Failed to reset model state: $e');
    }
  }

  /// Format bytes for display
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Truncate URL for display
  String _truncateUrl(String url) {
    if (url.length <= 60) return url;
    return '${url.substring(0, 30)}...${url.substring(url.length - 20)}';
  }

  /// Get download status
  bool get isDownloading => _isDownloading;

  /// Get current model version
  String get currentModelVersion => _currentModelVersion;

  /// Get the downloaded model path for use by AI Edge
  String? get modelPath => _modelPath;

  /// Get available models
  List<ModelMetadata> get availableModels => ModelAllowlist.allowedModels;

  /// Get downloaded models list
  Future<List<String>> getDownloadedModels() async {
    return await _downloadService.getDownloadedModels();
  }

  /// Get download statistics
  Future<Map<String, dynamic>> getDownloadStats() async {
    return await _downloadService.getDownloadStats();
  }

  /// Dispose resources
  void dispose() {
    _downloadService.dispose();
    _authService.dispose();
    _isDownloading = false;
    _emit('🧹 AI Edge Model Manager disposed');
  }
}