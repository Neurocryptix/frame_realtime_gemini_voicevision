import 'dart:async';
import '../interfaces/ai_edge_interfaces.dart';

/// AI Edge Agent Service
/// Pure Google AI Edge implementation that integrates with your existing agent architecture
/// Uses MediaPipe GenAI for all processing - no external dependencies
class AIEdgeAgentService {
  final AIEdgeRagService _ragService;
  final void Function(String)? _logger;
  bool _isInitialized = false;

  AIEdgeAgentService({
    required AIEdgeRagService ragService,
    void Function(String)? logger,
  })  : _ragService = ragService,
        _logger = logger;

  /// Initialize the AI Edge Agent service
  Future<bool> initialize() async {
    try {
      _logger?.call('🚀 Initializing AI Edge Agent Service...');

      if (!_ragService.isReady) {
        _logger?.call('❌ AI Edge RAG service not initialized');
        return false;
      }

      _isInitialized = true;
      _logger?.call('✅ AI Edge Agent Service ready (pure Google AI Edge)');
      return true;
    } catch (e) {
      _logger?.call('❌ AI Edge Agent Service initialization failed: $e');
      return false;
    }
  }

  /// Process user query with AI Edge RAG enhancement
  /// This completely replaces your old database pipeline with Google AI Edge
  Future<AIEdgeAgentOutput> processQuery({
    required String query,
    Map<String, dynamic>? context,
    bool storeQuery = true,
  }) async {
    if (!_isInitialized) {
      throw Exception('AI Edge Agent Service not initialized');
    }

    final startTime = DateTime.now();

    try {
      _logger?.call('🧠 Processing query with Google AI Edge RAG...');

      // Step 1: Store the user query in AI Edge RAG (if requested)
      if (storeQuery) {
        await _ragService.addDocument(
          content: query,
          metadata: {
            'type': 'user_query',
            'source': 'ai_edge_agent',
            'timestamp': startTime.toIso8601String(),
            'context': context?.toString() ?? 'none',
          },
        );
      }

      // Step 2: Use AI Edge RAG for enhanced response generation
      final searchResults = await _ragService.search(
        query: query,
        topK: 5,
        threshold: 0.3,
      );

      // Step 3: Store the AI Edge response
      final responseContent = searchResults.isNotEmpty 
        ? 'AI Edge found ${searchResults.length} relevant documents for query: $query'
        : 'No relevant documents found for query: $query';
        
      await _ragService.addDocument(
        content: responseContent,
        metadata: {
          'type': 'agent_response',
          'source': 'ai_edge_agent',
          'originalQuery': query,
          'timestamp': DateTime.now().toIso8601String(),
          'documentsUsed': searchResults.length,
        },
      );

      final totalProcessingTime = DateTime.now().difference(startTime);
      _logger?.call('✅ AI Edge processing completed in ${totalProcessingTime.inMilliseconds}ms');

      // Create AIEdgeRagResponse from search results
      final ragResponse = AIEdgeRagResponse(
        documents: searchResults.map((result) => RagDocument(
          id: result['id'] as String? ?? '',
          content: result['content'] as String? ?? '',
          metadata: result['metadata'] as Map<String, dynamic>? ?? {},
          timestamp: DateTime.tryParse(result['timestamp'] as String? ?? '') ?? DateTime.now(),
        )).toList(),
        query: query,
        totalResults: searchResults.length,
        processingTime: totalProcessingTime,
      );

      return AIEdgeAgentOutput(
        query: query,
        response: responseContent,
        relevantContext: _buildContextSummary(ragResponse.documents),
        confidence: _calculateConfidence(ragResponse.documents),
        processingTime: totalProcessingTime,
        timestamp: startTime,
        ragResponse: ragResponse,
        metadata: {
          'aiEdgeProcessing': true,
          'ragEnabled': true,
          'contextDocuments': ragResponse.documents.length,
          'model': 'gemma-3n-ai-edge',
          'processingMode': 'on_device',
        },
      );

    } catch (e) {
      _logger?.call('❌ AI Edge query processing failed: $e');
      
      return AIEdgeAgentOutput(
        query: query,
        response: 'I encountered an error processing your query with AI Edge. Please try again.',
        relevantContext: '',
        confidence: 0.0,
        processingTime: DateTime.now().difference(startTime),
        timestamp: startTime,
        ragResponse: null,
        metadata: {'error': e.toString(), 'aiEdgeProcessing': false},
      );
    }
  }

  /// Store ASR output using AI Edge RAG
  Future<void> storeASROutput({
    required String text,
    required double confidence,
    required DateTime timestamp,
    Map<String, dynamic>? additionalMetadata,
  }) async {
    await _ragService.addDocument(
      content: text,
      metadata: {
        'type': 'asr_output',
        'confidence': confidence,
        'timestamp': timestamp.toIso8601String(),
        ...?additionalMetadata,
      },
    );
    
    _logger?.call('🎤 Stored ASR in AI Edge RAG: ${_truncate(text)}');
  }

  /// Store OCR output using AI Edge RAG
  Future<void> storeOCROutput({
    required String text,
    required double confidence,
    required DateTime timestamp,
    Map<String, dynamic>? additionalMetadata,
  }) async {
    await _ragService.addDocument(
      content: text,
      metadata: {
        'type': 'ocr_output',
        'confidence': confidence,
        'timestamp': timestamp.toIso8601String(),
        ...?additionalMetadata,
      },
    );
    
    _logger?.call('👁️ Stored OCR in AI Edge RAG: ${_truncate(text)}');
  }

  /// Get AI Edge memory statistics
  Map<String, dynamic> getMemoryStatistics() {
    final ragStats = _ragService.getStatistics();
    
    return {
      ...ragStats,
      'agentService': 'ai_edge_agent',
      'isInitialized': _isInitialized,
      'integration': 'pure_google_ai_edge',
    };
  }

  /// Search AI Edge memory
  Future<List<RagDocument>> searchMemory({
    required String query,
    int limit = 10,
    double threshold = 0.3,
    String? contentType,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final searchResults = await _ragService.search(
        query: query,
        topK: limit,
        threshold: threshold,
      );

      var results = searchResults.map((result) => RagDocument(
        id: result['id'] as String? ?? '',
        content: result['content'] as String? ?? '',
        metadata: result['metadata'] as Map<String, dynamic>? ?? {},
        timestamp: DateTime.tryParse(result['timestamp'] as String? ?? '') ?? DateTime.now(),
      )).toList();

      // Apply content type filter
      if (contentType != null) {
        results = results.where((doc) => 
            doc.metadata['type'] == contentType).toList();
      }

      // Apply date range filter
      if (fromDate != null || toDate != null) {
        results = results.where((doc) {
          if (fromDate != null && doc.timestamp.isBefore(fromDate)) return false;
          if (toDate != null && doc.timestamp.isAfter(toDate)) return false;
          return true;
        }).toList();
      }

      _logger?.call('🔍 AI Edge memory search: found ${results.length} results');
      return results;
      
    } catch (e) {
      _logger?.call('❌ AI Edge memory search failed: $e');
      return [];
    }
  }

  /// Build context summary from relevant documents
  String _buildContextSummary(List<RagDocument> documents) {
    if (documents.isEmpty) {
      return 'No relevant context found in AI Edge knowledge base.';
    }

    final contextParts = documents.map((doc) {
      final type = doc.metadata['type'] ?? 'unknown';
      final source = doc.metadata['source'] ?? 'unknown';
      final content = doc.content.length > 100 
          ? '${doc.content.substring(0, 100)}...'
          : doc.content;
      
      return '[$type | $source] $content';
    });

    return 'AI Edge Context (${documents.length} sources):\n${contextParts.join('\n')}';
  }

  /// Calculate confidence based on AI Edge retrieval quality
  double _calculateConfidence(List<RagDocument> documents) {
    if (documents.isEmpty) return 0.3;

    // Higher confidence with more relevant documents and higher confidence ASR/OCR
    double totalConfidence = 0.0;
    int confidenceCount = 0;

    for (final doc in documents) {
      if (doc.metadata['confidence'] != null) {
        totalConfidence += doc.metadata['confidence'] as double;
        confidenceCount++;
      }
    }

    if (confidenceCount > 0) {
      final avgConfidence = totalConfidence / confidenceCount;
      // Scale based on number of documents and average confidence
      return (avgConfidence + (documents.length * 0.1)).clamp(0.0, 1.0);
    }

    // Base confidence on number of relevant documents
    if (documents.length >= 3) return 0.8;
    if (documents.length >= 2) return 0.6;
    return 0.4;
  }

  /// Truncate text for logging
  String _truncate(String text, {int maxLength = 50}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// Check if service is ready
  bool get isReady => _isInitialized;

  /// Get underlying AI Edge RAG service
  AIEdgeRagService get ragService => _ragService;

  /// Dispose resources
  void dispose() {
    _isInitialized = false;
    _logger?.call('🧹 AI Edge Agent Service disposed');
  }
}

/// AI Edge Agent Output model
class AIEdgeAgentOutput {
  final String query;
  final String response;
  final String relevantContext;
  final double confidence;
  final Duration processingTime;
  final DateTime timestamp;
  final AIEdgeRagResponse? ragResponse;
  final Map<String, dynamic> metadata;

  AIEdgeAgentOutput({
    required this.query,
    required this.response,
    required this.relevantContext,
    required this.confidence,
    required this.processingTime,
    required this.timestamp,
    this.ragResponse,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'query': query,
    'response': response,
    'relevantContext': relevantContext,
    'confidence': confidence,
    'processingTimeMs': processingTime.inMilliseconds,
    'timestamp': timestamp.toIso8601String(),
    'ragResponse': ragResponse?.toJson(),
    'metadata': metadata,
  };

  @override
  String toString() => 'AIEdgeAgentOutput(query: $query, confidence: $confidence)';
}