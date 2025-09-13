import 'dart:async';
import 'package:flutter/services.dart';

/// AI Edge RAG Platform Channel following Google AI Edge Gallery pattern
/// Handles native Android/iOS integration for AI Edge RAG functionality
class AiEdgeRagPlatformChannel {
  static const MethodChannel _channel = MethodChannel('com.brilliantlabs.frame.realtime/ai_edge_rag');
  
  final void Function(String)? _logger;
  bool _isInitialized = false;

  AiEdgeRagPlatformChannel({void Function(String)? logger}) : _logger = logger;

  void _log(String message) {
    _logger?.call(message);
  }

  /// Initialize the AI Edge RAG platform
  Future<bool> initialize({
    String? embeddingModelPath,
    String? vectorStorePath,
  }) async {
    try {
      _log('🔌 Initializing AI Edge RAG platform channel...');
      
      final result = await _channel.invokeMethod<bool>('initialize', {
        'embeddingModelPath': embeddingModelPath,
        'vectorStorePath': vectorStorePath,
      });
      
      _isInitialized = result ?? false;
      
      if (_isInitialized) {
        _log('✅ AI Edge RAG platform channel initialized');
      } else {
        _log('❌ AI Edge RAG platform channel initialization failed');
      }
      
      return _isInitialized;
    } on PlatformException catch (e) {
      _log('❌ Platform exception during AI Edge RAG initialization: ${e.message}');
      return false;
    } catch (e) {
      _log('❌ Error initializing AI Edge RAG platform: $e');
      return false;
    }
  }

  /// Add document to vector store
  Future<bool> addDocument(
    String content,
    Map<String, dynamic> metadata, [
    String? documentId,
  ]) async {
    if (!_isInitialized) {
      _log('⚠️ AI Edge RAG not initialized');
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('addDocument', {
        'content': content,
        'metadata': metadata,
        'documentId': documentId,
      });
      
      return result ?? false;
    } on PlatformException catch (e) {
      _log('❌ Platform exception adding document: ${e.message}');
      return false;
    } catch (e) {
      _log('❌ Error adding document: $e');
      return false;
    }
  }

  /// Search documents using semantic similarity
  Future<List<Map<String, dynamic>>> search(
    String query,
    int topK,
    double threshold,
  ) async {
    if (!_isInitialized) {
      _log('⚠️ AI Edge RAG not initialized');
      return [];
    }

    try {
      final result = await _channel.invokeMethod<List<dynamic>>('search', {
        'query': query,
        'topK': topK,
        'threshold': threshold,
      });
      
      if (result != null) {
        return result.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }
      
      return [];
    } on PlatformException catch (e) {
      _log('❌ Platform exception during search: ${e.message}');
      return [];
    } catch (e) {
      _log('❌ Error during search: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getDocument(String documentId) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getDocument', {
        'documentId': documentId,
      });
      return result?.cast<String, dynamic>();
    } on PlatformException catch (e) {
      _log("Failed to get document: '${e.message}'.");
      return null;
    }
  }

  Future<bool> removeDocument(String documentId) async {
    try {
      final bool? result = await _channel.invokeMethod('removeDocument', {
        'documentId': documentId,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      _log("Failed to remove document: '${e.message}'.");
      return false;
    }
  }

  /// Clear all documents from vector store
  Future<bool> clearDocuments() async {
    if (!_isInitialized) {
      _log('⚠️ AI Edge RAG not initialized');
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('clearDocuments');
      return result ?? false;
    } on PlatformException catch (e) {
      _log('❌ Platform exception clearing documents: ${e.message}');
      return false;
    } catch (e) {
      _log('❌ Error clearing documents: $e');
      return false;
    }
  }

  /// Get document count
  Future<int> getDocumentCount() async {
    if (!_isInitialized) {
      return 0;
    }

    try {
      final result = await _channel.invokeMethod<int>('getDocumentCount');
      return result ?? 0;
    } on PlatformException catch (e) {
      _log('❌ Platform exception getting document count: ${e.message}');
      return 0;
    } catch (e) {
      _log('❌ Error getting document count: $e');
      return 0;
    }
  }

  /// Get platform statistics
  Future<Map<String, dynamic>> getStatistics() async {
    if (!_isInitialized) {
      return {
        'isInitialized': false,
        'documentCount': 0,
        'backend': 'platform_channel',
        'version': '1.0.0',
      };
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getStatistics');
      
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
      
      return {
        'isInitialized': _isInitialized,
        'documentCount': 0,
        'backend': 'platform_channel',
        'version': '1.0.0',
      };
    } on PlatformException catch (e) {
      _log('❌ Platform exception getting statistics: ${e.message}');
      return {
        'isInitialized': false,
        'documentCount': 0,
        'backend': 'platform_channel',
        'version': '1.0.0',
        'error': e.message,
      };
    } catch (e) {
      _log('❌ Error getting statistics: $e');
      return {
        'isInitialized': false,
        'documentCount': 0,
        'backend': 'platform_channel',
        'version': '1.0.0',
        'error': e.toString(),
      };
    }
  }

  /// Dispose platform resources
  void dispose() {
    if (_isInitialized) {
      try {
        _channel.invokeMethod('dispose');
        _log('🧹 AI Edge RAG platform channel disposed');
      } catch (e) {
        _log('⚠️ Error disposing platform channel: $e');
      }
    }
    _isInitialized = false;
  }

  /// Check if platform is available
  Future<bool> isPlatformAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isPlatformAvailable');
      return result ?? false;
    } on PlatformException catch (e) {
      _log('⚠️ Platform not available: ${e.message}');
      return false;
    } catch (e) {
      _log('⚠️ Error checking platform availability: $e');
      return false;
    }
  }

  /// Check if initialized
  bool get isInitialized => _isInitialized;
}
