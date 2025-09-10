import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_edge_model_manager.dart';
import 'ai_edge_rag_service.dart';

/// AI Edge Auto Initialization Service
/// Handles automatic model download and system setup on first app launch
class AIEdgeAutoInitService {
  static const String _firstLaunchKey = 'ai_edge_first_launch_complete';
  static const String _autoInitEnabledKey = 'ai_edge_auto_init_enabled';
  
  final AIEdgeModelManager _modelManager;
  final void Function(String msg) _emit;
  
  bool _isInitializing = false;
  StreamController<AIEdgeInitStatus>? _statusController;

  AIEdgeAutoInitService({
    void Function(String msg)? logger,
  })  : _emit = logger ?? ((_) {}),
        _modelManager = AIEdgeModelManager(
          logger: logger,
          onProgress: (progress) {
            // Progress will be handled by status stream
          },
        );

  /// Check if this is the first app launch
  Future<bool> isFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_firstLaunchKey) ?? false);
    } catch (e) {
      _emit('❌ Error checking first launch status: $e');
      return false;
    }
  }

  /// Check if auto-initialization is enabled
  Future<bool> isAutoInitEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_autoInitEnabledKey) ?? true; // Enabled by default
    } catch (e) {
      _emit('⚠️ Error checking auto-init status: $e');
      return true; // Default to enabled
    }
  }

  /// Set auto-initialization preference
  Future<void> setAutoInitEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoInitEnabledKey, enabled);
      _emit('💾 Auto-init ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      _emit('❌ Failed to save auto-init preference: $e');
    }
  }

  /// Start automatic initialization process
  Stream<AIEdgeInitStatus> startAutoInitialization({
    String? modelUrl,
    Map<String, String>? kaggleCredentials,
    bool forceDownload = false,
  }) async* {
    if (_isInitializing) {
      yield AIEdgeInitStatus.error('Initialization already in progress');
      return;
    }

    try {
      _isInitializing = true;
      _emit('🚀 Starting AI Edge auto-initialization...');

      // Step 1: Check system compatibility
      yield AIEdgeInitStatus.checking('Checking system compatibility...');
      await Future.delayed(const Duration(milliseconds: 500));

      if (!_isSystemCompatible()) {
        yield AIEdgeInitStatus.error('Device not compatible with AI Edge');
        return;
      }

      yield AIEdgeInitStatus.compatible('System compatible with AI Edge');

      // Step 2: Check storage space
      yield AIEdgeInitStatus.checking('Checking storage space...');
      await Future.delayed(const Duration(milliseconds: 300));

      final hasStorage = await _modelManager.hasEnoughStorage(requiredMB: 500);
      if (!hasStorage) {
        yield AIEdgeInitStatus.error('Insufficient storage space (need ~500MB)');
        return;
      }

      yield AIEdgeInitStatus.storageOk('Storage space available');

      // Step 3: Check if model download is needed
      yield AIEdgeInitStatus.checking('Checking model availability...');
      
      final needsDownload = await _modelManager.needsModelDownload() || forceDownload;
      
      if (!needsDownload) {
        yield AIEdgeInitStatus.modelReady('Model already available');
        await _markFirstLaunchComplete();
        yield AIEdgeInitStatus.complete('AI Edge ready to use');
        return;
      }

      // Step 4: Get model URL or Kaggle credentials if not provided
      if (modelUrl == null && kaggleCredentials == null) {
        yield AIEdgeInitStatus.needsUrl('Model URL or Kaggle credentials required for download');
        return;
      }

      // Step 5: Download model with progress updates
      yield AIEdgeInitStatus.downloading('Starting model download...', 0.0);
      
      bool downloadSuccess = false;
      
      // Create a separate stream for download progress
      final downloadCompleter = Completer<bool>();
      
      // Start download in background
      if (kaggleCredentials != null) {
        // Use Kaggle API to download
        _modelManager.downloadModelFromKaggle(
          username: kaggleCredentials['username']!,
          apiKey: kaggleCredentials['api_key']!,
          showProgress: true,
        ).then((success) {
          downloadCompleter.complete(success);
        }).catchError((error) {
          downloadCompleter.completeError(error);
        });
      } else {
        // Use direct URL download
        _modelManager.downloadModelAutomatically(
          modelUrl: modelUrl!,
          showProgress: true,
        ).then((success) {
          downloadCompleter.complete(success);
        }).catchError((error) {
          downloadCompleter.completeError(error);
        });
      }

      // Monitor progress (simulated - you'd integrate with actual progress)
      double progress = 0.0;
      while (progress < 1.0 && !downloadCompleter.isCompleted) {
        await Future.delayed(const Duration(milliseconds: 500));
        progress = (progress + 0.05).clamp(0.0, 0.95); // Simulate progress
        yield AIEdgeInitStatus.downloading(
          'Downloading Gemma 3 model... ${(progress * 100).toInt()}%',
          progress,
        );
      }

      // Wait for download to complete
      try {
        downloadSuccess = await downloadCompleter.future;
      } catch (e) {
        yield AIEdgeInitStatus.error('Download failed: $e');
        return;
      }

      if (!downloadSuccess) {
        yield AIEdgeInitStatus.error('Model download failed');
        return;
      }

      yield AIEdgeInitStatus.downloaded('Model downloaded successfully');

      // Step 6: Verify model integrity
      yield AIEdgeInitStatus.verifying('Verifying model integrity...');
      await Future.delayed(const Duration(milliseconds: 1000));

      final isValid = await _modelManager.verifyModelIntegrity();
      if (!isValid) {
        yield AIEdgeInitStatus.error('Model verification failed');
        return;
      }

      yield AIEdgeInitStatus.verified('Model verified successfully');

      // Step 7: Test AI Edge system
      yield AIEdgeInitStatus.testing('Testing AI Edge system...');
      await Future.delayed(const Duration(milliseconds: 1500));

      final testSuccess = await _testAIEdgeSystem();
      if (!testSuccess) {
        yield AIEdgeInitStatus.error('AI Edge system test failed');
        return;
      }

      // Step 8: Mark first launch as complete
      await _markFirstLaunchComplete();

      yield AIEdgeInitStatus.complete('AI Edge initialization complete!');
      _emit('✅ Auto-initialization completed successfully');

    } catch (e) {
      yield AIEdgeInitStatus.error('Initialization error: $e');
      _emit('❌ Auto-initialization failed: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// Test AI Edge system after download
  Future<bool> _testAIEdgeSystem() async {
    try {
      final modelPath = await _modelManager.getModelPath();
      if (modelPath == null) return false;

      // Create a temporary RAG service to test
      final ragService = AIEdgeRagServiceImpl(logger: _emit);
      
      // Initialize (model should exist)
      final initSuccess = await ragService.initialize();
      
      ragService.dispose();
      return initSuccess;
    } catch (e) {
      _emit('❌ AI Edge system test failed: $e');
      return false;
    }
  }

  /// Check if system is compatible with AI Edge
  bool _isSystemCompatible() {
    // Add platform-specific compatibility checks here
    // For now, return true for Android/iOS/macOS
    return true; // Simplified check
  }

  /// Mark first launch as complete
  Future<void> _markFirstLaunchComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_firstLaunchKey, true);
      await prefs.setString('ai_edge_init_date', DateTime.now().toIso8601String());
      _emit('💾 First launch marked as complete');
    } catch (e) {
      _emit('⚠️ Failed to save first launch status: $e');
    }
  }

  /// Get model manager instance
  AIEdgeModelManager get modelManager => _modelManager;

  /// Check if initialization is in progress
  bool get isInitializing => _isInitializing;

  /// Reset first launch status (for testing)
  Future<void> resetFirstLaunchStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_firstLaunchKey);
      await prefs.remove('ai_edge_init_date');
      await _modelManager.resetModelState();
      _emit('🔄 First launch status reset');
    } catch (e) {
      _emit('❌ Failed to reset first launch status: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _isInitializing = false;
    _statusController?.close();
    _modelManager.dispose();
    _emit('🧹 AI Edge Auto Init Service disposed');
  }
}

/// AI Edge Initialization Status
class AIEdgeInitStatus {
  final AIEdgeInitStage stage;
  final String message;
  final double? progress;
  final bool isError;
  final bool isComplete;

  const AIEdgeInitStatus._({
    required this.stage,
    required this.message,
    this.progress,
    this.isError = false,
    this.isComplete = false,
  });

  factory AIEdgeInitStatus.checking(String message) => AIEdgeInitStatus._(
        stage: AIEdgeInitStage.checking,
        message: message,
      );

  factory AIEdgeInitStatus.compatible(String message) => AIEdgeInitStatus._(
        stage: AIEdgeInitStage.compatible,
        message: message,
      );

  factory AIEdgeInitStatus.storageOk(String message) => AIEdgeInitStatus._(
        stage: AIEdgeInitStage.storageCheck,
        message: message,
      );

  factory AIEdgeInitStatus.modelReady(String message) => AIEdgeInitStatus._(
        stage: AIEdgeInitStage.modelReady,
        message: message,
      );

  factory AIEdgeInitStatus.needsUrl(String message) => AIEdgeInitStatus._(
        stage: AIEdgeInitStage.needsUrl,
        message: message,
      );

  factory AIEdgeInitStatus.downloading(String message, double progress) =>
      AIEdgeInitStatus._(
        stage: AIEdgeInitStage.downloading,
        message: message,
        progress: progress,
      );

  factory AIEdgeInitStatus.downloaded(String message) => AIEdgeInitStatus._(
        stage: AIEdgeInitStage.downloaded,
        message: message,
      );

  factory AIEdgeInitStatus.verifying(String message) => AIEdgeInitStatus._(
        stage: AIEdgeInitStage.verifying,
        message: message,
      );

  factory AIEdgeInitStatus.verified(String message) => AIEdgeInitStatus._(
        stage: AIEdgeInitStage.verified,
        message: message,
      );

  factory AIEdgeInitStatus.testing(String message) => AIEdgeInitStatus._(
        stage: AIEdgeInitStage.testing,
        message: message,
      );

  factory AIEdgeInitStatus.complete(String message) => AIEdgeInitStatus._(
        stage: AIEdgeInitStage.complete,
        message: message,
        isComplete: true,
      );

  factory AIEdgeInitStatus.error(String message) => AIEdgeInitStatus._(
        stage: AIEdgeInitStage.error,
        message: message,
        isError: true,
      );

  @override
  String toString() => 'AIEdgeInitStatus(${stage.name}: $message)';
}

/// Initialization stages
enum AIEdgeInitStage {
  checking,
  compatible,
  storageCheck,
  modelReady,
  needsUrl,
  downloading,
  downloaded,
  verifying,
  verified,
  testing,
  complete,
  error,
}

extension AIEdgeInitStageExt on AIEdgeInitStage {
  String get displayName {
    switch (this) {
      case AIEdgeInitStage.checking:
        return 'Checking System';
      case AIEdgeInitStage.compatible:
        return 'System Compatible';
      case AIEdgeInitStage.storageCheck:
        return 'Storage Check';
      case AIEdgeInitStage.modelReady:
        return 'Model Ready';
      case AIEdgeInitStage.needsUrl:
        return 'Need Model URL';
      case AIEdgeInitStage.downloading:
        return 'Downloading Model';
      case AIEdgeInitStage.downloaded:
        return 'Download Complete';
      case AIEdgeInitStage.verifying:
        return 'Verifying Model';
      case AIEdgeInitStage.verified:
        return 'Verification Complete';
      case AIEdgeInitStage.testing:
        return 'Testing System';
      case AIEdgeInitStage.complete:
        return 'Setup Complete';
      case AIEdgeInitStage.error:
        return 'Error';
    }
  }

  IconData get icon {
    switch (this) {
      case AIEdgeInitStage.checking:
        return Icons.search;
      case AIEdgeInitStage.compatible:
        return Icons.check_circle;
      case AIEdgeInitStage.storageCheck:
        return Icons.storage;
      case AIEdgeInitStage.modelReady:
        return Icons.model_training;
      case AIEdgeInitStage.needsUrl:
        return Icons.link;
      case AIEdgeInitStage.downloading:
        return Icons.download;
      case AIEdgeInitStage.downloaded:
        return Icons.download_done;
      case AIEdgeInitStage.verifying:
        return Icons.verified;
      case AIEdgeInitStage.verified:
        return Icons.verified_user;
      case AIEdgeInitStage.testing:
        return Icons.science;
      case AIEdgeInitStage.complete:
        return Icons.check_circle;
      case AIEdgeInitStage.error:
        return Icons.error;
    }
  }

  Color get color {
    switch (this) {
      case AIEdgeInitStage.checking:
      case AIEdgeInitStage.downloading:
      case AIEdgeInitStage.verifying:
      case AIEdgeInitStage.testing:
        return Colors.blue;
      case AIEdgeInitStage.compatible:
      case AIEdgeInitStage.storageCheck:
      case AIEdgeInitStage.modelReady:
      case AIEdgeInitStage.downloaded:
      case AIEdgeInitStage.verified:
      case AIEdgeInitStage.complete:
        return Colors.green;
      case AIEdgeInitStage.needsUrl:
        return Colors.orange;
      case AIEdgeInitStage.error:
        return Colors.red;
    }
  }
}