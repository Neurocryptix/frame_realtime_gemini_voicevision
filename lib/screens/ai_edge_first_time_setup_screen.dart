import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ai_edge_auto_init_service.dart';

/// First-Time Setup Screen for AI Edge RAG System
/// Shown on first app launch to download and configure Gemma 3 model
class AIEdgeFirstTimeSetupScreen extends StatefulWidget {
  final VoidCallback? onSetupComplete;
  
  const AIEdgeFirstTimeSetupScreen({
    super.key,
    this.onSetupComplete,
  });

  @override
  State<AIEdgeFirstTimeSetupScreen> createState() => _AIEdgeFirstTimeSetupScreenState();
}

class _AIEdgeFirstTimeSetupScreenState extends State<AIEdgeFirstTimeSetupScreen>
    with TickerProviderStateMixin {
  
  late AIEdgeAutoInitService _autoInitService;
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;
  
  StreamSubscription<AIEdgeInitStatus>? _initSubscription;
  
  // UI State
  AIEdgeInitStatus? _currentStatus;
  bool _isSetupStarted = false;
  bool _isSetupComplete = false;
  bool _showAdvancedOptions = false;
  
  // Controllers
  final _modelUrlController = TextEditingController();
  final _scrollController = ScrollController();
  final _kaggleUsernameController = TextEditingController();
  final _kaggleApiKeyController = TextEditingController();
  
  // Setup logs
  final List<String> _setupLogs = [];

  @override
  void initState() {
    super.initState();
    
    _autoInitService = AIEdgeAutoInitService(logger: _addLog);
    
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _animationController.repeat(reverse: true);
    
    _addLog('👋 Welcome to AI Edge RAG Setup');
    _addLog('🚀 Preparing to download Gemma 3 model...');
    
    // Pre-fill with sample Kaggle URL format
    _modelUrlController.text = 'https://www.kaggle.com/models/google/gemma-3/';
  }

  @override
  void dispose() {
    _initSubscription?.cancel();
    _animationController.dispose();
    _modelUrlController.dispose();
    _scrollController.dispose();
    _kaggleUsernameController.dispose();
    _kaggleApiKeyController.dispose();
    _autoInitService.dispose();
    super.dispose();
  }

  /// Add log message
  void _addLog(String message) {
    if (mounted) {
      setState(() {
        _setupLogs.add('${DateTime.now().toString().substring(11, 19)} $message');
      });
      
      // Auto-scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// Start automatic setup process
  Future<void> _startSetup() async {
    if (_isSetupStarted) return;
    
    setState(() {
      _isSetupStarted = true;
    });

    String? modelUrl;
    Map<String, String>? kaggleCredentials;

    // Check which setup method is selected
    if (!_showAdvancedOptions) {
      // Kaggle authentication mode
      final username = _kaggleUsernameController.text.trim();
      final apiKey = _kaggleApiKeyController.text.trim();
      
      if (username.isEmpty || apiKey.isEmpty) {
        _addLog('❌ Please provide both Kaggle username and API key');
        setState(() {
          _isSetupStarted = false;
        });
        return;
      }
      
      kaggleCredentials = {
        'username': username,
        'api_key': apiKey,
      };
      _addLog('🔑 Using Kaggle authentication...');
    } else {
      // Manual URL mode
      modelUrl = _modelUrlController.text.trim();
      
      if (modelUrl.isEmpty) {
        _addLog('❌ Please provide a model URL');
        setState(() {
          _isSetupStarted = false;
        });
        return;
      }
      _addLog('🔗 Using manual model URL...');
    }

    _addLog('🚀 Starting automatic setup...');
    
    // Start initialization stream
    _initSubscription = _autoInitService.startAutoInitialization(
      modelUrl: modelUrl,
      kaggleCredentials: kaggleCredentials,
      forceDownload: false,
    ).listen(
      (status) {
        setState(() {
          _currentStatus = status;
        });
        
        _addLog('${_getStatusEmoji(status.stage)} ${status.message}');
        
        if (status.isComplete) {
          _onSetupComplete();
        } else if (status.isError) {
          _onSetupError(status.message);
        }
      },
      onError: (error) {
        _addLog('❌ Setup error: $error');
        _onSetupError(error.toString());
      },
    );
  }

  /// Handle setup completion
  void _onSetupComplete() {
    setState(() {
      _isSetupComplete = true;
    });
    
    _addLog('🎉 Setup completed successfully!');
    _addLog('✅ AI Edge RAG is ready to use');
    
    // Stop animation
    _animationController.stop();
    
    // Call completion callback after delay
    Future.delayed(const Duration(seconds: 2), () {
      widget.onSetupComplete?.call();
    });
  }

  /// Handle setup error
  void _onSetupError(String error) {
    setState(() {
      _isSetupStarted = false;
    });
    
    // Provide specific guidance based on error type
    if (error.toLowerCase().contains('authentication failed') || error.contains('401')) {
      _addLog('🔑 Check your Kaggle username and API key');
      _addLog('💡 Make sure your API key is correct and not expired');
      _showKaggleAuthErrorDialog();
    } else if (error.toLowerCase().contains('access denied') || error.contains('403')) {
      _addLog('🚫 Accept the model terms on Kaggle first');
      _addLog('💡 Visit the Gemma 3 model page and accept terms');
      _showKaggleAccessErrorDialog();
    } else if (error.toLowerCase().contains('network') || error.toLowerCase().contains('connection')) {
      _addLog('🌐 Check your internet connection');
      _addLog('💡 You can retry setup when online');
    } else {
      _addLog('💡 You can retry setup or check your configuration');
    }
  }

  /// Get emoji for status stage
  String _getStatusEmoji(AIEdgeInitStage stage) {
    switch (stage) {
      case AIEdgeInitStage.checking:
        return '🔍';
      case AIEdgeInitStage.compatible:
        return '✅';
      case AIEdgeInitStage.storageCheck:
        return '💾';
      case AIEdgeInitStage.modelReady:
        return '🧠';
      case AIEdgeInitStage.needsUrl:
        return '🔗';
      case AIEdgeInitStage.downloading:
        return '📥';
      case AIEdgeInitStage.downloaded:
        return '✅';
      case AIEdgeInitStage.verifying:
        return '🔍';
      case AIEdgeInitStage.verified:
        return '✅';
      case AIEdgeInitStage.testing:
        return '🧪';
      case AIEdgeInitStage.complete:
        return '🎉';
      case AIEdgeInitStage.error:
        return '❌';
    }
  }

  /// Show Kaggle API key help
  void _showKaggleApiHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.key, color: Colors.blue[600]),
            const SizedBox(width: 8),
            const Text('Get Kaggle API Key'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Follow these steps to get your Kaggle API key:'),
            SizedBox(height: 12),
            Text('1. Go to kaggle.com and sign in'),
            Text('2. Click on your profile picture → Account'),
            Text('3. Scroll down to "API" section'),
            Text('4. Click "Create New Token"'),
            Text('5. Download the kaggle.json file'),
            Text('6. Open the file and copy the "key" value'),
            SizedBox(height: 12),
            Text(
              'Your API key will look like:\n"abc123def456ghi789..."',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Open Kaggle model page
  void _openKaggleLink() {
    try {
      // You could use url_launcher package here, but for simplicity just show dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kaggle Model Page'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Visit this URL to download the Gemma 3 model:'),
              SizedBox(height: 8),
              SelectableText(
                'https://www.kaggle.com/models/google/gemma-3',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.blue,
                ),
              ),
              SizedBox(height: 12),
              Text('Look for: gemma-3n-2b-it-int4.bin'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
    } catch (e) {
      _addLog('❌ Could not open Kaggle link: $e');
    }
  }

  /// Show Kaggle authentication error dialog
  void _showKaggleAuthErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red[600]),
            const SizedBox(width: 8),
            const Text('Authentication Failed'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Kaggle credentials are not working.'),
            SizedBox(height: 12),
            Text('Please check:'),
            Text('• Your username is correct'),
            Text('• Your API key is valid and not expired'),
            Text('• You have accepted the model terms on Kaggle'),
            SizedBox(height: 12),
            Text(
              'You can get a new API key from:\nkaggle.com → Account → API → Create New Token',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  /// Show Kaggle access error dialog
  void _showKaggleAccessErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.block, color: Colors.orange[600]),
            const SizedBox(width: 8),
            const Text('Access Denied'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You need to accept the model terms on Kaggle first.'),
            SizedBox(height: 12),
            Text('Steps to fix:'),
            Text('1. Visit: kaggle.com/models/google/gemma-3'),
            Text('2. Click "Download" or "Use Model"'),
            Text('3. Accept the terms and conditions'),
            Text('4. Come back and try again'),
            SizedBox(height: 12),
            Text(
              'This is required to download models from Kaggle.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Skip setup (for users who want to configure later)
  void _skipSetup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip AI Edge Setup?'),
        content: const Text(
          'You can set up AI Edge RAG later in settings. The app will work without it, but you won\'t have enhanced AI capabilities.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onSetupComplete?.call();
            },
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Animated logo/icon
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isSetupComplete ? 1.0 : _pulseAnimation.value,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isSetupComplete 
                                  ? [Colors.green[400]!, Colors.green[600]!]
                                  : [Colors.blue[400]!, Colors.purple[600]!],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isSetupComplete 
                                ? Icons.check_circle
                                : Icons.smart_toy,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Text(
                    _isSetupComplete 
                        ? 'AI Edge Setup Complete!'
                        : 'Welcome to AI Edge RAG',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _isSetupComplete ? Colors.green[700] : Colors.grey[800],
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    _isSetupComplete 
                        ? 'Your Frame smart glasses now have enhanced AI capabilities'
                        : 'Let\'s set up Google AI Edge with Gemma 3 for enhanced Frame experiences',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            // Current status indicator
            if (_currentStatus != null && !_isSetupComplete)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _currentStatus!.stage.color.withValues(alpha: 0.1),
                  border: Border.all(color: _currentStatus!.stage.color.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _currentStatus!.stage.icon,
                      color: _currentStatus!.stage.color,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentStatus!.stage.displayName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _currentStatus!.stage.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currentStatus!.message,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          
                          // Progress bar for download
                          if (_currentStatus!.progress != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(
                                value: _currentStatus!.progress,
                                backgroundColor: Colors.grey[300],
                                valueColor: AlwaysStoppedAnimation(_currentStatus!.stage.color),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // Setup form (if not started or completed)
            if (!_isSetupStarted && !_isSetupComplete)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Setup method selection
                      const Text(
                        'Setup Method',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Tab selection for setup method
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _showAdvancedOptions = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: !_showAdvancedOptions ? Colors.blue[600] : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Kaggle Login',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: !_showAdvancedOptions ? Colors.white : Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _showAdvancedOptions = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _showAdvancedOptions ? Colors.blue[600] : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Manual URL',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _showAdvancedOptions ? Colors.white : Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),

                      // Kaggle Login Form
                      if (!_showAdvancedOptions) ...[
                        const Text(
                          'Kaggle Authentication',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter your Kaggle credentials to automatically download the Gemma 3 model:',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        
                        // Username field
                        TextField(
                          controller: _kaggleUsernameController,
                          decoration: const InputDecoration(
                            labelText: 'Kaggle Username',
                            hintText: 'your-kaggle-username',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // API Key field
                        TextField(
                          controller: _kaggleApiKeyController,
                          decoration: const InputDecoration(
                            labelText: 'Kaggle API Key',
                            hintText: 'Your Kaggle API token',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.key),
                            suffixIcon: Icon(Icons.visibility_off),
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 12),
                        
                        // API Key help link
                        Row(
                          children: [
                            Icon(Icons.help_outline, size: 16, color: Colors.blue[600]),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _showKaggleApiHelp(),
                              child: Text(
                                'How to get your Kaggle API key',
                                style: TextStyle(
                                  color: Colors.blue[600],
                                  decoration: TextDecoration.underline,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      // Manual URL Form
                      if (_showAdvancedOptions) ...[
                        const Text(
                          'Manual Model URL',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Provide a direct download URL for the Gemma 3 model:',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        
                        TextField(
                          controller: _modelUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Model Download URL',
                            hintText: 'https://your-storage.com/gemma-3n-2b-it-int4.bin',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.link),
                          ),
                          maxLines: 2,
                        ),
                      ],
                      
                      const SizedBox(height: 16),
                      
                      // Kaggle instructions card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          border: Border.all(color: Colors.orange[200]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.download, color: Colors.orange[700], size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'How to get the model URL:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text('1. Go to Kaggle.com and sign in', style: TextStyle(fontSize: 14)),
                            const Text('2. Visit: kaggle.com/models/google/gemma-3', style: TextStyle(fontSize: 14)),
                            const Text('3. Download "gemma-3n-2b-it-int4.bin"', style: TextStyle(fontSize: 14)),
                            const Text('4. Upload to your cloud storage (Google Drive, Dropbox, etc.)', style: TextStyle(fontSize: 14)),
                            const Text('5. Get the direct download URL and paste above', style: TextStyle(fontSize: 14)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.launch, color: Colors.orange[700], size: 16),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => _openKaggleLink(),
                                  child: Text(
                                    'Open Kaggle Model Page',
                                    style: TextStyle(
                                      color: Colors.orange[700],
                                      decoration: TextDecoration.underline,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),

                      // Info card
                      Container(
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
                                Icon(Icons.info, color: Colors.blue[700], size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'What happens during setup:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text('• Download Gemma 3 model (~300MB)', style: TextStyle(fontSize: 14)),
                            const Text('• Verify model integrity', style: TextStyle(fontSize: 14)),
                            const Text('• Test AI Edge system', style: TextStyle(fontSize: 14)),
                            const Text('• Enable enhanced Frame capabilities', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Action buttons
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _startSetup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Start AI Edge Setup',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _skipSetup,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Skip for Now'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Setup logs (if started)
            if (_isSetupStarted || _isSetupComplete)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.terminal, color: Colors.green[400], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Setup Progress',
                            style: TextStyle(
                              color: Colors.green[400],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_setupLogs.length} entries',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: _setupLogs.length,
                          itemBuilder: (context, index) {
                            final log = _setupLogs[index];
                            Color logColor = Colors.green[300]!;
                            
                            if (log.contains('❌')) {
                              logColor = Colors.red[300]!;
                            } else if (log.contains('⚠️')) {
                              logColor = Colors.orange[300]!;
                            } else if (log.contains('🔍') || log.contains('📥')) {
                              logColor = Colors.blue[300]!;
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

            // Complete button (if setup finished)
            if (_isSetupComplete)
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onSetupComplete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Continue to App',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}