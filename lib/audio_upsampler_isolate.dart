import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

/// Isolate-based audio upsampler for non-blocking audio processing
class AudioUpsamplerIsolate {
  Isolate? _isolate;
  SendPort? _sendPort;
  final _responseController = StreamController<Uint8List>.broadcast();
  ReceivePort? _receivePort;

  /// Stream of upsampled audio data
  Stream<Uint8List> get outputStream => _responseController.stream;

  /// Initialize the isolate
  Future<void> initialize() async {
    if (_isolate != null) return;

    _receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      _upsamplerIsolateEntry,
      _receivePort!.sendPort,
    );

    // Wait for the isolate to send back its SendPort
    _sendPort = await _receivePort!.first as SendPort;

    // Listen for upsampled audio from isolate
    _receivePort!.listen((message) {
      if (message is Uint8List) {
        _responseController.add(message);
      }
    });
  }

  /// Send audio data to isolate for upsampling
  void upsample(Uint8List audioData) {
    _sendPort?.send(audioData);
  }

  /// Dispose the isolate and clean up resources
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _receivePort?.close();
    _receivePort = null;
    _responseController.close();
  }

  /// Isolate entry point - runs audio upsampling in background
  static void _upsamplerIsolateEntry(SendPort mainSendPort) {
    final receivePort = ReceivePort();

    // Send this isolate's SendPort back to main isolate
    mainSendPort.send(receivePort.sendPort);

    // Listen for audio data to upsample
    receivePort.listen((message) {
      if (message is Uint8List) {
        try {
          final upsampled = _upsample8kTo16k(message);
          mainSendPort.send(upsampled);
        } catch (e) {
          // Silent fail - don't crash the isolate
        }
      }
    });
  }

  /// Upsamples PCM16 audio data from 8kHz to 16kHz using linear interpolation
  /// This runs in the isolate, off the main thread
  static Uint8List _upsample8kTo16k(Uint8List input) {
    // Convert input bytes to Int16List for easier sample manipulation
    Int16List inputSamples = Int16List.view(input.buffer);

    // Calculate output size (2x input since we're going from 8kHz to 16kHz)
    Int16List outputSamples = Int16List(inputSamples.length * 2);

    // Process each sample
    for (int i = 0; i < inputSamples.length - 1; i++) {
      int currentSample = inputSamples[i];
      int nextSample = inputSamples[i + 1];

      // Calculate interpolated values
      outputSamples[i * 2] = currentSample;
      outputSamples[i * 2 + 1] =
          currentSample + ((nextSample - currentSample) ~/ 2);
    }

    // Handle the last sample
    outputSamples[outputSamples.length - 2] = inputSamples.last;
    outputSamples[outputSamples.length - 1] = inputSamples.last;

    // Convert back to Uint8List
    return Uint8List.view(outputSamples.buffer);
  }
}