import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/agent_output.dart';

/// Local LLM service with tool calling capabilities
/// CRITICAL: This is agent-only and NEVER affects the Gemini pipeline
/// Supports multiple local LLM backends: Ollama, local API, or fallback mock
class LocalLLMService {
  final void Function(String)? _logger;
  bool _isReady = false;
  
  // Local LLM configuration (completely separate from Gemini)
  String _baseUrl = 'http://localhost:11434'; // Default Ollama port
  String _modelName = 'llama3.2:1b'; // Lightweight model for mobile
  bool _useLocalApi = false;
  
  // HTTP client for local LLM API calls (agent-only)
  late http.Client _httpClient;
  
  LocalLLMService({
    void Function(String)? logger,
    String? baseUrl,
    String? modelName,
  }) : _logger = logger {
    if (baseUrl != null) _baseUrl = baseUrl;
    if (modelName != null) _modelName = modelName;
    _httpClient = http.Client();
  }

  /// Initialize the local LLM service (SEPARATE from Gemini)
  Future<bool> initialize() async {
    try {
      _logger?.call('🤖 Initializing REAL Local LLM service (agent-only)...');
      
      // Try to connect to local LLM API (Ollama or custom)
      final hasLocalLLM = await _testLocalLLMConnection();
      
      if (hasLocalLLM) {
        _useLocalApi = true;
        _isReady = true;
        _logger?.call('✅ REAL Local LLM connected at $_baseUrl (model: $_modelName)');
        return true;
      } else {
        _logger?.call('⚠️ No local LLM found, falling back to mock implementation');
        // Graceful fallback to mock
        _useLocalApi = false;
        await Future.delayed(const Duration(milliseconds: 500));
        _isReady = true;
        return true;
      }
      
    } catch (e) {
      _logger?.call('❌ Local LLM initialization failed, using mock: $e');
      // Always fall back gracefully
      _useLocalApi = false;
      _isReady = true;
      return true;
    }
  }
  
  /// Test connection to local LLM API (doesn't affect Gemini)
  Future<bool> _testLocalLLMConnection() async {
    try {
      // Test Ollama API endpoint
      final response = await _httpClient.get(
        Uri.parse('$_baseUrl/api/tags'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = data['models'] as List?;
        
        if (models != null && models.isNotEmpty) {
          _logger?.call('🔍 Found ${models.length} local models');
          
          // Check if our preferred model is available
          final hasPreferredModel = models.any((model) => 
            model['name'].toString().startsWith(_modelName.split(':').first));
            
          if (!hasPreferredModel) {
            // Use first available model
            _modelName = models.first['name'];
            _logger?.call('📝 Using available model: $_modelName');
          }
          
          return true;
        }
      }
      
      return false;
    } catch (e) {
      _logger?.call('🔍 Local LLM connection test failed: $e');
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
    if (!_isReady) {
      _logger?.call('⚠️ Agent LLM service not ready');
      return null;
    }

    try {
      final startTime = DateTime.now();
      
      // Use real local LLM if available, otherwise fall back to mock
      Map<String, dynamic> response;
      String modelType;
      
      if (_useLocalApi) {
        response = await _realLLMProcess(context, availableTools);
        modelType = 'real_local_llm';
      } else {
        response = await _mockLLMProcess(context, availableTools);
        modelType = 'mock_llm';
      }
      
      final processingTime = DateTime.now().difference(startTime);
      final source = _useLocalApi ? "REAL" : "MOCK";
      _logger?.call('🧠 Agent LLM ($source) processed in ${processingTime.inMilliseconds}ms');
      
      return LLMResponse(
        content: response['content'] ?? '',
        toolCalls: _parseToolCalls(response['tool_calls'] ?? []),
        processingTime: processingTime,
        metadata: {
          'modelType': modelType,
          'modelName': _modelName,
          'contextLength': context.length,
          'availableTools': availableTools,
          'useLocalApi': _useLocalApi,
        },
      );
    } catch (e) {
      _logger?.call('❌ Agent LLM processing error: $e');
      // Fall back to mock if real LLM fails
      try {
        final mockResponse = await _mockLLMProcess(context, availableTools);
        return LLMResponse(
          content: mockResponse['content'] ?? '',
          toolCalls: _parseToolCalls(mockResponse['tool_calls'] ?? []),
          processingTime: const Duration(milliseconds: 100),
          metadata: {'modelType': 'fallback_mock'},
        );
      } catch (mockError) {
        return null;
      }
    }
  }

  /// Real local LLM processing using Ollama or similar API
  Future<Map<String, dynamic>> _realLLMProcess(String context, List<String> availableTools) async {
    try {
      // Construct prompt with tool calling instructions
      final systemPrompt = _buildSystemPrompt(availableTools);
      final fullPrompt = '$systemPrompt\n\nUser Context: $context\n\nPlease respond with your analysis and any tool calls needed.';
      
      // Call local LLM API (Ollama format)
      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': _modelName,
          'prompt': fullPrompt,
          'stream': false,
          'options': {
            'temperature': 0.3,
            'top_p': 0.9,
            'max_tokens': 500,
          },
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final generatedText = data['response'] ?? '';
        
        // Parse the response to extract content and tool calls
        return _parseRealLLMResponse(generatedText);
      } else {
        _logger?.call('❌ Local LLM API error: ${response.statusCode}');
        throw Exception('Local LLM API returned ${response.statusCode}');
      }
      
    } catch (e) {
      _logger?.call('❌ Real LLM processing failed: $e');
      rethrow;
    }
  }
  
  /// Build system prompt for tool calling
  String _buildSystemPrompt(List<String> availableTools) {
    final toolDescriptions = availableTools.map((tool) {
      switch (tool) {
        case 'store_memory':
          return '- store_memory(content, category): Store important information for later recall';
        case 'retrieve_memory':
          return '- retrieve_memory(query): Search for relevant stored information';
        case 'update_memory':
          return '- update_memory(id, content): Update existing stored information';
        case 'analyze_content':
          return '- analyze_content(type, content): Analyze content for insights';
        default:
          return '- $tool: Available tool';
      }
    }).join('\n');
    
    return '''You are an intelligent assistant integrated with Frame smart glasses. You help process user interactions and visual content.

Available tools:
$toolDescriptions

When you need to use a tool, format it like this:
TOOL_CALL: tool_name(parameter1="value1", parameter2="value2")

Analyze the user context and determine if any tools should be called. Respond with your analysis and any necessary tool calls.''';
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
  Future<Map<String, dynamic>> _mockLLMProcess(String context, List<String> availableTools) async {
    // Simulate processing time
    await Future.delayed(Duration(milliseconds: 100 + context.length ~/ 10));
    
    // Simple rule-based mock responses with tool calling
    final contextLower = context.toLowerCase();
    
    // Determine appropriate response and tool calls based on context
    if (contextLower.contains('asr') && contextLower.contains('speech')) {
      return {
        'content': 'I detected speech content that should be stored for future reference.',
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
    } else if (contextLower.contains('confidence') && contextLower.contains('high')) {
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
    } else if (contextLower.contains('query') || contextLower.contains('search')) {
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
        'content': 'I\'ve processed this information and determined it should be stored.',
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
    final importantWords = words.where((word) => 
      word.length > 3 && 
      !['the', 'and', 'for', 'are', 'but', 'not', 'you', 'all', 'can', 'had', 'was', 'one', 'our', 'out', 'day', 'get', 'has', 'him', 'his', 'how', 'its', 'may', 'new', 'now', 'old', 'see', 'two', 'way', 'who', 'boy', 'did', 'man', 'her', 'she', 'use', 'each', 'make', 'most', 'over', 'said', 'some', 'time', 'very', 'what', 'with', 'have', 'from', 'they', 'know', 'want', 'been', 'good', 'much', 'some', 'time', 'very', 'when', 'come', 'here', 'just', 'like', 'long', 'make', 'many', 'over', 'such', 'take', 'than', 'them', 'well', 'were'].contains(word)
    ).toList();
    
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
          parameters: Map<String, dynamic>.from(toolCallData['parameters'] ?? {}),
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
        'description': 'Store information in the vector database for future retrieval',
        'parameters': {
          'content': {'type': 'string', 'description': 'Content to store'},
          'category': {'type': 'string', 'description': 'Category of the content'},
          'priority': {'type': 'string', 'description': 'Priority level: low, medium, high'},
        },
      },
      {
        'name': 'retrieve_memory',
        'description': 'Retrieve relevant information from the vector database',
        'parameters': {
          'query': {'type': 'string', 'description': 'Search query'},
          'limit': {'type': 'integer', 'description': 'Maximum number of results'},
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
          'content_type': {'type': 'string', 'description': 'Type of content: text, image, audio'},
          'analysis_type': {'type': 'string', 'description': 'Type of analysis: semantic, sentiment, topic'},
        },
      },
    ];
  }

  /// Get service statistics
  Map<String, dynamic> getStatistics() {
    return {
      'isReady': _isReady,
      'modelType': 'mock_llm',
      'supportedTools': getToolDefinitions().map((tool) => tool['name']).toList(),
      'maxContextLength': 4096, // Mock value
    };
  }

  /// Dispose resources (doesn't affect main Gemini pipeline)
  void dispose() {
    _httpClient.close();
    _isReady = false;
    _useLocalApi = false;
    _logger?.call('🧹 Real Local LLM service disposed (agent-only)');
  }
}