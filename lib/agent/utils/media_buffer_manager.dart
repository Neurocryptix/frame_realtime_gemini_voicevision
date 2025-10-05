import 'dart:async';
import 'dart:typed_data';

/// Buffered audio packet with metadata
class BufferedAudioPacket {
  final Uint8List data;
  final DateTime timestamp;
  final int sequenceNumber;

  BufferedAudioPacket({
    required this.data,
    required this.timestamp,
    required this.sequenceNumber,
  });
}

/// Buffered image with metadata
class BufferedImage {
  final Uint8List data;
  final DateTime timestamp;
  final int sequenceNumber;

  BufferedImage({
    required this.data,
    required this.timestamp,
    required this.sequenceNumber,
  });
}

/// Audio batch ready for processing
class AudioBatch {
  final List<BufferedAudioPacket> packets;
  final Uint8List combinedData;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;

  AudioBatch({
    required this.packets,
    required this.combinedData,
    required this.startTime,
    required this.endTime,
    required this.duration,
  });

  int get packetCount => packets.length;
  int get totalBytes => combinedData.length;
}

/// Image batch ready for processing
class ImageBatch {
  final List<BufferedImage> images;
  final DateTime startTime;
  final DateTime endTime;
  final Duration timeSpan;

  ImageBatch({
    required this.images,
    required this.startTime,
    required this.endTime,
    required this.timeSpan,
  });

  int get imageCount => images.length;
}

/// Manages audio packet buffering for batch processing
/// Accumulates audio packets and triggers batch processing based on configurable thresholds
class AudioBufferManager {
  final void Function(String)? _logger;

  // Buffer configuration
  final int minPacketsPerBatch;
  final Duration maxBufferDuration;
  final int maxBufferSizeBytes;

  // Buffer state
  final List<BufferedAudioPacket> _buffer = [];
  int _sequenceNumber = 0;
  Timer? _flushTimer;

  // Callback for batch ready
  final void Function(AudioBatch batch)? onBatchReady;

  // Statistics
  int _totalPacketsBuffered = 0;
  int _totalBatchesProcessed = 0;
  int _totalBytesBuffered = 0;

  AudioBufferManager({
    void Function(String)? logger,
    this.minPacketsPerBatch = 40, // ~2 seconds at 20 packets/sec
    this.maxBufferDuration = const Duration(milliseconds: 3000), // Max 3 seconds
    this.maxBufferSizeBytes = 500 * 1024, // 500KB max buffer
    this.onBatchReady,
  }) : _logger = logger;

  /// Add an audio packet to the buffer
  void addPacket(Uint8List audioData) {
    final packet = BufferedAudioPacket(
      data: audioData,
      timestamp: DateTime.now(),
      sequenceNumber: _sequenceNumber++,
    );

    _buffer.add(packet);
    _totalPacketsBuffered++;
    _totalBytesBuffered += audioData.length;

    // Start flush timer on first packet
    if (_buffer.length == 1) {
      _startFlushTimer();
    }

    // Check if we should flush based on size thresholds
    if (_shouldFlushBuffer()) {
      _flushBuffer();
    }
  }

  /// Check if buffer should be flushed
  bool _shouldFlushBuffer() {
    if (_buffer.isEmpty) return false;

    // Check packet count threshold
    if (_buffer.length >= minPacketsPerBatch) {
      return true;
    }

    // Check buffer size threshold
    final totalSize = _buffer.fold<int>(0, (sum, packet) => sum + packet.data.length);
    if (totalSize >= maxBufferSizeBytes) {
      return true;
    }

    // Check time threshold
    final bufferDuration = DateTime.now().difference(_buffer.first.timestamp);
    if (bufferDuration >= maxBufferDuration) {
      return true;
    }

    return false;
  }

  /// Start or restart the flush timer
  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer(maxBufferDuration, () {
      if (_buffer.isNotEmpty) {
        _flushBuffer();
      }
    });
  }

  /// Flush the buffer and create a batch
  void _flushBuffer() {
    if (_buffer.isEmpty) return;

    _flushTimer?.cancel();
    _flushTimer = null;

    // Combine all audio data
    final totalSize = _buffer.fold<int>(0, (sum, packet) => sum + packet.data.length);
    final combinedData = Uint8List(totalSize);
    int offset = 0;

    for (final packet in _buffer) {
      combinedData.setRange(offset, offset + packet.data.length, packet.data);
      offset += packet.data.length;
    }

    // Create batch
    final batch = AudioBatch(
      packets: List.from(_buffer),
      combinedData: combinedData,
      startTime: _buffer.first.timestamp,
      endTime: _buffer.last.timestamp,
      duration: _buffer.last.timestamp.difference(_buffer.first.timestamp),
    );

    _totalBatchesProcessed++;
    _logger?.call(
      '🎤 Audio batch ready: ${batch.packetCount} packets, '
      '${(batch.totalBytes / 1024).toStringAsFixed(1)}KB, '
      '${batch.duration.inMilliseconds}ms duration'
    );

    // Clear buffer
    _buffer.clear();

    // Notify callback
    onBatchReady?.call(batch);
  }

  /// Force flush current buffer
  void flush() {
    _flushBuffer();
  }

  /// Get buffer statistics
  Map<String, dynamic> getStatistics() {
    return {
      'totalPacketsBuffered': _totalPacketsBuffered,
      'totalBatchesProcessed': _totalBatchesProcessed,
      'totalBytesBuffered': _totalBytesBuffered,
      'currentBufferSize': _buffer.length,
      'avgPacketsPerBatch': _totalBatchesProcessed > 0
          ? _totalPacketsBuffered / _totalBatchesProcessed
          : 0,
    };
  }

  /// Clean up resources
  void dispose() {
    _flushTimer?.cancel();
    _buffer.clear();
  }
}

/// Manages image buffering for batch processing
/// Groups images within temporal windows for related content analysis
class ImageBufferManager {
  final void Function(String)? _logger;

  // Buffer configuration
  final int minImagesPerBatch;
  final Duration maxBufferDuration;
  final int maxBufferCount;

  // Buffer state
  final List<BufferedImage> _buffer = [];
  int _sequenceNumber = 0;
  Timer? _flushTimer;

  // Callback for batch ready
  final void Function(ImageBatch batch)? onBatchReady;

  // Statistics
  int _totalImagesBuffered = 0;
  int _totalBatchesProcessed = 0;

  ImageBufferManager({
    void Function(String)? logger,
    this.minImagesPerBatch = 5, // Min 5 images per batch
    this.maxBufferDuration = const Duration(milliseconds: 3000), // Max 3 seconds
    this.maxBufferCount = 10, // Max 10 images in buffer
    this.onBatchReady,
  }) : _logger = logger;

  /// Add an image to the buffer
  void addImage(Uint8List imageData) {
    final bufferedImage = BufferedImage(
      data: imageData,
      timestamp: DateTime.now(),
      sequenceNumber: _sequenceNumber++,
    );

    _buffer.add(bufferedImage);
    _totalImagesBuffered++;

    // Start flush timer on first image
    if (_buffer.length == 1) {
      _startFlushTimer();
    }

    // Check if we should flush based on thresholds
    if (_shouldFlushBuffer()) {
      _flushBuffer();
    }
  }

  /// Check if buffer should be flushed
  bool _shouldFlushBuffer() {
    if (_buffer.isEmpty) return false;

    // Check image count threshold
    if (_buffer.length >= minImagesPerBatch) {
      return true;
    }

    // Check max buffer count
    if (_buffer.length >= maxBufferCount) {
      return true;
    }

    // Check time threshold
    final bufferDuration = DateTime.now().difference(_buffer.first.timestamp);
    if (bufferDuration >= maxBufferDuration) {
      return true;
    }

    return false;
  }

  /// Start or restart the flush timer
  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer(maxBufferDuration, () {
      if (_buffer.isNotEmpty) {
        _flushBuffer();
      }
    });
  }

  /// Flush the buffer and create a batch
  void _flushBuffer() {
    if (_buffer.isEmpty) return;

    _flushTimer?.cancel();
    _flushTimer = null;

    // Create batch
    final batch = ImageBatch(
      images: List.from(_buffer),
      startTime: _buffer.first.timestamp,
      endTime: _buffer.last.timestamp,
      timeSpan: _buffer.last.timestamp.difference(_buffer.first.timestamp),
    );

    _totalBatchesProcessed++;
    _logger?.call(
      '📸 Image batch ready: ${batch.imageCount} images, '
      '${batch.timeSpan.inMilliseconds}ms timespan'
    );

    // Clear buffer
    _buffer.clear();

    // Notify callback
    onBatchReady?.call(batch);
  }

  /// Force flush current buffer
  void flush() {
    _flushBuffer();
  }

  /// Get buffer statistics
  Map<String, dynamic> getStatistics() {
    return {
      'totalImagesBuffered': _totalImagesBuffered,
      'totalBatchesProcessed': _totalBatchesProcessed,
      'currentBufferSize': _buffer.length,
      'avgImagesPerBatch': _totalBatchesProcessed > 0
          ? _totalImagesBuffered / _totalBatchesProcessed
          : 0,
    };
  }

  /// Clean up resources
  void dispose() {
    _flushTimer?.cancel();
    _buffer.clear();
  }
}
