import 'dart:async';
import 'package:flutter/material.dart';
import '../models/model_metadata.dart';
import '../services/huggingface_auth_service.dart';
import '../services/model_download_service.dart';

/// Model download screen following Google AI Edge Gallery pattern
class ModelDownloadScreen extends StatefulWidget {
  final VoidCallback? onDownloadComplete;

  const ModelDownloadScreen({
    super.key,
    this.onDownloadComplete,
  });

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  
  late ModelDownloadService _downloadService;
  late HuggingFaceAuthService _authService;
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  StreamSubscription<ModelDownloadProgress>? _downloadSubscription;
  
  // UI State
  bool _isAuthenticated = false;
  bool _isDownloading = false;
  bool _downloadComplete = false;
  ModelMetadata? _selectedModel;
  ModelDownloadProgress? _currentProgress;
  
  // Authentication UI State
  String _authMethod = 'token'; // 'token' or 'oauth'
  final TextEditingController _tokenController = TextEditingController();
  bool _tokenObscured = true;
  bool _isValidatingToken = false;

  // Setup logs
  final List<String> _setupLogs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _authService = HuggingFaceAuthService(logger: _addLog);
    _downloadService = ModelDownloadService(
      authService: _authService,
      logger: _addLog,
    );
    
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
    
    _addLog('🤖 Welcome to AI Edge Model Setup');
    _addLog('📱 Preparing enhanced AI capabilities for Frame...');
    
    // Initialize with default model
    _selectedModel = ModelAllowlist.getDefaultModel('CHAT');
    
    _checkAuthenticationStatus();
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _animationController.dispose();
    _scrollController.dispose();
    _tokenController.dispose();
    _downloadService.dispose();
    _authService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _addLog('🔄 App resumed, checking authentication status...');
      _checkAuthenticationStatus();
    }
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

  /// Check authentication status
  Future<void> _checkAuthenticationStatus() async {
    try {
      final isAuth = await _authService.isAuthenticated();
      final currentAuthMethod = await _authService.getAuthMethod();
      
      setState(() {
        _isAuthenticated = isAuth;
        _authMethod = currentAuthMethod;
      });
      
      if (isAuth) {
        _addLog('✅ HuggingFace authentication verified ($currentAuthMethod)');
        final userInfo = await _authService.getUserInfo();
        if (userInfo != null) {
          _addLog('👋 Signed in as: ${userInfo['name'] ?? 'User'}');
        }
      } else {
        _addLog('🔑 HuggingFace authentication required');
      }
    } catch (e) {
      _addLog('❌ Error checking authentication: $e');
    }
  }

  /// Validate and set HuggingFace token
  Future<void> _validateAndSetToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _addLog('❌ Please enter a HuggingFace token');
      return;
    }

    setState(() {
      _isValidatingToken = true;
    });

    try {
      _addLog('🔍 Validating HuggingFace token...');
      final success = await _authService.setToken(token);
      
      if (success) {
        setState(() {
          _isAuthenticated = true;
          _authMethod = 'token';
        });
        _addLog('✅ Token validated successfully');
        
        // Clear token field for security
        _tokenController.clear();
      } else {
        _addLog('❌ Invalid token - please check your HuggingFace token');
      }
    } catch (e) {
      _addLog('❌ Token validation error: $e');
    } finally {
      setState(() {
        _isValidatingToken = false;
      });
    }
  }

  /// Clear authentication
  Future<void> _clearAuthentication() async {
    try {
      await _authService.clearToken();
      setState(() {
        _isAuthenticated = false;
        _authMethod = 'token';
      });
      _tokenController.clear();
      _addLog('🔄 Authentication cleared');
    } catch (e) {
      _addLog('❌ Error clearing authentication: $e');
    }
  }

  /// Start authentication flow
  Future<void> _startAuthentication() async {
    try {
      _addLog('🚀 Starting HuggingFace authentication...');
      _addLog('Redirecting to HuggingFace to sign in...');
      await _authService.startAuthenticationFlow();
      // The app will be backgrounded. When it resumes, `didChangeAppLifecycleState` 
      // will trigger `_checkAuthenticationStatus`.
    } catch (e) {
      _addLog('❌ Authentication error: $e');
    }
  }

  

  /// Start model download
  Future<void> _startDownload() async {
    if (_selectedModel == null || _isDownloading) return;
    
    setState(() {
      _isDownloading = true;
    });

    try {
      _addLog('🚀 Starting model download...');
      _addLog('📦 Model: ${_selectedModel!.displayName}');
      _addLog('💾 Size: ${_selectedModel!.formattedSize}');
      
      // Start download and listen to progress
      _downloadSubscription = _downloadService
          .getDownloadProgress(_selectedModel!.modelId)
          .listen((progress) {
        setState(() {
          _currentProgress = progress;
        });
        
        _handleProgressUpdate(progress);
      });

      final success = await _downloadService.downloadModel(_selectedModel!);
      
      if (success) {
        _onDownloadComplete();
      } else {
        _onDownloadError('Download failed');
      }
    } catch (e) {
      _onDownloadError(e.toString());
    }
  }

  /// Handle progress updates
  void _handleProgressUpdate(ModelDownloadProgress progress) {
    switch (progress.status) {
      case ModelDownloadStatus.enqueued:
        _addLog('⏳ Download queued');
        break;
      case ModelDownloadStatus.running:
        if (progress.progress > 0) {
          final percent = (progress.progress * 100).toStringAsFixed(1);
          String message = '📥 Downloading: $percent%';
          
          if (progress.downloadedBytes != null && progress.totalBytes != null) {
            final downloaded = _formatBytes(progress.downloadedBytes!);
            final total = _formatBytes(progress.totalBytes!);
            message += ' ($downloaded / $total)';
            
            if (progress.formattedSpeed != null) {
              message += ' @ ${progress.formattedSpeed}';
            }
          }
          
          // Only log every 10% to avoid spam
          final currentPercent = (progress.progress * 100).round();
          if (currentPercent % 10 == 0) {
            _addLog(message);
          }
        }
        break;
      case ModelDownloadStatus.succeeded:
        _addLog('✅ Download completed successfully!');
        break;
      case ModelDownloadStatus.failed:
        _addLog('❌ Download failed: ${progress.errorMessage ?? 'Unknown error'}');
        break;
      case ModelDownloadStatus.cancelled:
        _addLog('⏹️ Download cancelled');
        break;
      default:
        break;
    }
  }

  /// Handle download completion
  void _onDownloadComplete() {
    setState(() {
      _downloadComplete = true;
      _isDownloading = false;
    });
    
    _addLog('🎉 Model download completed successfully!');
    _addLog('🧠 AI Edge is now ready for enhanced Frame experiences');
    
    // Stop animation
    _animationController.stop();
    
    // Call completion callback after delay
    Future.delayed(const Duration(seconds: 2), () {
      widget.onDownloadComplete?.call();
    });
  }

  /// Handle download error
  void _onDownloadError(String error) {
    setState(() {
      _isDownloading = false;
    });
    
    _addLog('❌ Download error: $error');
    
    // Provide guidance based on error
    if (error.contains('Authentication')) {
      _addLog('💡 Please check your HuggingFace authentication');
    } else if (error.contains('storage') || error.contains('space')) {
      _addLog('💡 Free up storage space and try again');
    } else if (error.contains('network') || error.contains('connection')) {
      _addLog('💡 Check your internet connection');
    }
  }

  /// Format bytes for display
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Skip setup
  void _skipSetup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip AI Model Download?'),
        content: const Text(
          'You can download AI models later in settings. The app will work without them, but you won\'t have enhanced AI capabilities.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDownloadComplete?.call();
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
                        scale: _downloadComplete ? 1.0 : _pulseAnimation.value,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _downloadComplete
                                  ? [Colors.green[400]!, Colors.green[600]!]
                                  : [Colors.blue[400]!, Colors.purple[600]!],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _downloadComplete
                                ? Icons.check_circle
                                : Icons.download_for_offline,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Text(
                    _downloadComplete
                        ? 'AI Models Ready!'
                        : 'Download AI Models',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _downloadComplete ? Colors.green[700] : Colors.grey[800],
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    _downloadComplete
                        ? 'Your Frame smart glasses now have enhanced AI capabilities'
                        : 'Download AI models to enable enhanced Frame experiences',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            // Progress indicator
            if (_currentProgress != null && _isDownloading)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  border: Border.all(color: Colors.blue[200]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.download, color: Colors.blue[600]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Downloading ${_selectedModel?.displayName}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _currentProgress!.progress,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation(Colors.blue[600]),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(_currentProgress!.progress * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (_currentProgress!.formattedSpeed != null)
                          Text(
                            _currentProgress!.formattedSpeed!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // Setup form (if not downloading or completed)
            if (!_isDownloading && !_downloadComplete)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Authentication status and input
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _isAuthenticated ? Colors.green[50] : Colors.blue[50],
                          border: Border.all(
                            color: _isAuthenticated ? Colors.green[200]! : Colors.blue[200]!,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Status header
                            Row(
                              children: [
                                Icon(
                                  _isAuthenticated ? Icons.verified_user : Icons.key,
                                  color: _isAuthenticated ? Colors.green[700] : Colors.blue[700],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _isAuthenticated
                                            ? 'HuggingFace Authenticated'
                                            : 'HuggingFace Authentication',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: _isAuthenticated ? Colors.green[700] : Colors.blue[700],
                                        ),
                                      ),
                                      Text(
                                        _isAuthenticated
                                            ? 'Ready to download models'
                                            : 'Required for model downloads',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_isAuthenticated)
                                  TextButton.icon(
                                    onPressed: _clearAuthentication,
                                    icon: const Icon(Icons.logout, size: 16),
                                    label: const Text('Clear'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                            
                            // Authentication input (if not authenticated)
                            if (!_isAuthenticated) ...[
                              const SizedBox(height: 16),
                              
                              // Auth method selector
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _authMethod == 'token' ? Colors.blue[100] : Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _authMethod == 'token' ? Colors.blue[300]! : Colors.grey[300]!,
                                        ),
                                      ),
                                      child: RadioListTile<String>(
                                        value: 'token',
                                        groupValue: _authMethod,
                                        onChanged: (value) => setState(() => _authMethod = value!),
                                        title: const Text('Use Token', style: TextStyle(fontSize: 14)),
                                        subtitle: const Text('Enter HuggingFace access token', style: TextStyle(fontSize: 12)),
                                        dense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _authMethod == 'oauth' ? Colors.blue[100] : Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _authMethod == 'oauth' ? Colors.blue[300]! : Colors.grey[300]!,
                                        ),
                                      ),
                                      child: RadioListTile<String>(
                                        value: 'oauth',
                                        groupValue: _authMethod,
                                        onChanged: (value) => setState(() => _authMethod = value!),
                                        title: const Text('OAuth Flow', style: TextStyle(fontSize: 14)),
                                        subtitle: const Text('Sign in via browser', style: TextStyle(fontSize: 12)),
                                        dense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Token input (if token method selected)
                              if (_authMethod == 'token') ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _tokenController,
                                        decoration: InputDecoration(
                                          labelText: 'HuggingFace Token',
                                          hintText: 'hf_...',
                                          border: const OutlineInputBorder(),
                                          prefixIcon: const Icon(Icons.vpn_key),
                                          suffixIcon: IconButton(
                                            icon: Icon(_tokenObscured ? Icons.visibility : Icons.visibility_off),
                                            onPressed: () => setState(() => _tokenObscured = !_tokenObscured),
                                          ),
                                          helperText: 'Get token from huggingface.co/settings/tokens',
                                          helperStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                        ),
                                        obscureText: _tokenObscured,
                                        enabled: !_isValidatingToken,
                                        onFieldSubmitted: (_) => _validateAndSetToken(),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton(
                                      onPressed: _isValidatingToken ? null : _validateAndSetToken,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue[600],
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      ),
                                      child: _isValidatingToken
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Text('Validate'),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                // OAuth button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _startAuthentication,
                                    icon: const Icon(Icons.open_in_browser),
                                    label: const Text('Sign In with HuggingFace'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange[600],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),

                      // Model selection
                      const Text(
                        'Select Model',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Model cards
                      ...ModelAllowlist.allowedModels.map((model) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: RadioListTile<ModelMetadata>(
                          value: model,
                          groupValue: _selectedModel,
                          onChanged: (value) => setState(() => _selectedModel = value),
                          title: Text(model.displayName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Size: ${model.formattedSize}'),
                              Text('Memory: ${model.minMemoryMb}MB'),
                              if (model.description != null)
                                Text(model.description!, style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          isThreeLine: model.description != null,
                        ),
                      )),

                      const SizedBox(height: 24),

                      // Download button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isAuthenticated && _selectedModel != null
                              ? _startDownload
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            _isAuthenticated
                                ? 'Download Model'
                                : 'Sign In Required',
                            style: const TextStyle(
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

            // Setup logs (if downloading or completed)
            if (_isDownloading || _downloadComplete)
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
                            'Download Progress',
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
                            } else if (log.contains('📥') || log.contains('⏳')) {
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

            // Complete button (if download finished)
            if (_downloadComplete)
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onDownloadComplete,
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