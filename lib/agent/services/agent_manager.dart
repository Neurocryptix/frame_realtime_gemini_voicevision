import 'dart:async';
import 'dart:typed_data';
import 'asr_service.dart';
import 'local_llm_service.dart';
import 'ocr_service.dart';
import '../models/agent_output.dart';
import '../../services/vector_db_service.dart';
import '../../objectbox.g.dart';

/// Agent Manager - Coordinates all agent services and provides unified interface
/// CRITICAL: This is agent-only and NEVER affects the main Gemini pipeline
/// Orchestrates ASR, LLM, and OCR services for autonomous processing
class AgentManager {
  final void Function(String)? _logger;
  bool _isReady = false;
  bool _isEnabled = false;

  // Agent services
  late ASRService _asrService;
  late LocalLLMService _llmService;
  late OCRService _ocrService;
  VectorDbService? _vectorDbService;

  // Agent processing state
  bool _isProcessing = false;
  final List<String> _availableTools = [
    'store_memory',
    'retrieve_memory',
    'analyze_content',
    'update_memory',
  ];

  // Agent outputs stream
  final StreamController<AgentProcessingResult> _agentOutputController =
      StreamController<AgentProcessingResult>.broadcast();

  Stream<AgentProcessingResult> get agentOutput =>
      _agentOutputController.stream;

  AgentManager({void Function(String)? logger, Store? store}) : _logger = logger {
    // Initialize vector database service if store is provided
    if (store != null) {
      _vectorDbService = VectorDbService((message) => _logger?.call(message));
      _vectorDbService!.initialize(store).catchError((e) {
        _logger?.call('⚠️ Vector DB initialization failed: $e');
        _vectorDbService = null;
      });
    }
  }

  /// Initialize all agent services
  Future<bool> initialize() async {
    try {
      _logger?.call('🤖 Initializing Agent Manager...');

      // Initialize individual services
      _asrService = ASRService(logger: _logger);
      _llmService = LocalLLMService(logger: _logger);
      _ocrService = OCRService(logger: _logger);

      // Initialize services in parallel
      final results = await Future.wait([
        _asrService.initialize(),
        _llmService.initialize(),
        _ocrService.initialize(),
      ]);

      final allReady = results.every((ready) => ready);

      if (allReady) {
        _isReady = true;
        _isEnabled = true; // Auto-enable when ready
        _logger?.call('✅ Agent Manager ready - All services initialized');
        return true;
      } else {
        _logger?.call(
            '⚠️ Agent Manager partial initialization - some services failed');
        _isReady = true; // Still usable with graceful degradation
        _isEnabled = true;
        return true;
      }
    } catch (e) {
      _logger?.call('❌ Agent Manager initialization failed: $e');
      return false;
    }
  }

  /// Check if agent system is ready
  bool get isReady => _isReady;

  /// Check if agent system is enabled
  bool get isEnabled => _isEnabled;

  /// Enable/disable agent processing
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    _logger?.call(enabled
        ? '✅ Agent processing enabled'
        : '⏸️ Agent processing disabled');
  }

  /// Process audio through agent pipeline (parallel to Gemini)
  Future<void> processAudio(Uint8List audioData) async {
    if (!_isReady || !_isEnabled || _isProcessing) return;

    try {
      _isProcessing = true;
      _logger?.call('🎤 Agent processing audio (${audioData.length} bytes)...');

      // Run ASR on audio
      final asrResult = await _asrService.transcribeAudio(audioData);

      if (asrResult != null && asrResult.text.isNotEmpty) {
        _logger?.call(
            '🎤 Agent ASR: "${asrResult.text}" (${asrResult.confidence.toStringAsFixed(2)})');

        // Process with LLM if we have text
        await _processWithLLM(
          context: 'Audio transcription: ${asrResult.text}',
          inputType: 'audio',
          inputData: {
            'transcription': asrResult.text,
            'confidence': asrResult.confidence,
            'audioLength': audioData.length,
          },
        );
      }
    } catch (e) {
      _logger?.call('❌ Agent audio processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Process image through agent pipeline (parallel to Gemini)
  Future<void> processImage(Uint8List imageData) async {
    if (!_isReady || !_isEnabled || _isProcessing) return;

    try {
      _isProcessing = true;
      _logger?.call('📸 Agent processing image (${imageData.length} bytes)...');

      // Run OCR on image
      final ocrResult = await _ocrService.extractText(imageData);

      if (ocrResult != null && ocrResult.text.isNotEmpty) {
        _logger?.call(
            '👁️ Agent OCR: "${ocrResult.text}" (${ocrResult.confidence.toStringAsFixed(2)})');

        // Process with LLM if we have text
        await _processWithLLM(
          context: 'Image OCR text: ${ocrResult.text}',
          inputType: 'image',
          inputData: {
            'ocrText': ocrResult.text,
            'confidence': ocrResult.confidence,
            'textBlocks': ocrResult.textBlocks.length,
            'imageSize': imageData.length,
          },
        );
      } else {
        _logger?.call('👁️ Agent OCR: No text found in image');
      }
    } catch (e) {
      _logger?.call('❌ Agent image processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Process multimodal input (audio + image)
  Future<void> processMultimodal(
      Uint8List? audioData, Uint8List? imageData) async {
    if (!_isReady || !_isEnabled || _isProcessing) return;

    try {
      _isProcessing = true;
      _logger?.call('🔄 Agent multimodal processing...');

      String context = 'Multimodal input: ';
      final inputData = <String, dynamic>{};

      // Process audio if available
      if (audioData != null) {
        final asrResult = await _asrService.transcribeAudio(audioData);
        if (asrResult != null && asrResult.text.isNotEmpty) {
          context += 'Audio: ${asrResult.text}. ';
          inputData['audio'] = {
            'transcription': asrResult.text,
            'confidence': asrResult.confidence,
          };
        }
      }

      // Process image if available
      if (imageData != null) {
        final ocrResult = await _ocrService.extractText(imageData);
        if (ocrResult != null && ocrResult.text.isNotEmpty) {
          context += 'Image text: ${ocrResult.text}.';
          inputData['image'] = {
            'ocrText': ocrResult.text,
            'confidence': ocrResult.confidence,
            'textBlocks': ocrResult.textBlocks.length,
          };
        }
      }

      if (inputData.isNotEmpty) {
        await _processWithLLM(
          context: context,
          inputType: 'multimodal',
          inputData: inputData,
        );
      }
    } catch (e) {
      _logger?.call('❌ Agent multimodal processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Process context with local LLM and execute tools
  Future<void> _processWithLLM({
    required String context,
    required String inputType,
    required Map<String, dynamic> inputData,
  }) async {
    try {
      // Process with local LLM
      final llmResponse = await _llmService.processWithTools(
        context: context,
        availableTools: _availableTools,
      );

      if (llmResponse != null) {
        _logger?.call('🧠 Agent LLM response: "${llmResponse.content}"');

        // Execute any tool calls
        final toolResults = <String, dynamic>{};
        for (final toolCall in llmResponse.toolCalls) {
          final result = await _executeTool(toolCall);
          toolResults[toolCall.name] = result;
        }

        // Emit agent processing result
        final agentResult = AgentProcessingResult(
          inputType: inputType,
          inputData: inputData,
          llmResponse: llmResponse.content,
          toolCalls: llmResponse.toolCalls,
          toolResults: toolResults,
          processingTime: llmResponse.processingTime,
          timestamp: DateTime.now(),
        );

        _agentOutputController.add(agentResult);
        _logger?.call('✅ Agent processing complete - result emitted');
      }
    } catch (e) {
      _logger?.call('❌ Agent LLM processing error: $e');
    }
  }

  /// Execute a tool call
  Future<Map<String, dynamic>> _executeTool(ToolCall toolCall) async {
    try {
      _logger?.call('🔧 Executing tool: ${toolCall.name}');

      switch (toolCall.name) {
        case 'store_memory':
          return await _executeStoreMemory(toolCall.parameters);
        case 'retrieve_memory':
          return await _executeRetrieveMemory(toolCall.parameters);
        case 'analyze_content':
          return await _executeAnalyzeContent(toolCall.parameters);
        case 'update_memory':
          return await _executeUpdateMemory(toolCall.parameters);
        default:
          _logger?.call('⚠️ Unknown tool: ${toolCall.name}');
          return {'error': 'Unknown tool: ${toolCall.name}'};
      }
    } catch (e) {
      _logger?.call('❌ Tool execution error: $e');
      return {'error': e.toString()};
    }
  }

  /// Execute store_memory tool
  Future<Map<String, dynamic>> _executeStoreMemory(
      Map<String, dynamic> params) async {
    final content = params['content']?.toString() ?? '';
    final category = params['category']?.toString() ?? 'general';

    _logger?.call('💾 Storing memory: $category - $content');

    if (_vectorDbService != null) {
      try {
        await _vectorDbService!.addTextWithEmbedding(
          content: content,
          metadata: {
            'source': 'agent',
            'timestamp': DateTime.now().toIso8601String(),
            'category': category,
          },
        );

        return {
          'success': true,
          'action': 'stored',
          'content': content,
          'category': category,
          'id': 'db_${DateTime.now().millisecondsSinceEpoch}',
        };
      } catch (e) {
        _logger?.call('❌ Database store failed: $e');
        return {
          'success': false,
          'action': 'store_failed',
          'error': e.toString(),
        };
      }
    }

    // Fallback to mock if no database
    return {
      'success': true,
      'action': 'stored_mock',
      'content': content,
      'category': category,
      'id': 'mock_${DateTime.now().millisecondsSinceEpoch}',
    };
  }

  /// Execute retrieve_memory tool
  Future<Map<String, dynamic>> _executeRetrieveMemory(
      Map<String, dynamic> params) async {
    final query = params['query']?.toString() ?? '';
    final topK = params['topK'] as int? ?? 3;

    _logger?.call('🔍 Retrieving memories for: $query');

    if (_vectorDbService != null) {
      try {
        final results = await _vectorDbService!.queryText(
          queryText: query,
          topK: topK,
          threshold: 0.3,
        );

        return {
          'success': true,
          'action': 'retrieved',
          'query': query,
          'results': results.map((result) => {
            'content': result['text'] ?? '',
            'confidence': result['score'] ?? 0.0,
            'metadata': result['metadata'] ?? {},
            'category': result['category'] ?? 'general',
          }).toList(),
        };
      } catch (e) {
        _logger?.call('❌ Database retrieve failed: $e');
        return {
          'success': false,
          'action': 'retrieve_failed',
          'error': e.toString(),
        };
      }
    }

    // Fallback to mock if no database
    return {
      'success': true,
      'action': 'retrieved_mock',
      'query': query,
      'results': [
        {'content': 'Sample memory 1', 'confidence': 0.8},
        {'content': 'Sample memory 2', 'confidence': 0.6},
      ],
    };
  }

  /// Execute analyze_content tool
  Future<Map<String, dynamic>> _executeAnalyzeContent(
      Map<String, dynamic> params) async {
    final type = params['type']?.toString() ?? 'text';
    final content = params['content']?.toString() ?? '';

    _logger?.call('🔍 Analyzing content: $type - $content');

    return {
      'success': true,
      'action': 'analyzed',
      'type': type,
      'content': content,
      'analysis': {
        'sentiment': 'neutral',
        'topics': ['general'],
        'entities': [],
        'confidence': 0.7,
      },
    };
  }

  /// Execute update_memory tool
  Future<Map<String, dynamic>> _executeUpdateMemory(
      Map<String, dynamic> params) async {
    // TODO: Implement with vector database integration
    final id = params['id']?.toString() ?? '';
    final content = params['content']?.toString() ?? '';

    _logger?.call('✏️ Updating memory: $id - $content');

    return {
      'success': true,
      'action': 'updated',
      'id': id,
      'content': content,
    };
  }

  /// Get agent status for UI
  Map<String, dynamic> getStatus() {
    return {
      'isReady': _isReady,
      'isEnabled': _isEnabled,
      'isProcessing': _isProcessing,
      'services': {
        'asr': _asrService.isReady,
        'llm': _llmService.isReady,
        'ocr': _ocrService.isReady,
      },
      'availableTools': _availableTools,
    };
  }

  /// Dispose all resources
  void dispose() {
    _agentOutputController.close();
    _asrService.dispose();
    _llmService.dispose();
    _ocrService.dispose();
    _isReady = false;
    _isEnabled = false;
    _logger?.call('🧹 Agent Manager disposed');
  }
}

/// Agent processing result
class AgentProcessingResult {
  final String inputType;
  final Map<String, dynamic> inputData;
  final String llmResponse;
  final List<ToolCall> toolCalls;
  final Map<String, dynamic> toolResults;
  final Duration processingTime;
  final DateTime timestamp;

  AgentProcessingResult({
    required this.inputType,
    required this.inputData,
    required this.llmResponse,
    required this.toolCalls,
    required this.toolResults,
    required this.processingTime,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'AgentProcessingResult('
        'type: $inputType, '
        'response: $llmResponse, '
        'tools: ${toolCalls.length}, '
        'time: ${processingTime.inMilliseconds}ms'
        ')';
  }
}
