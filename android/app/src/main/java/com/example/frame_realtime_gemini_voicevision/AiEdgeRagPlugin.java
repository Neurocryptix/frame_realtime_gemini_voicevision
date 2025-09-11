package com.example.frame_realtime_gemini_voicevision;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import com.google.ai.edge.localagents.rag.RagAgent;
import com.google.ai.edge.localagents.rag.RagAgent.RagAgentOptions;
import com.google.ai.edge.localagents.rag.doc.Document;
import com.google.ai.edge.localagents.rag.doc.Metadata;
import com.google.ai.edge.localagents.rag.embed.text.GeckoEmbedder;
import com.google.ai.edge.localagents.rag.vectordb.VectorStore;
import com.google.ai.edge.localagents.rag.vectordb.impl.InMemoryVectorStore;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class AiEdgeRagPlugin implements FlutterPlugin, MethodCallHandler {
    private static final String CHANNEL = "com.example.frame_realtime_gemini_voicevision/ai_edge_rag";
    private MethodChannel channel;
    private RagAgent ragAgent;

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
                    GeckoEmbedder geckoEmbedder = GeckoEmbedder.builder().build();
                    VectorStore vectorStore = new InMemoryVectorStore(geckoEmbedder.getEmbeddingDimension());
                    RagAgentOptions options = RagAgentOptions.builder()
                            .setEmbedder(geckoEmbedder)
                            .setVectorStore(vectorStore)
                            .build();
                    ragAgent = RagAgent.create(options);
                    result.success(true);
                } catch (Exception e) {
                    result.error("INITIALIZATION_FAILED", e.getMessage(), null);
                }
                break;
            case "addDocument":
                try {
                    String content = call.argument("content");
                    Map<String, Object> metadataMap = call.argument("metadata");
                    String documentId = call.argument("documentId");
                    Metadata metadata = new Metadata();
                    for (Map.Entry<String, Object> entry : metadataMap.entrySet()) {
                        metadata.put(entry.getKey(), entry.getValue().toString());
                    }
                    Document document = Document.builder()
                            .setId(documentId)
                            .setContent(content)
                            .setMetadata(metadata)
                            .build();
                    ragAgent.addDocument(document);
                    result.success(true);
                } catch (Exception e) {
                    result.error("ADD_DOCUMENT_FAILED", e.getMessage(), null);
                }
                break;
            case "search":
                try {
                    String query = call.argument("query");
                    int topK = call.argument("topK");
                    List<Document> searchResults = ragAgent.search(query, topK);
                    List<Map<String, Object>> resultsList = new ArrayList<>();
                    for (Document doc : searchResults) {
                        Map<String, Object> docMap = new HashMap<>();
                        docMap.put("id", doc.getId());
                        docMap.put("content", doc.getContent());
                        docMap.put("metadata", doc.getMetadata().toMap());
                        resultsList.add(docMap);
                    }
                    result.success(resultsList);
                } catch (Exception e) {
                    result.error("SEARCH_FAILED", e.getMessage(), null);
                }
                break;
            case "getDocument":
                // Not implemented in the native SDK
                result.success(null);
                break;
            case "removeDocument":
                // Not implemented in the native SDK
                result.success(true);
                break;
            case "clearDocuments":
                try {
                    ragAgent.clear();
                    result.success(null);
                } catch (Exception e) {
                    result.error("CLEAR_DOCUMENTS_FAILED", e.getMessage(), null);
                }
                break;
            case "dispose":
                try {
                    ragAgent.close();
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