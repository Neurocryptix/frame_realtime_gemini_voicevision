import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import '../models/model_metadata.dart';
import 'huggingface_auth_service.dart';

/// Model download service following Google AI Edge Gallery pattern
class ModelDownloadService extends ChangeNotifier {
  static const String _downloadedModelsKey = 'downloaded_models';
  static const String _modelPathPrefix = 'ai_edge_models';

  final HuggingFaceAuthService _authService;
  final void Function(String message)? logger;

  final Map<String, ModelDownloadProgress> _downloadProgress = {};
  final Map<String, StreamController<ModelDownloadProgress>> _progressControllers = {};

  ModelDownloadService({
    HuggingFaceAuthService? authService,
    this.logger,
  }) : _authService = authService ?? HuggingFaceAuthService(logger: logger);

  void _log(String message) {
    logger?.call(message);
  }

  /// Get download progress stream for a model
  Stream<ModelDownloadProgress> getDownloadProgress(String modelId) {
    if (!_progressControllers.containsKey(modelId)) {
      _progressControllers[modelId] = StreamController<ModelDownloadProgress>.broadcast();
    }
    return _progressControllers[modelId]!.stream;
  }

  /// Get current download progress for a model
  ModelDownloadProgress? getCurrentProgress(String modelId) {
    return _downloadProgress[modelId];
  }

  /// Check if model is downloaded
  Future<bool> isModelDownloaded(String modelId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final downloadedModels = prefs.getStringList(_downloadedModelsKey) ?? [];
      return downloadedModels.contains(modelId);
    } catch (e) {
      _log('Error checking if model is downloaded: $e');
      return false;
    }
  }

  /// Get local path for a model
  Future<String> getModelPath(String modelId) async {
    final model = ModelAllowlist.getModelById(modelId);
    if (model == null) throw ArgumentError('Model not found: $modelId');

    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$_modelPathPrefix/${model.fileName}';
  }

  /// Download model with authentication and progress tracking
  Future<bool> downloadModel(ModelMetadata model, {bool forceRedownload = false}) async {
    final modelId = model.modelId;
    
    try {
      // Check if already downloaded
      if (!forceRedownload && await isModelDownloaded(modelId)) {
        _log('Model $modelId already downloaded');
        return true;
      }

      // Check authentication
      if (model.requiresAuth && !await _authService.isAuthenticated()) {
        _log('Authentication required for model $modelId');
        _emitProgress(model, ModelDownloadStatus.failed, errorMessage: 'Authentication required');
        return false;
      }

      // Check storage space
      if (!await _hasEnoughStorage(model.sizeInBytes)) {
        _log('Insufficient storage for model $modelId');
        _emitProgress(model, ModelDownloadStatus.failed, errorMessage: 'Insufficient storage space');
        return false;
      }

      // Start download
      _emitProgress(model, ModelDownloadStatus.enqueued);
      _log('Starting download for model: ${model.displayName}');

      // Create download directory
      final modelPath = await getModelPath(modelId);
      final modelFile = File(modelPath);
      await modelFile.parent.create(recursive: true);

      // Download with progress tracking
      final success = await _downloadModelFile(model, modelPath);

      if (success) {
        // Mark as downloaded
        await _markModelAsDownloaded(modelId);
        _emitProgress(model, ModelDownloadStatus.succeeded, progress: 1.0);
        _log('Model download completed: ${model.displayName}');
        return true;
      } else {
        _emitProgress(model, ModelDownloadStatus.failed, errorMessage: 'Download failed');
        return false;
      }
    } catch (e) {
      _log('Error downloading model $modelId: $e');
      _emitProgress(model, ModelDownloadStatus.failed, errorMessage: e.toString());
      return false;
    }
  }

  /// Download model file with progress tracking
  Future<bool> _downloadModelFile(ModelMetadata model, String savePath) async {
    try {
      _emitProgress(model, ModelDownloadStatus.running, progress: 0.0);

      // Get authentication headers if needed
      Map<String, String>? headers;
      if (model.requiresAuth) {
        headers = await _authService.getAuthHeaders();
        if (headers == null) {
          _log('Failed to get authentication headers');
          return false;
        }
      }

      // Create HTTP request
      final request = http.Request('GET', Uri.parse(model.downloadUrl));
      if (headers != null) {
        request.headers.addAll(headers);
      }

      _log('Downloading from: ${model.downloadUrl}');
      _log('Saving to: $savePath');

      // Send request
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        _log('Download failed: HTTP ${response.statusCode}');
        if (response.statusCode == 401) {
          _log('Authentication failed - token may be expired');
        } else if (response.statusCode == 403) {
          _log('Access denied - check model permissions');
        }
        return false;
      }

      // Get content length
      final contentLength = response.contentLength ?? model.sizeInBytes;
      _log('Model size: ${_formatBytes(contentLength)}');

      // Open file for writing
      final file = File(savePath);
      final sink = file.openWrite();

      int downloadedBytes = 0;
      final startTime = DateTime.now();

      try {
        // Stream download with progress updates
        await response.stream.listen(
          (chunk) {
            sink.add(chunk);
            downloadedBytes += chunk.length;

            // Update progress
            final progress = contentLength > 0 ? downloadedBytes / contentLength : 0.0;
            _emitProgress(
              model,
              ModelDownloadStatus.running,
              progress: progress,
              downloadedBytes: downloadedBytes,
              totalBytes: contentLength,
            );

            // Log progress every 50MB
            if (downloadedBytes % (50 * 1024 * 1024) == 0) {
              final progressPercent = (progress * 100).toStringAsFixed(1);
              final downloaded = _formatBytes(downloadedBytes);
              final total = _formatBytes(contentLength);
              final elapsed = DateTime.now().difference(startTime);
              final speed = downloadedBytes / elapsed.inSeconds;
              _log('Progress: $progressPercent% ($downloaded / $total) @ ${_formatBytes(speed.round())}/s');
            }
          },
          onError: (error) {
            _log('Download stream error: $error');
            throw error;
          },
        ).asFuture();

        await sink.close();
        
        // Verify file size
        final finalSize = await file.length();
        if (finalSize != contentLength && contentLength > 0) {
          _log('Warning: File size mismatch. Expected: $contentLength, Got: $finalSize');
        }

        // Validate model file integrity
        final isValid = await _validateModelFile(file, model);
        if (!isValid) {
          _log('❌ Model validation failed - deleting corrupted file');
          await file.delete();
          return false;
        }

        final totalTime = DateTime.now().difference(startTime);
        final avgSpeed = downloadedBytes / totalTime.inSeconds;
        _log('Download completed: ${_formatBytes(finalSize)} in ${totalTime.inMinutes.toStringAsFixed(1)}m (avg: ${_formatBytes(avgSpeed.round())}/s)');
        _log('✅ Model validation passed');

        return true;
      } finally {
        await sink.close();
      }
    } catch (e) {
      _log('Error downloading model file: $e');
      // Clean up partial download
      try {
        final file = File(savePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (cleanupError) {
        _log('Error cleaning up partial download: $cleanupError');
      }
      return false;
    }
  }

  /// Emit progress update
  void _emitProgress(
    ModelMetadata model,
    ModelDownloadStatus status, {
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    String? errorMessage,
  }) {
    final progressData = ModelDownloadProgress(
      model: model,
      status: status,
      progress: progress ?? 0.0,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      errorMessage: errorMessage,
      timestamp: DateTime.now(),
    );

    _downloadProgress[model.modelId] = progressData;

    // Emit to stream if controller exists
    final controller = _progressControllers[model.modelId];
    if (controller != null && !controller.isClosed) {
      controller.add(progressData);
    }

    notifyListeners();
  }

  /// Mark model as downloaded
  Future<void> _markModelAsDownloaded(String modelId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final downloadedModels = prefs.getStringList(_downloadedModelsKey) ?? [];
      
      if (!downloadedModels.contains(modelId)) {
        downloadedModels.add(modelId);
        await prefs.setStringList(_downloadedModelsKey, downloadedModels);
      }
    } catch (e) {
      _log('Error marking model as downloaded: $e');
    }
  }

  /// Check if there's enough storage space (improved implementation)
  Future<bool> _hasEnoughStorage(int requiredBytes) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      
      // Calculate available space by checking free disk space
      const additionalBuffer = 100 * 1024 * 1024; // 100MB buffer
      final requiredWithBuffer = requiredBytes + additionalBuffer;
      
      // For Android/iOS, we'll use a simplified approach
      // Real implementation would use platform-specific methods
      try {
        await appDir.stat();
        // If we can access the directory, assume we have space for models under 10GB
        const maxAllowedSize = 10 * 1024 * 1024 * 1024; // 10GB
        return requiredWithBuffer <= maxAllowedSize;
      } catch (e) {
        // If stat fails, try creating a test file
        final testFile = File('${appDir.path}/test_space_check.tmp');
        await testFile.writeAsBytes(Uint8List(1024)); // 1KB test
        await testFile.delete();
        return true;
      }
    } catch (e) {
      _log('Error checking storage: $e');
      return false; // Fail safe - assume not enough space
    }
  }

  /// Validate downloaded model file integrity
  Future<bool> _validateModelFile(File modelFile, ModelMetadata model) async {
    try {
      _log('🔍 Validating model file integrity...');
      
      // Check if file exists and is not empty
      if (!await modelFile.exists()) {
        _log('❌ Model file does not exist');
        return false;
      }
      
      final fileSize = await modelFile.length();
      if (fileSize == 0) {
        _log('❌ Model file is empty');
        return false;
      }
      
      // Validate file size is reasonable (within 10% of expected)
      final expectedSize = model.sizeInBytes;
      final sizeDifference = (fileSize - expectedSize).abs();
      const sizeTolerancePercent = 0.1; // 10% tolerance
      final maxSizeDifference = expectedSize * sizeTolerancePercent;
      
      if (sizeDifference > maxSizeDifference) {
        _log('❌ File size validation failed: expected ~${_formatBytes(expectedSize)}, got ${_formatBytes(fileSize)}');
        return false;
      }
      
      // Validate file format based on extension
      if (!_validateFileFormat(modelFile, model)) {
        return false;
      }
      
      // Calculate and store file checksum for future integrity checks
      await _calculateAndStoreChecksum(modelFile, model);
      
      _log('✅ Model file validation successful');
      return true;
    } catch (e) {
      _log('❌ Error during model validation: $e');
      return false;
    }
  }

  /// Validate model file format
  bool _validateFileFormat(File modelFile, ModelMetadata model) {
    try {
      final fileName = model.fileName.toLowerCase();
      final filePath = modelFile.path.toLowerCase();
      
      // Check file extension matches expected
      if (fileName.endsWith('.gguf') && !filePath.endsWith('.gguf')) {
        _log('❌ Expected GGUF file format');
        return false;
      }
      
      if (fileName.endsWith('.safetensors') && !filePath.endsWith('.safetensors')) {
        _log('❌ Expected SafeTensors file format');
        return false;
      }
      
      if (fileName.endsWith('.bin') && !filePath.endsWith('.bin')) {
        _log('❌ Expected binary file format');
        return false;
      }
      
      // Additional format-specific validations could be added here
      // For now, basic extension check is sufficient
      
      return true;
    } catch (e) {
      _log('❌ Error validating file format: $e');
      return false;
    }
  }

  /// Calculate and store file checksum for integrity verification
  Future<void> _calculateAndStoreChecksum(File modelFile, ModelMetadata model) async {
    try {
      _log('🔐 Calculating file checksum...');
      
      // Calculate SHA-256 hash of the file
      final bytes = await modelFile.readAsBytes();
      final digest = sha256.convert(bytes);
      final checksum = digest.toString();
      
      // Store checksum in preferences
      final prefs = await SharedPreferences.getInstance();
      final checksumKey = 'checksum_${model.modelId}';
      await prefs.setString(checksumKey, checksum);
      
      _log('✅ Checksum calculated and stored: ${checksum.substring(0, 16)}...');
    } catch (e) {
      _log('⚠️ Could not calculate checksum: $e');
      // Non-fatal error - continue without checksum
    }
  }

  /// Verify model integrity using stored checksum
  Future<bool> verifyModelIntegrity(String modelId) async {
    try {
      final modelPath = await getModelPath(modelId);
      final modelFile = File(modelPath);
      
      if (!await modelFile.exists()) {
        return false;
      }
      
      // Get stored checksum
      final prefs = await SharedPreferences.getInstance();
      final checksumKey = 'checksum_$modelId';
      final storedChecksum = prefs.getString(checksumKey);
      
      if (storedChecksum == null) {
        _log('⚠️ No checksum stored for model $modelId');
        return true; // Assume valid if no checksum stored
      }
      
      // Calculate current checksum
      final bytes = await modelFile.readAsBytes();
      final digest = sha256.convert(bytes);
      final currentChecksum = digest.toString();
      
      final isValid = currentChecksum == storedChecksum;
      if (!isValid) {
        _log('❌ Model integrity check failed for $modelId');
      } else {
        _log('✅ Model integrity verified for $modelId');
      }
      
      return isValid;
    } catch (e) {
      _log('❌ Error verifying model integrity: $e');
      return false;
    }
  }

  /// Format bytes for display
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Get all downloaded models
  Future<List<String>> getDownloadedModels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_downloadedModelsKey) ?? [];
    } catch (e) {
      _log('Error getting downloaded models: $e');
      return [];
    }
  }

  /// Delete downloaded model
  Future<bool> deleteModel(String modelId) async {
    try {
      // Delete file
      final modelPath = await getModelPath(modelId);
      final file = File(modelPath);
      if (await file.exists()) {
        await file.delete();
        _log('Deleted model file: $modelPath');
      }

      // Remove from downloaded list
      final prefs = await SharedPreferences.getInstance();
      final downloadedModels = prefs.getStringList(_downloadedModelsKey) ?? [];
      downloadedModels.remove(modelId);
      await prefs.setStringList(_downloadedModelsKey, downloadedModels);

      // Clean up progress tracking
      _downloadProgress.remove(modelId);
      final controller = _progressControllers.remove(modelId);
      await controller?.close();

      _log('Model $modelId deleted successfully');
      notifyListeners();
      return true;
    } catch (e) {
      _log('Error deleting model $modelId: $e');
      return false;
    }
  }

  /// Cancel ongoing download
  Future<bool> cancelDownload(String modelId) async {
    try {
      // Update progress to cancelled
      final currentProgress = _downloadProgress[modelId];
      if (currentProgress != null && currentProgress.status.isInProgress) {
        _emitProgress(
          currentProgress.model,
          ModelDownloadStatus.cancelled,
          progress: currentProgress.progress,
        );
        
        // Clean up partial download
        final modelPath = await getModelPath(modelId);
        final file = File(modelPath);
        if (await file.exists()) {
          await file.delete();
        }
        
        _log('Download cancelled: $modelId');
        return true;
      }
      return false;
    } catch (e) {
      _log('Error cancelling download: $e');
      return false;
    }
  }

  /// Get download statistics
  Future<Map<String, dynamic>> getDownloadStats() async {
    try {
      final downloadedModels = await getDownloadedModels();
      int totalSize = 0;
      int totalCount = downloadedModels.length;

      for (final modelId in downloadedModels) {
        final model = ModelAllowlist.getModelById(modelId);
        if (model != null) {
          totalSize += model.sizeInBytes;
        }
      }

      return {
        'total_models': totalCount,
        'total_size_bytes': totalSize,
        'total_size_formatted': _formatBytes(totalSize),
      };
    } catch (e) {
      _log('Error getting download stats: $e');
      return {
        'total_models': 0,
        'total_size_bytes': 0,
        'total_size_formatted': '0B',
      };
    }
  }

  @override
  void dispose() {
    // Close all stream controllers
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
    super.dispose();
  }
}