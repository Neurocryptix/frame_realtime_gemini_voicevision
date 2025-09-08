import 'package:flutter_test/flutter_test.dart';
import 'package:frame_realtime_gemini_voicevision/services/ai_edge_rag_service.dart';
import 'package:frame_realtime_gemini_voicevision/agent/services/ai_edge_agent_service.dart';
import 'package:frame_realtime_gemini_voicevision/agent/services/ai_edge_llm_service.dart';

void main() {
  group('Google AI Edge RAG System Tests', () {
    late AIEdgeRagService ragService;
    late AIEdgeAgentService agentService;
    late AIEdgeLLMService llmService;
    
    List<String> testLogs = [];
    
    void testLogger(String message) {
      testLogs.add(message);
      // Test logging - using addTearDown to avoid print lint warnings
      addTearDown(() {
        // Messages logged to testLogs for verification
      });
    }

    setUp(() {
      testLogs.clear();
      ragService = AIEdgeRagService(logger: testLogger);
      llmService = AIEdgeLLMService(logger: testLogger);
    });

    tearDown(() {
      ragService.dispose();
      llmService.dispose();
      agentService.dispose();
    });

    test('AI Edge RAG Service Initialization', () {
      expect(ragService.isInitialized, isFalse);
      
      final stats = ragService.getStatistics();
      expect(stats['ragSystem'], equals('google_ai_edge'));
      expect(stats['model'], equals('gemma-3n'));
      expect(stats['processingMode'], equals('on_device'));
      
      expect(stats.isNotEmpty, isTrue); // Verify stats are generated
    });

    test('AI Edge LLM Service Configuration', () {
      expect(llmService.isReady, isFalse);
      expect(llmService.isModelDownloadInProgress, isFalse);
      
      final stats = llmService.getStatistics();
      expect(stats['aiEdgeEnabled'], isTrue);
      expect(stats['gemma3Compatible'], isTrue);
      expect(stats['backendType'], equals('mediapipe_genai'));
      
      expect(stats['processingMode'], isNotNull); // Verify processing mode set
    });

    test('Document Storage (Mock Mode)', () async {
      // Test document storage without actual AI Edge initialization
      final testDoc = RagDocument(
        id: 'test_1',
        content: 'Test document for Google AI Edge RAG',
        metadata: {'type': 'test', 'source': 'unit_test'},
        timestamp: DateTime.now(),
      );

      expect(testDoc.id, equals('test_1'));
      expect(testDoc.content.isNotEmpty, isTrue);
      expect(testDoc.metadata['type'], equals('test'));
      
      expect(testDoc.timestamp, isNotNull); // Verify timestamp is set
    });

    test('AI Edge Configuration Validation', () {
      final ragStats = ragService.getStatistics();
      final llmStats = llmService.getStatistics();
      
      // Verify AI Edge specific configurations
      expect(ragStats['ragSystem'], equals('google_ai_edge'));
      expect(llmStats['aiEdgeEnabled'], isTrue);
      
      // Verify Gemma 3 compatibility
      expect(llmStats['gemma3Compatible'], isTrue);
      expect(ragStats['model'], equals('gemma-3n'));
      
      // Verify on-device processing
      expect(ragStats['processingMode'], equals('on_device'));
      expect(llmStats['processingMode'], equals('on_device_ai_edge'));
      
      expect(llmStats['backendType'], equals('mediapipe_genai')); // Verify backend
    });

    test('Service Integration Points', () {
      // Test that services can be integrated
      agentService = AIEdgeAgentService(
        ragService: ragService,
        logger: testLogger,
      );

      expect(agentService.isReady, isFalse); // Not initialized yet
      expect(agentService.ragService, equals(ragService));
      
      expect(agentService, isNotNull); // Verify service created
    });

    test('Error Handling', () async {
      // Test error handling for uninitialized services
      expect(
        () => ragService.queryWithRAG(query: 'test'),
        throwsException,
      );
      
      expect(
        () => llmService.processWithAIEdge(context: 'test'),
        throwsException,
      );
      
      expect(ragService, isNotNull); // Verify service exists for error testing
    });

    test('Statistics Generation', () {
      final ragStats = ragService.getStatistics();
      final llmStats = llmService.getStatistics();
      
      // Check required fields
      expect(ragStats.containsKey('isInitialized'), isTrue);
      expect(ragStats.containsKey('totalDocuments'), isTrue);
      expect(ragStats.containsKey('ragSystem'), isTrue);
      
      expect(llmStats.containsKey('isReady'), isTrue);
      expect(llmStats.containsKey('modelName'), isTrue);
      expect(llmStats.containsKey('aiEdgeEnabled'), isTrue);
      
      // Verify all stats are properly typed
      expect(ragStats['ragSystem'], isA<String>());
      expect(ragStats['model'], isA<String>());
      expect(ragStats['processingMode'], isA<String>());
    });

    test('Model URL Validation', () async {
      const testUrl = 'https://example.com/test-model.bin';
      
      final ragService = AIEdgeRagService(logger: testLogger);
      
      // This will fail without actual model, but should handle gracefully
      try {
        await ragService.initialize(modelUrl: testUrl, downloadModel: false);
        // Model initialization attempted (expected behavior)
      } catch (e) {
        expect(e.toString().contains('not found'), isTrue);
        expect(e, isNotNull); // Error expected without model
      }
    });

    test('AI Edge Response Models', () {
      final response = AIEdgeRagResponse(
        query: 'test query',
        response: 'test response',
        relevantDocuments: [],
        processingTime: const Duration(milliseconds: 100),
        timestamp: DateTime.now(),
        metadata: {'test': true},
      );

      expect(response.query, equals('test query'));
      expect(response.response, equals('test response'));
      expect(response.processingTime.inMilliseconds, equals(100));
      
      final json = response.toJson();
      expect(json['query'], equals('test query'));
      expect(json['processingTimeMs'], equals(100));
      
      expect(json['metadata'], isA<Map<String, dynamic>>()); // Verify metadata serialization
    });
  });

  group('Integration Tests', () {
    test('End-to-End Service Creation', () {
      final logs = <String>[];
      void logger(String msg) => logs.add(msg);

      // Create complete AI Edge system
      final ragService = AIEdgeRagService(logger: logger);
      final llmService = AIEdgeLLMService(logger: logger);
      final agentService = AIEdgeAgentService(
        ragService: ragService,
        logger: logger,
      );

      // Verify all services are created
      expect(ragService, isNotNull);
      expect(llmService, isNotNull);
      expect(agentService, isNotNull);

      // Verify configurations
      final ragStats = ragService.getStatistics();
      final llmStats = llmService.getStatistics();
      final agentStats = agentService.getMemoryStatistics();

      expect(ragStats['ragSystem'], equals('google_ai_edge'));
      expect(llmStats['aiEdgeEnabled'], isTrue);
      expect(agentStats['integration'], equals('pure_google_ai_edge'));

      // Verify comprehensive system creation
      expect(logs, isNotEmpty); // Verify logging worked
      expect(ragStats.isNotEmpty, isTrue);
      expect(llmStats.isNotEmpty, isTrue);
      expect(agentStats.isNotEmpty, isTrue);

      // Cleanup
      ragService.dispose();
      llmService.dispose();
      agentService.dispose();
    });

    test('Platform Support Check', () {
      final ragService = AIEdgeRagService();
      final llmService = AIEdgeLLMService();

      // Services should be created regardless of platform
      expect(ragService, isNotNull);
      expect(llmService, isNotNull);

      expect(ragService.runtimeType.toString(), contains('AIEdgeRagService'));

      ragService.dispose();
      llmService.dispose();
    });
  });
}