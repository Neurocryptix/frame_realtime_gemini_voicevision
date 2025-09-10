import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frame_realtime_gemini_voicevision/services/ai_edge_rag_service.dart';
import 'package:frame_realtime_gemini_voicevision/agent/services/ai_edge_agent_service.dart';
import 'package:frame_realtime_gemini_voicevision/agent/services/ai_edge_llm_service.dart';
import 'package:frame_realtime_gemini_voicevision/agent/interfaces/ai_edge_interfaces.dart';

/// Pure Google AI Edge Integration Example
/// Demonstrates the complete AI Edge RAG system using MediaPipe GenAI
/// IMPORTANT: This does NOT affect your Frame-to-Gemini streaming pipeline
class AIEdgeIntegrationExample extends StatefulWidget {
  final String? gemmaModelUrl; // Kaggle model URL required
  
  const AIEdgeIntegrationExample({
    super.key,
    this.gemmaModelUrl,
  });

  @override
  State<AIEdgeIntegrationExample> createState() => _AIEdgeIntegrationExampleState();
}

class _AIEdgeIntegrationExampleState extends State<AIEdgeIntegrationExample> {
  // Pure Google AI Edge services
  AIEdgeRagService? _ragService;
  AIEdgeAgentService? _agentService;
  AIEdgeLLMService? _llmService;
  
  // UI state
  bool _isInitializing = false;
  bool _isReady = false;
  final List<String> _logs = [];
  
  // Controllers
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  final _modelUrlController = TextEditingController();
  
  String? _lastResponse;
  Map<String, dynamic>? _systemStats;

  @override
  void initState() {
    super.initState();
    if (widget.gemmaModelUrl != null) {
      _modelUrlController.text = widget.gemmaModelUrl!;
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    _modelUrlController.dispose();
    _ragService?.dispose();
    _agentService?.dispose();
    _llmService?.dispose();
    super.dispose();
  }

  /// Initialize pure Google AI Edge system
  Future<void> _initializeAIEdge() async {
    setState(() {
      _isInitializing = true;
      _logs.clear();
    });

    try {
      _addLog('🚀 Initializing Pure Google AI Edge System...');
      _addLog('📋 Framework: MediaPipe GenAI');
      _addLog('🧠 Model: Gemma 3');
      _addLog('📱 Processing: On-device AI Edge');
      _addLog('');

      final modelUrl = _modelUrlController.text.trim();
      if (modelUrl.isEmpty) {
        _addLog('❌ Please provide Kaggle model URL');
        setState(() {
          _isInitializing = false;
        });
        return;
      }

      // Step 1: Initialize AI Edge RAG Service
      _addLog('🔧 Initializing AI Edge RAG Service...');
      _ragService = AIEdgeRagServiceImpl(logger: _addLog);
      
      final ragSuccess = await _ragService!.initialize();

      if (!ragSuccess) {
        _addLog('❌ AI Edge RAG initialization failed');
        setState(() {
          _isInitializing = false;
        });
        return;
      }

      // Step 2: Initialize AI Edge LLM Service
      _addLog('🤖 Initializing AI Edge LLM Service...');
      _llmService = AIEdgeLLMServiceImpl(logger: _addLog);
      
      final llmSuccess = await _llmService!.initialize(modelPath: '/path/to/model.bin');
      
      if (!llmSuccess) {
        _addLog('❌ AI Edge LLM initialization failed');
        setState(() {
          _isInitializing = false;
        });
        return;
      }

      // Step 3: Initialize AI Edge Agent Service
      _addLog('👨‍💻 Initializing AI Edge Agent Service...');
      _agentService = AIEdgeAgentService(
        ragService: _ragService!,
        logger: _addLog,
      );
      
      final agentSuccess = await _agentService!.initialize();
      
      if (!agentSuccess) {
        _addLog('❌ AI Edge Agent initialization failed');
        setState(() {
          _isInitializing = false;
        });
        return;
      }

      // Step 4: Add sample data
      await _addSampleData();
      
      // Step 5: Get system statistics
      await _updateStats();
      
      _addLog('');
      _addLog('✅ Google AI Edge System Ready!');
      _addLog('');
      _addLog('🎯 Key Features:');
      _addLog('   • Pure Google AI Edge implementation');
      _addLog('   • MediaPipe GenAI RAG processing');
      _addLog('   • Gemma 3 on-device inference');
      _addLog('   • No external database dependencies');
      _addLog('   • Frame-to-Gemini pipeline UNTOUCHED');
      _addLog('');
      _addLog('💡 Note: Your Frame-to-Gemini streaming remains unchanged!');
      
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

  /// Add sample data to AI Edge RAG
  Future<void> _addSampleData() async {
    try {
      _addLog('📝 Adding sample data to AI Edge RAG...');
      
      await _ragService!.addSampleData();
      _addLog('✅ Sample data added successfully');
      
    } catch (e) {
      _addLog('❌ Failed to add sample data: $e');
    }
  }

  /// Update system statistics
  Future<void> _updateStats() async {
    try {
      if (_ragService != null && _agentService != null && _llmService != null) {
        final ragStats = _ragService!.getStatistics();
        final agentStats = _agentService!.getMemoryStatistics();
        final llmStats = _llmService!.getStatistics();
        
        setState(() {
          _systemStats = {
            ...ragStats,
            ...agentStats,
            ...llmStats,
          };
        });
      }
    } catch (e) {
      _addLog('⚠️ Failed to update stats: $e');
    }
  }

  /// Process user query using AI Edge
  Future<void> _processQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty || !_isReady) return;

    _addLog('🔍 Processing with Google AI Edge: "$query"');
    
    try {
      final startTime = DateTime.now();
      
      final agentOutput = await _agentService!.processQuery(
        query: query,
        context: {
          'timestamp': startTime.toIso8601String(),
          'source': 'ai_edge_example',
          'frameIntegration': false, // This is separate from Frame pipeline
        },
        storeQuery: true,
      );
      
      final processingTime = DateTime.now().difference(startTime);
      
      setState(() {
        _lastResponse = agentOutput.response;
      });
      
      _addLog('✅ AI Edge response generated in ${processingTime.inMilliseconds}ms');
      _addLog('📊 Confidence: ${(agentOutput.confidence * 100).toStringAsFixed(1)}%');
      _addLog('📚 Context docs used: ${agentOutput.ragResponse?.relevantDocuments.length ?? 0}');
      _addLog('💬 Response: ${agentOutput.response}');
      _addLog('');
      
      // Update stats after processing
      await _updateStats();
      
      // Clear query
      _queryController.clear();
      
    } catch (e) {
      _addLog('❌ AI Edge query processing failed: $e');
    }
  }

  /// Test AI Edge RAG capabilities
  Future<void> _testAIEdgeRAG() async {
    if (!_isReady) return;

    _addLog('🧪 Testing Google AI Edge RAG capabilities...');
    
    final testQueries = [
      'What are Frame smart glasses?',
      'How does Google AI Edge work?',
      'What is Gemma 3?',
      'Explain MediaPipe GenAI',
      'Benefits of on-device AI processing',
    ];

    for (final query in testQueries) {
      try {
        _addLog('🔍 Testing: "$query"');
        
        final startTime = DateTime.now();
        final ragResponse = await _ragService!.queryWithRAG(
          query: query,
          maxResults: 3,
          similarityThreshold: 0.2,
        );
        final processingTime = DateTime.now().difference(startTime);
        
        _addLog('   Response time: ${processingTime.inMilliseconds}ms');
        _addLog('   Context docs: ${ragResponse.relevantDocuments.length}');
        _addLog('   Response: ${ragResponse.response.substring(0, 80)}...');
        _addLog('');
        
        // Small delay between queries
        await Future.delayed(const Duration(milliseconds: 500));
        
      } catch (e) {
        _addLog('❌ Test failed for "$query": $e');
      }
    }
    
    _addLog('✅ AI Edge RAG testing completed');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google AI Edge RAG Integration'),
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
                Expanded(
                  child: Text(
                    _isReady 
                        ? 'Google AI Edge System Ready' 
                        : _isInitializing 
                            ? 'Initializing AI Edge...' 
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
                ),
              ],
            ),
          ),

          // Model URL input (if not initialized)
          if (!_isReady)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kaggle Model URL (Required):',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _modelUrlController,
                    decoration: const InputDecoration(
                      hintText: 'https://www.kaggle.com/models/google/gemma-3/...',
                      border: OutlineInputBorder(),
                      helperText: 'Download Gemma 3 model from Kaggle',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isInitializing ? null : _initializeAIEdge,
                    child: _isInitializing 
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Initializing...'),
                            ],
                          )
                        : const Text('Initialize AI Edge System'),
                  ),
                ],
              ),
            ),

          // Query input (if ready)
          if (_isReady)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      decoration: const InputDecoration(
                        hintText: 'Ask Google AI Edge anything...',
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

          // Action buttons (if ready)
          if (_isReady)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _testAIEdgeRAG,
                    icon: const Icon(Icons.science),
                    label: const Text('Test RAG'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _ragService?.clearDocuments(),
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
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
                          'Google AI Edge Logs',
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
                        } else if (log.contains('🚀') || log.contains('🎯')) {
                          logColor = Colors.purple[700]!;
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
                      Icon(Icons.smart_toy, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Google AI Edge Response',
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