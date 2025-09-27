import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/agent_output.dart';
import './ai_edge_llm_service.dart';

/// Local LLM service with tool calling capabilities
/// CRITICAL: This is agent-only and NEVER affects the Gemini pipeline
/// Supports multiple local LLM backends: Ollama, local API, or fallback mock
class LocalLLMService {
  final void Function(String)? _logger;
  bool _isReady = false;

  // Local LLM configuration (completely separate from Gemini)

  String _modelName = 'llama3.2:1b'; // Lightweight model for mobile
  bool _useLocalApi = false;
  bool _useGemmaNano = false;

  // HTTP client for local LLM API calls (agent-only)
  late http.Client _httpClient;

  // AI Edge LLM for on-device agentic processing
  AIEdgeLLMServiceImpl? _aiEdgeLLM; // AI Edge LLM service instance
  bool _aiEdgeInitialized = false;
  final bool _modelDownloadInProgress = false; // No longer used for downloads
  String? _modelPath;

  // Model configuration - Using downloaded AI Edge models
  static const String _modelFileName = 'model.safetensors'; // AI Edge model file

  LocalLLMService({
    void Function(String)? logger,
    String? modelName,
  }) : _logger = logger {

    if (modelName != null) _modelName = modelName;
    _httpClient = http.Client();
  }

  /// Initialize the local LLM service (SEPARATE from Gemini)
  Future<bool> initialize() async {
    try {
      _logger?.call('🤖 Initializing Local LLM service (agent-only)...');

      // Initialize AI Edge LLM for on-device processing. No fallback.
      final hasAIEdge = await _initializeAIEdge();

      if (hasAIEdge) {
        _useGemmaNano = true; // Keep variable name for compatibility
        _isReady = true;
        _logger?.call('✅ AI Edge LLM initialized for on-device agentic processing');
        return true;
      } else {
        // If AI Edge fails, the entire service fails.
        _isReady = false;
        _logger?.call('❌ AI Edge LLM initialization failed. The on-device agent will not be available.');
        return false;
      }
    } catch (e) {
      _logger?.call('❌ Local LLM initialization failed: $e');
      _isReady = false;
      return false;
    }
  }

  /// Initialize AI Edge LLM for on-device agentic processing
  Future<bool> _initializeAIEdge() async {
    try {
      _logger?.call('🧠 Initializing AI Edge LLM for on-device processing...');

      if (!Platform.isAndroid) {
        _logger?.call('⚠️ AI Edge LLM is primarily supported on Android, skipping...');
        return false;
      }

      // Use the model that's already downloaded and working (google/gemma-3-270m)
      // The app logs show: "✅ AI Edge model ready: Gemma 3 270M (Ultra Compact)"
      final appDir = await getApplicationDocumentsDirectory();
      _modelPath = '${appDir.path}/ai_edge_models/$_modelFileName'; // Use actual downloaded model path
      final modelFile = File(_modelPath!);

      if (!await modelFile.exists()) {
        _logger?.call('⚠️ Downloaded AI Edge model not found at $_modelPath');
        _logger?.call('ℹ️ Skipping asset installation - using integrated AI Edge service instead');
        // Don't try to install from assets - the working model is managed by IntegratedAgenticService
        return false;
      } else {
        _logger?.call('✅ AI Edge model found at $_modelPath');
      }

      return await _initializeAIEdgeModel();
    } catch (e) {
      _logger?.call('❌ AI Edge LLM initialization failed: $e');
      return false;
    }
  }


  /// Initialize AI Edge model after installation
  Future<bool> _initializeAIEdgeModel() async {
    try {
      _logger?.call('🔧 Initializing AI Edge LLM model instance...');
      
      // Initialize AI Edge LLM service
      _aiEdgeLLM = AIEdgeLLMServiceImpl(logger: _logger);
      
      if (_modelPath != null) {
        final success = await _aiEdgeLLM!.initialize(
          modelPath: _modelPath!,
          maxTokens: 512,
          temperature: 0.8,
        );
        
        if (success) {
          _aiEdgeInitialized = true;
          _logger?.call('✅ AI Edge LLM service ready');
          return true;
        } else {
          _logger?.call('❌ AI Edge LLM initialization failed');
          _aiEdgeLLM = null;
          return false;
        }
      } else {
        _logger?.call('❌ Model path not set');
        return false;
      }
    } catch (e) {
      _logger?.call('❌ AI Edge model initialization failed: $e');
      _aiEdgeLLM = null;
      return false;
    }
  }



  /// Check if the service is ready
  bool get isReady => _isReady;

  /// Process context with tool calling capabilities (AGENT-ONLY, doesn't affect Gemini)
  /// This is the main interface for agent LLM processing
  Future<LLMResponse?> processWithTools({
    required String context,
    required List<String> availableTools,
  }) async {
    if (!_isReady || !_useGemmaNano || !_aiEdgeInitialized) {
      _logger?.call('⚠️ On-device agent not ready. Cannot process.');
      // Throw an exception to be caught by the UI layer
      throw Exception('AI Edge LLM agent is not initialized.');
    }

    final startTime = DateTime.now();

    // Process directly with AI Edge LLM. Any exception will be propagated.
    final response = await _aiEdgeProcess(context, availableTools);
    
    final processingTime = DateTime.now().difference(startTime);
    _logger?.call(
        '🧠 Agent LLM (AI_EDGE) processed in ${processingTime.inMilliseconds}ms');

    return LLMResponse(
      content: response['content'] ?? '',
      toolCalls: _parseToolCalls(response['tool_calls'] ?? []),
      processingTime: processingTime,
      metadata: {
        'modelType': 'ai_edge',
        'modelName': _modelName,
        'contextLength': context.length,
        'availableTools': availableTools,
      },
    );
  }

  /// AI Edge LLM on-device processing for agentic decision making
  Future<Map<String, dynamic>> _aiEdgeProcess(
      String context, List<String> availableTools) async {
    if (!_aiEdgeInitialized || _aiEdgeLLM == null) {
      throw Exception('AI Edge LLM not initialized');
    }

    final systemPrompt = _buildAgenticSystemPrompt(availableTools);
    final fullPrompt = '$systemPrompt\n\nUser Context: $context\n\nAnalyze this context and decide what actions to take. Respond with your reasoning and any tool calls needed:';

    _logger?.call('🧠 Processing with AI Edge LLM: ${_truncateForLog(context)}');

    // Get response from AI Edge LLM service
    final response = await _aiEdgeLLM!.generateResponse(fullPrompt);

    if (response != null && response.isNotEmpty) {
      _logger?.call('✅ AI Edge LLM response: ${_truncateForLog(response)}');
      return _parseRealLLMResponse(response);
    } else {
      throw Exception('Empty response from AI Edge LLM');
    }
  }

  /// Truncate text for logging purposes
  String _truncateForLog(String text, {int maxLength = 100}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// Build optimized system prompt for agentic decision making with Gemma Nano
  String _buildAgenticSystemPrompt(List<String> availableTools) {
    final toolDescriptions = availableTools.map((tool) {
      switch (tool) {
        case 'store_memory':
          return '- store_memory(content, category): Store important information';
        case 'retrieve_memory':
          return '- retrieve_memory(query): Search stored information';
        case 'update_memory':
          return '- update_memory(id, content): Update stored information';
        case 'analyze_content':
          return '- analyze_content(type, content): Analyze content for insights';
        default:
          return '- $tool: Available tool';
      }
    }).join('\n');

    return '''You are an intelligent agent for Frame smart glasses. Your job is to make quick, smart decisions about processing user interactions and visual content.

Available tools:
$toolDescriptions

Instructions:
- Be concise and decisive
- Use tools when data should be stored or retrieved
- For speech/text: usually store important information
- For visual content: analyze and store if significant
- Format tool calls like: TOOL_CALL: tool_name(param1="value1", param2="value2")
- Give brief reasoning for your decisions

Respond with your analysis and tool calls:''';
  }





  /// Parse real LLM response to extract content and tool calls
  Map<String, dynamic> _parseRealLLMResponse(String response) {
    final toolCalls = <Map<String, dynamic>>[];
    String content = response;

    // Look for TOOL_CALL: patterns in the response
    final toolCallPattern = RegExp(r'TOOL_CALL:\s*(\w+)\((.*?)\)');
    final matches = toolCallPattern.allMatches(response);

    for (final match in matches) {
      final toolName = match.group(1) ?? '';
      final paramString = match.group(2) ?? '';

      // Parse parameters (simple key=value parsing)
      final parameters = <String, dynamic>{};
      final paramPattern = RegExp(r'(\w+)="([^"]*)"');
      final paramMatches = paramPattern.allMatches(paramString);

      for (final paramMatch in paramMatches) {
        final key = paramMatch.group(1) ?? '';
        final value = paramMatch.group(2) ?? '';
        parameters[key] = value;
      }

      toolCalls.add({
        'name': toolName,
        'parameters': parameters,
      });

      // Remove tool call from content
      content = content.replaceAll(match.group(0) ?? '', '');
    }

    return {
      'content': content.trim(),
      'tool_calls': toolCalls,
    };
  }

  /// Mock LLM processing (replace with actual LLM integration)
  Future<Map<String, dynamic>> _mockLLMProcess(
      String context, List<String> availableTools) async {
    // Simulate processing time
    await Future.delayed(Duration(milliseconds: 100 + context.length ~/ 10));

    // Simple rule-based mock responses with tool calling
    final contextLower = context.toLowerCase();

    // Determine appropriate response and tool calls based on context
    if (contextLower.contains('asr') && contextLower.contains('speech')) {
      return {
        'content':
            'I detected speech content that should be stored for future reference.',
        'tool_calls': [
          {
            'name': 'store_memory',
            'parameters': {
              'content': 'Speech recognition detected user utterance',
              'category': 'speech_interaction',
            },
          },
        ],
      };
    } else if (contextLower.contains('ocr') && contextLower.contains('text')) {
      return {
        'content': 'I found text in the visual content that might be useful.',
        'tool_calls': [
          {
            'name': 'store_memory',
            'parameters': {
              'content': 'OCR extracted text from image',
              'category': 'visual_text',
            },
          },
          {
            'name': 'analyze_content',
            'parameters': {
              'content_type': 'text',
              'analysis_type': 'semantic',
            },
          },
        ],
      };
    } else if (contextLower.contains('confidence') &&
        contextLower.contains('high')) {
      return {
        'content': 'This seems like important information worth remembering.',
        'tool_calls': [
          {
            'name': 'store_memory',
            'parameters': {
              'content': context,
              'priority': 'high',
            },
          },
          {
            'name': 'retrieve_memory',
            'parameters': {
              'query': 'similar important information',
            },
          },
        ],
      };
    } else if (contextLower.contains('query') ||
        contextLower.contains('search')) {
      return {
        'content': 'Let me search for relevant information in memory.',
        'tool_calls': [
          {
            'name': 'retrieve_memory',
            'parameters': {
              'query': _extractSearchQuery(context),
            },
          },
        ],
      };
    } else {
      // Default response for general content
      return {
        'content':
            'I\'ve processed this information and determined it should be stored.',
        'tool_calls': [
          {
            'name': 'store_memory',
            'parameters': {
              'content': _summarizeContent(context),
            },
          },
        ],
      };
    }
  }

  /// Extract search query from context
  String _extractSearchQuery(String context) {
    // Simple extraction logic - in a real implementation, this would be more sophisticated
    final words = context.toLowerCase().split(' ');
    final importantWords = words
        .where((word) =>
            word.length > 3 &&
            ![
              'the',
              'and',
              'for',
              'are',
              'but',
              'not',
              'you',
              'all',
              'can',
              'had',
              'was',
              'one',
              'our',
              'out',
              'day',
              'get',
              'has',
              'him',
              'his',
              'how',
              'its',
              'may',
              'new',
              'now',
              'old',
              'see',
              'two',
              'way',
              'who',
              'boy',
              'did',
              'man',
              'her',
              'she',
              'use',
              'each',
              'make',
              'most',
              'over',
              'said',
              'some',
              'time',
              'very',
              'what',
              'with',
              'have',
              'from',
              'they',
              'know',
              'want',
              'been',
              'good',
              'much',
              'some',
              'time',
              'very',
              'when',
              'come',
              'here',
              'just',
              'like',
              'long',
              'make',
              'many',
              'over',
              'such',
              'take',
              'than',
              'them',
              'well',
              'were'
            ].contains(word))
        .toList();

    return importantWords.take(5).join(' ');
  }

  /// Summarize content for storage
  String _summarizeContent(String context) {
    if (context.length <= 100) return context;

    // Simple summarization - take first meaningful sentence or first 100 chars
    final sentences = context.split('. ');
    if (sentences.isNotEmpty && sentences.first.length <= 150) {
      return sentences.first;
    }

    return '${context.substring(0, 100)}...';
  }

  /// Parse tool calls from mock response
  List<ToolCall> _parseToolCalls(List<dynamic> toolCallsData) {
    return toolCallsData.map((toolCallData) {
      if (toolCallData is Map<String, dynamic>) {
        return ToolCall(
          name: toolCallData['name'] ?? '',
          parameters:
              Map<String, dynamic>.from(toolCallData['parameters'] ?? {}),
          id: toolCallData['id'],
        );
      }
      return const ToolCall(name: 'unknown', parameters: {});
    }).toList();
  }

  /// Generate a simple text response without tool calls
  Future<String?> generateResponse(String prompt) async {
    if (!_isReady) return null;

    try {
      final response = await _mockLLMProcess(prompt, []);
      return response['content'];
    } catch (e) {
      _logger?.call('❌ Simple LLM response error: $e');
      return null;
    }
  }

  /// Get available tool definitions
  List<Map<String, dynamic>> getToolDefinitions() {
    return [
      {
        'name': 'store_memory',
        'description':
            'Store information in the vector database for future retrieval',
        'parameters': {
          'content': {'type': 'string', 'description': 'Content to store'},
          'category': {
            'type': 'string',
            'description': 'Category of the content'
          },
          'priority': {
            'type': 'string',
            'description': 'Priority level: low, medium, high'
          },
        },
      },
      {
        'name': 'retrieve_memory',
        'description': 'Retrieve relevant information from the vector database',
        'parameters': {
          'query': {'type': 'string', 'description': 'Search query'},
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of results'
          },
        },
      },
      {
        'name': 'update_memory',
        'description': 'Update existing information in the vector database',
        'parameters': {
          'id': {'type': 'string', 'description': 'ID of the entry to update'},
          'content': {'type': 'string', 'description': 'Updated content'},
        },
      },
      {
        'name': 'analyze_content',
        'description': 'Analyze content for insights and patterns',
        'parameters': {
          'content_type': {
            'type': 'string',
            'description': 'Type of content: text, image, audio'
          },
          'analysis_type': {
            'type': 'string',
            'description': 'Type of analysis: semantic, sentiment, topic'
          },
        },
      },
    ];
  }

  /// Get service statistics including model download status
  Map<String, dynamic> getStatistics() {
    String modelType;
    int maxContextLength;

    if (_useGemmaNano && _aiEdgeInitialized) {
      modelType = 'ai_edge_llm';
      maxContextLength = 2048; // AI Edge LLM context window
    } else if (_useLocalApi) {
      modelType = 'local_llm';
      maxContextLength = 4096; // Typical local LLM
    } else {
      modelType = 'mock_llm';
      maxContextLength = 4096; // Mock value
    }

    return {
      'isReady': _isReady,
      'modelType': modelType,
      'useGemmaNano': _useGemmaNano,
      'aiEdgeInitialized': _aiEdgeInitialized,
      'modelDownloadInProgress': _modelDownloadInProgress,
      'modelPath': _modelPath,
      'useLocalApi': _useLocalApi,
      'supportedTools':
          getToolDefinitions().map((tool) => tool['name']).toList(),
      'maxContextLength': maxContextLength,
    };
  }

  /// Check if Gemma Nano model download is in progress
  bool get isModelDownloadInProgress => _modelDownloadInProgress;

  /// Get model installation status and information
  Future<Map<String, dynamic>> getModelStatus() async {
    try {
      final modelFile = File(_modelPath ?? '');
      final modelInstalled = await modelFile.exists();
      // AI Edge models are managed through MediaPipe GenAI

      Map<String, dynamic> status = {
        'modelInstalled': modelInstalled,
        'modelPath': _modelPath,
        'modelFileName': _modelFileName,
        'installInProgress': _modelDownloadInProgress,
        'aiEdgeInitialized': _aiEdgeInitialized,
      };

      status['note'] = 'AI Edge models managed through MediaPipe GenAI';

      return status;
    } catch (e) {
      return {
        'error': e.toString(),
        'modelInstalled': false,
        'installInProgress': _modelDownloadInProgress,
      };
    }
  }

  /// Force reinstallation of Gemma Nano model (for updates or corruption recovery)
  Future<bool> forceModelReinstall() async {
    try {
      _logger?.call('🔄 Forcing AI Edge model reinstallation...');

      // Reset state
      _aiEdgeInitialized = false;
      _aiEdgeLLM?.dispose();
      _aiEdgeLLM = null;
      _modelPath = null;

      // Trigger fresh installation and initialization
      return await _initializeAIEdge();
    } catch (e) {
      _logger?.call('❌ Force reinstallation failed: $e');
      return false;
    }
  }

  /// Dispose resources (doesn't affect main Gemini pipeline)
  void dispose() {
    _httpClient.close();

    // Clean up AI Edge LLM resources
    if (_aiEdgeLLM != null) {
      try {
        _aiEdgeLLM!.dispose();
        _logger?.call('🧹 AI Edge LLM disposed');
      } catch (e) {
        _logger?.call('⚠️ Error disposing AI Edge LLM: $e');
      }
      _aiEdgeLLM = null;
    }

    _isReady = false;
    _useLocalApi = false;
    _useGemmaNano = false;
    _aiEdgeInitialized = false;
    _logger?.call('🧹 Local LLM service disposed (agent-only)');
  }
}
