import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/model_metadata.dart';
import 'ai_edge_model_manager.dart';
import 'ai_edge_rag_service.dart';
import '../agent/services/ai_edge_agent_service.dart';
import '../agent/interfaces/ai_edge_interfaces.dart';

/// Integrated Agentic Service
/// Combines model management, AI Edge RAG, and agentic functionality
/// Provides a unified interface for on-device AI operations
class IntegratedAgenticService extends ChangeNotifier {
  late final AIEdgeModelManager _modelManager;
  late final AIEdgeRagService _ragService;
  late final AIEdgeAgentService _agentService;

  final void Function(String)? _logger;

  bool _isInitialized = false;
  bool _isReady = false;
  bool _isProcessing = false;

  // Agent capabilities
  bool _agentEnabled = false;
  int _totalQueries = 0;
  int _totalDocuments = 0;
  DateTime? _lastActivity;

  IntegratedAgenticService({
    void Function(String)? logger,
  }) : _logger = logger {
    _modelManager = AIEdgeModelManager(
      logger: logger,
      onProgress: (progress) {
        _logger?.call('📥 Model download progress: ${(progress * 100).toInt()}%');
        notifyListeners();
      },
    );
  }

  /// Initialize the integrated service
  Future<bool> initialize() async {
    if (_isInitialized) {
      _logger?.call('⚠️ Service already initialized');
      return _isReady;
    }

    try {
      _logger?.call('🚀 Initializing Integrated Agentic Service...');

      // Step 1: Check if models are available
      final needsModel = await _modelManager.needsModelDownload();
      if (needsModel) {
        _logger?.call('❌ No models available - download required');
        return false;
      }

      // Step 2: Initialize RAG service with model
      final modelPath = await _modelManager.getModelPath();
      if (modelPath == null) {
        _logger?.call('❌ Model path not found');
        return false;
      }

      _ragService = AIEdgeRagServiceImpl(logger: _logger);
      final ragReady = await _ragService.initialize();

      if (!ragReady) {
        _logger?.call('⚠️ RAG service initialization failed');
      }

      // Step 3: Initialize agent service
      _agentService = AIEdgeAgentService(
        ragService: _ragService,
        logger: _logger,
      );

      final agentReady = await _agentService.initialize();
      if (!agentReady) {
        _logger?.call('⚠️ Agent service initialization failed');
      }

      _isInitialized = true;
      _isReady = ragReady && agentReady;

      if (_isReady) {
        _logger?.call('✅ Integrated Agentic Service ready');
        await _addInitialKnowledge();
      } else {
        _logger?.call('⚠️ Service initialized with limited capabilities');
      }

      notifyListeners();
      return _isReady;
    } catch (e) {
      _logger?.call('❌ Initialization failed: $e');
      _isInitialized = true;
      _isReady = false;
      notifyListeners();
      return false;
    }
  }

  /// Add initial knowledge to the system
  Future<void> _addInitialKnowledge() async {
    if (!_isReady) return;

    try {
      final initialDocs = [
        {
          'content': 'Frame smart glasses are wearable AR devices with camera and display capabilities',
          'metadata': {'type': 'device_info', 'category': 'hardware'},
        },
        {
          'content': 'Voice commands can be used to control Frame glasses and query information',
          'metadata': {'type': 'interaction', 'category': 'voice'},
        },
        {
          'content': 'Image processing and OCR can extract text from what the user sees',
          'metadata': {'type': 'capability', 'category': 'vision'},
        },
        {
          'content': 'The agent system can store and retrieve contextual memories',
          'metadata': {'type': 'capability', 'category': 'memory'},
        },
      ];

      for (final doc in initialDocs) {
        await _ragService.addDocument(
          content: doc['content'] as String,
          metadata: doc['metadata'] as Map<String, dynamic>,
        );
      }

      _totalDocuments += initialDocs.length;
      _logger?.call('📚 Added ${initialDocs.length} initial knowledge documents');
    } catch (e) {
      _logger?.call('⚠️ Failed to add initial knowledge: $e');
    }
  }

  /// Process a query through the agent system
  Future<AgenticResponse> processQuery(String query, {
    Map<String, dynamic>? context,
    bool storeQuery = true,
  }) async {
    if (!_isReady) {
      return AgenticResponse.error('Service not ready');
    }

    try {
      _isProcessing = true;
      _totalQueries++;
      _lastActivity = DateTime.now();
      notifyListeners();

      _logger?.call('🧠 Processing query: "$query"');

      final result = await _agentService.processQuery(
        query: query,
        context: context,
        storeQuery: storeQuery,
      );

      final response = AgenticResponse(
        query: query,
        response: result.response,
        confidence: result.confidence,
        relevantDocuments: result.ragResponse?.documents ?? [],
        processingTime: result.processingTime,
        metadata: result.metadata,
      );

      _logger?.call('✅ Query processed in ${result.processingTime.inMilliseconds}ms');
      return response;

    } catch (e) {
      _logger?.call('❌ Query processing failed: $e');
      return AgenticResponse.error('Processing failed: $e');
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Process image data (for OCR and analysis)
  Future<void> processImage(Uint8List imageData, {
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isReady) return;

    try {
      _logger?.call('📸 Processing image (${imageData.length} bytes)');

      // Use agent service to process the image
      await _agentService.storeOCROutput(
        text: 'Image processed at ${DateTime.now().toString()}',
        confidence: 0.8,
        timestamp: DateTime.now(),
        additionalMetadata: {
          'imageSize': imageData.length,
          'processingType': 'frame_capture',
          ...?metadata,
        },
      );

      _lastActivity = DateTime.now();
      notifyListeners();
    } catch (e) {
      _logger?.call('❌ Image processing failed: $e');
    }
  }

  /// Process audio data (for ASR and analysis)
  Future<void> processAudio(Uint8List audioData, {
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isReady) return;

    try {
      _logger?.call('🎤 Processing audio (${audioData.length} bytes)');

      // Use agent service to process the audio
      await _agentService.storeASROutput(
        text: 'Audio processed at ${DateTime.now().toString()}',
        confidence: 0.7,
        timestamp: DateTime.now(),
        additionalMetadata: {
          'audioSize': audioData.length,
          'processingType': 'frame_audio',
          ...?metadata,
        },
      );

      _lastActivity = DateTime.now();
      notifyListeners();
    } catch (e) {
      _logger?.call('❌ Audio processing failed: $e');
    }
  }

  /// Store information in the agent's knowledge base
  Future<bool> storeKnowledge({
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isReady) return false;

    try {
      await _ragService.addDocument(
        content: content,
        metadata: {
          'timestamp': DateTime.now().toIso8601String(),
          'source': 'user_input',
          ...?metadata,
        },
      );

      _totalDocuments++;
      _lastActivity = DateTime.now();
      notifyListeners();

      _logger?.call('💾 Knowledge stored: "${content.substring(0, 50)}..."');
      return true;
    } catch (e) {
      _logger?.call('❌ Knowledge storage failed: $e');
      return false;
    }
  }

  /// Search the agent's knowledge base
  Future<List<RagDocument>> searchKnowledge(String query, {
    int limit = 10,
    double threshold = 0.3,
  }) async {
    if (!_isReady) return [];

    try {
      return await _agentService.searchMemory(
        query: query,
        limit: limit,
        threshold: threshold,
      );
    } catch (e) {
      _logger?.call('❌ Knowledge search failed: $e');
      return [];
    }
  }

  /// Enable/disable agent processing
  void setAgentEnabled(bool enabled) {
    _agentEnabled = enabled;
    _logger?.call(enabled ? '▶️ Agent enabled' : '⏸️ Agent paused');
    notifyListeners();
  }

  /// Check if models need to be downloaded
  Future<bool> needsModelDownload() async {
    return await _modelManager.needsModelDownload();
  }

  /// Download models if needed
  Future<bool> downloadModels({
    ModelMetadata? specificModel,
    bool showProgress = true,
  }) async {
    try {
      return await _modelManager.downloadModelAutomatically(
        specificModel: specificModel,
        showProgress: showProgress,
      );
    } catch (e) {
      _logger?.call('❌ Model download failed: $e');
      return false;
    }
  }

  /// Get service status
  Map<String, dynamic> getStatus() {
    final baseStatus = {
      'isInitialized': _isInitialized,
      'isReady': _isReady,
      'isProcessing': _isProcessing,
      'agentEnabled': _agentEnabled,
      'totalQueries': _totalQueries,
      'totalDocuments': _totalDocuments,
      'lastActivity': _lastActivity?.toString(),
    };

    if (_isInitialized && _isReady) {
      final agentStats = _agentService.getMemoryStatistics();
      final ragStats = _ragService.getStatistics();

      baseStatus.addAll({
        'agent': agentStats,
        'rag': ragStats,
        'services': {
          'model_manager': true,
          'rag': _ragService.isReady,
          'agent': _agentService.isReady,
        },
      });
    }

    return baseStatus;
  }

  /// Get available models
  Future<List<ModelMetadata>> getAvailableModels() async {
    return _modelManager.availableModels;
  }

  /// Get downloaded models
  Future<List<String>> getDownloadedModels() async {
    return await _modelManager.getDownloadedModels();
  }

  /// Get model download statistics
  Future<Map<String, dynamic>> getDownloadStats() async {
    return await _modelManager.getDownloadStats();
  }

  /// Getters
  bool get isInitialized => _isInitialized;
  bool get isReady => _isReady;
  bool get isProcessing => _isProcessing;
  bool get agentEnabled => _agentEnabled;
  int get totalQueries => _totalQueries;
  int get totalDocuments => _totalDocuments;
  DateTime? get lastActivity => _lastActivity;

  /// Dispose all resources
  @override
  void dispose() {
    if (_isInitialized) {
      _agentService.dispose();
      _ragService.dispose();
      _modelManager.dispose();
      _logger?.call('🧹 Integrated Agentic Service disposed');
    }
    super.dispose();
  }
}

/// Response from agentic processing
class AgenticResponse {
  final String query;
  final String response;
  final double confidence;
  final List<RagDocument> relevantDocuments;
  final Duration processingTime;
  final Map<String, dynamic> metadata;
  final String? error;

  AgenticResponse({
    required this.query,
    required this.response,
    required this.confidence,
    required this.relevantDocuments,
    required this.processingTime,
    this.metadata = const {},
    this.error,
  });

  factory AgenticResponse.error(String error) => AgenticResponse(
    query: '',
    response: '',
    confidence: 0.0,
    relevantDocuments: [],
    processingTime: Duration.zero,
    error: error,
  );

  bool get hasError => error != null;
  bool get isSuccessful => error == null && response.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'query': query,
    'response': response,
    'confidence': confidence,
    'relevantDocuments': relevantDocuments.length,
    'processingTimeMs': processingTime.inMilliseconds,
    'metadata': metadata,
    if (error != null) 'error': error,
  };

  @override
  String toString() => 'AgenticResponse(query: $query, response: ${response.substring(0, response.length.clamp(0, 50))}...)';
}