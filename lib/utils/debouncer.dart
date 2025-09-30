import 'dart:async';
import 'dart:ui';

/// Debouncer for reducing setState call frequency
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  void call(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Throttler for limiting setState call rate
class Throttler {
  final Duration duration;
  Timer? _timer;
  bool _isReady = true;
  VoidCallback? _pendingAction;

  Throttler({required this.duration});

  void call(VoidCallback action) {
    if (_isReady) {
      // Execute immediately
      action();
      _isReady = false;

      // Set up cooldown
      _timer = Timer(duration, () {
        _isReady = true;

        // Execute pending action if any
        if (_pendingAction != null) {
          final pending = _pendingAction;
          _pendingAction = null;
          call(pending!);
        }
      });
    } else {
      // Queue the action to run after cooldown
      _pendingAction = action;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pendingAction = null;
  }
}