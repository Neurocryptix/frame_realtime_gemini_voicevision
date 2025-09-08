import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
// Removed flutter_gemini - using google_generative_ai instead
import 'package:objectbox/objectbox.dart';
import 'package:frame_realtime_gemini_voicevision/model/document_entity.dart';
import 'package:frame_realtime_gemini_voicevision/objectbox.g.dart';

/// Enhanced RAG Service compatible with Gemma 3
/// Uses flutter_gemini for embeddings instead of MobileBERT
/// Maintains ObjectBox for vector storage while improving search capabilities
class EnhancedRagService {
  late final Box<Document> _box;
  late final Store _store;
  // Using Google Generative AI instead of flutter_gemini

  bool _isInitialized = false;

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;
  String? _geminiApiKey;
  
  // Enhanced embedding configuration - using fallback dimensions to match existing ObjectBox setup
  static const int embeddingDimension = 384; // Match existing ObjectBox setup, will adjust dynamically
  static const String embeddingModel = 'models/embedding-001';
  
  final void Function(String msg) _emit;

  EnhancedRagService({void Function(String msg)? uiLogger})
      : _emit = uiLogger ?? ((_) {});

  /// Initialize the enhanced RAG service
  Future<void> initialize(Store store, {String? geminiApiKey}) async {
    try {
      _store = store;
      _box = _store.box<Document>();
      _geminiApiKey = geminiApiKey;

      // Test Gemini API connectivity for embeddings
      if (_geminiApiKey != null && _geminiApiKey!.isNotEmpty) {
        await _testGeminiEmbedding();
        _emit('✅ Enhanced RAG initialized with Gemini embeddings (docs: ${_box.count()})');
      } else {
        _emit('⚠️ Enhanced RAG initialized without API key - using fallback embeddings');
      }

      _isInitialized = true;
    } catch (e) {
      _emit('❌ Enhanced RAG initialization failed: $e');
      rethrow;
    }
  }

  /// Test Gemini embedding API
  Future<void> _testGeminiEmbedding() async {
    try {
      final testEmbedding = await _generateGeminiEmbedding('test text');
      if (testEmbedding.length == embeddingDimension) {
        _emit('✅ Gemini embedding API test successful ($embeddingDimension dims)');
      } else {
        _emit('⚠️ Unexpected embedding dimension: ${testEmbedding.length}');
      }
    } catch (e) {
      _emit('❌ Gemini embedding test failed: $e');
      rethrow;
    }
  }

  /// Generate embeddings using Gemini API
  Future<List<double>> _generateGeminiEmbedding(String text) async {
    try {
      if (_geminiApiKey == null || _geminiApiKey!.isEmpty) {
        return _generateFallbackEmbedding(text);
      }

      final embeddingResponse = await _gemini.embedContent(text);

      if (embeddingResponse != null && embeddingResponse.isNotEmpty) {
        final embedding = embeddingResponse.map((num) => num.toDouble()).toList();
        _emit('🧠 Generated Gemini embedding (${embedding.length} dims)');
        return embedding;
      } else {
        _emit('⚠️ Empty Gemini embedding response, using fallback');
        return _generateFallbackEmbedding(text);
      }
    } catch (e) {
      _emit('❌ Gemini embedding failed: $e, using fallback');
      return _generateFallbackEmbedding(text);
    }
  }

  /// Enhanced fallback embedding with better distribution
  List<double> _generateFallbackEmbedding(String text) {
    final words = text.toLowerCase().split(RegExp(r'\W+'));
    final embedding = List<double>.filled(embeddingDimension, 0.0);

    // Use multiple hash functions for better distribution
    for (int i = 0; i < words.length && i < 100; i++) {
      final word = words[i];
      if (word.isEmpty) continue;

      final hash1 = word.hashCode;
      final hash2 = word.split('').reversed.join('').hashCode;
      final hash3 = (word + i.toString()).hashCode;

      for (int j = 0; j < embeddingDimension; j++) {
        final seed = hash1 + hash2 * 31 + hash3 * 97 + i * 7 + j;
        final value = (seed % 10000) / 10000.0 - 0.5; // Range: -0.5 to 0.5
        embedding[j] += value * 0.1;
      }
    }

    // L2 normalization for better cosine similarity
    final norm = math.sqrt(embedding.map((x) => x * x).reduce((a, b) => a + b));
    if (norm > 0) {
      for (int i = 0; i < embedding.length; i++) {
        embedding[i] /= norm;
      }
    }

    return embedding;
  }

  /// Add document with enhanced metadata support
  Future<void> addDocument({
    required String content,
    required Map<String, dynamic> metadata,
    bool generateEmbedding = true,
  }) async {
    if (!_isInitialized) {
      throw Exception('Enhanced RAG service not initialized');
    }

    try {
      List<double> embedding = [];
      
      if (generateEmbedding) {
        final contentPreview = content.length > 50 
            ? '${content.substring(0, 50)}...'
            : content;
        _emit('🧠 Generating embedding for: "$contentPreview"');
        
        embedding = await _generateGeminiEmbedding(content);
      }

      // Enhanced metadata serialization
      final enhancedMetadata = {
        ...metadata,
        'addedAt': DateTime.now().toIso8601String(),
        'contentLength': content.length,
        'embeddingModel': _geminiApiKey != null ? 'gemini' : 'fallback',
        'embeddingDimensions': embedding.length,
      };

      final metadataString = _serializeMetadata(enhancedMetadata);

      final doc = Document(
        textContent: content,
        embedding: embedding.isNotEmpty ? embedding : null,
        createdAt: DateTime.now(),
        metadata: metadataString,
      );

      final docId = _box.put(doc);
      _emit('📝 Added document (ID: $docId, ${embedding.length} dims)');
    } catch (e) {
      _emit('❌ Failed to add document: $e');
      rethrow;
    }
  }

  /// Enhanced semantic search with multiple ranking factors
  Future<List<Map<String, Object?>>> semanticSearch({
    required String query,
    int limit = 10,
    double similarityThreshold = 0.3,
    Map<String, dynamic>? metadataFilter,
    bool hybridSearch = true,
  }) async {
    if (!_isInitialized) {
      throw Exception('Enhanced RAG service not initialized');
    }

    try {
      final queryPreview = query.length > 30 
          ? '${query.substring(0, 30)}...'
          : query;
      _emit('🔍 Semantic search: "$queryPreview"');

      // Generate query embedding
      final queryEmbedding = await _generateGeminiEmbedding(query);

      // Get all documents
      final allDocs = _box.getAll();
      final results = <Map<String, Object?>>[];

      for (final doc in allDocs) {
        if (doc.embedding == null || doc.embedding!.isEmpty) continue;

        // Parse metadata
        final metadata = _deserializeMetadata(doc.metadata);

        // Apply metadata filters
        if (metadataFilter != null && !_matchesFilter(metadata, metadataFilter)) {
          continue;
        }

        // Calculate semantic similarity
        final semanticScore = _cosineSimilarity(queryEmbedding, doc.embedding!);
        
        // Calculate lexical similarity for hybrid search
        double lexicalScore = 0.0;
        if (hybridSearch) {
          lexicalScore = _calculateLexicalSimilarity(query, doc.textContent);
        }

        // Combined scoring (80% semantic, 20% lexical)
        final combinedScore = hybridSearch 
            ? (semanticScore * 0.8 + lexicalScore * 0.2)
            : semanticScore;

        if (combinedScore >= similarityThreshold) {
          results.add({
            'id': doc.id,
            'document': doc.textContent,
            'score': combinedScore,
            'semanticScore': semanticScore,
            'lexicalScore': lexicalScore,
            'metadata': metadata,
            'createdAt': doc.createdAt?.toIso8601String(),
          });
        }
      }

      // Sort by combined score
      results.sort((a, b) => 
          (b['score'] as double).compareTo(a['score'] as double));

      final topResults = results.take(limit).toList();
      _emit('✅ Found ${topResults.length} relevant documents');
      
      return topResults;
    } catch (e) {
      _emit('❌ Semantic search failed: $e');
      return [];
    }
  }

  /// Calculate lexical similarity using token overlap
  double _calculateLexicalSimilarity(String query, String document) {
    final queryTokens = _tokenize(query.toLowerCase());
    final docTokens = _tokenize(document.toLowerCase());
    
    if (queryTokens.isEmpty || docTokens.isEmpty) return 0.0;

    final querySet = queryTokens.toSet();
    final docSet = docTokens.toSet();
    
    final intersection = querySet.intersection(docSet).length;
    final union = querySet.union(docSet).length;
    
    return union > 0 ? intersection / union : 0.0;
  }

  /// Simple tokenization
  List<String> _tokenize(String text) {
    return text
        .split(RegExp(r'\W+'))
        .where((token) => token.length > 2)
        .toList();
  }

  /// Enhanced cosine similarity with numerical stability
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    // Add small epsilon for numerical stability
    const epsilon = 1e-10;
    normA = math.sqrt(normA + epsilon);
    normB = math.sqrt(normB + epsilon);

    return dotProduct / (normA * normB);
  }

  /// Check if metadata matches filter criteria
  bool _matchesFilter(Map<String, dynamic> metadata, Map<String, dynamic> filter) {
    for (final filterEntry in filter.entries) {
      final key = filterEntry.key;
      final expectedValue = filterEntry.value;
      
      if (!metadata.containsKey(key)) return false;
      
      final actualValue = metadata[key];
      
      if (expectedValue is List) {
        if (!expectedValue.contains(actualValue)) return false;
      } else if (actualValue != expectedValue) {
        return false;
      }
    }
    return true;
  }

  /// Serialize metadata to string
  String _serializeMetadata(Map<String, dynamic> metadata) {
    return metadata.entries
        .map((e) => '${e.key}=${e.value}')
        .join('|');
  }

  /// Deserialize metadata from string
  Map<String, dynamic> _deserializeMetadata(String? metadataString) {
    if (metadataString == null || metadataString.isEmpty) {
      return <String, dynamic>{};
    }

    final metadata = <String, dynamic>{};
    final pairs = metadataString.split('|');
    
    for (final pair in pairs) {
      final keyValue = pair.split('=');
      if (keyValue.length == 2) {
        final key = keyValue[0];
        final value = keyValue[1];
        
        // Try to parse numbers and booleans
        if (value == 'true') {
          metadata[key] = true;
        } else if (value == 'false') {
          metadata[key] = false;
        } else if (double.tryParse(value) != null) {
          metadata[key] = double.parse(value);
        } else {
          metadata[key] = value;
        }
      }
    }
    
    return metadata;
  }

  /// Get enhanced conversation context with relevance ranking
  Future<String> getConversationContext({
    required String query,
    int maxResults = 5,
    double threshold = 0.4,
    bool includeMetadata = true,
  }) async {
    try {
      final results = await semanticSearch(
        query: query,
        limit: maxResults,
        similarityThreshold: threshold,
        hybridSearch: true,
      );

      if (results.isEmpty) {
        return 'No relevant conversation history found.';
      }

      final contextParts = <String>[];
      
      for (final result in results) {
        final score = result['score'] as double;
        final semanticScore = result['semanticScore'] as double;
        final content = result['document']?.toString() ?? '';
        final metadata = result['metadata'] as Map<String, dynamic>?;
        
        final scorePercent = (score * 100).round();
        final semanticPercent = (semanticScore * 100).round();
        
        var contextLine = '[$scorePercent%] $content';
        
        if (includeMetadata && metadata != null) {
          final type = metadata['type'] ?? 'unknown';
          final timestamp = metadata['timestamp'] ?? metadata['addedAt'];
          contextLine = '[$scorePercent% ($semanticPercent% semantic) | $type] $content';
        }
        
        contextParts.add(contextLine);
      }

      return 'Relevant context (hybrid search):\n${contextParts.join('\n')}';
    } catch (e) {
      _emit('❌ Failed to get conversation context: $e');
      return 'Error retrieving conversation context.';
    }
  }

  /// Get enhanced statistics
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final totalDocs = _box.count();
      final allDocs = _box.getAll();
      
      int docsWithEmbeddings = 0;
      int geminiEmbeddings = 0;
      int fallbackEmbeddings = 0;
      final typeDistribution = <String, int>{};
      final modelDistribution = <String, int>{};
      
      for (final doc in allDocs) {
        if (doc.embedding != null && doc.embedding!.isNotEmpty) {
          docsWithEmbeddings++;
          
          final metadata = _deserializeMetadata(doc.metadata);
          final embeddingModel = metadata['embeddingModel'] ?? 'unknown';
          
          if (embeddingModel == 'gemini') {
            geminiEmbeddings++;
          } else {
            fallbackEmbeddings++;
          }
          
          final currentCount = modelDistribution[embeddingModel] ?? 0;
          modelDistribution[embeddingModel] = currentCount + 1;
          
          final type = metadata['type'] ?? 'unknown';
          final typeCount = typeDistribution[type] ?? 0;
          typeDistribution[type] = typeCount + 1;
        }
      }

      return {
        'totalDocuments': totalDocs,
        'documentsWithEmbeddings': docsWithEmbeddings,
        'geminiEmbeddings': geminiEmbeddings,
        'fallbackEmbeddings': fallbackEmbeddings,
        'embeddingDimension': embeddingDimension,
        'embeddingModel': embeddingModel,
        'typeDistribution': typeDistribution,
        'modelDistribution': modelDistribution,
        'hasGeminiApiKey': _geminiApiKey != null && _geminiApiKey!.isNotEmpty,
        'hybridSearchEnabled': true,
        'service': 'enhanced_rag',
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Batch embed multiple documents
  Future<void> batchEmbedDocuments(List<Map<String, dynamic>> documents) async {
    if (!_isInitialized) {
      throw Exception('Enhanced RAG service not initialized');
    }

    try {
      _emit('📦 Batch embedding ${documents.length} documents...');
      
      for (int i = 0; i < documents.length; i++) {
        final docData = documents[i];
        final content = docData['content'] as String;
        final metadata = docData['metadata'] as Map<String, dynamic>? ?? {};
        
        await addDocument(
          content: content,
          metadata: {
            ...metadata,
            'batchIndex': i,
            'batchTotal': documents.length,
          },
        );
        
        // Small delay to avoid API rate limits
        if (_geminiApiKey != null) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        
        if ((i + 1) % 10 == 0) {
          _emit('📦 Processed ${i + 1}/${documents.length} documents');
        }
      }
      
      _emit('✅ Batch embedding completed');
    } catch (e) {
      _emit('❌ Batch embedding failed: $e');
      rethrow;
    }
  }

  /// Clear all documents
  Future<void> clearAll() async {
    try {
      final count = _box.count();
      _box.removeAll();
      _emit('🗑️ Cleared $count documents');
    } catch (e) {
      _emit('❌ Failed to clear documents: $e');
      rethrow;
    }
  }

  /// Update Gemini API key
  void updateApiKey(String apiKey) {
    _geminiApiKey = apiKey;
    _emit('🔑 Updated Gemini API key');
  }

  /// Dispose resources
  void dispose() {
    _isInitialized = false;
    _emit('🧹 Enhanced RAG service disposed');
  }
}