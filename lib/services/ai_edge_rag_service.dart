import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:mediapipe_core/mediapipe_core.dart';
import 'package:mediapipe_genai/mediapipe_genai.dart';

/// Pure Google AI Edge RAG Service
/// Uses Google's official AI Edge RAG implementation with MediaPipe GenAI
/// Replaces the entire database pipeline with Google's edge computing solution
class AIEdgeRagService {
  // AI Edge components
  LlmInferenceEngine? _engine;
  bool _isInitialized = false;
  bool _isModelDownloading = false;
  String? _modelPath;
  
  // Configuration
  static const String _gemmaModelUrl = 'YOUR_KAGGLE_MODEL_URL'; // Must be provided by user
  static const String _gemmaModelName = 'gemma-3n-2b-it-int4.bin';
  
  // RAG memory storage (in-memory for AI Edge processing)
  final List<RagDocument> _ragDocuments = [];
  
  final void Function(String msg) _emit;

  AIEdgeRagService({void Function(String msg)? logger})
      : _emit = logger ?? ((_) {});

  /// Initialize the AI Edge RAG service
  Future<bool> initialize({String? modelUrl, bool downloadModel = true}) async {
    try {
      _emit('🚀 Initializing Google AI Edge RAG Service...');
      
      // Check platform compatibility
      if (!_isPlatformSupported()) {
        _emit('❌ Platform not supported. Requires Android/iOS/macOS with adequate specs');
        return false;
      }

      // Setup model path
      final appDir = await getApplicationDocumentsDirectory();
      _modelPath = '${appDir.path}/$_gemmaModelName';

      // Download or verify model
      if (downloadModel && modelUrl != null) {
        final downloadSuccess = await _downloadGemmaModel(modelUrl);
        if (!downloadSuccess) {
          _emit('❌ Model download failed');
          return false;
        }
      } else if (!await File(_modelPath!).exists()) {
        _emit('⚠️ Model not found. Please provide model URL for download');
        return false;
      }

      // Initialize MediaPipe GenAI engine
      await _initializeEngine();
      
      if (_engine != null) {
        _isInitialized = true;
        _emit('✅ Google AI Edge RAG Service initialized successfully');
        _emit('🧠 Using Gemma 3 model for on-device RAG processing');
        return true;
      } else {
        _emit('❌ Failed to initialize AI Edge engine');
        return false;
      }

    } catch (e) {
      _emit('❌ AI Edge RAG initialization failed: $e');
      return false;
    }
  }

  /// Check if the current platform is supported by AI Edge
  bool _isPlatformSupported() {
    if (Platform.isAndroid || Platform.isIOS) {
      // Note: Requires Pixel 7+ or iPhone 13+ for optimal performance
      return true;
    } else if (Platform.isMacOS) {
      return true;
    }
    return false;
  }

  /// Download Gemma model from provided URL
  Future<bool> _downloadGemmaModel(String modelUrl) async {
    if (_isModelDownloading) {
      _emit('⏳ Model download already in progress...');
      return false;
    }

    try {
      _isModelDownloading = true;
      _emit('📥 Downloading Gemma 3 model from AI Edge repository...');
      _emit('🌐 URL: ${modelUrl.length > 50 ? '${modelUrl.substring(0, 50)}...' : modelUrl}');

      final response = await http.get(Uri.parse(modelUrl));
      
      if (response.statusCode == 200) {
        final file = File(_modelPath!);
        await file.writeAsBytes(response.bodyBytes);
        
        final fileSizeMB = (response.bodyBytes.length / (1024 * 1024)).toStringAsFixed(2);
        _emit('✅ Model downloaded successfully: ${fileSizeMB}MB');
        return true;
      } else {
        _emit('❌ Download failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _emit('❌ Model download error: $e');
      return false;
    } finally {
      _isModelDownloading = false;
    }
  }

  /// Initialize MediaPipe GenAI engine
  Future<void> _initializeEngine() async {
    try {
      _emit('🔧 Initializing MediaPipe GenAI engine...');

      // Configure AI Edge LLM options for RAG processing
      final options = LlmInferenceOptions.cpu(
        modelPath: _modelPath!,
        maxTokens: 2048,
        randomSeed: 42,
        // RAG-specific configurations
        loraPath: null, // Optional LoRA adaptation
      );

      // Create the AI Edge inference engine
      _engine = LlmInferenceEngine(options);
      
      _emit('✅ MediaPipe GenAI engine initialized');
      _emit('🎯 RAG processing ready with Gemma 3 model');
      
    } catch (e) {
      _emit('❌ Engine initialization failed: $e');
      _engine = null;
      rethrow;
    }
  }

  /// Store document in AI Edge RAG system
  Future<void> storeDocument({
    required String content,
    required Map<String, dynamic> metadata,
  }) async {
    if (!_isInitialized || _engine == null) {
      throw Exception('AI Edge RAG service not initialized');
    }

    try {
      final document = RagDocument(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: content,
        metadata: metadata,
        timestamp: DateTime.now(),
      );

      // Store in memory for AI Edge processing
      _ragDocuments.add(document);
      
      final contentPreview = content.length > 60 
          ? '${content.substring(0, 60)}...'
          : content;
      
      _emit('📝 Stored document in AI Edge RAG: "$contentPreview"');
      _emit('📊 Total documents: ${_ragDocuments.length}');
      
    } catch (e) {
      _emit('❌ Failed to store document: $e');
      rethrow;
    }
  }

  /// Perform RAG-enhanced query using Google AI Edge
  Future<AIEdgeRagResponse> queryWithRAG({
    required String query,
    int maxResults = 5,
    double similarityThreshold = 0.3,
  }) async {
    if (!_isInitialized || _engine == null) {
      throw Exception('AI Edge RAG service not initialized');
    }

    try {
      final startTime = DateTime.now();
      
      _emit('🔍 Processing RAG query: "${_truncate(query, 50)}"');

      // Step 1: Retrieve relevant documents using AI Edge semantic matching
      final relevantDocs = await _retrieveRelevantDocuments(
        query: query,
        maxResults: maxResults,
        threshold: similarityThreshold,
      );

      // Step 2: Build RAG context from retrieved documents
      final ragContext = _buildRagContext(relevantDocs);

      // Step 3: Generate AI Edge enhanced response
      final aiResponse = await _generateRAGResponse(query, ragContext);

      final processingTime = DateTime.now().difference(startTime);
      
      _emit('✅ RAG response generated in ${processingTime.inMilliseconds}ms');
      _emit('📚 Used ${relevantDocs.length} relevant documents');

      return AIEdgeRagResponse(
        query: query,
        response: aiResponse,
        relevantDocuments: relevantDocs,
        processingTime: processingTime,
        timestamp: startTime,
        metadata: {
          'documentsUsed': relevantDocs.length,
          'totalDocuments': _ragDocuments.length,
          'model': 'gemma-3n-ai-edge',
          'ragEnabled': true,
        },
      );

    } catch (e) {
      _emit('❌ RAG query failed: $e');
      rethrow;
    }
  }

  /// Retrieve relevant documents using AI Edge semantic understanding
  Future<List<RagDocument>> _retrieveRelevantDocuments({
    required String query,
    required int maxResults,
    required double threshold,
  }) async {
    try {
      // Use AI Edge engine for semantic document retrieval
      final retrievalPrompt = _buildRetrievalPrompt(query, _ragDocuments);
      
      final retrievalStream = _engine!.generateResponse(retrievalPrompt);
      final retrievalResponse = await retrievalStream.join();
      
      // Parse AI Edge response to identify relevant document IDs
      final relevantIds = _parseRetrievalResponse(retrievalResponse);
      
      // Return matching documents
      final relevantDocs = _ragDocuments
          .where((doc) => relevantIds.contains(doc.id))
          .take(maxResults)
          .toList();

      _emit('🎯 Retrieved ${relevantDocs.length} relevant documents via AI Edge');
      
      return relevantDocs;
    } catch (e) {
      _emit('⚠️ Retrieval failed, using fallback method: $e');
      return _fallbackDocumentRetrieval(query, maxResults);
    }
  }

  /// Build retrieval prompt for AI Edge semantic search
  String _buildRetrievalPrompt(String query, List<RagDocument> documents) {
    final docSummaries = documents.map((doc) {
      final preview = _truncate(doc.content, 100);
      return 'ID:${doc.id} - $preview';
    }).join('\n');

    return '''
You are a document retrieval system. Given the user query and available documents, identify the most relevant document IDs.

Query: "$query"

Available Documents:
$docSummaries

Task: Return only the IDs of the most relevant documents, separated by commas. Return up to 5 IDs.
Format: ID1,ID2,ID3

Response:''';
  }

  /// Parse AI Edge retrieval response to extract document IDs
  List<String> _parseRetrievalResponse(String response) {
    try {
      // Extract document IDs from AI Edge response
      final cleanResponse = response.replaceAll(RegExp(r'[^\d,]'), '');
      final ids = cleanResponse.split(',').where((id) => id.isNotEmpty).toList();
      return ids;
    } catch (e) {
      _emit('⚠️ Failed to parse retrieval response: $e');
      return [];
    }
  }

  /// Fallback document retrieval using keyword matching
  List<RagDocument> _fallbackDocumentRetrieval(String query, int maxResults) {
    final queryWords = query.toLowerCase().split(' ').where((w) => w.length > 2);
    
    final scoredDocs = _ragDocuments.map((doc) {
      final contentWords = doc.content.toLowerCase().split(' ');
      int score = 0;
      
      for (final queryWord in queryWords) {
        score += contentWords.where((w) => w.contains(queryWord)).length;
      }
      
      return {'doc': doc, 'score': score};
    }).where((item) => item['score']! > 0).toList();

    scoredDocs.sort((a, b) => (b['score']! as int).compareTo(a['score']! as int));
    
    return scoredDocs
        .take(maxResults)
        .map((item) => item['doc']! as RagDocument)
        .toList();
  }

  /// Build RAG context from relevant documents
  String _buildRagContext(List<RagDocument> relevantDocs) {
    if (relevantDocs.isEmpty) {
      return 'No relevant documents found in knowledge base.';
    }

    final contextParts = relevantDocs.map((doc) {
      final timestamp = doc.timestamp.toIso8601String().substring(0, 19);
      final source = doc.metadata['source'] ?? 'unknown';
      return '[$timestamp | $source] ${doc.content}';
    });

    return 'Relevant Context:\n${contextParts.join('\n\n')}';
  }

  /// Generate RAG-enhanced response using AI Edge
  Future<String> _generateRAGResponse(String query, String context) async {
    final ragPrompt = '''
You are an intelligent assistant with access to a knowledge base. Use the provided context to answer the user's question accurately and helpfully.

Context Information:
$context

User Question: $query

Instructions:
- Use the context information to provide a comprehensive answer
- If the context doesn't contain relevant information, say so clearly
- Be concise but thorough
- Maintain a helpful and professional tone

Answer:''';

    try {
      final responseStream = _engine!.generateResponse(ragPrompt);
      final response = await responseStream.join();
      
      return response.trim();
    } catch (e) {
      _emit('❌ Response generation failed: $e');
      return 'I apologize, but I encountered an error while processing your query. Please try again.';
    }
  }

  /// Store ASR output in AI Edge RAG
  Future<void> storeASROutput({
    required String text,
    required double confidence,
    required DateTime timestamp,
  }) async {
    await storeDocument(
      content: text,
      metadata: {
        'type': 'asr_output',
        'confidence': confidence,
        'source': 'frame_microphone',
        'timestamp': timestamp.toIso8601String(),
        'processingType': 'ai_edge_rag',
      },
    );
  }

  /// Store OCR output in AI Edge RAG  
  Future<void> storeOCROutput({
    required String text,
    required double confidence,
    required DateTime timestamp,
  }) async {
    await storeDocument(
      content: text,
      metadata: {
        'type': 'ocr_output',
        'confidence': confidence,
        'source': 'frame_camera',
        'timestamp': timestamp.toIso8601String(),
        'processingType': 'ai_edge_rag',
      },
    );
  }

  /// Get AI Edge RAG statistics
  Map<String, dynamic> getStatistics() {
    final docTypes = <String, int>{};
    double totalConfidence = 0;
    int confidenceCount = 0;

    for (final doc in _ragDocuments) {
      final type = doc.metadata['type']?.toString() ?? 'unknown';
      docTypes[type] = (docTypes[type] ?? 0) + 1;

      if (doc.metadata['confidence'] != null) {
        totalConfidence += doc.metadata['confidence'] as double;
        confidenceCount++;
      }
    }

    return {
      'isInitialized': _isInitialized,
      'totalDocuments': _ragDocuments.length,
      'documentTypes': docTypes,
      'averageConfidence': confidenceCount > 0 ? totalConfidence / confidenceCount : 0.0,
      'modelPath': _modelPath,
      'modelDownloading': _isModelDownloading,
      'platform': Platform.operatingSystem,
      'ragSystem': 'google_ai_edge',
      'model': 'gemma-3n',
      'processingMode': 'on_device',
    };
  }

  /// Clear all RAG documents
  void clearDocuments() {
    _ragDocuments.clear();
    _emit('🗑️ Cleared all AI Edge RAG documents');
  }

  /// Add sample data for testing
  Future<void> addSampleData() async {
    final sampleDocs = [
      {
        'content': 'Frame smart glasses provide immersive AR experiences with voice control and real-time visual processing',
        'metadata': {'type': 'product_info', 'source': 'documentation'},
      },
      {
        'content': 'Google AI Edge enables on-device AI processing for privacy and performance',
        'metadata': {'type': 'technology', 'source': 'ai_edge_docs'},
      },
      {
        'content': 'Gemma 3 models support multimodal processing including text, images, and audio',
        'metadata': {'type': 'model_info', 'source': 'model_specs'},
      },
      {
        'content': 'MediaPipe GenAI provides RAG capabilities for enhanced AI responses',
        'metadata': {'type': 'framework', 'source': 'mediapipe_docs'},
      },
    ];

    for (final docData in sampleDocs) {
      await storeDocument(
        content: docData['content'] as String,
        metadata: docData['metadata'] as Map<String, dynamic>,
      );
    }

    _emit('📝 Added ${sampleDocs.length} sample documents to AI Edge RAG');
  }

  /// Truncate text for display
  String _truncate(String text, int maxLength) {
    return text.length <= maxLength ? text : '${text.substring(0, maxLength)}...';
  }

  /// Check if service is ready
  bool get isInitialized => _isInitialized;

  /// Dispose resources
  void dispose() {
    _engine?.close();
    _engine = null;
    _isInitialized = false;
    _ragDocuments.clear();
    _emit('🧹 AI Edge RAG service disposed');
  }
}

/// RAG Document model for AI Edge processing
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'metadata': metadata,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// AI Edge RAG Response model
class AIEdgeRagResponse {
  final String query;
  final String response;
  final List<RagDocument> relevantDocuments;
  final Duration processingTime;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  AIEdgeRagResponse({
    required this.query,
    required this.response,
    required this.relevantDocuments,
    required this.processingTime,
    required this.timestamp,
    required this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'query': query,
    'response': response,
    'relevantDocuments': relevantDocuments.map((doc) => doc.toJson()).toList(),
    'processingTimeMs': processingTime.inMilliseconds,
    'timestamp': timestamp.toIso8601String(),
    'metadata': metadata,
  };
}