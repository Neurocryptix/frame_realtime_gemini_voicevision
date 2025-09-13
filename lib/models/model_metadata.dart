import 'dart:convert';

/// Model metadata structure following Google AI Edge Gallery pattern
class ModelMetadata {
  final String name;
  final String displayName;
  final String modelId;
  final String fileName;
  final int sizeInBytes;
  final int minMemoryMb;
  final String commitHash;
  final Map<String, dynamic> defaultConfig;
  final List<String> taskTypes;
  final String? description;
  final String? learnMoreUrl;
  final bool requiresAuth;

  const ModelMetadata({
    required this.name,
    required this.displayName,
    required this.modelId,
    required this.fileName,
    required this.sizeInBytes,
    required this.minMemoryMb,
    required this.commitHash,
    required this.defaultConfig,
    required this.taskTypes,
    this.description,
    this.learnMoreUrl,
    this.requiresAuth = true,
  });

  /// Generate HuggingFace download URL
  String get downloadUrl {
    return 'https://huggingface.co/$modelId/resolve/$commitHash/$fileName';
  }

  /// Format file size for display
  String get formattedSize {
    if (sizeInBytes < 1024) return '${sizeInBytes}B';
    if (sizeInBytes < 1024 * 1024) return '${(sizeInBytes / 1024).toStringAsFixed(1)}KB';
    if (sizeInBytes < 1024 * 1024 * 1024) return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Check if model supports specific task type
  bool supportsTask(String taskType) => taskTypes.contains(taskType);

  /// Create from JSON
  factory ModelMetadata.fromJson(Map<String, dynamic> json) {
    return ModelMetadata(
      name: json['name'] ?? '',
      displayName: json['displayName'] ?? json['name'] ?? '',
      modelId: json['modelId'] ?? '',
      fileName: json['fileName'] ?? '',
      sizeInBytes: json['sizeInBytes'] ?? 0,
      minMemoryMb: json['minMemoryMb'] ?? 0,
      commitHash: json['commitHash'] ?? '',
      defaultConfig: Map<String, dynamic>.from(json['defaultConfig'] ?? {}),
      taskTypes: List<String>.from(json['taskTypes'] ?? []),
      description: json['description'],
      learnMoreUrl: json['learnMoreUrl'],
      requiresAuth: json['requiresAuth'] ?? true,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'displayName': displayName,
      'modelId': modelId,
      'fileName': fileName,
      'sizeInBytes': sizeInBytes,
      'minMemoryMb': minMemoryMb,
      'commitHash': commitHash,
      'defaultConfig': defaultConfig,
      'taskTypes': taskTypes,
      'description': description,
      'learnMoreUrl': learnMoreUrl,
      'requiresAuth': requiresAuth,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ModelMetadata &&
        other.modelId == modelId &&
        other.commitHash == commitHash;
  }

  @override
  int get hashCode => Object.hash(modelId, commitHash);

  @override
  String toString() => 'ModelMetadata(name: $name, modelId: $modelId)';
}

/// Model allowlist following Google AI Edge Gallery pattern
class ModelAllowlist {
  static const List<ModelMetadata> allowedModels = [
    // Gemma 2 models (these actually exist on HuggingFace)
    ModelMetadata(
      name: 'Gemma 2B Instruct',
      displayName: 'Gemma 2B (Instruct)',
      modelId: 'google/gemma-2b-it',
      fileName: 'model.safetensors',
      sizeInBytes: 4940000000, // ~4.9GB
      minMemoryMb: 6144,
      commitHash: 'main',
      defaultConfig: {
        'temperature': 0.7,
        'topK': 40,
        'topP': 0.95,
        'maxTokens': 2048,
      },
      taskTypes: ['CHAT', 'PROMPT_LAB', 'TEXT_GENERATION'],
      description: 'Lightweight instruction-tuned model optimized for conversational AI',
      learnMoreUrl: 'https://huggingface.co/google/gemma-2b-it',
      requiresAuth: true,
    ),
    ModelMetadata(
      name: 'Gemma 7B Instruct',
      displayName: 'Gemma 7B (Instruct)',
      modelId: 'google/gemma-7b-it',
      fileName: 'model.safetensors',
      sizeInBytes: 17400000000, // ~17.4GB
      minMemoryMb: 20480,
      commitHash: 'main',
      defaultConfig: {
        'temperature': 0.7,
        'topK': 40,
        'topP': 0.95,
        'maxTokens': 4096,
      },
      taskTypes: ['CHAT', 'PROMPT_LAB', 'TEXT_GENERATION', 'CODE_GENERATION'],
      description: 'High-performance instruction-tuned model for complex reasoning',
      learnMoreUrl: 'https://huggingface.co/google/gemma-7b-it',
      requiresAuth: true,
    ),
    // Gemma 2 2B model (quantized version for mobile)
    ModelMetadata(
      name: 'Gemma 2 2B Instruct GGUF',
      displayName: 'Gemma 2 2B (GGUF Q4)',
      modelId: 'bartowski/gemma-2-2b-it-GGUF',
      fileName: 'gemma-2-2b-it-Q4_K_M.gguf',
      sizeInBytes: 1500000000, // ~1.5GB
      minMemoryMb: 3072,
      commitHash: 'main',
      defaultConfig: {
        'temperature': 0.7,
        'topK': 40,
        'topP': 0.95,
        'maxTokens': 2048,
      },
      taskTypes: ['CHAT', 'PROMPT_LAB', 'TEXT_GENERATION'],
      description: 'Quantized Gemma 2 model optimized for mobile deployment',
      learnMoreUrl: 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF',
      requiresAuth: false,
    ),
    // Phi-3 Mini (Microsoft, small and efficient)
    ModelMetadata(
      name: 'Phi-3 Mini Instruct GGUF',
      displayName: 'Phi-3 Mini (GGUF Q4)',
      modelId: 'microsoft/Phi-3-mini-4k-instruct-gguf',
      fileName: 'Phi-3-mini-4k-instruct-q4.gguf',
      sizeInBytes: 2300000000, // ~2.3GB
      minMemoryMb: 4096,
      commitHash: 'main',
      defaultConfig: {
        'temperature': 0.7,
        'topK': 40,
        'topP': 0.95,
        'maxTokens': 4096,
      },
      taskTypes: ['CHAT', 'PROMPT_LAB', 'TEXT_GENERATION', 'CODE_GENERATION'],
      description: 'Efficient small language model optimized for mobile devices',
      learnMoreUrl: 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf',
      requiresAuth: false,
    ),
  ];

  /// Get model by ID
  static ModelMetadata? getModelById(String modelId) {
    for (final model in allowedModels) {
      if (model.modelId == modelId) return model;
    }
    return null;
  }

  /// Get models supporting specific task
  static List<ModelMetadata> getModelsByTask(String taskType) {
    return allowedModels.where((model) => model.supportsTask(taskType)).toList();
  }

  /// Get models within memory constraints
  static List<ModelMetadata> getModelsByMemory(int maxMemoryMb) {
    return allowedModels.where((model) => model.minMemoryMb <= maxMemoryMb).toList();
  }

  /// Get default model for task
  static ModelMetadata? getDefaultModel([String? taskType]) {
    if (taskType != null) {
      final compatibleModels = getModelsByTask(taskType);
      if (compatibleModels.isNotEmpty) {
        // Return smallest compatible model
        compatibleModels.sort((a, b) => a.sizeInBytes.compareTo(b.sizeInBytes));
        return compatibleModels.first;
      }
    }
    
    // Return default smallest model
    if (allowedModels.isNotEmpty) {
      final sortedModels = List<ModelMetadata>.from(allowedModels);
      sortedModels.sort((a, b) => a.sizeInBytes.compareTo(b.sizeInBytes));
      return sortedModels.first;
    }
    
    return null;
  }

  /// Load allowlist from JSON
  static List<ModelMetadata> fromJson(String jsonString) {
    final Map<String, dynamic> data = json.decode(jsonString);
    final List<dynamic> models = data['models'] ?? [];
    
    return models.map((modelJson) => ModelMetadata.fromJson(modelJson)).toList();
  }

  /// Convert allowlist to JSON
  static String toJson(List<ModelMetadata> models) {
    final data = {
      'version': '1.0.0',
      'models': models.map((model) => model.toJson()).toList(),
    };
    return json.encode(data);
  }
}

/// Download status following Google AI Edge Gallery pattern
enum ModelDownloadStatus {
  notStarted,
  enqueued,
  running,
  succeeded,
  failed,
  cancelled,
}

extension ModelDownloadStatusExtension on ModelDownloadStatus {
  bool get isComplete => this == ModelDownloadStatus.succeeded;
  bool get isError => this == ModelDownloadStatus.failed || this == ModelDownloadStatus.cancelled;
  bool get isInProgress => this == ModelDownloadStatus.running || this == ModelDownloadStatus.enqueued;
}

/// Download progress information
class ModelDownloadProgress {
  final ModelMetadata model;
  final ModelDownloadStatus status;
  final double progress; // 0.0 to 1.0
  final int? downloadedBytes;
  final int? totalBytes;
  final String? errorMessage;
  final DateTime timestamp;

  const ModelDownloadProgress({
    required this.model,
    required this.status,
    this.progress = 0.0,
    this.downloadedBytes,
    this.totalBytes,
    this.errorMessage,
    required this.timestamp,
  });

  /// Get download speed in bytes per second
  double? get downloadSpeedBps {
    if (downloadedBytes == null || progress <= 0) return null;
    
    final elapsedSeconds = DateTime.now().difference(timestamp).inSeconds;
    if (elapsedSeconds <= 0) return null;
    
    return downloadedBytes! / elapsedSeconds;
  }

  /// Format download speed for display
  String? get formattedSpeed {
    final speed = downloadSpeedBps;
    if (speed == null) return null;
    
    if (speed < 1024) return '${speed.toStringAsFixed(0)}B/s';
    if (speed < 1024 * 1024) return '${(speed / 1024).toStringAsFixed(1)}KB/s';
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)}MB/s';
  }

  /// Estimated time remaining
  Duration? get estimatedTimeRemaining {
    final speed = downloadSpeedBps;
    if (speed == null || totalBytes == null || downloadedBytes == null) return null;
    
    final remainingBytes = totalBytes! - downloadedBytes!;
    if (remainingBytes <= 0 || speed <= 0) return null;
    
    return Duration(seconds: (remainingBytes / speed).round());
  }

  /// Copy with updated values
  ModelDownloadProgress copyWith({
    ModelDownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    String? errorMessage,
  }) {
    return ModelDownloadProgress(
      model: model,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() => 'ModelDownloadProgress(model: ${model.name}, status: $status, progress: ${(progress * 100).toStringAsFixed(1)}%)';
}