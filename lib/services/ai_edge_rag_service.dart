import 'dart:async';

// MediaPipe imports disabled for CI compatibility (requires Flutter master channel)
// When MediaPipe GenAI is available, uncomment these:
// import 'package:mediapipe_core/mediapipe_core.dart';
// import 'package:mediapipe_genai/mediapipe_genai.dart';

/// Simple document class for RAG functionality
class RagDocument {
  final String id;
  final String content;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;
  
  RagDocument({
    required this.id,
    required this.content, 
    required this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'metadata': metadata,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// AI Edge RAG Response class
class AIEdgeRagResponse {
  final String query;
  final String response;
  final List<RagDocument> relevantDocuments;
  final Duration processingTime;
  final DateTime timestamp;
  final double confidence;
  final Map<String, dynamic> metadata;
  
  AIEdgeRagResponse({
    required this.query,
    required this.response,
    required this.relevantDocuments,
    required this.processingTime,
    required this.confidence,
    DateTime? timestamp,
    this.metadata = const {},
  }) : timestamp = timestamp ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'query': query,
    'response': response,
    'relevantDocuments': relevantDocuments.map((d) => d.toJson()).toList(),
    'processingTimeMs': processingTime.inMilliseconds,
    'timestamp': timestamp.toIso8601String(),
    'confidence': confidence,
    'metadata': metadata,
  };
}

/// AI Edge RAG Service - STUB Implementation for CI Compatibility
/// 
/// This is a simplified stub that provides the RAG interface without MediaPipe dependencies.
/// For full AI Edge functionality with MediaPipe GenAI, the app requires:
/// - Flutter master channel
/// - MediaPipe GenAI package
/// - Native assets compilation
class AIEdgeRagService {
  // Service state
  bool _isInitialized = false;
  String? _modelPath;
  
  // In-memory document storage (stub)
  final List<RagDocument> _ragDocuments = [];
  
  final void Function(String msg) _emit;

  AIEdgeRagService({void Function(String msg)? logger})
      : _emit = logger ?? ((_) {});

  /// Initialize the AI Edge RAG service (stub)
  Future<bool> initialize({
    String? modelUrl,
    bool downloadModel = false,
  }) async {
    try {
      _emit('🚀 Initializing AI Edge RAG service (stub mode)');
      
      if (downloadModel && modelUrl != null) {
        _emit('📥 RAG model download requested: $modelUrl (stub - would download in real implementation)');
        _modelPath = modelUrl;
      }
      
      // Simulate initialization delay
      await Future.delayed(const Duration(milliseconds: 500));
      
      _isInitialized = true;
      _emit('✅ AI Edge RAG service ready (stub - MediaPipe disabled for CI)');
      return true;
      
    } catch (e) {
      _emit('❌ AI Edge RAG initialization failed: $e');
      return false;
    }
  }

  /// Add document to RAG index (stub)
  Future<void> addDocument({
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isInitialized) {
      throw StateError('Service not initialized');
    }

    final doc = RagDocument(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      metadata: metadata ?? {},
    );
    
    _ragDocuments.add(doc);
    _emit('📝 Document added to RAG index (stub): ${content.substring(0, 50)}...');
  }

  /// Query RAG documents (stub - simple text matching)
  Future<List<RagDocument>> queryDocuments({
    required String query,
    int maxResults = 5,
    double threshold = 0.3,
  }) async {
    if (!_isInitialized) {
      throw StateError('Service not initialized');
    }

    // Simple text matching (stub implementation)
    final results = _ragDocuments.where((doc) {
      return doc.content.toLowerCase().contains(query.toLowerCase());
    }).take(maxResults).toList();

    _emit('🔍 RAG query completed (stub): found ${results.length} matches');
    return results;
  }

  /// Store document (alias for addDocument)
  Future<void> storeDocument({
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    await addDocument(content: content, metadata: metadata);
  }

  /// Query with RAG response
  Future<AIEdgeRagResponse> queryWithRAG({
    required String query,
    int maxResults = 5,
    double similarityThreshold = 0.3,
  }) async {
    final startTime = DateTime.now();
    final documents = await queryDocuments(
      query: query,
      maxResults: maxResults,
      threshold: similarityThreshold,
    );

    final response = await generateResponse(prompt: query, context: documents);
    final processingTime = DateTime.now().difference(startTime);

    return AIEdgeRagResponse(
      query: query,
      response: response,
      relevantDocuments: documents,
      processingTime: processingTime,
      confidence: documents.isEmpty ? 0.3 : 0.8,
    );
  }

  /// Store ASR output
  Future<void> storeASROutput({
    required String text,
    required double confidence,
    required DateTime timestamp,
  }) async {
    await addDocument(
      content: text,
      metadata: {
        'type': 'asr_output',
        'confidence': confidence,
        'timestamp': timestamp.toIso8601String(),
      },
    );
  }

  /// Store OCR output
  Future<void> storeOCROutput({
    required String text,
    required double confidence,
    required DateTime timestamp,
  }) async {
    await addDocument(
      content: text,
      metadata: {
        'type': 'ocr_output',
        'confidence': confidence,
        'timestamp': timestamp.toIso8601String(),
      },
    );
  }

  /// Add sample data for testing
  Future<void> addSampleData() async {
    await addDocument(
      content: 'Sample document for AI Edge RAG testing',
      metadata: {'type': 'sample', 'source': 'test'},
    );
    _emit('📝 Sample data added to RAG service (stub)');
  }

  /// Clear documents (alias for clearAll)
  Future<void> clearDocuments() async {
    await clearAll();
  }

  /// Generate response with RAG context (stub)
  Future<String> generateResponse({
    required String prompt,
    List<RagDocument>? context,
  }) async {
    if (!_isInitialized) {
      throw StateError('Service not initialized');
    }

    // Stub response
    final contextInfo = context?.isNotEmpty == true 
        ? ' (with ${context!.length} context docs)' 
        : '';
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    final response = 'AI Edge RAG response (stub mode): "$prompt"$contextInfo\n\n'
        'Note: This is a stub implementation. Full MediaPipe GenAI functionality '
        'requires Flutter master channel and MediaPipe packages.';
    
    _emit('🤖 Generated AI Edge response (stub)');
    return response;
  }

  /// Get service statistics
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'totalDocuments': _ragDocuments.length,
      'ragSystem': 'ai_edge_stub',
      'model': 'stub_model',
      'processingMode': 'stub',
      'backendType': 'stub_mediapipe',
      'modelPath': _modelPath,
    };
  }

  /// Clear all documents
  Future<void> clearAll() async {
    _ragDocuments.clear();
    _emit('🗑️ All RAG documents cleared (stub)');
  }

  /// Dispose service
  void dispose() {
    _ragDocuments.clear();
    _isInitialized = false;
    _emit('🧹 AI Edge RAG service disposed (stub)');
  }

  /// Check if service is ready
  bool get isInitialized => _isInitialized;

  /// Get document count
  int get documentCount => _ragDocuments.length;
}