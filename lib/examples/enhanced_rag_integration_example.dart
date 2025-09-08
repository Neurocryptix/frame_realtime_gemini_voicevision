import 'dart:async';
import 'package:flutter/material.dart';
// Removed flutter_gemini - using flutter_gemma instead
import 'package:frame_realtime_gemini_voicevision/services/enhanced_rag_service.dart';
import 'package:frame_realtime_gemini_voicevision/services/rag_migration_service.dart';
import 'package:frame_realtime_gemini_voicevision/services/vector_db_service.dart';
import 'package:frame_realtime_gemini_voicevision/agent/services/enhanced_agent_service.dart';
import 'package:frame_realtime_gemini_voicevision/objectbox.g.dart';

/// Example showing how to integrate the Enhanced RAG System
/// This demonstrates migration from old system to new Gemma 3 compatible RAG
class EnhancedRagIntegrationExample extends StatefulWidget {
  final String? geminiApiKey;
  
  const EnhancedRagIntegrationExample({
    super.key,
    this.geminiApiKey,
  });

  @override
  State<EnhancedRagIntegrationExample> createState() => _EnhancedRagIntegrationExampleState();
}

class _EnhancedRagIntegrationExampleState extends State<EnhancedRagIntegrationExample> {
  // Core services
  Store? _store;
  EnhancedRagService? _ragService;
  VectorDbService? _oldVectorService;
  RagMigrationService? _migrationService;
  EnhancedAgentService? _agentService;
  
  // UI state
  bool _isInitializing = false;
  bool _isMigrating = false;
  bool _isReady = false;
  List<String> _logs = [];
  
  // Controllers
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  
  String? _lastResponse;
  Map<String, dynamic>? _systemStats;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    _ragService?.dispose();
    _oldVectorService?.dispose();
    _agentService?.dispose();
    _store?.close();
    super.dispose();
  }

  /// Initialize all services and perform migration if needed
  Future<void> _initializeServices() async {
    setState(() {
      _isInitializing = true;
      _logs.clear();
    });

    try {
      _addLog('🚀 Initializing Enhanced RAG System...');
      
      // Step 1: Initialize ObjectBox store
      _addLog('📦 Setting up ObjectBox store...');
      _store = await openStore();
      
      // Step 2: Initialize services
      _addLog('🔧 Initializing services...');
      _ragService = EnhancedRagService(uiLogger: _addLog);
      _oldVectorService = VectorDbService(_addLog);
      _migrationService = RagMigrationService(logger: _addLog);
      
      // Initialize Gemini if API key is provided
      if (widget.geminiApiKey != null && widget.geminiApiKey!.isNotEmpty) {
        _addLog('🔑 Initializing Gemini API...');
        // Gemini initialization - handled by main app
      }
      
      // Initialize services with store
      await _ragService!.initialize(_store!, geminiApiKey: widget.geminiApiKey);
      await _oldVectorService!.initialize(_store!);
      
      // Step 3: Check if migration is needed
      _addLog('🔍 Checking migration requirements...');
      final needsMigration = await _migrationService!.isMigrationNeeded(
        _oldVectorService!,
        _ragService!,
      );
      
      if (needsMigration) {
        await _performMigration();
      } else {
        _addLog('✅ No migration needed');
      }
      
      // Step 4: Initialize agent service
      _addLog('🤖 Initializing Enhanced Agent Service...');
      _agentService = EnhancedAgentService(
        ragService: _ragService!,
        logger: _addLog,
      );
      
      final agentReady = await _agentService!.initialize();
      
      if (!agentReady) {
        _addLog('⚠️ Agent service initialization failed');
      }
      
      // Step 5: Add sample data for testing
      if (widget.geminiApiKey != null) {
        await _addSampleData();
      }
      
      // Step 6: Get system statistics
      await _updateStats();
      
      _addLog('✅ Enhanced RAG System ready!');
      _addLog('');
      _addLog('🎯 Key improvements:');
      _addLog('   • Gemma 3 compatible RAG pipeline');
      _addLog('   • Enhanced semantic search with hybrid scoring');
      _addLog('   • Better embedding quality with Gemini models');
      _addLog('   • Improved context-aware response generation');
      _addLog('   • Advanced metadata handling and filtering');
      
      setState(() {
        _isReady = true;
      });
      
    } catch (e) {
      _addLog('❌ Initialization failed: $e');
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  /// Perform migration from old system to new RAG system
  Future<void> _performMigration() async {
    setState(() {
      _isMigrating = true;
    });

    try {
      _addLog('🔄 Starting migration to Enhanced RAG System...');
      
      final migrationSuccess = await _migrationService!.performMigration(
        oldService: _oldVectorService!,
        newService: _ragService!,
        geminiApiKey: widget.geminiApiKey,
        clearNewService: true,
      );
      
      if (migrationSuccess) {
        _addLog('✅ Migration completed successfully!');
        
        // Test the new system
        await _migrationService!.testNewRagSystem(_ragService!);
      } else {
        _addLog('❌ Migration failed');
      }
    } catch (e) {
      _addLog('❌ Migration error: $e');
    } finally {
      setState(() {
        _isMigrating = false;
      });
    }
  }

  /// Add sample data to demonstrate the system
  Future<void> _addSampleData() async {
    try {
      _addLog('📝 Adding sample data...');
      
      final sampleDocs = [
        {
          'content': 'Frame smart glasses provide immersive AR experiences with voice control, gesture recognition, and real-time visual processing',
          'metadata': {
            'type': 'product_info',
            'category': 'hardware',
            'source': 'documentation',
            'priority': 'high',
          },
        },
        {
          'content': 'Gemma 3 models offer improved performance for on-device AI processing with better efficiency and accuracy',
          'metadata': {
            'type': 'ai_model',
            'category': 'software', 
            'source': 'technical_specs',
            'version': '3.0',
          },
        },
        {
          'content': 'Enhanced RAG systems combine semantic search with hybrid scoring for more relevant and contextual responses',
          'metadata': {
            'type': 'system_feature',
            'category': 'ai_technology',
            'source': 'implementation_guide',
          },
        },
        {
          'content': 'Voice recognition accuracy improved with new ASR models supporting multiple languages and accents',
          'metadata': {
            'type': 'feature_update',
            'category': 'speech_processing',
            'source': 'release_notes',
          },
        },
        {
          'content': 'Computer vision capabilities enhanced for better object detection and scene understanding in AR environments',
          'metadata': {
            'type': 'capability',
            'category': 'computer_vision',
            'source': 'feature_documentation',
          },
        },
      ];

      await _ragService!.batchEmbedDocuments(sampleDocs);
      _addLog('✅ Sample data added successfully');
      
    } catch (e) {
      _addLog('❌ Failed to add sample data: $e');
    }
  }

  /// Update system statistics
  Future<void> _updateStats() async {
    try {
      if (_ragService != null && _agentService != null) {
        final ragStats = await _ragService!.getStatistics();
        final agentStats = await _agentService!.getMemoryStatistics();
        
        setState(() {
          _systemStats = {
            ...ragStats,
            ...agentStats,
          };
        });
      }
    } catch (e) {
      _addLog('⚠️ Failed to update stats: $e');
    }
  }

  /// Process user query using the enhanced agent
  Future<void> _processQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty || !_isReady) return;

    _addLog('🔍 Processing query: "$query"');
    
    try {
      final startTime = DateTime.now();
      
      final agentOutput = await _agentService!.processQuery(
        query: query,
        context: {
          'timestamp': startTime.toIso8601String(),
          'source': 'ui_example',
        },
        storeQuery: true,
      );
      
      final processingTime = DateTime.now().difference(startTime);
      
      setState(() {
        _lastResponse = agentOutput.response;
      });
      
      _addLog('✅ Response generated in ${processingTime.inMilliseconds}ms');
      _addLog('📊 Confidence: ${(agentOutput.confidence * 100).toStringAsFixed(1)}%');
      _addLog('💬 Response: ${agentOutput.response}');
      _addLog('');
      
      // Update stats after processing
      await _updateStats();
      
      // Clear query
      _queryController.clear();
      
    } catch (e) {
      _addLog('❌ Query processing failed: $e');
    }
  }

  /// Add a log message and update UI
  void _addLog(String message) {
    setState(() {
      _logs.add('${DateTime.now().toString().substring(11, 19)} $message');
    });
    
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Test the semantic search functionality
  Future<void> _testSemanticSearch() async {
    if (!_isReady) return;

    _addLog('🧪 Testing semantic search...');
    
    final testQueries = [
      'Frame smart glasses',
      'voice recognition',
      'computer vision',
      'AI models',
      'augmented reality',
    ];

    for (final query in testQueries) {
      try {
        final results = await _ragService!.semanticSearch(
          query: query,
          limit: 3,
          similarityThreshold: 0.2,
          hybridSearch: true,
        );
        
        _addLog('🔍 "$query" -> ${results.length} results');
        
        if (results.isNotEmpty) {
          final topScore = results.first['score'] as double;
          _addLog('   Top match: ${(topScore * 100).toStringAsFixed(1)}% similarity');
        }
      } catch (e) {
        _addLog('❌ Search failed for "$query": $e');
      }
    }
    
    _addLog('✅ Semantic search test completed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhanced RAG Integration'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          if (_isReady)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _updateStats,
              tooltip: 'Refresh Stats',
            ),
        ],
      ),
      body: Column(
        children: [
          // Status indicator
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _isReady 
                ? Colors.green[100] 
                : _isInitializing 
                    ? Colors.orange[100] 
                    : Colors.red[100],
            child: Row(
              children: [
                Icon(
                  _isReady 
                      ? Icons.check_circle 
                      : _isInitializing 
                          ? Icons.hourglass_empty 
                          : Icons.error,
                  color: _isReady 
                      ? Colors.green[700] 
                      : _isInitializing 
                          ? Colors.orange[700] 
                          : Colors.red[700],
                ),
                const SizedBox(width: 8),
                Text(
                  _isReady 
                      ? 'Enhanced RAG System Ready' 
                      : _isInitializing 
                          ? 'Initializing System...' 
                          : 'System Not Ready',
                  style: TextStyle(
                    color: _isReady 
                        ? Colors.green[700] 
                        : _isInitializing 
                            ? Colors.orange[700] 
                            : Colors.red[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Query input
          if (_isReady)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      decoration: const InputDecoration(
                        hintText: 'Enter your query here...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _processQuery(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _processQuery,
                    child: const Text('Query'),
                  ),
                ],
              ),
            ),

          // Action buttons
          if (_isReady)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _testSemanticSearch,
                    icon: const Icon(Icons.search),
                    label: const Text('Test Search'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _ragService?.clearAll().then((_) {
                      _addLog('🗑️ Cleared all documents');
                      _updateStats();
                    }),
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear Data'),
                  ),
                  const Spacer(),
                  if (_systemStats != null)
                    Chip(
                      label: Text('${_systemStats!['totalDocuments']} docs'),
                      backgroundColor: Colors.blue[100],
                    ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Logs display
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.terminal, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'System Logs',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          '${_logs.length} entries',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        Color logColor = Colors.black87;
                        
                        if (log.contains('❌')) {
                          logColor = Colors.red[700]!;
                        } else if (log.contains('⚠️')) {
                          logColor = Colors.orange[700]!;
                        } else if (log.contains('✅')) {
                          logColor = Colors.green[700]!;
                        } else if (log.contains('🔍') || log.contains('🧪')) {
                          logColor = Colors.blue[700]!;
                        }
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: logColor,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Last response display
          if (_lastResponse != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                border: Border.all(color: Colors.blue[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.chat_bubble, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Latest Response',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _lastResponse!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}