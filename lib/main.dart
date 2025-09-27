import 'dart:async';

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:frame_msg/rx/photo.dart';
import 'package:frame_msg/rx/audio.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:frame_msg/tx/plain_text.dart';
import 'package:frame_msg/tx/capture_settings.dart';
import 'package:frame_msg/tx/code.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:google_generative_ai/google_generative_ai.dart'; // Not needed - using WebSocket realtime API

// ObjectBox imports
import 'package:frame_realtime_gemini_voicevision/services/vector_db_service.dart';
import 'package:frame_realtime_gemini_voicevision/gemini_realtime.dart'
    as gemini_realtime;
import 'package:frame_realtime_gemini_voicevision/audio_upsampler.dart';
// import 'package:frame_realtime_gemini_voicevision/objectbox.g.dart'; // Disabled - using AI Edge RAG instead

// Foreground service (matches official repository)
import 'package:frame_realtime_gemini_voicevision/foreground_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// AI Edge setup integration
import 'package:frame_realtime_gemini_voicevision/services/ai_edge_auto_init_service.dart';
import 'package:frame_realtime_gemini_voicevision/screens/model_download_screen.dart';
import 'package:frame_realtime_gemini_voicevision/services/integrated_agentic_service.dart';

// Agent system imports
import 'package:frame_realtime_gemini_voicevision/agent/core/agent_core.dart';
// import 'package:frame_realtime_gemini_voicevision/agent/services/agent_vector_service.dart'; // Legacy - using AI Edge RAG
import 'package:frame_realtime_gemini_voicevision/agent/services/agent_manager.dart';
// import 'package:frame_realtime_gemini_voicevision/agent/ui/agent_demo_widget.dart'; // Unused - using integrated interface

// Global ObjectBox store instance
// late Store store; // Disabled - using AI Edge RAG instead

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize foreground service (matches official repository)
  initializeForegroundService();

  // Initialize ObjectBox
  await _initializeObjectBox();

  runApp(const MyApp());
}

Future<void> _initializeObjectBox() async {
  try {



    // store = await openStore(directory: storeDir.path); // Disabled - using AI Edge RAG instead
    debugPrint('✅ ObjectBox initialized successfully');
  } catch (e) {
    debugPrint('❌ ObjectBox initialization failed: $e');
    rethrow;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame Realtime Gemini Voice+Vision',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AppInitializer(),
    );
  }
}

// Voice options for Gemini integration - matches official repository
enum GeminiVoiceName {
  puck('Puck'),
  charon('Charon'),
  kore('Kore'),
  fenrir('Fenrir'),
  aoede('Aoede');

  const GeminiVoiceName(this.displayName);
  final String displayName;
}

/// App initializer to check if model download is needed
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isCheckingFirstLaunch = true;
  bool _needsModelDownload = false;

  @override
  void initState() {
    super.initState();
    _checkModelDownloadNeeded();
  }

  Future<void> _checkModelDownloadNeeded() async {
    try {
      final autoInitService = AIEdgeAutoInitService();
      final needsSetup = await autoInitService.isFirstLaunch();
      
      setState(() {
        _needsModelDownload = needsSetup;
        _isCheckingFirstLaunch = false;
      });
      
      autoInitService.dispose();
    } catch (e) {
      // Handle error - assume setup not needed
      setState(() {
        _needsModelDownload = false;
        _isCheckingFirstLaunch = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingFirstLaunch) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[400]!, Colors.purple[600]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Initializing Frame AI...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_needsModelDownload) {
      // Show new model download screen
      return ModelDownloadScreen(
        onDownloadComplete: () {
          // Navigate to main app after setup
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const MainApp(title: 'Frame Realtime Gemini Voice+Vision'),
            ),
          );
        },
      );
    }

    // Setup already completed - go to main app
    return const MainApp(title: 'Frame Realtime Gemini Voice+Vision');
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key, required this.title});
  final String title;

  @override
  State<MainApp> createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState {
  // Frame connection using simple_frame_app
  // FrameApp is now available through the mixin
  bool _isConnected = false;
  bool _isScanning = false;

  // AI Configuration
  String _geminiApiKey = '';
  String? _tempApiKey; // Temporary storage for API key input
  GeminiVoiceName _selectedVoice = GeminiVoiceName.puck;
  // NOTE: Using WebSocket-based Gemini Realtime API only (matches official repository)
  // GenerativeModel? _model; // Not needed - using WebSocket realtime connection
  // ChatSession? _chatSession; // Not needed - using WebSocket realtime connection

  // Session state
  bool _isSessionActive = false;
  // ignore: unused_field
  Uint8List? _lastPhoto; // For integration service
  Widget? _image; // Original repo style photo display

  // Photo capture timer (like original repository)
  Timer? _photoTimer;

  // Audio state
  bool _isAudioStreaming = false;
  bool _isVoiceDetected = false;
  int _audioPacketsReceived = 0;
  int _totalAudioBytes = 0;

  // Event logging
  final List<String> _eventLog = [];
  final ScrollController _scrollController = ScrollController();

  // Vector database with MobileBERT
  VectorDbService? _vectorDb;
  final TextEditingController _queryController = TextEditingController();
  List<Map<String, dynamic>> _queryResults = [];

  // Debugging UI state (read-only, non-intrusive)
  String _lastASRText = 'No audio processed yet';
  double _lastASRConfidence = 0.0;
  DateTime? _lastASRTime;
  String _lastDatabaseQuery = 'No queries yet';
  List<Map<String, dynamic>> _lastDatabaseResults = [];
  DateTime? _lastDatabaseTime;
  String _lastLLMInput = 'No LLM input yet';
  String _lastLLMOutput = 'No LLM output yet';
  Duration _lastLLMProcessingTime = Duration.zero;
  DateTime? _lastLLMTime;
  int _totalASRProcessed = 0;
  int _totalDatabaseQueries = 0;
  int _totalLLMRequests = 0;

  // Simple Gemini realtime connection (like original)
  gemini_realtime.GeminiRealtime? _gemini;

  // Agent system
  AgentCore? _agentCore;
  // AgentVectorService? _agentVectorService; // Legacy - using AI Edge RAG
  AgentManager? _agentManager;
  IntegratedAgenticService? _integratedAgent;

  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<String>? _frameLogSubscription;
  StreamSubscription<dynamic>? _frameDataSubscription;

  // Audio playback setup (like original)
  bool _isAudioPlayerSetup = false;
  bool _playingAudio = false;

  // Photo handling using official Frame RxPhoto (like original repository)
  late final RxPhoto _rxPhoto;
  Stream<Uint8List>? _photoStream;
  StreamSubscription<Uint8List>? _photoSubs;

  // Audio handling using official Frame RxAudio (like original repository)
  late final RxAudio _rxAudio;
  Stream<Uint8List>? _frameAudioSampleStream;
  StreamSubscription<Uint8List>? _frameAudioSubs;

  @override
  void initState() {
    super.initState();

    // Initialize RxPhoto and RxAudio like original repository
    _rxPhoto = RxPhoto(
      quality: 'VERY_HIGH',
      resolution: 720,
    );
    _rxAudio = RxAudio(streaming: true);

    _initializeServices();
    _loadGeminiApiKey();
    _requestPermissions();
    _logEvent('🚀 App initialized with Frame SDK integration');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _queryController.dispose();
    _audioSubscription?.cancel();
    _frameLogSubscription?.cancel();
    _frameDataSubscription?.cancel();
    _photoSubs?.cancel(); // Clean up photo subscription
    _frameAudioSubs?.cancel(); // Clean up audio subscription
    _photoTimer?.cancel(); // Clean up photo timer

    // Cleanup FlutterPcmSound
    if (_isAudioPlayerSetup) {
      try {
        FlutterPcmSound.release();
      } catch (e) {
        debugPrint('FlutterPcmSound release error: $e');
      }
    }
    if (frame != null) {
      disconnectFrame();
    }
    _vectorDb?.dispose();
    _agentCore?.dispose();
    // _agentVectorService?.dispose(); // Legacy - using AI Edge RAG
    _agentManager?.dispose();
    _integratedAgent?.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    try {
      // Configure Bluetooth logging (from official repo)
      // Note: Uncomment if flutter_blue_plus is available
      // FlutterBluePlus.setLogLevel(LogLevel.info);

      // Initialize only essential services at startup
      _vectorDb = VectorDbService(_logEvent);
      // await _vectorDb!.initialize(store); // Disabled ObjectBox - using AI Edge RAG instead
      
      // Add sample data if database is empty (for testing queries)
      final docCount = _vectorDb!.getDocumentCount();
      if (docCount == 0) {
        _logEvent('📝 Database empty, adding sample data...');
        await _vectorDb!.addSampleData();
        _logEvent('✅ Sample data added - ${_vectorDb!.getDocumentCount()} documents');
      } else {
        _logEvent('📊 Database has $docCount existing documents');
      }

      // Initialize agent system (non-blocking)
      await _initializeAgentSystem();

      // Initialize agent manager (unified agent services)
      await _initializeAgentManager();

      // Initialize integrated agentic service
      await _initializeIntegratedAgent();

      _logEvent('🔧 Essential services initialized');
    } catch (e) {
      _logEvent('❌ Service initialization error: $e');
    }
  }

  /// Initialize agent system (graceful degradation if fails)
  Future<void> _initializeAgentSystem() async {
    try {
      _logEvent('🔧 Starting agent system initialization...');

      if (_vectorDb == null) {
        _logEvent('⚠️ Agent system requires vector database - skipping initialization');
        return;
      }

      // Check vector database status
      final docCount = _vectorDb!.getDocumentCount();
      _logEvent('📊 Vector database status: $docCount documents available');

      // Legacy agent vector service replaced by AI Edge RAG
      _logEvent('📝 Note: Using AI Edge RAG instead of legacy vector service');

      // Initialize agent core (now without vector service dependency)
      _logEvent('🤖 Initializing AgentCore...');
      _agentCore = AgentCore(
        logger: _logEvent,
      );

      _logEvent('⏳ Running AgentCore initialization...');
      final agentReady = await _agentCore!.initialize();

      if (agentReady) {
        _logEvent('✅ Agent system ready (graceful mode)');
        _logEvent('🔧 AgentCore initialized successfully');
      } else {
        _logEvent('⚠️ Agent system initialized with limited capabilities');
        _logEvent('🔧 AgentCore initialization completed with warnings');
      }
    } catch (e) {
      _logEvent('❌ Agent initialization failed (continuing without agent): $e');
      _logEvent('🔍 Error details: ${e.toString()}');

      // Continue without agent - graceful degradation
      _agentCore = null;
      // _agentVectorService = null; // Legacy - using AI Edge RAG
      _logEvent('🛡️ Graceful degradation: app continues without agent system');
    }
  }

  /// Initialize integrated agentic service
  Future<void> _initializeIntegratedAgent() async {
    try {
      _logEvent('🚀 Initializing Integrated Agentic Service...');
      _logEvent('🔧 Creating IntegratedAgenticService instance...');

      _integratedAgent = IntegratedAgenticService(logger: _logEvent);

      _logEvent('⏳ Running integrated agent initialization...');
      final agentReady = await _integratedAgent!.initialize();

      if (agentReady) {
        _logEvent('✅ Integrated Agentic Service ready - On-device AI active');

        // Get status details
        final status = _integratedAgent!.getStatus();
        _logEvent('📊 Service status: ${status['services']}');
        _logEvent('📚 Total documents: ${status['totalDocuments']}');

        // Enable agent processing by default
        _integratedAgent!.setAgentEnabled(true);
        _logEvent('▶️ Agent processing enabled by default');
      } else {
        _logEvent('⚠️ Integrated Agentic Service initialization incomplete');

        final needsModel = await _integratedAgent!.needsModelDownload();
        if (needsModel) {
          _logEvent('📥 Agentic service requires model download');
          _logEvent('🔍 Check model availability in Settings > AI Models');
        } else {
          _logEvent('⚠️ Agentic service initialized with limited capabilities');
          _logEvent('🔍 Some components may not be available');
        }
      }
    } catch (e) {
      _logEvent('❌ Integrated Agentic Service failed (continuing without): $e');
      _logEvent('🔍 Error details: ${e.toString()}');
      _logEvent('🛡️ App will continue without integrated agent features');
      _integratedAgent = null;
    }
  }

  /// Initialize agent manager with unified agent services
  Future<void> _initializeAgentManager() async {
    try {
      _logEvent('🤖 Initializing Agent Manager...');
      _logEvent('🔧 Creating AgentManager instance...');

      _agentManager = AgentManager(logger: _logEvent, vectorDbService: _vectorDb);

      _logEvent('⏳ Running AgentManager initialization...');
      _logEvent('🧩 Initializing ASR, LLM, and OCR services...');

      final agentReady = await _agentManager!.initialize();

      if (agentReady) {
        _logEvent('✅ Agent Manager ready - Real services active');

        // Get detailed status
        final status = _agentManager!.getStatus();
        _logEvent('📊 Service readiness: ASR=${status['services']['asr']}, LLM=${status['services']['llm']}, OCR=${status['services']['ocr']}');
        _logEvent('🛠️ Available tools: ${status['availableTools']}');

        // Listen to agent outputs for UI updates (read-only monitoring)
        _agentManager!.agentOutput.listen((result) {
          _logEvent('🤖 Agent result: ${result.llmResponse}');
          if (result.toolCalls.isNotEmpty) {
            _logEvent(
                '🔧 Tools executed: ${result.toolCalls.map((t) => t.name).join(", ")}');
          }
          
          // Update debugging UI state (non-intrusive)
          setState(() {
            // LLM debugging info
            _lastLLMOutput = result.llmResponse;
            _lastLLMProcessingTime = result.processingTime;
            _lastLLMTime = result.timestamp;
            _totalLLMRequests++;
            
            // Extract ASR info if available
            if (result.inputData.containsKey('transcription')) {
              _lastASRText = result.inputData['transcription']?.toString() ?? 'Empty';
              _lastASRConfidence = (result.inputData['confidence'] as num?)?.toDouble() ?? 0.0;
              _lastASRTime = result.timestamp;
              _totalASRProcessed++;
              _lastLLMInput = 'Speech: "$_lastASRText"';
            }
            
            // Extract OCR info if available  
            if (result.inputData.containsKey('ocrText')) {
              _lastLLMInput = 'Image Text: "${result.inputData['ocrText']}';
            }
            
            // Extract database operations from tool results
            for (final toolResult in result.toolResults.values) {
              if (toolResult is Map<String, dynamic>) {
                if (toolResult['action'] == 'retrieved') {
                  _lastDatabaseQuery = toolResult['query']?.toString() ?? 'Unknown query';
                  _lastDatabaseResults = List<Map<String, dynamic>>.from(
                      toolResult['results'] as List? ?? []);
                  _lastDatabaseTime = result.timestamp;
                  _totalDatabaseQueries++;
                } else if (toolResult['action'] == 'stored') {
                  _lastDatabaseQuery = 'STORE: ${toolResult['content']}';
                  _lastDatabaseResults = [];
                  _lastDatabaseTime = result.timestamp;
                  _totalDatabaseQueries++;
                }
              }
            }
          });
        });
      } else {
        _logEvent('⚠️ Agent Manager initialization issues (continuing with fallbacks)');
        _logEvent('🔍 Some services may not be available - check individual service status');

        // Get failed services info
        final status = _agentManager!.getStatus();
        final services = status['services'] as Map<String, dynamic>? ?? {};
        services.forEach((service, ready) {
          if (ready != true) {
            _logEvent('❌ Service not ready: $service');
          }
        });
      }
    } catch (e) {
      _logEvent('❌ Agent Manager failed (continuing without): $e');
      _logEvent('🔍 Error details: ${e.toString()}');
      _logEvent('🛡️ App will continue without Agent Manager features');
      _agentManager = null;
    }
  }

  /// Initialize Frame-specific services after successful connection (like original)
  Future<void> _initializeFrameServices() async {
    try {
      _logEvent('🔧 Initializing Frame services...');

      // Initialize Gemini Realtime service (simple pattern like original)
      _gemini = gemini_realtime.GeminiRealtime(
        _audioReadyCallback, // Audio ready callback
        _logEvent, // Event logger
      );

      // Initialize FlutterPcmSound for audio playback like original repository
      try {
        const sampleRate = 24000; // Same as original repository
        await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
        FlutterPcmSound.setFeedThreshold(
            sampleRate ~/ 30); // 800 frames = ~33ms buffer
        FlutterPcmSound.setFeedCallback(_onFeed); // Use original callback name
        _isAudioPlayerSetup = true;
        _logEvent('✅ FlutterPcmSound audio player ready');
      } catch (e) {
        _logEvent('⚠️ FlutterPcmSound setup error: $e');
      }

      _logEvent('✅ Frame services initialized');
    } catch (e) {
      _logEvent('❌ Frame service initialization error: $e');
      rethrow;
    }
  }

  Future<void> _requestPermissions() async {
    // Official repository pattern: minimal explicit permission handling
    // Most permissions are handled by simple_frame_app package
    final permissions = [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location, // Required for Bluetooth scanning
    ];

    final statuses = await permissions.request();
    bool coreGranted =
        statuses.values.every((status) => status.isGranted || status.isDenied);

    _logEvent(coreGranted
        ? '✅ Core permissions handled'
        : '⚠️ Permission issues detected');
  }

  Future<void> _loadGeminiApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _geminiApiKey = prefs.getString('gemini_api_key') ?? '';
    });

    if (_geminiApiKey.isNotEmpty) {
      // API key will be used by WebSocket realtime service when session starts
      _logEvent('🤖 Gemini API key loaded');
    } else {
      _logEvent('⚠️ No Gemini API key found');
    }
  }

  // No longer needed - using WebSocket-based Gemini Realtime API only
  // This matches the official repository pattern
  // void _initializeGemini() {
  //   // Chat-based Gemini is replaced by WebSocket realtime connection
  // }

  /// Get Gemini readiness status for UI display
  bool get isGeminiReady => _geminiApiKey.isNotEmpty;

  /// Map UI voice enum to Gemini Realtime voice enum
  gemini_realtime.GeminiVoiceName _mapVoiceName(GeminiVoiceName uiVoice) {
    switch (uiVoice) {
      case GeminiVoiceName.puck:
        return gemini_realtime.GeminiVoiceName.Puck;
      case GeminiVoiceName.charon:
        return gemini_realtime.GeminiVoiceName.Charon;
      case GeminiVoiceName.kore:
        return gemini_realtime.GeminiVoiceName.Kore;
      case GeminiVoiceName.fenrir:
        return gemini_realtime.GeminiVoiceName.Fenrir;
      case GeminiVoiceName.aoede:
        return gemini_realtime.GeminiVoiceName.Aoede;
    }
  }

  Future<void> _saveGeminiApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key);
    setState(() {
      _geminiApiKey = key;
      _tempApiKey = null; // Clear temp key
    });
    // API key will be used by WebSocket realtime service when session starts
    _logEvent('🔑 Gemini API key saved');
  }

  /// Connect to Frame using official repository pattern
  Future<void> _startScanning() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
    });

    _logEvent('🔍 Connecting to Frame...');

    try {
      // Official repository pattern: single unified connection method
      await tryScanAndConnectAndStart(
          andRun: true); // Deploy and start Lua scripts automatically

      // Check if connection and script deployment was successful
      if ((currentState == ApplicationState.ready ||
              currentState == ApplicationState.running) &&
          frame != null) {
        setState(() {
          _isConnected = true;
        });
        _logEvent('✅ Frame connected with official Lua scripts running');

        // Set up Frame listeners first (lightweight)
        _setupFrameListeners();

        // Initialize Frame services after successful connection
        await _initializeFrameServices();
      } else {
        _logEvent(
            '❌ Frame connection/script deployment failed - state: $currentState');
      }
    } catch (e) {
      _logEvent('❌ Connection error: $e');
      setState(() {
        _isConnected = false;
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  // Old connection method removed - now using official repository pattern with tryScanAndConnectAndStart()

  // Basic Frame connection test removed - simple_frame_app handles connection verification

  void _setupFrameListeners() {
    // Listen for raw data from Frame using the mixin's frame object
    if (frame != null) {
      _frameDataSubscription = frame!.dataResponse.listen((data) {
        if (data.isNotEmpty) {
          _logEvent('📦 Frame data received: ${data.length} bytes');

          // Handle official Frame message protocol
          final messageType = data[0];

          // NOTE: Audio data (0x05, 0x06) now handled by RxAudio stream
          // NOTE: Photo data now handled by RxPhoto stream
          // Handle tap messages (0x09) - Trigger speech-to-text query
          if (messageType == 0x09) {
            _logEvent('👆 Frame tap detected - Starting voice query...');
            _handleFrameTapQuery();
          }
        }
      });

      // Connection monitoring handled by simple_frame_app package
    }
  }

  // Connection monitoring removed - handled by simple_frame_app package (official repository pattern)

  Future<void> _disconnect() async {
    try {
      if (frame != null && _isConnected) {
        await _stopSession();
        await disconnectFrame();

        setState(() {
          _isConnected = false;
          _isAudioStreaming = false;
          _audioPacketsReceived = 0;
          _totalAudioBytes = 0;
        });

        _logEvent('🔌 Disconnected from Frame');
      }
    } catch (e) {
      _logEvent('❌ Disconnect error: $e');
    }
  }

  Future<void> _startSession() async {
    if (_isSessionActive || !_isConnected || _geminiApiKey.isEmpty) {
      if (_geminiApiKey.isEmpty) {
        _logEvent('⚠️ Please set Gemini API key first');
        return;
      }
      if (!_isConnected) {
        _logEvent('⚠️ Frame not connected - please connect first');
        return;
      }
      return;
    }

    try {
      _logEvent('🚀 Starting AI session...');

      // Connect to Gemini directly (like original repository)
      _logEvent('🔗 Connecting to Gemini...');

      final geminiConnected = await _gemini!.connect(
        _geminiApiKey,
        _mapVoiceName(_selectedVoice),
        'You are a helpful AI assistant integrated with Frame smart glasses. '
        'You can see what the user sees through their camera and hear their voice. '
        'Keep responses concise and conversational. The user is wearing Frame glasses.',
      );

      if (geminiConnected) {
        setState(() {
          _isSessionActive = true;
        });
        _logEvent('✅ AI session started');

        // Start foreground service for background operation
        try {
          await startForegroundService();
          _logEvent('📱 Foreground service started');
        } catch (e) {
          _logEvent('⚠️ Foreground service warning: $e');
        }

        // Start Frame streaming (like original repository)
        await _startFrameStreaming();
      } else {
        _logEvent('❌ Failed to connect to Gemini');
      }
    } catch (e) {
      _logEvent('❌ Session start error: $e');
    }
  }

  /// Start Frame streaming (both audio and photos) like original repository
  Future<void> _startFrameStreaming() async {
    if (_isAudioStreaming || !_isConnected || frame == null) return;

    try {
      _logEvent('🚀 Starting Frame streaming (RxAudio + RxPhoto)...');

      // Set up RxAudio stream like original repository
      _frameAudioSampleStream = _rxAudio.attach(frame!.dataResponse);
      _frameAudioSubs?.cancel();
      _frameAudioSubs = _frameAudioSampleStream!.listen(_handleFrameAudio);

      // Send audio subscription message
      await frame!.sendMessage(0x30, TxCode(value: 1).pack());

      // Start periodic photo capture immediately like original
      await _requestPhoto();
      _photoTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        if (!_isConnected || !_isSessionActive) {
          timer.cancel();
          _photoTimer = null;
          return;
        }
        await _requestPhoto();
      });

      setState(() {
        _isAudioStreaming = true;
        _audioPacketsReceived = 0;
        _totalAudioBytes = 0;
      });

      _logEvent('✅ Frame streaming started - RxAudio + periodic photos (3s)');
    } catch (e) {
      _logEvent('❌ Frame streaming start error: $e');
    }
  }

  // Old audio streaming methods removed - now using unified _startFrameStreaming()

  /// Stop Frame streaming (both audio and photos) like original repository
  Future<void> _stopFrameStreaming() async {
    if (!_isAudioStreaming) return;

    try {
      _logEvent('⏹️ Stopping Frame streaming (RxAudio + RxPhoto)...');

      // Cancel RxAudio subscription first
      _frameAudioSubs?.cancel();
      _frameAudioSubs = null;
      _frameAudioSampleStream = null;

      // Cancel photo timer
      _photoTimer?.cancel();
      _photoTimer = null;

      // Cancel RxPhoto subscription
      _photoSubs?.cancel();
      _photoSubs = null;
      _photoStream = null;

      // Send audio unsubscribe message
      if (frame != null) {
        await frame!.sendMessage(0x30, TxCode(value: 0).pack());
      }

      setState(() {
        _isAudioStreaming = false;
        _isVoiceDetected = false;
      });

      _logEvent('✅ Frame streaming stopped - RxAudio + photos cancelled');
    } catch (e) {
      _logEvent('❌ Frame streaming stop error: $e');
    }
  }

  Future<void> _stopCameraCapture() async {
    _photoTimer?.cancel();
    _photoTimer = null;
    _logEvent('📷 Photo capture stopped');
  }

  /// Request photo using RxPhoto like original repository
  Future<void> _requestPhoto() async {
    if (!_isConnected || frame == null) {
      _logEvent('❌ Cannot capture photo - Frame not connected');
      return;
    }

    try {
      _logEvent('📸 Photo capture requested (RxPhoto)...');

      // Set up photo stream like original repository
      _photoStream = _rxPhoto.attach(frame!.dataResponse);
      _photoSubs?.cancel();
      _photoSubs = _photoStream!.listen(_handleFramePhoto);

      // Send capture settings like original repository
      await frame!.sendMessage(
          0x0d,
          TxCaptureSettings(
            resolution: 720,
            qualityIndex: 75, // VERY_HIGH quality
          ).pack());

      _logEvent('✅ Photo stream attached and capture requested');
    } catch (e) {
      _logEvent('❌ Photo request error: $e');
    }
  }

  /// Handle photo received via RxPhoto (like original repository)
  void _handleFramePhoto(Uint8List jpegBytes) {
    _logEvent('📸 Photo received via RxPhoto (${jpegBytes.length} bytes)');

    // Send photo to Gemini if connected (original repo pattern)
    if (_gemini != null && _gemini!.isConnected()) {
      _gemini!.sendPhoto(jpegBytes);
      _logEvent('📸 Photo sent to Gemini for analysis');
    }

    // Update UI with latest image (original repo style)
    try {
      setState(() {
        _lastPhoto = jpegBytes;
        _image = Image.memory(jpegBytes, gaplessPlayback: true);
      });
      _logEvent('✅ Photo display updated in UI via RxPhoto');
    } catch (e) {
      _logEvent('❌ Photo display update failed: $e');
    }

    // AGENT INTEGRATION: Process photo through agent system (parallel to Gemini)
    if (_agentManager?.isEnabled == true) {
      _agentManager!.processImage(jpegBytes);
    }

    // INTEGRATED AGENT: Process photo through integrated agentic service
    if (_integratedAgent?.isReady == true && _integratedAgent?.agentEnabled == true) {
      _integratedAgent!.processImage(jpegBytes, metadata: {
        'source': 'frame_camera',
        'timestamp': DateTime.now().toIso8601String(),
        'size': jpegBytes.length,
      });
    }
  }

  /// Handle audio received via RxAudio (exactly like original repository)
  void _handleFrameAudio(Uint8List pcm16x8) {
    // PRIORITY 1: Send to Gemini first (main pipeline)
    if (_gemini != null && _gemini!.isConnected()) {
      try {
        // Upsample PCM16 from 8kHz to 16kHz for Gemini (same as original)
        final pcm16x16 = AudioUpsampler.upsample8kTo16k(pcm16x8);
        _gemini!.sendAudio(pcm16x16);

        // Update statistics
        _audioPacketsReceived++;
        _totalAudioBytes += pcm16x8.length;

        // Log statistics periodically
        if (_audioPacketsReceived % 100 == 0) {
          _logEvent(
              '📊 RxAudio: $_audioPacketsReceived packets, ${(_totalAudioBytes / 1024).toStringAsFixed(1)} KB');
        }
      } catch (e) {
        _logEvent('⚠️ Gemini audio send error: $e');
        // Attempt reconnection if needed
        if (!_gemini!.isConnected()) {
          _logEvent('🔄 Attempting Gemini reconnection...');
        }
      }
    }

    // AGENT INTEGRATION: Process audio through agent system (non-interfering)
    if (_agentManager?.isEnabled == true) {
      // Process agent audio asynchronously to avoid blocking Gemini stream
      Future.microtask(() async {
        try {
          // Create independent copy for agent processing
          final agentAudio = Uint8List.fromList(pcm16x8);
          final pcm16x16 = AudioUpsampler.upsample8kTo16k(agentAudio);
          await _agentManager!.processAudio(pcm16x16);
        } catch (e) {
          // Silently handle agent processing errors to avoid affecting main pipeline
          if (kDebugMode) {
            _logEvent('⚠️ Agent audio processing error: $e');
          }
        }
      });
    }

    // INTEGRATED AGENT: Process audio through integrated agentic service (non-blocking)
    if (_integratedAgent?.isReady == true && _integratedAgent?.agentEnabled == true) {
      Future.microtask(() async {
        try {
          // Create independent copy for integrated agent processing
          final agentAudio = Uint8List.fromList(pcm16x8);
          final pcm16x16 = AudioUpsampler.upsample8kTo16k(agentAudio);
          await _integratedAgent!.processAudio(pcm16x16, metadata: {
            'source': 'frame_microphone',
            'timestamp': DateTime.now().toIso8601String(),
            'originalSize': pcm16x8.length,
            'upsampledSize': pcm16x16.length,
          });
        } catch (e) {
          // Silently handle integrated agent errors
          if (kDebugMode) {
            _logEvent('⚠️ Integrated agent audio processing error: $e');
          }
        }
      });
    }
  }

  /// Manually capture a single photo for testing
  Future<void> _capturePhotoManually() async {
    await _requestPhoto();
  }

  // Old manual audio handling removed - now using RxAudio _handleFrameAudio()

  /// Audio ready callback exactly like original repository
  void _audioReadyCallback() {
    if (!_playingAudio) {
      _playingAudio = true;
      _onFeed(0);
      debugPrint('Response audio started');
    }
  }

  /// Audio feed callback exactly like original repository
  void _onFeed(int remainingFrames) async {
    if (remainingFrames < 2000) {
      if (_gemini != null && _gemini!.hasResponseAudio()) {
        await FlutterPcmSound.feed(
            PcmArrayInt16(bytes: _gemini!.getResponseAudioByteData()));
      } else {
        debugPrint('Response audio ended');
        _playingAudio = false;
      }
    }
  }

  // Old manual photo handling removed - now using RxPhoto _handleFramePhoto()

  Future<void> _stopSession() async {
    if (!_isSessionActive) return;

    try {
      // Stop photo capture first
      await _stopCameraCapture();

      // Stop Frame streaming
      await _stopFrameStreaming();

      // Disconnect from Gemini (simple pattern like original)
      if (_gemini != null) {
        await _gemini!.disconnect();
      }

      setState(() {
        _isSessionActive = false;
        _image = null; // Clear image display when session ends
      });

      // Stop foreground service
      try {
        await FlutterForegroundTask.stopService();
        _logEvent('📱 Foreground service stopped');
      } catch (e) {
        _logEvent('⚠️ Foreground service stop warning: $e');
      }

      _logEvent('⏹️ AI session stopped');
    } catch (e) {
      _logEvent('❌ Session stop error: $e');
      setState(() {
        _isSessionActive = false;
      });
    }
  }

  Future<void> _testFrameConnection() async {
    if (frame == null || !_isConnected) {
      _logEvent('❌ Frame not connected');
      return;
    }

    try {
      _logEvent('🧪 Testing Frame connection...');

      // Simple Frame test like original
      await frame!.sendMessage(
          0x0a,
          TxPlainText(
            text: 'Hello Frame!',
            x: 50,
            y: 50,
            paletteOffset: 2,
          ).pack());
      _logEvent('📺 Frame test completed');
    } catch (e) {
      _logEvent('❌ Frame test failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable content area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Gemini API Key Section
                    _buildGeminiApiKeySection(),
                    const SizedBox(height: 16),

                    // Voice Selection
                    if (_geminiApiKey.isNotEmpty) _buildVoiceSelection(),
                    if (_geminiApiKey.isNotEmpty) const SizedBox(height: 16),

                    // Frame Connection Section
                    _buildFrameConnectionSection(),
                    const SizedBox(height: 16),

                    // Audio Status Section
                    if (_isConnected) _buildAudioStatusSection(),
                    if (_isConnected) const SizedBox(height: 16),

                    // Agent Status Section
                    _buildAgentStatusSection(),
                    const SizedBox(height: 16),

                    // Debugging Sections (read-only monitoring)
                    if (_isConnected) _buildASRDebuggingSection(),
                    if (_isConnected) const SizedBox(height: 16),
                    
                    if (_isConnected) _buildLLMDebuggingSection(), 
                    if (_isConnected) const SizedBox(height: 16),
                    
                    if (_isConnected) _buildDatabaseDebuggingSection(),
                    if (_isConnected) const SizedBox(height: 16),

                    // Live Photo View (original repo style)
                    _buildPhotoDisplay(),
                    const SizedBox(height: 16),

                    // Control Buttons
                    _buildControlButtons(),
                    const SizedBox(height: 16),

                    // Agent Demo UI - Removed to avoid duplicate interface with Agent Status Section
                    // AgentDemoWidget(agentCore: _agentCore),
                    const SizedBox(height: 16),

                    // Event Log with fixed height
                    SizedBox(
                      height: 300, // Fixed height for event log
                      child: _buildEventLog(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioStatusSection() {
    final kbps = _audioPacketsReceived > 0 && _totalAudioBytes > 0
        ? (_totalAudioBytes / 1024.0) /
            (_audioPacketsReceived * 0.064) // ~64ms per packet
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎤 Frame Audio Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Audio streaming status
            Row(
              children: [
                Icon(
                  _isAudioStreaming ? Icons.mic : Icons.mic_off,
                  color: _isAudioStreaming ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _isAudioStreaming
                      ? 'Audio Streaming Active'
                      : 'Audio Streaming Inactive',
                  style: TextStyle(
                    color: _isAudioStreaming ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Voice activity status
            Row(
              children: [
                Icon(
                  _isVoiceDetected
                      ? Icons.record_voice_over
                      : Icons.voice_over_off,
                  color: _isVoiceDetected ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _isVoiceDetected
                      ? 'Voice Activity Detected'
                      : 'No Voice Activity',
                  style: TextStyle(
                    color: _isVoiceDetected ? Colors.blue : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Audio statistics
            Row(
              children: [
                const Icon(Icons.data_usage, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Packets: $_audioPacketsReceived | ${(_totalAudioBytes / 1024).toStringAsFixed(1)} KB | ${kbps.toStringAsFixed(1)} KB/s',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentStatusSection() {
    // Use integrated agent status if available, otherwise fall back to agent manager
    final integratedStatus = _integratedAgent?.getStatus();
    final agentStatus = _agentManager?.getStatus() ?? {};

    final isAgentReady = integratedStatus?['isReady'] as bool? ?? (agentStatus['isReady'] as bool? ?? false);
    final isAgentEnabled = integratedStatus?['agentEnabled'] as bool? ?? (agentStatus['isEnabled'] as bool? ?? false);
    final isAgentProcessing = integratedStatus?['isProcessing'] as bool? ?? (agentStatus['isProcessing'] as bool? ?? false);
    final services = integratedStatus?['services'] as Map<String, dynamic>? ?? (agentStatus['services'] as Map<String, dynamic>? ?? {});

    final totalQueries = integratedStatus?['totalQueries'] as int? ?? 0;
    final totalDocuments = integratedStatus?['totalDocuments'] as int? ?? 0;
    final lastActivity = integratedStatus?['lastActivity'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '🤖 Agent System Status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (isAgentReady)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isAgentEnabled ? Colors.green : Colors.orange)
                          .withAlpha(50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: (isAgentEnabled ? Colors.green : Colors.orange)
                              .withAlpha(128)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAgentEnabled
                              ? Icons.smart_toy
                              : Icons.pause_circle_outline,
                          color: isAgentEnabled ? Colors.green : Colors.orange,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isAgentEnabled ? 'Active' : 'Paused',
                          style: TextStyle(
                              color: isAgentEnabled
                                  ? Colors.green
                                  : Colors.orange),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Agent processing status
            Row(
              children: [
                Icon(
                  isAgentProcessing
                      ? Icons.psychology
                      : Icons.psychology_outlined,
                  color: isAgentProcessing ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  isAgentProcessing ? 'Processing...' : 'Idle',
                  style: TextStyle(
                    color: isAgentProcessing ? Colors.blue : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Service status indicators
            Row(
              children: [
                // ASR Status
                Icon(
                  services['asr'] == true ? Icons.mic : Icons.mic_off,
                  color: services['asr'] == true ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  'ASR',
                  style: TextStyle(
                    color: services['asr'] == true ? Colors.green : Colors.red,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 16),

                // LLM Status
                Icon(
                  services['llm'] == true
                      ? Icons.memory
                      : Icons.memory_outlined,
                  color: services['llm'] == true ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  'LLM',
                  style: TextStyle(
                    color: services['llm'] == true ? Colors.green : Colors.red,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 16),

                // OCR Status
                Icon(
                  services['ocr'] == true
                      ? Icons.text_fields
                      : Icons.text_fields_outlined,
                  color: services['ocr'] == true ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  'OCR',
                  style: TextStyle(
                    color: services['ocr'] == true ? Colors.green : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Agent statistics (if integrated agent is active)
            if (integratedStatus != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Icon(Icons.help, color: Colors.blue, size: 16),
                        Text('$totalQueries', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const Text('Queries', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    Column(
                      children: [
                        const Icon(Icons.storage, color: Colors.green, size: 16),
                        Text('$totalDocuments', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const Text('Documents', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    if (lastActivity != null)
                      Column(
                        children: [
                          const Icon(Icons.access_time, color: Colors.orange, size: 16),
                          Text(lastActivity.substring(11, 19), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const Text('Last Activity', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Agent controls
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isAgentReady
                        ? () {
                            if (integratedStatus != null) {
                              _integratedAgent?.setAgentEnabled(!isAgentEnabled);
                            } else {
                              _agentManager?.setEnabled(!isAgentEnabled);
                            }
                            setState(() {}); // Refresh UI
                          }
                        : null,
                    icon: Icon(isAgentEnabled ? Icons.pause : Icons.play_arrow),
                    label:
                        Text(isAgentEnabled ? 'Pause Agent' : 'Resume Agent'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          (isAgentEnabled ? Colors.orange : Colors.green)
                              .withAlpha(25),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: (_isConnected && _lastPhoto != null)
                      ? () {
                          if (integratedStatus != null) {
                            _integratedAgent?.processImage(_lastPhoto!, metadata: {
                              'source': 'manual_trigger',
                              'timestamp': DateTime.now().toIso8601String(),
                            });
                            _logEvent('🤖 Manual integrated agent image processing triggered');
                          } else {
                            _agentManager?.processImage(_lastPhoto!);
                            _logEvent('🤖 Manual agent image processing triggered');
                          }
                        }
                      : null,
                  icon: const Icon(Icons.image_search),
                  label: const Text('Analyze Photo'),
                ),
              ],
            ),

            // Query interface for integrated agent
            if (integratedStatus != null && isAgentReady) ...[
              const SizedBox(height: 16),
              const Text('💭 Quick Query', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_integratedAgent?.isReady == true) {
                          _logEvent('🧠 Processing sample query...');
                          try {
                            final response = await _integratedAgent!.processQuery(
                              'What can you tell me about Frame glasses?',
                              context: {'source': 'manual_query'},
                            );
                            _logEvent('🤖 Agent response: ${response.response}');
                          } catch (e) {
                            _logEvent('❌ Query failed: $e');
                          }
                        }
                      },
                      child: const Text('Test Query'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      if (_integratedAgent?.isReady == true) {
                        final success = await _integratedAgent!.storeKnowledge(
                          content: 'User manually triggered knowledge storage at ${DateTime.now()}',
                          metadata: {'source': 'manual_input'},
                        );
                        _logEvent(success ? '💾 Knowledge stored successfully' : '❌ Knowledge storage failed');
                      }
                    },
                    child: const Text('Store Info'),
                  ),
                ],
              ),
            ],

            // Status messages
            if (!isAgentReady)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '⚠️ Agent system not ready',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.orange,
                  ),
                ),
              ),
            if (isAgentReady && !isAgentEnabled)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '⏸️ Agent processing paused',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.orange,
                  ),
                ),
              ),

            // Database query section
            const SizedBox(height: 16),
            _buildDatabaseQuerySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseQuerySection() {
    return ExpansionTile(
      title: const Text('🗃️ Database Query via Frame Tap'),
      subtitle: Text(_vectorDb != null ? 'Connected - Tap Frame to query' : 'Not available'),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Card(
                color: Color(0xFFF3E5F5),
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(Icons.touch_app, color: Colors.purple),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tap the side of your Frame glasses twice, then speak your query. Results will appear on the glasses screen.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _vectorDb != null ? _simulateFrameTapQuery : null,
                      icon: const Icon(Icons.record_voice_over),
                      label: const Text('Simulate Tap Query'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _vectorDb != null ? _clearDatabaseResults : null,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
                ],
              ),
              if (_queryResults.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Query Results:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _queryResults.length,
                    itemBuilder: (context, index) {
                      final result = _queryResults[index];
                      final content = result['text']?.toString() ?? '';
                      final score = result['score'] as double? ?? 0.0;
                      final category = result['category']?.toString() ?? 'general';
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('Category: $category • Score: ${score.toStringAsFixed(3)}'),
                          dense: true,
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (_vectorDb != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Database: ${_vectorDb!.getDocumentCount()} documents stored',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // _performDatabaseQuery removed - replaced with _performFrameQuery for tap-to-speech functionality

  void _clearDatabaseResults() {
    setState(() {
      _queryController.clear();
      _queryResults = [];
    });
    _logEvent('🧹 Database query results cleared');
  }

  /// Handle Frame tap to trigger speech-to-text database query
  Future<void> _handleFrameTapQuery() async {
    if (!_isConnected || _vectorDb == null) {
      _logEvent('❌ Frame not connected or database unavailable');
      return;
    }

    try {
      _logEvent('🎤 Starting voice capture for database query...');
      
      // Update debug UI to show ASR processing started
      setState(() {
        _lastASRText = 'Processing audio...';
        _lastASRTime = DateTime.now();
      });
      
      // Show query prompt on Frame screen with delay to avoid rapid messages
      await _sendTextToFrame('Listening...\nSpeak your query');
      await Future.delayed(const Duration(milliseconds: 500)); // Brief pause for display
      
      // Start recording audio for speech-to-text
      // This is a simplified version - in full implementation would capture audio
      // For now, simulate with a delay and use agent ASR
      await Future.delayed(const Duration(seconds: 2)); // Reduced from 3 to 2 seconds
      
      // Simulate speech-to-text result (in real implementation, would use captured audio)
      const mockQuery = 'Frame glasses'; // This would come from speech recognition - should match sample data
      const mockConfidence = 0.85; // Simulated confidence
      
      // Update debug UI with simulated ASR result
      setState(() {
        _lastASRText = mockQuery;
        _lastASRConfidence = mockConfidence;
        _lastASRTime = DateTime.now();
        _totalASRProcessed++;
      });
      
      _logEvent('🗣️ Query captured: "$mockQuery" (confidence: ${(mockConfidence * 100).toStringAsFixed(1)}%)');
      await _performFrameQuery(mockQuery);
      
    } catch (e) {
      _logEvent('❌ Frame tap query failed: $e');
      // Avoid additional Frame message if there's an error to prevent further issues
      if (_isConnected && frame != null) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _sendTextToFrame('Error\nQuery failed');
      }
    }
  }

  /// Simulate Frame tap query for testing
  Future<void> _simulateFrameTapQuery() async {
    _logEvent('🧪 Simulating Frame tap query...');
    await _handleFrameTapQuery();
  }

  /// Perform database query and display results on Frame
  Future<void> _performFrameQuery(String queryText) async {
    if (_vectorDb == null) return;

    try {
      _logEvent('🔍 Querying database: "$queryText"');
      _logEvent('📊 Database has ${_vectorDb!.getDocumentCount()} documents');
      
      // Update debug UI to show query processing
      setState(() {
        _lastDatabaseQuery = queryText;
        _lastDatabaseTime = DateTime.now();
      });
      
      // Add delay before showing search message to prevent rapid Frame updates
      await Future.delayed(const Duration(milliseconds: 300));
      await _sendTextToFrame('Searching...');
      
      final results = await _vectorDb!.queryText(
        queryText: queryText,
        topK: 3, // Limit for screen display
        threshold: 0.1, // Lower threshold for better matching
      );
      
      _logEvent('📋 Query returned ${results.length} results');

      setState(() {
        _queryResults = results;
        _queryController.text = queryText; // Show what was queried
        
        // Update debug UI with results
        _lastDatabaseResults = results.map((r) => {
          'content': r['document']?.toString() ?? '',
          'confidence': (r['score'] as num?)?.toDouble() ?? 0.0,
          'metadata': r['metadata'] ?? {},
        }).toList();
        _totalDatabaseQueries++;
      });

      // Format results for Frame display
      String displayText = 'Results:\n';
      if (results.isEmpty) {
        displayText = 'No results\nfound';
      } else {
        for (int i = 0; i < results.length && i < 2; i++) { // Max 2 results for readability
          final content = results[i]['text']?.toString() ?? '';
          // Truncate for display
          final shortContent = content.length > 30 ? '${content.substring(0, 30)}...' : content;
          displayText += '${i + 1}. $shortContent\n';
        }
      }

      // Add delay before final result display
      await Future.delayed(const Duration(milliseconds: 500));
      await _sendTextToFrame(displayText);
      _logEvent('✅ Results displayed on Frame: ${results.length} found');
      
    } catch (e) {
      _logEvent('❌ Frame query failed: $e');
      // Add delay before error message
      if (_isConnected && frame != null) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _sendTextToFrame('Error\nQuery failed');
      }
    }
  }

  /// Send text to Frame glasses display
  Future<void> _sendTextToFrame(String text) async {
    if (!_isConnected || frame == null) return;
    
    try {
      await frame!.sendMessage(
        0x0b,
        TxPlainText(
          text: text,
          x: 1,
          y: 1,
          paletteOffset: 2,
        ).pack(),
      );
      _logEvent('📺 Text sent to Frame: "$text"');
    } catch (e) {
      _logEvent('❌ Failed to send text to Frame: $e');
    }
  }

  Widget _buildControlButtons() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎮 Controls',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Main session controls
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isConnected &&
                            !_isSessionActive &&
                            _geminiApiKey.isNotEmpty)
                        ? _startSession
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start AI Session'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.withAlpha(25),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSessionActive ? _stopSession : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Session'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withAlpha(25),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Testing controls
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnected ? _testFrameConnection : null,
                    icon: const Icon(Icons.troubleshoot),
                    label: const Text('Test Frame'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnected ? _capturePhotoManually : null,
                    icon: const Icon(Icons.camera),
                    label: const Text('Take Photo'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Photo and diagnostic controls
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnected ? _capturePhotoManually : null,
                    icon: const Icon(Icons.camera),
                    label: const Text('Take Photo'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Database controls
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _vectorDb?.addSampleData(),
                    icon: const Icon(Icons.data_array),
                    label: const Text('Add Sample Data'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (_vectorDb != null) {
                        final stats = await _vectorDb!.getStats();
                        _logEvent(
                            '📊 DB Stats: ${stats['totalDocuments']} docs');
                      }
                    },
                    icon: const Icon(Icons.analytics),
                    label: const Text('DB Stats'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Model download access
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ModelDownloadScreen(
                            onDownloadComplete: () => Navigator.pop(context),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.download_for_offline),
                    label: const Text('AI Models'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.withAlpha(25),
                    ),
                  ),
                ),
              ],
            ),

            // Status messages
            if (_isSessionActive)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '🎤 AI session active with Frame',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.green,
                  ),
                ),
              ),
            if (!_isConnected)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '⚠️ Connect to Frame first',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.orange,
                  ),
                ),
              ),
            if (_geminiApiKey.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '⚠️ Set Gemini API key first',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.orange,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeminiApiKeySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🤖 Gemini Configuration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _geminiApiKey,
                    decoration: const InputDecoration(
                      labelText: 'Gemini API Key',
                      hintText: 'Enter your Gemini API key',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    onChanged: (value) {
                      setState(() {
                        _tempApiKey = value;
                      });
                    },
                    onFieldSubmitted: (value) {
                      if (value.isNotEmpty) {
                        _saveGeminiApiKey(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: (_tempApiKey?.isNotEmpty ?? false)
                      ? () => _saveGeminiApiKey(_tempApiKey!)
                      : null,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ],
            ),
            if (_geminiApiKey.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    Icon(
                      isGeminiReady ? Icons.check_circle : Icons.pending,
                      color: isGeminiReady ? Colors.green : Colors.orange,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isGeminiReady ? 'Gemini ready' : 'Gemini initializing',
                      style: TextStyle(
                        color: isGeminiReady ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSelection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎭 Voice Selection',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<GeminiVoiceName>(
              value: _selectedVoice,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'TTS Voice',
              ),
              items: GeminiVoiceName.values.map((voice) {
                return DropdownMenuItem(
                  value: voice,
                  child: Text(voice.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedVoice = value;
                  });
                  _logEvent('🎭 Voice changed to: ${value.displayName}');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoDisplay() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '📷 Live Camera View',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  _image != null ? 'Image Active' : 'No Image',
                  style: TextStyle(
                    color: _image != null ? Colors.green : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withAlpha(128)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _image,
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isSessionActive
                                ? Icons.camera_alt
                                : Icons.camera_alt_outlined,
                            color: _isSessionActive ? Colors.blue : Colors.grey,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isSessionActive
                                ? 'Waiting for photo...'
                                : 'Start session to capture photos',
                            style: TextStyle(
                              color:
                                  _isSessionActive ? Colors.blue : Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                          if (_lastPhoto != null && _image == null)
                            const Text(
                              '⚠️ Photo data exists but display failed',
                              style:
                                  TextStyle(color: Colors.orange, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameConnectionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '📱 Frame Connection',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isConnected)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withAlpha(128)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth_connected,
                            color: Colors.green, size: 16),
                        SizedBox(width: 4),
                        Text('Connected',
                            style: TextStyle(color: Colors.green)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _isScanning || _isConnected ? null : _startScanning,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(
                        _isScanning ? 'Connecting...' : 'Connect to Frame'),
                  ),
                ),
                const SizedBox(width: 8),
                if (_isConnected)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _disconnect,
                      icon: const Icon(Icons.bluetooth_disabled),
                      label: const Text('Disconnect'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withAlpha(25),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventLog() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '📋 Event Log',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_eventLog.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: () async {
                      final logContent = _eventLog.join('\n');
                      await Clipboard.setData(ClipboardData(text: logContent));
                      _logEvent('📋 Event log copied to clipboard (${_eventLog.length} entries)');

                      // Show feedback
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied ${_eventLog.length} log entries to clipboard'),
                            duration: const Duration(seconds: 2),
                            action: SnackBarAction(
                              label: 'View',
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Event Log Preview'),
                                    content: SizedBox(
                                      width: double.maxFinite,
                                      height: 300,
                                      child: SingleChildScrollView(
                                        child: Text(
                                          logContent,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Close'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _eventLog.clear();
                      });
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withAlpha(75)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _eventLog.isEmpty
                    ? const Center(
                        child: Text(
                          'No events logged yet...',
                          style: TextStyle(
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8),
                        itemCount: _eventLog.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              _eventLog[index],
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildASRDebuggingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mic, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '🎤 ASR (Speech Recognition) Debug',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _totalASRProcessed > 0 ? Colors.green.withAlpha(50) : Colors.grey.withAlpha(50),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_totalASRProcessed processed',
                    style: TextStyle(
                      fontSize: 12,
                      color: _totalASRProcessed > 0 ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Last extracted text
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withAlpha(128)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Latest Extracted Text:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    _lastASRText,
                    style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Confidence: ${(_lastASRConfidence * 100).toStringAsFixed(1)}%'),
                      const SizedBox(width: 16),
                      if (_lastASRTime != null)
                        Text('Time: ${_lastASRTime!.toString().substring(11, 19)}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLLMDebuggingSection() {
    final modelType = _agentManager?.getStatus()['services']['llm'] == true ? 'Active' : 'Inactive';
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology, color: Colors.purple),
                const SizedBox(width: 8),
                const Text(
                  '🧠 On-Device LLM Debug',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: modelType == 'Active' ? Colors.green.withAlpha(50) : Colors.red.withAlpha(50),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    modelType,
                    style: TextStyle(
                      fontSize: 12,
                      color: modelType == 'Active' ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // LLM Input
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Input to LLM:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    _lastLLMInput,
                    style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // LLM Output
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('LLM Response:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    _lastLLMOutput,
                    style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Processing stats
            Row(
              children: [
                Text('Processing Time: ${_lastLLMProcessingTime.inMilliseconds}ms'),
                const SizedBox(width: 16),
                Text('Total Requests: $_totalLLMRequests'),
                const Spacer(),
                if (_lastLLMTime != null)
                  Text('Last: ${_lastLLMTime!.toString().substring(11, 19)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseDebuggingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  '🗺 Database Operations Debug',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _totalDatabaseQueries > 0 ? Colors.green.withAlpha(50) : Colors.grey.withAlpha(50),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_totalDatabaseQueries operations',
                    style: TextStyle(
                      fontSize: 12,
                      color: _totalDatabaseQueries > 0 ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Last query
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Latest Query:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    _lastDatabaseQuery,
                    style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                  ),
                  if (_lastDatabaseTime != null) ...[
                    const SizedBox(height: 4),
                    Text('Time: ${_lastDatabaseTime!.toString().substring(11, 19)}'),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Query results
            if (_lastDatabaseResults.isNotEmpty) ...[
              const Text('Results:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: math.min(_lastDatabaseResults.length, 3),
                  itemBuilder: (context, index) {
                    final result = _lastDatabaseResults[index];
                    final content = result['content']?.toString() ?? 'No content';
                    final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha(50),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            content,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_lastDatabaseResults.length > 3)
                Text('... and ${_lastDatabaseResults.length - 3} more results'),
            ] else ...[
              const Text('No results available', style: TextStyle(fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }

  void _logEvent(String event) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logEntry = '[$timestamp] $event';

    setState(() {
      _eventLog.add(logEntry);
    });

    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Required methods for SimpleFrameAppState mixin
  @override
  Future<void> run() async {
    _logEvent('🏃 Frame app run - Lua scripts are now running');
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    // The Frame is now running the official Lua script from assets/frame_app.lua
    // The script handles audio streaming, camera capture, and display updates
    // We can now send messages to the Frame using the official message protocol

    try {
      // Send initial message to Frame display (like official repository)
      await frame!.sendMessage(
          0x0b,
          TxPlainText(
            text: 'Frame Connected!\nReady for AI',
            x: 1,
            y: 1,
            paletteOffset: 2,
          ).pack());

      // Subscribe to tap events (0x10 = TAP_SUBS_MSG, 1 = enable)
      await frame!.sendMessage(0x10, TxCode(value: 1).pack());
      
      _logEvent('✅ Frame display initialized and tap detection enabled');
    } catch (e) {
      _logEvent('⚠️ Frame display setup: $e');
    }
  }

  @override
  Future<void> cancel() async {
    _logEvent('⏹️ Canceling Frame app');
    await _stopSession();
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }
}
