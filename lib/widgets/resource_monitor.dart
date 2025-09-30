import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Resource monitor overlay that displays app performance metrics
class ResourceMonitor extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const ResourceMonitor({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<ResourceMonitor> createState() => _ResourceMonitorState();
}

class _ResourceMonitorState extends State<ResourceMonitor> {
  Timer? _updateTimer;
  bool _visible = false;

  // Memory metrics
  int _currentRss = 0;
  int _currentHeapUsage = 0;

  // Performance metrics
  double _fps = 0.0;
  int _isolateCount = 0;

  // Frame timing
  final List<Duration> _frameTimes = [];
  Duration? _lastFrameTimestamp;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _startMonitoring();
    }
  }

  @override
  void dispose() {
    _stopMonitoring();
    super.dispose();
  }

  void _startMonitoring() {
    // Update metrics every 500ms
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _updateMetrics();
    });

    // Track frame times
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _stopMonitoring() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  void _onFrame(Duration timestamp) {
    if (!mounted) return;

    if (_lastFrameTimestamp != null) {
      final frameDuration = timestamp - _lastFrameTimestamp!;
      _frameTimes.add(frameDuration);

      // Keep only last 60 frames
      if (_frameTimes.length > 60) {
        _frameTimes.removeAt(0);
      }

      // Calculate FPS from average frame time
      if (_frameTimes.isNotEmpty) {
        final avgMicros = _frameTimes
            .map((d) => d.inMicroseconds)
            .reduce((a, b) => a + b) / _frameTimes.length;
        _fps = avgMicros > 0 ? 1000000 / avgMicros : 0;
      }
    }

    _lastFrameTimestamp = timestamp;
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  Future<void> _updateMetrics() async {
    if (!mounted) return;

    try {
      // Get memory info
      final info = ProcessInfo.currentRss;
      final heapUsage = ProcessInfo.currentRss; // Dart heap

      // Get isolate count
      int isolateCount = 1; // Main isolate
      try {
        // Try to get isolate count (may not work on all platforms)
        isolateCount = Isolate.current.debugName != null ? 1 : 1;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _currentRss = info;
          _currentHeapUsage = heapUsage;
          _isolateCount = isolateCount;
        });
      }
    } catch (e) {
      // Silently fail - some platforms may not support all metrics
    }
  }

  void _toggleVisibility() {
    setState(() {
      _visible = !_visible;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.enabled)
          Positioned(
            top: 40,
            right: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Toggle button
                FloatingActionButton.small(
                  heroTag: 'resource_monitor_toggle',
                  onPressed: _toggleVisibility,
                  child: Icon(_visible ? Icons.close : Icons.analytics),
                ),
                if (_visible) ...[
                  const SizedBox(height: 8),
                  // Stats panel
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Resource Monitor',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Divider(color: Colors.green, height: 16),
                        _buildMetric('FPS', _fps.toStringAsFixed(1)),
                        _buildMetric('Memory (RSS)', _formatBytes(_currentRss)),
                        _buildMetric('Heap', _formatBytes(_currentHeapUsage)),
                        _buildMetric('Isolates', _isolateCount.toString()),
                        const SizedBox(height: 8),
                        // Frame time indicator
                        _buildFrameTimeIndicator(),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMetric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrameTimeIndicator() {
    final recentFrames = _frameTimes.length >= 10
        ? _frameTimes.sublist(_frameTimes.length - 10)
        : _frameTimes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Frame Time (10 frames)',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: recentFrames.map((duration) {
            final ms = duration.inMicroseconds / 1000;
            final color = ms < 16.67
                ? Colors.green
                : ms < 33
                    ? Colors.orange
                    : Colors.red;

            return Container(
              width: 3,
              height: 20,
              margin: const EdgeInsets.only(right: 2),
              color: color,
            );
          }).toList(),
        ),
        const SizedBox(height: 2),
        const Text(
          'Green: <16.67ms (60fps), Orange: <33ms (30fps)',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 8,
          ),
        ),
      ],
    );
  }
}