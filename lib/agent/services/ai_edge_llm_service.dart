import 'dart:async';
import 'dart:io';
import 'package:mediapipe_genai/mediapipe_genai.dart';
import '../interfaces/ai_edge_interfaces.dart';

/// AI Edge LLM Service using MediaPipe GenAI
/// Implements proper Google AI Edge patterns for on-device LLM inference
class AIEdgeLLMServiceImpl implements AIEdgeLLMService {
  LlmInferenceEngine? _llmEngine;
  bool _isInitialized = false;
  final void Function(String)? _logger;

  AIEdgeLLMServiceImpl({void Function(String)? logger}) : _logger = logger;

  /// Initialize the AI Edge LLM service with MediaPipe GenAI
  @override
  Future<bool> initialize({
    required String modelPath,
    int maxTokens = 512,
    double temperature = 0.8,
    double topP = 0.95,
    int topK = 20,
    int randomSeed = 0,
  }) async {
    try {
      _logger?.call('🚀 Initializing AI Edge LLM with MediaPipe GenAI...');

      // Verify model file exists
      final modelFile = File(modelPath);
      if (!await modelFile.exists()) {
        _logger?.call('❌ Model file not found: $modelPath');
        return false;
      }

      // Create LLM inference options following MediaPipe GenAI patterns
      final options = LlmInferenceOptions.cpu(
        modelPath: modelPath,
        cacheDir: '/tmp/mediapipe_cache', // Temporary directory for MediaPipe cache
        maxTokens: maxTokens,
        temperature: temperature,
        topK: topK,
        randomSeed: randomSeed,
      );

      // Initialize the LLM inference engine
      _llmEngine = LlmInferenceEngine(options);
      
      if (_llmEngine != null) {
        _isInitialized = true;
        _logger?.call('✅ AI Edge LLM initialized successfully');
        return true;
      } else {
        _logger?.call('❌ Failed to create LLM inference engine');
        return false;
      }
    } catch (e) {
      _logger?.call('❌ AI Edge LLM initialization failed: $e');
      return false;
    }
  }

  /// Generate streaming response using MediaPipe GenAI
  @override
  Stream<String> generateResponseStream(String prompt) async* {
    if (!_isInitialized || _llmEngine == null) {
      _logger?.call('⚠️ AI Edge LLM not initialized');
      return;
    }

    try {
      _logger?.call('🌊 Starting streaming response...');
      
      await for (final token in _llmEngine!.generateResponse(prompt)) {
        if (token.isNotEmpty) {
          yield token;
        }
      }
    } catch (e) {
      _logger?.call('❌ Streaming response failed: $e');
    }
  }

  /// Generate complete response by collecting stream
  @override
  Future<String?> generateResponse(String prompt, {List<String>? stopSequences}) async {
    if (!_isInitialized || _llmEngine == null) {
      _logger?.call('⚠️ AI Edge LLM not initialized');
      return null;
    }

    try {
      _logger?.call('🧠 Generating response with AI Edge LLM...');
      
      final responseBuffer = StringBuffer();
      await for (final token in _llmEngine!.generateResponse(prompt)) {
        responseBuffer.write(token);
        
        // Check for stop sequences
        if (stopSequences != null) {
          final currentResponse = responseBuffer.toString();
          for (final stopSeq in stopSequences) {
            if (currentResponse.contains(stopSeq)) {
              final stopIndex = currentResponse.indexOf(stopSeq);
              final finalResponse = currentResponse.substring(0, stopIndex);
              _logger?.call('✅ Response generated with stop sequence');
              return finalResponse;
            }
          }
        }
      }
      
      final response = responseBuffer.toString();
      if (response.isNotEmpty) {
        _logger?.call('✅ Response generated successfully');
        return response;
      } else {
        _logger?.call('⚠️ Empty response from LLM');
        return null;
      }
    } catch (e) {
      _logger?.call('❌ Response generation failed: $e');
      return null;
    }
  }

  /// Check if the service is ready
  @override
  bool get isReady => _isInitialized && _llmEngine != null;

  /// Get service statistics
  @override
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isReady': isReady,
      'backend': 'mediapipe_genai',
      'version': '1.0.0',
    };
  }

  /// Dispose resources
  @override
  void dispose() {
    try {
      // MediaPipe GenAI engines are automatically disposed
      _llmEngine = null;
      _isInitialized = false;
      _logger?.call('🧹 AI Edge LLM service disposed');
    } catch (e) {
      _logger?.call('⚠️ Error disposing LLM service: $e');
    }
  }
}