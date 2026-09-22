import 'package:flutter/foundation.dart';

/// Debug-only pipeline tracing. Tags are intentionally stable for adb logcat.
final class NadrDiagnostics {
  NadrDiagnostics._();

  static final Map<String, DateTime> _lastLogAt = {};

  static void log(String tag, String message) {
    if (!kDebugMode) return;
    debugPrint('$tag $message');
  }

  static void throttled(
    String tag,
    String key,
    String message, {
    Duration interval = const Duration(seconds: 1),
  }) {
    if (!kDebugMode) return;
    final now = DateTime.now();
    final previous = _lastLogAt[key];
    if (previous != null && now.difference(previous) < interval) return;
    _lastLogAt[key] = now;
    log(tag, message);
  }
}
