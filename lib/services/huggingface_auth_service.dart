import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// HuggingFace OAuth authentication service following Google AI Edge Gallery pattern
class HuggingFaceAuthService {
  static const String _tokenKey = 'huggingface_access_token';
  static const String _refreshTokenKey = 'huggingface_refresh_token';
  static const String _tokenExpiryKey = 'huggingface_token_expiry';
  static const String _userInfoKey = 'huggingface_user_info';

  // TODO: Replace with your HuggingFace OAuth App client ID
  // You can create one at: https://huggingface.co/settings/oauth/apps
  static const String clientId = 'your-huggingface-client-id'; 
  
  // TODO: Configure this redirect URI in your HuggingFace OAuth App
  // and in your application's deep link settings (e.g., AndroidManifest.xml).
  static const String redirectUri = 'com.example.frame_realtime_gemini_voicevision://oauth/huggingface';
  static const String scope = 'read-repos';
  
  final void Function(String message)? logger;
  
  HuggingFaceAuthService({this.logger});

  void _log(String message) {
    logger?.call(message);
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      
      if (token == null) return false;
      
      // Check token expiry
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
      if (clientId == 'your-huggingface-client-id') {
        _log('❌ ERROR: HuggingFace client ID is not configured.');
        _log('Please create an OAuth App in your HuggingFace settings and set the clientId.');
        // Optionally, show an error to the user in the UI.
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