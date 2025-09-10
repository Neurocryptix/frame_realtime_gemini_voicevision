/// AI Edge interfaces for Google AI Edge compliance
library ai_edge_interfaces;

abstract class AIEdgeRagService {
  Future<bool> initialize({String? embeddingModelPath, String? vectorStorePath});
  Future<bool> addDocument({required String content, required Map<String, dynamic> metadata, String? documentId});
  Future<List<Map<String, dynamic>>> search({required String query, int topK = 5, double threshold = 0.3});
  Future<Map<String, dynamic>?> getDocument(String documentId);
  Future<bool> removeDocument(String documentId);
  int get documentCount;
  bool get isReady;
  Map<String, dynamic> getStatistics();
  void dispose();
  
  // Additional methods for example compatibility
  Future<void> addSampleData();
  Future<AIEdgeRagResponse> queryWithRAG({required String query, int maxResults = 5, double similarityThreshold = 0.3});
  Future<void> clearDocuments();
}

abstract class AIEdgeLLMService {
  Future<bool> initialize({required String modelPath, int maxTokens = 512, double temperature = 0.8, double topP = 0.95, int topK = 20, int randomSeed = 0});
  Future<String?> generateResponse(String prompt, {List<String>? stopSequences});
  Stream<String> generateResponseStream(String prompt);
  bool get isReady;
  Map<String, dynamic> getStatistics();
  void dispose();
}

class RagDocument {
  final String id;
  final String content;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  RagDocument({
    required this.id,
    required this.content,
    required this.metadata,
    required this.timestamp,
  });

  factory RagDocument.fromMap(Map<String, dynamic> map) {
    return RagDocument(
      id: map['id'] as String,
      content: map['content'] as String,
      metadata: Map<String, dynamic>.from(map['metadata'] as Map),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'metadata': metadata,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class AIEdgeRagResponse {
  final List<RagDocument> documents;
  final String query;
  final int totalResults;
  final Duration processingTime;

  AIEdgeRagResponse({
    required this.documents,
    required this.query,
    required this.totalResults,
    required this.processingTime,
  });

  // Compatibility getters
  List<RagDocument> get relevantDocuments => documents;
  String get response => documents.isNotEmpty 
    ? 'Found ${documents.length} relevant documents'
    : 'No relevant documents found';

  Map<String, dynamic> toJson() {
    return {
      'documents': documents.map((d) => d.toMap()).toList(),
      'query': query,
      'totalResults': totalResults,
      'processingTimeMs': processingTime.inMilliseconds,
    };
  }
}