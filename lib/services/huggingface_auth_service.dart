import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// HuggingFace authentication service following Google AI Edge Gallery pattern
/// Supports both OAuth and direct token authentication
class HuggingFaceAuthService {
  static const String _tokenKey = 'huggingface_access_token';
  static const String _refreshTokenKey = 'huggingface_refresh_token';
  static const String _tokenExpiryKey = 'huggingface_token_expiry';
  static const String _userInfoKey = 'huggingface_user_info';
  static const String _authMethodKey = 'huggingface_auth_method';

  // OAuth configuration - can be configured later for OAuth flow
  static const String clientId = 'hf_oauth_frame_ai_edge'; // Placeholder - configure for OAuth
  static const String redirectUri = 'com.brilliantlabs.frame.realtime://oauth/huggingface';
  static const String scope = 'read-repos';
  
  final void Function(String message)? logger;
  static const MethodChannel _oauthChannel = MethodChannel('com.brilliantlabs.frame.realtime/oauth');
  StreamSubscription<dynamic>? _oauthSubscription;
  
  HuggingFaceAuthService({this.logger}) {
    _setupOAuthCallbackListener();
  }

  void _log(String message) {
    logger?.call(message);
  }

  /// Setup OAuth callback listener for deep link handling
  void _setupOAuthCallbackListener() {
    _oauthChannel.setMethodCallHandler((call) async {
      if (call.method == 'oauth_callback') {
        final callbackUrl = call.arguments as String;
        _log('📱 OAuth callback received: $callbackUrl');
        await handleAuthorizationCallback(callbackUrl);
      }
    });
  }

  /// Dispose the service and cleanup resources
  void dispose() {
    _oauthSubscription?.cancel();
    _log('🧹 HuggingFace auth service disposed');
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      
      if (token == null) return false;
      
      // For direct token auth, validate token by testing API access
      final authMethod = prefs.getString(_authMethodKey) ?? 'token';
      if (authMethod == 'token') {
        return await testApiAccess();
      }
      
      // For OAuth, check token expiry
      final expiryTimestamp = prefs.getInt(_tokenExpiryKey);
      if (expiryTimestamp != null) {
        final expiryTime = DateTime.fromMillisecondsSinceEpoch(expiryTimestamp);
        if (DateTime.now().isAfter(expiryTime.subtract(const Duration(minutes: 5)))) {
          // Token expires soon, try to refresh
          return await _refreshAccessToken();
        }
      }
      
      return true;
    } catch (e) {
      _log('Error checking authentication: $e');
      return false;
    }
  }

  /// Set HuggingFace token directly (following Google AI Edge Gallery pattern)
  Future<bool> setToken(String token) async {
    try {
      if (token.trim().isEmpty) {
        _log('Empty token provided');
        return false;
      }

      // Validate token format (should start with hf_)
      if (!token.startsWith('hf_')) {
        _log('Invalid token format - HuggingFace tokens should start with "hf_"');
        return false;
      }

      _log('Setting HuggingFace token...');
      
      // Store token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token.trim());
      await prefs.setString(_authMethodKey, 'token');
      await prefs.remove(_refreshTokenKey); // Clear OAuth refresh token
      await prefs.remove(_tokenExpiryKey); // Clear OAuth expiry
      
      // Test token validity
      final isValid = await testApiAccess();
      if (isValid) {
        await _fetchUserInfo();
        _log('✅ HuggingFace token validated successfully');
        return true;
      } else {
        // Clear invalid token
        await clearToken();
        _log('❌ Invalid HuggingFace token');
        return false;
      }
    } catch (e) {
      _log('Error setting token: $e');
      return false;
    }
  }

  /// Clear stored token
  Future<void> clearToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_authMethodKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_tokenExpiryKey);
      await prefs.remove(_userInfoKey);
      _log('Token cleared');
    } catch (e) {
      _log('Error clearing token: $e');
    }
  }

  /// Get authentication method (token or oauth)
  Future<String> getAuthMethod() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_authMethodKey) ?? 'token';
    } catch (e) {
      return 'token';
    }
  }

  /// Get stored access token
  Future<String?> getAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (e) {
      _log('Error getting access token: $e');
      return null;
    }
  }

  /// Get user information
  Future<Map<String, dynamic>?> getUserInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoJson = prefs.getString(_userInfoKey);
      if (userInfoJson != null) {
        return json.decode(userInfoJson) as Map<String, dynamic>;
      }
    } catch (e) {
      _log('Error getting user info: $e');
    }
    return null;
  }

  /// Start OAuth flow by launching the authorization URL in a browser.
  Future<void> startAuthenticationFlow() async {
    try {
      if (clientId == 'hf_oauth_frame_ai_edge') {
        _log('❌ OAuth not configured. Please set up OAuth credentials or use token authentication.');
        _log('For OAuth: Create an OAuth App in HuggingFace settings and configure clientId.');
        _log('For Token: Use the "Enter Token" option instead.');
        return;
      }
      final authUrl = await getAuthorizationUrl();
      _log('Opening authentication URL: $authUrl');
      await _launchUrl(authUrl);
    } catch (e) {
      _log('Error starting authentication flow: $e');
    }
  }

  /// Helper to launch a URL.
  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _log('Could not launch $url');
    }
  }

  /// Generate the full authorization URL
  Future<String> getAuthorizationUrl() async {
    // Generate state for security
    final state = _generateRandomString(32);
    await _storeOAuthState(state);

    final params = {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scope,
      'state': state,
    };

    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return 'https://huggingface.co/oauth/authorize?$queryString';
  }

  /// Handle OAuth callback from the deep link.
  /// This should be called by your app when it receives the redirect URI.
  Future<bool> handleAuthorizationCallback(String callbackUrl) async {
    try {
      final uri = Uri.parse(callbackUrl);
      final code = uri.queryParameters['code'];
      final state = uri.queryParameters['state'];
      final error = uri.queryParameters['error'];

      if (error != null) {
        _log('OAuth error: $error');
        return false;
      }

      if (code == null || state == null) {
        _log('Missing authorization code or state');
        return false;
      }

      // Verify state
      if (!await _verifyOAuthState(state)) {
        _log('Invalid OAuth state - possible CSRF attack');
        return false;
      }

      // Exchange code for tokens
      return await _exchangeCodeForTokens(code);
    } catch (e) {
      _log('Error handling authorization callback: $e');
      return false;
    }
  }

  /// Exchange authorization code for access tokens
  Future<bool> _exchangeCodeForTokens(String code) async {
    try {
      _log('Exchanging authorization code for tokens...');
      
      final response = await http.post(
        Uri.parse('https://huggingface.co/oauth/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'code': code,
          'redirect_uri': redirectUri,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        await _storeTokens(data);
        await _fetchUserInfo();
        _log('✅ Successfully authenticated with HuggingFace');
        return true;
      } else {
        _log('❌ Token exchange failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      _log('Error exchanging code for tokens: $e');
      return false;
    }
  }

  /// Refresh access token
  Future<bool> _refreshAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString(_refreshTokenKey);
      
      if (refreshToken == null) {
        _log('No refresh token available');
        return false;
      }

      _log('Refreshing access token...');
      
      final response = await http.post(
        Uri.parse('https://huggingface.co/oauth/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {
          'grant_type': 'refresh_token',
          'client_id': clientId,
          'refresh_token': refreshToken,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        await _storeTokens(data);
        _log('Access token refreshed successfully');
        return true;
      } else {
        _log('Token refresh failed: ${response.statusCode} ${response.body}');
        await _clearStoredTokens();
        return false;
      }
    } catch (e) {
      _log('Error refreshing access token: $e');
      return false;
    }
  }

  /// Fetch user information
  Future<void> _fetchUserInfo() async {
    try {
      final token = await getAccessToken();
      if (token == null) return;

      final response = await http.get(
        Uri.parse('https://huggingface.co/api/whoami'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final userInfo = json.decode(response.body) as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userInfoKey, json.encode(userInfo));
        _log('User info fetched: ${userInfo['name'] ?? 'Unknown user'}');
      } else {
        _log('Failed to fetch user info: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error fetching user info: $e');
    }
  }

  /// Store OAuth tokens
  Future<void> _storeTokens(Map<String, dynamic> tokenData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final accessToken = tokenData['access_token'] as String?;
      final refreshToken = tokenData['refresh_token'] as String?;
      final expiresIn = tokenData['expires_in'] as int?;

      if (accessToken != null) {
        await prefs.setString(_tokenKey, accessToken);
        await prefs.setString(_authMethodKey, 'oauth'); // Mark as OAuth authentication
      }

      if (refreshToken != null) {
        await prefs.setString(_refreshTokenKey, refreshToken);
      }

      if (expiresIn != null) {
        final expiryTime = DateTime.now().add(Duration(seconds: expiresIn));
        await prefs.setInt(_tokenExpiryKey, expiryTime.millisecondsSinceEpoch);
      }
    } catch (e) {
      _log('Error storing tokens: $e');
      rethrow;
    }
  }

  /// Clear stored tokens
  Future<void> _clearStoredTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_tokenExpiryKey);
      await prefs.remove(_userInfoKey);
    } catch (e) {
      _log('Error clearing tokens: $e');
    }
  }

  /// Store OAuth state for verification
  Future<void> _storeOAuthState(String state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('oauth_state', state);
    } catch (e) {
      _log('Error storing OAuth state: $e');
    }
  }

  /// Verify OAuth state
  Future<bool> _verifyOAuthState(String state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedState = prefs.getString('oauth_state');
      await prefs.remove('oauth_state'); // Clean up
      return storedState == state;
    } catch (e) {
      _log('Error verifying OAuth state: $e');
      return false;
    }
  }

  /// Generate random string for OAuth state
  String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(length, (index) => chars[random.nextInt(chars.length)]).join();
  }

  /// Sign out user
  Future<void> signOut() async {
    try {
      _log('Signing out from HuggingFace...');
      await _clearStoredTokens();
      _log('Signed out successfully');
    } catch (e) {
      _log('Error signing out: $e');
    }
  }

  /// Test API access with current token
  Future<bool> testApiAccess() async {
    try {
      final token = await getAccessToken();
      if (token == null) return false;

      final response = await http.get(
        Uri.parse('https://huggingface.co/api/whoami'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        _log('API access test successful');
        return true;
      } else if (response.statusCode == 401) {
        _log('API access test failed: Unauthorized');
        // Try to refresh token
        return await _refreshAccessToken();
      } else {
        _log('API access test failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _log('Error testing API access: $e');
      return false;
    }
  }

  /// Get authentication headers for API requests
  Future<Map<String, String>?> getAuthHeaders() async {
    final token = await getAccessToken();
    if (token == null) return null;
    
    return {
      'Authorization': 'Bearer $token',
      'User-Agent': 'Frame-AI-Edge/1.0',
    };
  }

  /// Validate model access
  Future<bool> validateModelAccess(String modelId) async {
    try {
      final headers = await getAuthHeaders();
      if (headers == null) return false;

      final response = await http.head(
        Uri.parse('https://huggingface.co/api/models/$modelId'),
        headers: headers,
      );

      return response.statusCode == 200;
    } catch (e) {
      _log('Error validating model access for $modelId: $e');
      return false;
    }
  }
}