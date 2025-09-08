import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:frame_msg/rx/photo.dart';
import 'package:frame_msg/rx/audio.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:frame_msg/tx/plain_text.dart';
import 'package:frame_msg/tx/capture_settings.dart';
import 'package:frame_msg/tx/code.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

// AI Edge imports (NEW - replaces ObjectBox)
import 'package:frame_realtime_gemini_voicevision/services/ai_edge_rag_service.dart';
import 'package:frame_realtime_gemini_voicevision/services/ai_edge_auto_init_service.dart';
import 'package:frame_realtime_gemini_voicevision/agent/services/ai_edge_agent_service.dart';
import 'package:frame_realtime_gemini_voicevision/screens/ai_edge_first_time_setup_screen.dart';

// Existing Frame-to-Gemini pipeline (UNCHANGED)
import 'package:frame_realtime_gemini_voicevision/gemini_realtime.dart' as gemini_realtime;
import 'package:frame_realtime_gemini_voicevision/audio_upsampler.dart';

// Foreground service (matches official repository)
import 'package:frame_realtime_gemini_voicevision/foreground_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// Global AI Edge services (replaces ObjectBox store)
late AIEdgeRagService aiEdgeRagService;
late AIEdgeAgentService aiEdgeAgentService;
late AIEdgeAutoInitService aiEdgeInitService;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize foreground service (matches official repository)
  initializeForegroundService();

  runApp(const FrameAIEdgeApp());
}

class FrameAIEdgeApp extends StatefulWidget {
  const FrameAIEdgeApp({super.key});

  @override
  State<FrameAIEdgeApp> createState() => _FrameAIEdgeAppState();
}

class _FrameAIEdgeAppState extends State<FrameAIEdgeApp> {
  bool _isFirstLaunch = true;
  bool _isCheckingFirstLaunch = true;
  bool _aiEdgeInitialized = false;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  /// Check if this is the first app launch
  Future<void> _checkFirstLaunch() async {
    try {
      // Initialize AI Edge auto-init service
      aiEdgeInitService = AIEdgeAutoInitService(
        logger: (msg) => debugPrint('[AI_EDGE] $msg'),
      );

      final isFirstLaunch = await aiEdgeInitService.isFirstLaunch();
      final isAutoInitEnabled = await aiEdgeInitService.isAutoInitEnabled();

      setState(() {
        _isFirstLaunch = isFirstLaunch && isAutoInitEnabled;
        _isCheckingFirstLaunch = false;
      });

      // If not first launch, initialize AI Edge services
      if (!_isFirstLaunch) {
        await _initializeAIEdgeServices();
      }
    } catch (e) {
      debugPrint('Error checking first launch: $e');
      setState(() {
        _isFirstLaunch = false;
        _isCheckingFirstLaunch = false;
      });
    }
  }

  /// Initialize AI Edge services after first-time setup
  Future<void> _initializeAIEdgeServices() async {
    try {
      debugPrint('[AI_EDGE] Initializing AI Edge services...');
      
      // Initialize RAG service
      aiEdgeRagService = AIEdgeRagService(
        logger: (msg) => debugPrint('[AI_EDGE_RAG] $msg'),
      );

      // Get model path from model manager
      final modelPath = await aiEdgeInitService.modelManager.getModelPath();
      
      if (modelPath != null) {
        final ragInitialized = await aiEdgeRagService.initialize(downloadModel: false);
        
        if (ragInitialized) {
          // Initialize agent service
          aiEdgeAgentService = AIEdgeAgentService(
            ragService: aiEdgeRagService,
            logger: (msg) => debugPrint('[AI_EDGE_AGENT] $msg'),
          );
          
          final agentInitialized = await aiEdgeAgentService.initialize();
          
          setState(() {
            _aiEdgeInitialized = agentInitialized;
          });
          
          if (agentInitialized) {
            debugPrint('[AI_EDGE] All services initialized successfully');
          }
        }
      } else {
        debugPrint('[AI_EDGE] No model found - AI Edge features disabled');
      }
    } catch (e) {
      debugPrint('[AI_EDGE] Initialization error: $e');
    }
  }

  /// Handle first-time setup completion
  void _onFirstTimeSetupComplete() async {
    await _initializeAIEdgeServices();
    
    setState(() {
      _isFirstLaunch = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame AI Edge',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: _isCheckingFirstLaunch
          ? const SplashScreen()
          : _isFirstLaunch
              ? AIEdgeFirstTimeSetupScreen(
                  onSetupComplete: _onFirstTimeSetupComplete,
                )
              : FrameRealtimeGeminiApp(
                  aiEdgeInitialized: _aiEdgeInitialized,
                ),
    );
  }
}

/// Splash screen shown while checking first launch status
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[50],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[400]!, Colors.purple[600]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.smart_toy,
                color: Colors.white,
                size: 50,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Frame AI Edge',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Powered by Google AI Edge',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

/// Main Frame app with AI Edge integration
class FrameRealtimeGeminiApp extends StatefulWidget {
  final bool aiEdgeInitialized;
  
  const FrameRealtimeGeminiApp({
    super.key,
    required this.aiEdgeInitialized,
  });

  @override
  State<FrameRealtimeGeminiApp> createState() => _FrameRealtimeGeminiAppState();
}

class _FrameRealtimeGeminiAppState extends State<FrameRealtimeGeminiApp> {
  // Frame connection and streaming (UNCHANGED from original)
  StreamSubscription<Photo>? _photoSubscription;
  StreamSubscription<Audio>? _audioSubscription;
  
  // Gemini WebSocket connection (UNCHANGED from original)
  StreamSubscription<gemini_realtime.ChatResponse>? _chatResponseSubscription;
  bool _isGeminiConnected = false;
  String _geminiApiKey = '';
  
  // Audio processing (UNCHANGED from original)
  final FlutterPcmSound _flutterPcmSound = FlutterPcmSound();
  final AudioUpsampler _audioUpsampler = AudioUpsampler();
  
  // UI state
  bool _isConnectedToFrame = false;
  List<String> _conversationLog = [];
  String? _lastGeminiResponse;
  
  // AI Edge integration status
  Map<String, dynamic>? _aiEdgeStats;

  @override
  void initState() {
    super.initState();
    _loadGeminiApiKey();
    _updateAIEdgeStats();
  }

  @override
  void dispose() {
    _photoSubscription?.cancel();
    _audioSubscription?.cancel();
    _chatResponseSubscription?.cancel();
    super.dispose();
  }

  /// Load Gemini API key from preferences (UNCHANGED)
  Future<void> _loadGeminiApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _geminiApiKey = prefs.getString('gemini_api_key') ?? '';
    });
  }

  /// Update AI Edge statistics
  Future<void> _updateAIEdgeStats() async {
    if (!widget.aiEdgeInitialized) return;
    
    try {
      final stats = aiEdgeAgentService.getMemoryStatistics();
      setState(() {
        _aiEdgeStats = stats;
      });
    } catch (e) {
      debugPrint('Error updating AI Edge stats: $e');
    }
  }

  /// Connect to Frame (UNCHANGED from original implementation)
  Future<void> _connectToFrame() async {
    try {
      debugPrint('Connecting to Frame...');
      
      // Request permissions
      await Permission.bluetooth.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetoothScan.request();
      await Permission.microphone.request();
      
      // Connect to Frame
      await SimpleFrameApp.connect();
      
      setState(() {
        _isConnectedToFrame = true;
      });
      
      _addToLog('✅ Connected to Frame');
      
      // Set up Frame streams
      _setupFrameStreams();
      
    } catch (e) {
      _addToLog('❌ Frame connection failed: $e');
    }
  }

  /// Set up Frame photo and audio streams (UNCHANGED)
  void _setupFrameStreams() {
    // Photo stream
    _photoSubscription = SimpleFrameApp.rx.photo.listen(
      (photo) async {
        _addToLog('📸 Photo received (${photo.data.lengthInBytes} bytes)');
        
        // Process with AI Edge if available
        if (widget.aiEdgeInitialized) {
          await _processPhotoWithAIEdge(photo);
        }
        
        // Send to Gemini (original pipeline - UNCHANGED)
        if (_isGeminiConnected) {
          gemini_realtime.sendImageToGemini(photo.data);
        }
      },
    );
    
    // Audio stream
    _audioSubscription = SimpleFrameApp.rx.audio.listen(
      (audio) async {
        // Process with AI Edge if available
        if (widget.aiEdgeInitialized) {
          await _processAudioWithAIEdge(audio);
        }
        
        // Send to Gemini (original pipeline - UNCHANGED)
        if (_isGeminiConnected) {
          final upsampledAudio = _audioUpsampler.upsample(audio.data);
          gemini_realtime.sendAudioToGemini(upsampledAudio);
        }
        
        // Play audio feedback (UNCHANGED)
        await _flutterPcmSound.play(
          bytes: audio.data,
          sampleRate: 8000,
        );
      },
    );
  }

  /// Process photo with AI Edge (NEW)
  Future<void> _processPhotoWithAIEdge(Photo photo) async {
    try {
      // For now, just log that we received a photo
      // In a full implementation, you'd extract text with OCR
      final timestamp = DateTime.now();
      
      await aiEdgeAgentService.storeOCROutput(
        text: 'Photo captured from Frame camera',
        confidence: 1.0,
        timestamp: timestamp,
      );
      
      _updateAIEdgeStats();
    } catch (e) {
      debugPrint('Error processing photo with AI Edge: $e');
    }
  }

  /// Process audio with AI Edge (NEW)
  Future<void> _processAudioWithAIEdge(Audio audio) async {
    try {
      // For now, just log that we received audio
      // In a full implementation, you'd use ASR to convert to text
      final timestamp = DateTime.now();
      
      await aiEdgeAgentService.storeASROutput(
        text: 'Audio captured from Frame microphone',
        confidence: 0.8,
        timestamp: timestamp,
      );
      
      _updateAIEdgeStats();
    } catch (e) {
      debugPrint('Error processing audio with AI Edge: $e');
    }
  }

  /// Connect to Gemini (UNCHANGED from original)
  Future<void> _connectToGemini() async {
    if (_geminiApiKey.isEmpty) {
      _addToLog('❌ Please set Gemini API key first');
      return;
    }
    
    try {
      await gemini_realtime.connectToGemini(_geminiApiKey);
      
      setState(() {
        _isGeminiConnected = true;
      });
      
      _addToLog('✅ Connected to Gemini');
      
      // Listen for Gemini responses
      _chatResponseSubscription = gemini_realtime.chatResponseStream.listen(
        (response) {
          setState(() {
            _lastGeminiResponse = response.content;
          });
          _addToLog('🤖 Gemini: ${response.content}');
          
          // Process Gemini response with AI Edge for learning
          if (widget.aiEdgeInitialized) {
            _processGeminiResponseWithAIEdge(response.content);
          }
        },
      );
      
    } catch (e) {
      _addToLog('❌ Gemini connection failed: $e');
    }
  }

  /// Process Gemini response with AI Edge for learning (NEW)
  Future<void> _processGeminiResponseWithAIEdge(String response) async {
    try {
      await aiEdgeRagService.storeDocument(
        content: response,
        metadata: {
          'type': 'gemini_response',
          'source': 'frame_gemini_stream',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      _updateAIEdgeStats();
    } catch (e) {
      debugPrint('Error storing Gemini response in AI Edge: $e');
    }
  }

  /// Add message to conversation log
  void _addToLog(String message) {
    setState(() {
      _conversationLog.add('${DateTime.now().toString().substring(11, 19)} $message');
    });
  }

  /// Save Gemini API key (UNCHANGED)
  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key);
    setState(() {
      _geminiApiKey = key;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Frame AI Edge'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          // AI Edge status indicator
          if (widget.aiEdgeInitialized)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green[600],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.smart_toy, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'AI Edge',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Connection status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              children: [
                // Frame and Gemini status (UNCHANGED)
                Row(
                  children: [
                    _buildStatusChip(
                      'Frame',
                      _isConnectedToFrame,
                      _isConnectedToFrame ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    _buildStatusChip(
                      'Gemini',
                      _isGeminiConnected,
                      _isGeminiConnected ? Colors.blue : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    _buildStatusChip(
                      'AI Edge',
                      widget.aiEdgeInitialized,
                      widget.aiEdgeInitialized ? Colors.purple : Colors.orange,
                    ),
                  ],
                ),
                
                // AI Edge stats
                if (widget.aiEdgeInitialized && _aiEdgeStats != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'AI Edge: ${_aiEdgeStats!['totalDocuments']} docs stored',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // API Key input (UNCHANGED)
          if (_geminiApiKey.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Gemini API Key',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                onSubmitted: _saveApiKey,
              ),
            ),
          
          // Connection buttons (UNCHANGED)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isConnectedToFrame ? null : _connectToFrame,
                    child: Text(_isConnectedToFrame ? 'Frame Connected' : 'Connect Frame'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_isGeminiConnected || _geminiApiKey.isEmpty) ? null : _connectToGemini,
                    child: Text(_isGeminiConnected ? 'Gemini Connected' : 'Connect Gemini'),
                  ),
                ),
              ],
            ),
          ),
          
          // Conversation log
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.chat, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Frame Stream Log',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          '${_conversationLog.length} entries',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _conversationLog.length,
                      itemBuilder: (context, index) {
                        final log = _conversationLog[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            log,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
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
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, bool isConnected, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected ? color : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}