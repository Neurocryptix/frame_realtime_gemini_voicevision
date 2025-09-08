import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:frame_realtime_gemini_voicevision/services/enhanced_rag_service.dart';
import 'package:frame_realtime_gemini_voicevision/services/rag_migration_service.dart';
import 'package:frame_realtime_gemini_voicevision/services/vector_db_service.dart';
import 'package:frame_realtime_gemini_voicevision/agent/services/enhanced_agent_service.dart';
import 'package:frame_realtime_gemini_voicevision/objectbox.g.dart';
import 'package:objectbox/objectbox.dart';
import 'dart:io';

void main() {
  group('Enhanced RAG System Tests', () {
    late Store store;
    late EnhancedRagService ragService;
    late VectorDbService oldVectorService;
    late RagMigrationService migrationService;
    late EnhancedAgentService agentService;
    
    List<String> testLogs = [];
    
    void testLogger(String message) {
      testLogs.add(message);
      print('[TEST LOG] $message');
    }

    setUpAll(() async {
      // Create a temporary directory for test database
      final testDir = Directory.systemTemp.createTempSync('enhanced_rag_test');
      
      // Initialize ObjectBox store
      store = await openStore(directory: testDir.path);
      
      // Initialize services
      ragService = EnhancedRagService(uiLogger: testLogger);
      oldVectorService = VectorDbService(testLogger);
      migrationService = RagMigrationService(logger: testLogger);
      
      // Initialize services
      await ragService.initialize(store);
      await oldVectorService.initialize(store);
      
      agentService = EnhancedAgentService(
        ragService: ragService,
        logger: testLogger,
      );
      await agentService.initialize();
      
      testLogs.clear(); // Clear setup logs
    });

    tearDownAll(() async {
      ragService.dispose();
      oldVectorService.dispose();
      agentService.dispose();
      store.close();
    });

    setUp(() {
      testLogs.clear();
    });

    test('Enhanced RAG Service Initialization', () async {
      expect(ragService.isInitialized, isTrue);
      
      final stats = await ragService.getStatistics();
      expect(stats['service'], equals('enhanced_rag'));
      expect(stats['embeddingDimension'], equals(768));
      expect(stats['hybridSearchEnabled'], isTrue);
      
      print('✅ Enhanced RAG service initialized successfully');
    });

    test('Fallback Embedding Generation', () async {
      // Test fallback embeddings (without Gemini API key)
      await ragService.addDocument(
        content: 'This is a test document for fallback embeddings',
        metadata: {'type': 'test', 'source': 'unit_test'},
      );

      final stats = await ragService.getStatistics();
      expect(stats['totalDocuments'], equals(1));
      expect(stats['documentsWithEmbeddings'], equals(1));
      
      print('✅ Fallback embedding generation works');
    });

    test('Semantic Search with Hybrid Scoring', () async {
      // Add test documents
      final testDocs = [
        {
          'content': 'Frame smart glasses provide augmented reality experiences',
          'metadata': {'type': 'product', 'category': 'hardware'},
        },
        {
          'content': 'Artificial intelligence enhances user interactions',
          'metadata': {'type': 'technology', 'category': 'software'},
        },
        {
          'content': 'Voice recognition enables hands-free control',
          'metadata': {'type': 'feature', 'category': 'input'},
        },
      ];

      for (final doc in testDocs) {
        await ragService.addDocument(
          content: doc['content'] as String,
          metadata: doc['metadata'] as Map<String, dynamic>,
        );
      }

      // Test semantic search
      final results = await ragService.semanticSearch(
        query: 'smart glasses augmented reality',
        limit: 2,
        similarityThreshold: 0.1,
        hybridSearch: true,
      );

      expect(results.length, greaterThan(0));
      expect(results.first['score'], greaterThan(0.0));
      expect(results.first['semanticScore'], greaterThan(0.0));
      
      print('✅ Semantic search with hybrid scoring works');
      print('   Found ${results.length} results');
      print('   Top score: ${((results.first['score'] as double) * 100).toStringAsFixed(1)}%');
    });

    test('Metadata Filtering', () async {
      // Clear previous test data
      await ragService.clearAll();
      
      // Add documents with different metadata
      await ragService.addDocument(
        content: 'Hardware component description',
        metadata: {'type': 'hardware', 'priority': 'high'},
      );
      
      await ragService.addDocument(
        content: 'Software feature explanation', 
        metadata: {'type': 'software', 'priority': 'medium'},
      );

      // Search with metadata filter
      final hardwareResults = await ragService.semanticSearch(
        query: 'component',
        limit: 10,
        similarityThreshold: 0.0,
        metadataFilter: {'type': 'hardware'},
      );

      expect(hardwareResults.length, equals(1));
      
      final metadata = hardwareResults.first['metadata'] as Map<String, dynamic>;
      expect(metadata['type'], equals('hardware'));
      
      print('✅ Metadata filtering works correctly');
    });

    test('Enhanced Agent Service Query Processing', () async {
      // Add some context documents
      await ragService.addDocument(
        content: 'Frame glasses are wearable AR devices with voice control',
        metadata: {'type': 'product_info', 'source': 'documentation'},
      );

      // Process a user query
      final agentOutput = await agentService.processQuery(
        query: 'What are Frame glasses?',
        storeQuery: true,
      );

      expect(agentOutput.query, equals('What are Frame glasses?'));
      expect(agentOutput.response.isNotEmpty, isTrue);
      expect(agentOutput.confidence, greaterThan(0.0));
      expect(agentOutput.processingTime.inMilliseconds, greaterThan(0));
      
      print('✅ Agent query processing works');
      print('   Response: ${agentOutput.response.substring(0, 50)}...');
      print('   Confidence: ${(agentOutput.confidence * 100).toStringAsFixed(1)}%');
    });

    test('ASR and OCR Output Storage', () async {
      final timestamp = DateTime.now();
      
      // Store ASR output
      await agentService.storeASROutput(
        text: 'Hello, this is a voice command',
        confidence: 0.85,
        timestamp: timestamp,
        additionalMetadata: {'language': 'en'},
      );

      // Store OCR output  
      await agentService.storeOCROutput(
        text: 'Some text extracted from an image',
        confidence: 0.92,
        timestamp: timestamp,
        additionalMetadata: {'source_image': 'frame_camera'},
      );

      // Search for ASR outputs
      final asrResults = await agentService.searchMemory(
        query: 'voice command',
        contentType: 'asr_output',
        limit: 5,
      );

      expect(asrResults.length, equals(1));
      
      final asrMetadata = asrResults.first['metadata'] as Map<String, dynamic>;
      expect(asrMetadata['type'], equals('asr_output'));
      expect(asrMetadata['confidence'], equals(0.85));
      
      print('✅ ASR/OCR output storage and retrieval works');
    });

    test('Batch Document Embedding', () async {
      await ragService.clearAll();
      
      final batchDocs = List.generate(5, (index) => {
        'content': 'Test document number ${index + 1} with unique content about topic $index',
        'metadata': {'type': 'batch_test', 'index': index, 'batch_id': 'test_batch_1'},
      });

      await ragService.batchEmbedDocuments(batchDocs);

      final stats = await ragService.getStatistics();
      expect(stats['totalDocuments'], equals(5));
      
      // Test that all documents are retrievable
      final results = await ragService.semanticSearch(
        query: 'test document',
        limit: 10,
        similarityThreshold: 0.1,
      );
      
      expect(results.length, equals(5));
      
      print('✅ Batch document embedding works');
    });

    test('Migration Service Functionality', () async {
      // Add some data to old service
      await oldVectorService.addSampleData();
      
      // Check migration need
      final needsMigration = await migrationService.isMigrationNeeded(
        oldVectorService,
        ragService,
      );
      
      expect(needsMigration, isTrue);
      
      // Note: Full migration test would require Gemini API key
      // For now, just test the migration need detection
      
      print('✅ Migration service detects migration need correctly');
    });

    test('Memory Search with Date Filtering', () async {
      await ragService.clearAll();
      
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      
      // Add document with specific timestamp
      await ragService.addDocument(
        content: 'Recent document',
        metadata: {
          'type': 'test',
          'timestamp': now.toIso8601String(),
        },
      );

      // Search with date filter
      final results = await agentService.searchMemory(
        query: 'document',
        fromDate: yesterday,
        toDate: now.add(const Duration(hours: 1)),
      );

      expect(results.length, equals(1));
      
      print('✅ Date-filtered memory search works');
    });

    test('Enhanced Statistics Generation', () async {
      final stats = await ragService.getStatistics();
      
      expect(stats.containsKey('totalDocuments'), isTrue);
      expect(stats.containsKey('documentsWithEmbeddings'), isTrue);
      expect(stats.containsKey('embeddingDimension'), isTrue);
      expect(stats.containsKey('hybridSearchEnabled'), isTrue);
      expect(stats.containsKey('typeDistribution'), isTrue);
      expect(stats.containsKey('modelDistribution'), isTrue);
      
      print('✅ Enhanced statistics generation works');
      print('   Total documents: ${stats['totalDocuments']}');
      print('   Embedding dimensions: ${stats['embeddingDimension']}');
    });

    test('Conversation Context Retrieval', () async {
      // Add conversational data
      await ragService.addDocument(
        content: 'User asked about Frame battery life',
        metadata: {'type': 'user_query'},
      );
      
      await ragService.addDocument(
        content: 'Frame battery lasts approximately 8 hours with normal use',
        metadata: {'type': 'agent_response'},
      );

      final context = await ragService.getConversationContext(
        query: 'battery life',
        maxResults: 3,
        threshold: 0.2,
        includeMetadata: true,
      );

      expect(context.contains('battery'), isTrue);
      expect(context.contains('Relevant context'), isTrue);
      
      print('✅ Conversation context retrieval works');
    });

    test('Error Handling and Resilience', () async {
      // Test with empty query
      final emptyResults = await ragService.semanticSearch(
        query: '',
        limit: 5,
        similarityThreshold: 0.5,
      );
      
      expect(emptyResults, isEmpty);
      
      // Test with very high threshold
      final noResults = await ragService.semanticSearch(
        query: 'test query',
        limit: 5,
        similarityThreshold: 0.99,
      );
      
      expect(noResults, isEmpty);
      
      print('✅ Error handling works correctly');
    });

    test('Service Integration Test', () async {
      // End-to-end test of the complete system
      await ragService.clearAll();
      
      // 1. Add initial knowledge
      await ragService.addDocument(
        content: 'Frame smart glasses enable AR experiences with voice and gesture control',
        metadata: {'type': 'product_manual', 'section': 'overview'},
      );
      
      // 2. Simulate user interaction
      final agentOutput = await agentService.processQuery(
        query: 'How do Frame glasses work?',
        context: {'session_id': 'test_session'},
      );
      
      // 3. Verify agent response
      expect(agentOutput.response.isNotEmpty, isTrue);
      expect(agentOutput.confidence, greaterThan(0.0));
      
      // 4. Check that query and response were stored
      final finalStats = await ragService.getStatistics();
      expect(finalStats['totalDocuments'], greaterThan(1)); // Original + query + response
      
      print('✅ End-to-end system integration works');
      print('   Final document count: ${finalStats['totalDocuments']}');
      print('   Agent confidence: ${(agentOutput.confidence * 100).toStringAsFixed(1)}%');
    });
  });
  
  group('Performance Tests', () {
    late Store store;
    late EnhancedRagService ragService;
    
    void perfLogger(String message) {
      print('[PERF] $message');
    }

    setUpAll(() async {
      final testDir = Directory.systemTemp.createTempSync('perf_test');
      store = await openStore(directory: testDir.path);
      ragService = EnhancedRagService(uiLogger: perfLogger);
      await ragService.initialize(store);
    });

    tearDownAll(() async {
      ragService.dispose();
      store.close();
    });

    test('Embedding Generation Performance', () async {
      final stopwatch = Stopwatch()..start();
      
      // Generate 10 embeddings
      for (int i = 0; i < 10; i++) {
        await ragService.addDocument(
          content: 'Performance test document number $i with some content to embed',
          metadata: {'type': 'performance_test', 'index': i},
          generateEmbedding: true,
        );
      }
      
      stopwatch.stop();
      final averageTime = stopwatch.elapsedMilliseconds / 10;
      
      print('✅ Average embedding time: ${averageTime.toStringAsFixed(1)}ms per document');
      
      // Should be reasonably fast (under 1 second per document for fallback)
      expect(averageTime, lessThan(1000));
    });

    test('Search Performance with Large Dataset', () async {
      await ragService.clearAll();
      
      // Add many documents
      final docs = List.generate(50, (i) => {
        'content': 'Document $i contains information about topic ${i % 10} with additional details',
        'metadata': {'type': 'large_test', 'topic': i % 10, 'index': i},
      });
      
      final addStartTime = DateTime.now();
      await ragService.batchEmbedDocuments(docs);
      final addDuration = DateTime.now().difference(addStartTime);
      
      print('Added ${docs.length} documents in ${addDuration.inMilliseconds}ms');
      
      // Test search performance
      final searchStartTime = DateTime.now();
      final results = await ragService.semanticSearch(
        query: 'topic information',
        limit: 10,
        similarityThreshold: 0.1,
        hybridSearch: true,
      );
      final searchDuration = DateTime.now().difference(searchStartTime);
      
      print('Search completed in ${searchDuration.inMilliseconds}ms');
      print('Found ${results.length} results');
      
      // Search should be fast (under 500ms for 50 documents)
      expect(searchDuration.inMilliseconds, lessThan(500));
      expect(results.length, greaterThan(0));
    });
  });
}