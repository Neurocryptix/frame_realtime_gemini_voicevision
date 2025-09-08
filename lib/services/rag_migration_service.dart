import 'dart:async';
// Removed flutter_gemini - using google_generative_ai instead
import 'package:frame_realtime_gemini_voicevision/services/vector_db_service.dart';
import 'package:frame_realtime_gemini_voicevision/services/enhanced_rag_service.dart';
import 'package:frame_realtime_gemini_voicevision/objectbox.g.dart';

/// Service to migrate from old VectorDbService to Enhanced RAG Service
/// Handles data migration and system transition
class RagMigrationService {
  final void Function(String msg) _emit;
  
  bool _migrationInProgress = false;
  bool _migrationCompleted = false;

  RagMigrationService({void Function(String msg)? logger})
      : _emit = logger ?? ((_) {});

  /// Check if migration is needed
  Future<bool> isMigrationNeeded(
    VectorDbService oldService,
    EnhancedRagService newService,
  ) async {
    try {
      // Check if new service has documents
      final newStats = await newService.getStatistics();
      final newDocs = newStats['totalDocuments'] ?? 0;
      
      // Check if old service has documents
      final oldStats = await oldService.getStats();
      final oldDocs = oldStats['totalDocuments'] ?? 0;
      
      _emit('📊 Migration check: Old service has $oldDocs docs, new service has $newDocs docs');
      
      // Migration needed if old has docs but new doesn't, or if embedding models differ
      return oldDocs > 0 && (newDocs == 0 || _hasModelMismatch(oldStats, newStats));
    } catch (e) {
      _emit('❌ Migration check failed: $e');
      return false;
    }
  }

  /// Check if there's a model mismatch requiring re-embedding
  bool _hasModelMismatch(Map<String, dynamic> oldStats, Map<String, dynamic> newStats) {
    final oldModel = oldStats['embeddingModel'] ?? 'unknown';
    final newModel = newStats['embeddingModel'] ?? 'unknown';
    
    final oldDims = oldStats['averageEmbeddingDimensions'] ?? 0;
    final newDims = newStats['embeddingDimension'] ?? 0;
    
    // Model mismatch if different models or different dimensions
    return oldModel != newModel || oldDims != newDims;
  }

  /// Perform full migration from old to new RAG service
  Future<bool> performMigration({
    required VectorDbService oldService,
    required EnhancedRagService newService,
    required String? geminiApiKey,
    bool clearNewService = false,
  }) async {
    if (_migrationInProgress) {
      _emit('⚠️ Migration already in progress');
      return false;
    }

    try {
      _migrationInProgress = true;
      _emit('🚀 Starting RAG migration...');

      // Step 1: Initialize Gemini for embeddings if API key provided
      if (geminiApiKey != null && geminiApiKey.isNotEmpty) {
        // Using Google Generative AI instead of flutter_gemini
        newService.updateApiKey(geminiApiKey);
        _emit('🔑 Initialized Gemini API for embeddings');
      } else {
        _emit('⚠️ No API key provided - using fallback embeddings');
      }

      // Step 2: Clear new service if requested
      if (clearNewService) {
        await newService.clearAll();
        _emit('🗑️ Cleared new service for fresh migration');
      }

      // Step 3: Get all documents from old service
      final oldDocuments = await oldService.getAllDocuments();
      _emit('📦 Found ${oldDocuments.length} documents to migrate');

      if (oldDocuments.isEmpty) {
        _emit('✅ No documents to migrate');
        _migrationCompleted = true;
        return true;
      }

      // Step 4: Batch migrate documents with enhanced metadata
      final batchSize = 10; // Process in batches to avoid overwhelming the API
      
      for (int i = 0; i < oldDocuments.length; i += batchSize) {
        final batch = oldDocuments.skip(i).take(batchSize).toList();
        
        _emit('📦 Processing batch ${(i ~/ batchSize) + 1}/${((oldDocuments.length - 1) ~/ batchSize) + 1}');
        
        for (final doc in batch) {
          await _migrateDocument(doc, newService);
          
          // Small delay to avoid API rate limits
          if (geminiApiKey != null) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
        }
        
        final progress = ((i + batch.length) / oldDocuments.length * 100).round();
        _emit('📈 Migration progress: $progress%');
      }

      // Step 5: Verify migration
      final verificationResult = await _verifyMigration(oldService, newService);
      
      if (verificationResult) {
        _migrationCompleted = true;
        _emit('✅ Migration completed successfully!');
        
        // Step 6: Generate migration report
        await _generateMigrationReport(oldService, newService);
        
        return true;
      } else {
        _emit('❌ Migration verification failed');
        return false;
      }
      
    } catch (e) {
      _emit('❌ Migration failed: $e');
      return false;
    } finally {
      _migrationInProgress = false;
    }
  }

  /// Migrate a single document with enhanced metadata
  Future<void> _migrateDocument(dynamic oldDoc, EnhancedRagService newService) async {
    try {
      // Extract content and metadata from old document
      String content = '';
      Map<String, dynamic> metadata = {};
      
      // Handle different document types
      if (oldDoc.textContent != null) {
        final parts = oldDoc.textContent.split('||META:');
        content = parts.isNotEmpty ? parts[0] : oldDoc.textContent;
        
        // Parse old metadata
        if (parts.length > 1) {
          final metadataStr = parts[1];
          final pairs = metadataStr.split('|');
          for (final pair in pairs) {
            final keyValue = pair.split('=');
            if (keyValue.length == 2) {
              metadata[keyValue[0]] = keyValue[1];
            }
          }
        }
      }

      // Enhance metadata for new system
      final enhancedMetadata = {
        ...metadata,
        'migratedFrom': 'vector_db_service',
        'migrationTimestamp': DateTime.now().toIso8601String(),
        'originalId': oldDoc.id?.toString() ?? 'unknown',
        'originalCreatedAt': oldDoc.createdAt?.toIso8601String() ?? 'unknown',
        'hadOriginalEmbedding': (oldDoc.embedding != null && oldDoc.embedding.isNotEmpty),
        'originalEmbeddingDims': oldDoc.embedding?.length ?? 0,
      };

      // Add to new service (will generate new embeddings)
      await newService.addDocument(
        content: content,
        metadata: enhancedMetadata,
      );

      final contentPreview = content.length > 50 
          ? '${content.substring(0, 50)}...'
          : content;
      _emit('✅ Migrated: "$contentPreview"');
      
    } catch (e) {
      _emit('❌ Failed to migrate document: $e');
      rethrow;
    }
  }

  /// Verify that migration was successful
  Future<bool> _verifyMigration(VectorDbService oldService, EnhancedRagService newService) async {
    try {
      _emit('🔍 Verifying migration...');
      
      final oldStats = await oldService.getStats();
      final newStats = await newService.getStatistics();
      
      final oldDocs = oldStats['totalDocuments'] ?? 0;
      final newDocs = newStats['totalDocuments'] ?? 0;
      
      _emit('📊 Verification: Old($oldDocs) -> New($newDocs)');
      
      // Allow for some variance due to potential duplicates or errors
      final migrationSuccess = newDocs >= (oldDocs * 0.95); // 95% success rate
      
      if (migrationSuccess) {
        _emit('✅ Migration verification passed');
      } else {
        _emit('❌ Migration verification failed - too few documents migrated');
      }
      
      return migrationSuccess;
    } catch (e) {
      _emit('❌ Migration verification error: $e');
      return false;
    }
  }

  /// Generate detailed migration report
  Future<void> _generateMigrationReport(VectorDbService oldService, EnhancedRagService newService) async {
    try {
      _emit('📋 Generating migration report...');
      
      final oldStats = await oldService.getStats();
      final newStats = await newService.getStatistics();
      
      _emit('═══════════════════════════════════════');
      _emit('📊 MIGRATION REPORT');
      _emit('═══════════════════════════════════════');
      _emit('');
      _emit('🗂️ DOCUMENT COUNTS:');
      _emit('   Old Service: ${oldStats['totalDocuments'] ?? 0} documents');
      _emit('   New Service: ${newStats['totalDocuments'] ?? 0} documents');
      _emit('');
      _emit('🧠 EMBEDDING MODELS:');
      _emit('   Old Model: ${oldStats['embeddingModel'] ?? 'unknown'}');
      _emit('   New Model: ${newStats['embeddingModel'] ?? 'unknown'}');
      _emit('');
      _emit('📐 EMBEDDING DIMENSIONS:');
      _emit('   Old Dimensions: ${oldStats['averageEmbeddingDimensions'] ?? 0}');
      _emit('   New Dimensions: ${newStats['embeddingDimension'] ?? 0}');
      _emit('');
      _emit('🔄 MIGRATION STATUS:');
      _emit('   Completed: ${_migrationCompleted ? '✅ Yes' : '❌ No'}');
      _emit('   Gemini API: ${newStats['hasGeminiApiKey'] ? '✅ Available' : '❌ Not configured'}');
      _emit('   Hybrid Search: ${newStats['hybridSearchEnabled'] ? '✅ Enabled' : '❌ Disabled'}');
      _emit('');
      _emit('📈 IMPROVEMENTS:');
      _emit('   • Enhanced semantic search with hybrid scoring');
      _emit('   • Better embedding quality with Gemini models');
      _emit('   • Improved metadata handling and filtering');
      _emit('   • Context-aware response generation');
      _emit('   • Gemma 3 compatibility for local LLM processing');
      _emit('');
      _emit('═══════════════════════════════════════');
      
    } catch (e) {
      _emit('❌ Failed to generate migration report: $e');
    }
  }

  /// Test the new RAG system with sample queries
  Future<void> testNewRagSystem(EnhancedRagService ragService) async {
    try {
      _emit('🧪 Testing new RAG system...');
      
      // Test queries
      final testQueries = [
        'Frame smart glasses',
        'artificial intelligence',
        'voice recognition',
        'computer vision',
        'machine learning',
      ];

      for (final query in testQueries) {
        _emit('🔍 Testing query: "$query"');
        
        final results = await ragService.semanticSearch(
          query: query,
          limit: 3,
          similarityThreshold: 0.2,
          hybridSearch: true,
        );
        
        _emit('   Results: ${results.length} documents found');
        
        if (results.isNotEmpty) {
          final topScore = results.first['score'] as double;
          final scorePercent = (topScore * 100).round();
          _emit('   Top match: $scorePercent% similarity');
        }
      }
      
      _emit('✅ RAG system testing completed');
    } catch (e) {
      _emit('❌ RAG system testing failed: $e');
    }
  }

  /// Add sample data to test the new system
  Future<void> addSampleData(EnhancedRagService ragService) async {
    try {
      _emit('📝 Adding sample data to test new RAG system...');
      
      final sampleDocs = [
        {
          'content': 'Frame smart glasses provide augmented reality experiences with voice and vision capabilities',
          'metadata': {'type': 'product_info', 'category': 'hardware', 'source': 'migration_sample'},
        },
        {
          'content': 'Gemini AI models offer advanced natural language processing and multimodal understanding',
          'metadata': {'type': 'ai_technology', 'category': 'software', 'source': 'migration_sample'},
        },
        {
          'content': 'RAG systems combine retrieval and generation for more accurate and contextual AI responses',
          'metadata': {'type': 'ai_concept', 'category': 'methodology', 'source': 'migration_sample'},
        },
        {
          'content': 'Flutter provides cross-platform development capabilities for mobile and desktop applications',
          'metadata': {'type': 'development', 'category': 'framework', 'source': 'migration_sample'},
        },
        {
          'content': 'Vector databases enable semantic search by comparing high-dimensional embedding vectors',
          'metadata': {'type': 'database', 'category': 'technology', 'source': 'migration_sample'},
        },
      ];

      await ragService.batchEmbedDocuments(sampleDocs);
      _emit('✅ Sample data added successfully');
      
    } catch (e) {
      _emit('❌ Failed to add sample data: $e');
    }
  }

  /// Get migration status
  Map<String, dynamic> getMigrationStatus() {
    return {
      'inProgress': _migrationInProgress,
      'completed': _migrationCompleted,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Reset migration status (for testing)
  void resetMigrationStatus() {
    _migrationInProgress = false;
    _migrationCompleted = false;
    _emit('🔄 Migration status reset');
  }
}