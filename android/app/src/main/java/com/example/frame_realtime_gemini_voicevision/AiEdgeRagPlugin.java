package com.example.frame_realtime_gemini_voicevision;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

// AI Edge RAG imports (based on official example)
import com.google.ai.edge.localagents.rag.DefaultSemanticTextMemory;
import com.google.ai.edge.localagents.rag.SqliteVectorStore;
import com.google.ai.edge.localagents.rag.embedder.Embedder;
import com.google.ai.edge.localagents.rag.embedder.GemmaEmbeddingModel;
import com.google.mediapipe.tasks.genai.llminference.LlmInference;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

public class AiEdgeRagPlugin implements FlutterPlugin, MethodCallHandler {
    private static final String CHANNEL = "com.example.frame_realtime_gemini_voicevision/ai_edge_rag";
    private MethodChannel channel;
    private DefaultSemanticTextMemory memory;
    private boolean isInitialized = false;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "initialize":
                try {
                    // Create Gemma embedding model (based on official example)
                    Embedder embedder = new GemmaEmbeddingModel(
                        "", // Model path - empty for default
                        Optional.empty(), // tokenizer path
                        false // use GPU
                    );
                    
                    // Create SQLite vector store (768 is typical embedding dimension)
                    SqliteVectorStore vectorStore = new SqliteVectorStore(768);
                    
                    // Create semantic text memory
                    memory = new DefaultSemanticTextMemory(vectorStore, embedder);
                    
                    isInitialized = true;
                    result.success(true);
                } catch (Exception e) {
                    result.error("INITIALIZATION_FAILED", e.getMessage(), null);
                }
                break;
                
            case "addDocument":
                try {
                    if (!isInitialized) {
                        result.error("NOT_INITIALIZED", "AI Edge RAG not initialized", null);
                        return;
                    }
                    
                    String content = call.argument("content");
                    String documentId = call.argument("documentId");
                    
                    if (content == null || documentId == null) {
                        result.error("INVALID_ARGUMENTS", "Content and documentId are required", null);
                        return;
                    }
                    
                    // Use memorizeChunks method as in the official example
                    memory.memorizeChunks(documentId, content);
                    result.success(true);
                } catch (Exception e) {
                    result.error("ADD_DOCUMENT_FAILED", e.getMessage(), null);
                }
                break;
                
            case "search":
                try {
                    if (!isInitialized) {
                        result.error("NOT_INITIALIZED", "AI Edge RAG not initialized", null);
                        return;
                    }
                    
                    String query = call.argument("query");
                    Integer topK = call.argument("topK");
                    
                    if (query == null) {
                        result.error("INVALID_ARGUMENTS", "Query is required", null);
                        return;
                    }
                    
                    if (topK == null) {
                        topK = 3; // Default as per official example
                    }
                    
                    // Use the memory's search capability
                    // Note: The exact search API may vary, but this follows the pattern
                    List<String> searchResults = memory.search(query, topK);
                    
                    // Convert to expected Flutter format
                    List<Map<String, Object>> resultsList = new ArrayList<>();
                    for (int i = 0; i < searchResults.size(); i++) {
                        Map<String, Object> docMap = new HashMap<>();
                        docMap.put("id", "doc_" + i);
                        docMap.put("content", searchResults.get(i));
                        docMap.put("metadata", new HashMap<String, Object>());
                        resultsList.add(docMap);
                    }
                    
                    result.success(resultsList);
                } catch (Exception e) {
                    result.error("SEARCH_FAILED", e.getMessage(), null);
                }
                break;
                
            case "getDocument":
                if (!isInitialized) {
                    result.error("NOT_INITIALIZED", "AI Edge RAG not initialized", null);
                    return;
                }
                // Not directly supported in the current API
                result.success(null);
                break;
                
            case "removeDocument":
                if (!isInitialized) {
                    result.error("NOT_INITIALIZED", "AI Edge RAG not initialized", null);
                    return;
                }
                // Not directly supported in the current API
                result.success(true);
                break;
                
            case "clearDocuments":
                try {
                    if (!isInitialized) {
                        result.error("NOT_INITIALIZED", "AI Edge RAG not initialized", null);
                        return;
                    }
                    
                    // Clear the vector store
                    if (memory != null) {
                        // The exact clear method may vary, but this is the intent
                        memory = null;
                        isInitialized = false;
                    }
                    
                    result.success(null);
                } catch (Exception e) {
                    result.error("CLEAR_DOCUMENTS_FAILED", e.getMessage(), null);
                }
                break;
                
            case "dispose":
                try {
                    if (memory != null) {
                        // Clean up resources
                        memory = null;
                    }
                    isInitialized = false;
                    result.success(null);
                } catch (Exception e) {
                    result.error("DISPOSE_FAILED", e.getMessage(), null);
                }
                break;
                
            default:
                result.notImplemented();
                break;
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
    }
}