import 'package:flutter/services.dart';

class AiEdgeRagPlatformChannel {
  final void Function(String message)? logger;

  AiEdgeRagPlatformChannel({this.logger});

  static const MethodChannel _channel =
      MethodChannel('com.example.frame_realtime_gemini_voicevision/ai_edge_rag');

  Future<bool> initialize() async {
    try {
      final bool? result = await _channel.invokeMethod('initialize');
      return result ?? false;
    } on PlatformException catch (e) {
      logger?.call("Failed to initialize AI Edge RAG: '${e.message}'.");
      return false;
    }
  }

  Future<bool> addDocument(String content, Map<String, dynamic> metadata, String? documentId) async {
    try {
      final bool? result = await _channel.invokeMethod('addDocument', {
        'content': content,
        'metadata': metadata,
        'documentId': documentId,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      logger?.call("Failed to add document: '${e.message}'.");
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> search(String query, int topK, double threshold) async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('search', {
        'query': query,
        'topK': topK,
        'threshold': threshold,
      });
      return result?.cast<Map<String, dynamic>>() ?? [];
    } on PlatformException catch (e) {
      logger?.call("Failed to search: '${e.message}'.");
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
      logger?.call("Failed to get document: '${e.message}'.");
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
      logger?.call("Failed to remove document: '${e.message}'.");
      return false;
    }
  }

  Future<void> clearDocuments() async {
    try {
      await _channel.invokeMethod('clearDocuments');
    } on PlatformException catch (e) {
      logger?.call("Failed to clear documents: '${e.message}'.");
    }
  }

  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
    } on PlatformException catch (e) {
      logger?.call("Failed to dispose AI Edge RAG: '${e.message}'.");
    }
  }
}
