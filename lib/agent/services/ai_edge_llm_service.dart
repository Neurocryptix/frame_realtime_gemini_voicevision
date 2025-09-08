import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_genai/mediapipe_genai.dart';

/// AI Edge LLM Service for Gemma 3 compatibility
/// Replaces the existing local_llm_service with pure Google AI Edge implementation
/// Uses MediaPipe GenAI for all local LLM processing
class AIEdgeLLMService {
  final void Function(String)? _logger;
  bool _isReady = false;

  // AI Edge LLM configuration
  LlmInferenceEngine? _engine;
  String? _modelPath;
  bool _modelDownloadInProgress = false;

  // Model configuration - Gemma 3 compatible
  static const String _gemma3ModelName = 'gemma-3n-E2B-it-int4.bin';
  static const int _maxTokens = 2048;
  static const double _temperature = 0.7;

  AIEdgeLLMService({
    void Function(String)? logger,
  }) : _logger = logger;

  /// Initialize the AI Edge LLM service (Pure Google AI Edge - NO fallbacks)
  Future<bool> initialize({String? modelUrl}) async {
    try {
      _logger?.call('🤖 Initializing AI Edge LLM service (Gemma 3 compatible)...');

      if (!_isPlatformSupported()) {
        _logger?.call('❌ Platform not supported for AI Edge GenAI');
        return false;
      }

      // Setup model path
      final appDir = await getApplicationDocumentsDirectory();
      _modelPath = '${appDir.path}/$_gemma3ModelName';

      // Check if model exists or download it
      if (!await File(_modelPath!).exists()) {
        if (modelUrl != null) {
          final downloadSuccess = await _downloadModel(modelUrl);
          if (!downloadSuccess) {
            _logger?.call('❌ Gemma 3 model download failed');
            return false;
          }
        } else {
          _logger?.call('❌ Gemma 3 model not found and no download URL provided');
          return false;
        }
      }

      // Initialize AI Edge GenAI engine
      await _initializeAIEdgeEngine();

      if (_engine != null) {
        _isReady = true;
        _logger?.call('✅ AI Edge LLM service ready with Gemma 3');
        return true;
      } else {
        _logger?.call('❌ Failed to initialize AI Edge GenAI engine');
        return false;
      }

    } catch (e) {
      _logger?.call('❌ AI Edge LLM initialization failed: $e');
      _isReady = false;
      return false;
    }
  }

  /// Check if platform supports AI Edge GenAI
  bool _isPlatformSupported() {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Download Gemma 3 model for AI Edge processing
  Future<bool> _downloadModel(String modelUrl) async {
    if (_modelDownloadInProgress) {
      _logger?.call('⏳ Model download already in progress...');
      return false;
    }

    try {
      _modelDownloadInProgress = true;
      _logger?.call('📥 Downloading Gemma 3 model for AI Edge...');

      final response = await http.get(Uri.parse(modelUrl));
      
      if (response.statusCode == 200) {
        final file = File(_modelPath!);
        await file.writeAsBytes(response.bodyBytes);
        
        final fileSizeMB = (response.bodyBytes.length / (1024 * 1024)).toStringAsFixed(2);
        _logger?.call('✅ Gemma 3 model downloaded: ${fileSizeMB}MB');
        return true;
      } else {
        _logger?.call('❌ Download failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _logger?.call('❌ Model download error: $e');
      return false;
    } finally {
      _modelDownloadInProgress = false;
    }
  }

  /// Initialize AI Edge GenAI engine with Gemma 3
  Future<void> _initializeAIEdgeEngine() async {
    try {
      _logger?.call('🔧 Initializing AI Edge GenAI engine with Gemma 3...');

      // Configure AI Edge LLM options for Gemma 3
      final options = LlmInferenceOptions.cpu(
        modelPath: _modelPath!,
        maxTokens: _maxTokens,
        randomSeed: 42,
        // Gemma 3 specific configurations
        loraPath: null,
      );

      // Create the AI Edge inference engine
      _engine = LlmInferenceEngine(options);
      
      _logger?.call('✅ AI Edge GenAI engine initialized with Gemma 3');
      _logger?.call('🎯 Ready for on-device LLM processing');
      
    } catch (e) {
      _logger?.call('❌ AI Edge engine initialization failed: $e');
      _engine = null;
      rethrow;
    }
  }

  /// Process context with AI Edge GenAI (replaces old tool calling system)
  Future<AIEdgeLLMResponse> processWithAIEdge({
    required String context,
    String? systemPrompt,
    double temperature = 0.7,
  }) async {
    if (!_isReady || _engine == null) {
      throw Exception('AI Edge LLM service not ready');
    }

    final startTime = DateTime.now();

    try {
      _logger?.call('🧠 Processing with AI Edge Gemma 3: ${_truncate(context)}');

      // Build AI Edge optimized prompt
      final fullPrompt = _buildAIEdgePrompt(context, systemPrompt);

      // Generate response using AI Edge GenAI
      final responseStream = _engine!.generateResponse(fullPrompt);
      final response = await responseStream.join();

      final processingTime = DateTime.now().difference(startTime);
      
      _logger?.call('✅ AI Edge processing completed in ${processingTime.inMilliseconds}ms');

      return AIEdgeLLMResponse(
        content: response.trim(),
        processingTime: processingTime,
        metadata: {
          'model': 'gemma-3n-ai-edge',
          'contextLength': context.length,
          'temperature': temperature,
          'maxTokens': _maxTokens,
          'processingMode': 'on_device_ai_edge',
        },
      );

    } catch (e) {
      _logger?.call('❌ AI Edge processing failed: $e');
      throw Exception('AI Edge LLM processing failed: $e');
    }
  }

  /// Build optimized prompt for AI Edge Gemma 3
  String _buildAIEdgePrompt(String context, String? systemPrompt) {
    final defaultSystemPrompt = '''
You are an intelligent AI assistant running on Google AI Edge with Gemma 3. 
You help users with Frame smart glasses by processing their voice and visual inputs.
Be concise, helpful, and accurate in your responses.
''';

    final actualSystemPrompt = systemPrompt ?? defaultSystemPrompt;

    return '''$actualSystemPrompt

User Context: $context

Please provide a helpful response:''';
  }

  /// Generate a simple response using AI Edge
  Future<String?> generateResponse(String prompt) async {
    if (!_isReady) return null;

    try {
      final response = await processWithAIEdge(context: prompt);
      return response.content;
    } catch (e) {
      _logger?.call('❌ AI Edge response generation error: $e');
      return null;
    }
  }

  /// Get AI Edge LLM statistics
  Map<String, dynamic> getStatistics() {
    return {
      'isReady': _isReady,
      'modelPath': _modelPath,
      'modelDownloading': _modelDownloadInProgress,
      'modelName': _gemma3ModelName,
      'maxTokens': _maxTokens,
      'temperature': _temperature,
      'platform': Platform.operatingSystem,
      'aiEdgeEnabled': true,
      'gemma3Compatible': true,
      'processingMode': 'on_device_ai_edge',
      'backendType': 'mediapipe_genai',
    };
  }

  /// Get model status
  Future<Map<String, dynamic>> getModelStatus() async {
    try {
      final modelExists = _modelPath != null && await File(_modelPath!).exists();
      
      return {
        'modelInstalled': modelExists,
        'modelPath': _modelPath,
        'modelName': _gemma3ModelName,
        'downloadInProgress': _modelDownloadInProgress,
        'aiEdgeInitialized': _engine != null,
        'platform': Platform.operatingSystem,
        'gemma3Ready': _isReady,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'modelInstalled': false,
        'downloadInProgress': _modelDownloadInProgress,
      };
    }
  }

  /// Check if ready
  bool get isReady => _isReady;

  /// Check if model download is in progress
  bool get isModelDownloadInProgress => _modelDownloadInProgress;

  /// Truncate text for logging
  String _truncate(String text, {int maxLength = 100}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// Dispose resources
  void dispose() {
    _engine?.close();
    _engine = null;
    _isReady = false;
    _logger?.call('🧹 AI Edge LLM service disposed');
  }
}

/// AI Edge LLM Response model
class AIEdgeLLMResponse {
  final String content;
  final Duration processingTime;
  final Map<String, dynamic> metadata;

  AIEdgeLLMResponse({
    required this.content,
    required this.processingTime,
    required this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'content': content,
    'processingTimeMs': processingTime.inMilliseconds,
    'metadata': metadata,
  };

  @override
  String toString() => 'AIEdgeLLMResponse(${content.length} chars, ${processingTime.inMilliseconds}ms)';
}