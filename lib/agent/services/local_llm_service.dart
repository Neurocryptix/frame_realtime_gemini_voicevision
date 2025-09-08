import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/src/flutter_gemma_src.dart';
import 'package:flutter/services.dart';
import '../models/agent_output.dart';

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

  // Gemma Nano for on-device agentic processing
  InferenceModel? _gemmaModel; // FlutterGemma model instance
  bool _gemmaInitialized = false;
  bool _modelDownloadInProgress = false;
  String? _modelPath;

  // Model download configuration - Updated for Gemma 3
  static const String _modelFileName = 'gemma-3n-2b-it-int4.bin'; // Gemma 3 compatible model - downloaded via Kaggle
  static const String _modelAssetPath = 'assets/models/$_modelFileName'; // Not used - models downloaded via Kaggle

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

      // Initialize Gemma Nano for on-device processing. No fallback.
      final hasGemmaNano = await _initializeGemmaNano();

      if (hasGemmaNano) {
        _useGemmaNano = true;
        _isReady = true;
        _logger?.call('✅ Gemma Nano initialized for on-device agentic processing');
        return true;
      } else {
        // If Gemma Nano fails, the entire service fails.
        _isReady = false;
        _logger?.call('❌ Gemma Nano initialization failed. The on-device agent will not be available.');
        return false;
      }
    } catch (e) {
      _logger?.call('❌ Local LLM initialization failed: $e');
      _isReady = false;
      return false;
    }
  }

  /// Initialize Gemma Nano for on-device agentic processing
  Future<bool> _initializeGemmaNano() async {
    try {
      _logger?.call('🧠 Initializing Gemma Nano for on-device processing...');

      if (!Platform.isAndroid) {
        _logger?.call('⚠️ Gemma Nano is primarily supported on Android, skipping...');
        return false;
      }

      final appDir = await getApplicationDocumentsDirectory();
      _modelPath = '${appDir.path}/$_modelFileName';
      final modelFile = File(_modelPath!);

      if (!await modelFile.exists()) {
        _logger?.call('📥 Model not found in app directory. Installing from assets...');
        final installSuccess = await _installModel();
        if (!installSuccess) {
          _logger?.call('❌ Model installation failed.');
          return false;
        }
      } else {
        _logger?.call('✅ Gemma Nano model already exists in app directory.');
      }

      return await _initializeGemmaModel();
    } catch (e) {
      _logger?.call('❌ Gemma Nano initialization failed: $e');
      return false;
    }
  }

  /// Install Gemma Nano model from assets to the app directory
  Future<bool> _installModel() async {
    if (_modelDownloadInProgress) {
      _logger?.call('⏳ Model installation already in progress...');
      return false;
    }
    try {
      _modelDownloadInProgress = true;
      _logger?.call('📥 Installing Gemma Nano model from assets...');
      
      final byteData = await rootBundle.load(_modelAssetPath);
      final modelFile = File(_modelPath!);
      await modelFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      _logger?.call('✅ Model installed successfully to $_modelPath');
      return true;
    } catch (e) {
      _logger?.call('❌ Model installation from assets failed: $e');
      return false;
    } finally {
      _modelDownloadInProgress = false;
    }
  }

  /// Initialize Gemma model after installation
  Future<bool> _initializeGemmaModel() async {
    try {
      _logger?.call('🔧 Initializing Gemma Nano model instance...');
      _gemmaModel = await FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt, // Instruction-tuned model
        maxTokens: 512,
      );
      _gemmaInitialized = true;
      _logger?.call('✅ Gemma Nano model instance created.');
      return true;
    } catch (e) {
      _logger?.call('❌ Model initialization failed: $e');
      _gemmaModel = null;
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
    if (!_isReady || !_useGemmaNano || !_gemmaInitialized) {
      _logger?.call('⚠️ On-device agent not ready. Cannot process.');
      // Throw an exception to be caught by the UI layer
      throw Exception('Gemma Nano agent is not initialized.');
    }

    final startTime = DateTime.now();

    // Process directly with Gemma Nano. Any exception will be propagated.
    final response = await _gemmaNanoProcess(context, availableTools);
    
    final processingTime = DateTime.now().difference(startTime);
    _logger?.call(
        '🧠 Agent LLM (GEMMA_NANO) processed in ${processingTime.inMilliseconds}ms');

    return LLMResponse(
      content: response['content'] ?? '',
      toolCalls: _parseToolCalls(response['tool_calls'] ?? []),
      processingTime: processingTime,
      metadata: {
        'modelType': 'gemma_nano',
        'modelName': _modelName,
        'contextLength': context.length,
        'availableTools': availableTools,
      },
    );
  }

  /// Gemma Nano on-device processing for agentic decision making
  Future<Map<String, dynamic>> _gemmaNanoProcess(
      String context, List<String> availableTools) async {
    if (!_gemmaInitialized || _gemmaModel == null) {
      throw Exception('Gemma Nano not initialized');
    }

    final systemPrompt = _buildAgenticSystemPrompt(availableTools);
    final fullPrompt = '$systemPrompt\n\nUser Context: $context\n\nAnalyze this context and decide what actions to take. Respond with your reasoning and any tool calls needed:';

    _logger?.call('🧠 Processing with Gemma Nano: ${_truncateForLog(context)}');

    // Create a chat session and get response
    final chat = await _gemmaModel!.createChat();
    await chat.addQueryChunk(Message.text(text: fullPrompt, isUser: true));
    final response = await chat.generateChatResponse();

    if (response is TextResponse && response.token.isNotEmpty) {
      _logger?.call('✅ Gemma Nano response: ${_truncateForLog(response.token)}');
      return _parseRealLLMResponse(response.token);
    } else {
      throw Exception('Empty response from Gemma Nano');
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

    if (_useGemmaNano && _gemmaInitialized) {
      modelType = 'gemma_nano';
      maxContextLength = 2048; // Gemma Nano context window
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
      'gemmaInitialized': _gemmaInitialized,
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
      // TODO: Re-enable when flutter_gemma API is verified
      // final modelManager = FlutterGemmaPlugin.instance.modelManager;

      Map<String, dynamic> status = {
        'modelInstalled': modelInstalled,
        'modelPath': _modelPath,
        'modelFileName': _modelFileName,
        'installInProgress': _modelDownloadInProgress,
        'gemmaInitialized': _gemmaInitialized,
      };

      // TODO: Re-enable when flutter_gemma API is verified
      // Get installed models info
      // try {
      //   final installedModels = await modelManager.getInstalledModels();
      //   status['installedModelsCount'] = installedModels.length;
      //
      //   if (installedModels.isNotEmpty) {
      //     status['installedModels'] = installedModels.map((model) => {
      //       'path': model.path,
      //       'type': model.type.toString(),
      //       'size': model.sizeInBytes,
      //     }).toList();
      //   }
      // } catch (e) {
      //   status['modelInfoError'] = e.toString();
      // }

      status['note'] =
          'Model info disabled pending flutter_gemma API verification';

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
      _logger?.call('🔄 Forcing Gemma Nano model reinstallation...');

      // TODO: Re-enable when flutter_gemma API is verified
      // final modelManager = FlutterGemmaPlugin.instance.modelManager;

      // TODO: Re-enable when flutter_gemma API is verified
      // Clean up existing models
      // try {
      //   final installedModels = await modelManager.getInstalledModels();
      //   for (final model in installedModels) {
      //     await modelManager.uninstallModel(model);
      //     _logger?.call('🗑️ Uninstalled model: ${model.path}');
      //   }
      // } catch (e) {
      //   _logger?.call('⚠️ Error during cleanup: $e');
      // }

      _logger?.call('⚠️ Model cleanup disabled pending API verification');

      // Reset state
      _gemmaInitialized = false;
      // TODO: Re-enable when flutter_gemma API is verified
      // _gemmaModel?.dispose();
      _gemmaModel = null;
      _modelPath = null;

      // Trigger fresh installation and initialization
      return await _initializeGemmaNano();
    } catch (e) {
      _logger?.call('❌ Force reinstallation failed: $e');
      return false;
    }
  }

  /// Dispose resources (doesn't affect main Gemini pipeline)
  void dispose() {
    _httpClient.close();

    // Clean up Gemma Nano resources
    if (_gemmaModel != null) {
      try {
        _gemmaModel!.close(); // Fire and forget
        _logger?.call('🧹 Gemma model closed');
      } catch (e) {
        _logger?.call('⚠️ Error closing Gemma model: $e');
      }
      _gemmaModel = null;
    }

    _isReady = false;
    _useLocalApi = false;
    _useGemmaNano = false;
    _gemmaInitialized = false;
    _logger?.call('🧹 Local LLM service disposed (agent-only)');
  }
}
