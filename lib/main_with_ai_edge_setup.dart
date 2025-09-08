import 'dart:async';
import 'package:flutter/material.dart';

// AI Edge imports (NEW - replaces ObjectBox)
import 'package:frame_realtime_gemini_voicevision/services/ai_edge_rag_service.dart';
import 'package:frame_realtime_gemini_voicevision/services/ai_edge_auto_init_service.dart';
import 'package:frame_realtime_gemini_voicevision/agent/services/ai_edge_agent_service.dart';
import 'package:frame_realtime_gemini_voicevision/screens/ai_edge_first_time_setup_screen.dart';

/// Example: Frame App with AI Edge Setup Integration
/// This demonstrates how to integrate the AI Edge first-time setup
/// into your existing Frame smart glasses app
void main() {
  runApp(const FrameAppWithAIEdge());
}

class FrameAppWithAIEdge extends StatelessWidget {
  const FrameAppWithAIEdge({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame AI Edge Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AppInitializer(),
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isCheckingFirstLaunch = true;
  bool _isFirstLaunch = false;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    try {
      final autoInitService = AIEdgeAutoInitService();
      final isFirstLaunch = await autoInitService.isFirstLaunch();
      
      setState(() {
        _isFirstLaunch = isFirstLaunch;
        _isCheckingFirstLaunch = false;
      });
      
      autoInitService.dispose();
    } catch (e) {
      // Handle error - assume not first launch
      setState(() {
        _isFirstLaunch = false;
        _isCheckingFirstLaunch = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingFirstLaunch) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isFirstLaunch) {
      // Show AI Edge setup screen
      return AIEdgeFirstTimeSetupScreen(
        onSetupComplete: () {
          // Navigate to main app after setup
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const MainApp(),
            ),
          );
        },
      );
    }

    // Setup already completed - go to main app
    return const MainApp();
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  AIEdgeRagService? _ragService;
  AIEdgeAgentService? _agentService;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _initializeAIEdge();
  }

  Future<void> _initializeAIEdge() async {
    try {
      _addLog('🚀 Initializing AI Edge services...');
      
      // Initialize RAG service
      _ragService = AIEdgeRagService(logger: _addLog);
      final ragInitialized = await _ragService!.initialize();
      
      if (ragInitialized) {
        _addLog('✅ AI Edge RAG service ready');
        
        // Initialize Agent service
        _agentService = AIEdgeAgentService(
          ragService: _ragService!,
          logger: _addLog,
        );
        
        await _agentService!.initialize();
        _addLog('✅ AI Edge Agent service ready');
        _addLog('🎯 Frame AI Edge integration complete!');
      } else {
        _addLog('❌ AI Edge RAG initialization failed');
      }
    } catch (e) {
      _addLog('❌ AI Edge initialization error: $e');
    }
  }

  void _addLog(String message) {
    if (mounted) {
      setState(() {
        _logs.add('${DateTime.now().toString().substring(11, 19)} $message');
      });
    }
  }

  Future<void> _testAIEdge() async {
    if (_agentService == null) {
      _addLog('⚠️ AI Edge not ready - run setup first');
      return;
    }

    try {
      _addLog('🧪 Testing AI Edge capabilities...');
      
      // Test document storage
      await _ragService!.storeDocument(
        content: 'Test document for Frame AI Edge integration',
        metadata: {'type': 'test', 'timestamp': DateTime.now().toIso8601String()},
      );
      
      _addLog('✅ Document stored successfully');
      
      // Test RAG query
      final result = await _ragService!.queryWithRAG(
        query: 'Tell me about the test document',
        maxResults: 1,
      );
      
      if (result.relevantDocuments.isNotEmpty) {
        _addLog('✅ RAG query successful: ${result.relevantDocuments.first.content.substring(0, 50)}...');
      } else {
        _addLog('⚠️ No results from RAG query');
      }
      
    } catch (e) {
      _addLog('❌ AI Edge test failed: $e');
    }
  }

  @override
  void dispose() {
    _ragService?.dispose();
    _agentService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Frame AI Edge Demo'),
      ),
      body: Column(
        children: [
          // Status card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
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
                    Icon(Icons.smart_toy, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Text(
                      'AI Edge Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('RAG Service: ${_ragService != null ? '✅ Ready' : '⏳ Initializing'}'),
                Text('Agent Service: ${_agentService != null ? '✅ Ready' : '⏳ Initializing'}'),
              ],
            ),
          ),
          
          // Test button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _testAIEdge,
                child: const Text('Test AI Edge Integration'),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Logs
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.terminal, color: Colors.green[400]),
                      const SizedBox(width: 8),
                      Text(
                        'AI Edge Logs',
                        style: TextStyle(
                          color: Colors.green[400],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        return Text(
                          log,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.green[300],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}