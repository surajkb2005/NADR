import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_compass/flutter_compass.dart';
import 'package:nadr_mobile/core/diagnostics/nadr_diagnostics.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_sample.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_source.dart';
import 'package:nadr_mobile/features/imu/infrastructure/android_heading_capability.dart';
import 'package:nadr_mobile/features/navigation/domain/connection_status.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Android's user accelerometer removes gravity like DeviceMotion.acceleration.
/// flutter_compass heading is already clockwise from north; no browser -90°.
final class AndroidImuSensorSource implements ImuSensorSource {
  AndroidImuSensorSource({
    HeadingCapabilitySource? headingCapability,
    Stream<CompassEvent>? Function()? compassEvents,
    Stream<UserAccelerometerEvent> Function()? motionEvents,
  }) : _headingCapability =
           headingCapability ?? const AndroidHeadingCapabilitySource(),
       _compassEvents = compassEvents ?? (() => FlutterCompass.events),
       _motionEvents =
           motionEvents ??
           (() => userAccelerometerEventStream(
             samplingPeriod: const Duration(milliseconds: 50),
           ));

  final HeadingCapabilitySource _headingCapability;
  final Stream<CompassEvent>? Function() _compassEvents;
  final Stream<UserAccelerometerEvent> Function() _motionEvents;
  final _samples = StreamController<ImuSensorSample>.broadcast();
  final _statuses = StreamController<SensorStatus>.broadcast();
  StreamSubscription<UserAccelerometerEvent>? _motion;
  StreamSubscription<CompassEvent>? _compass;
  Timer? _availabilityTimer;
  double? _heading;
  bool _hasMotion = false;
  bool _headingSupported = false;
  bool _headingUnavailableAnnounced = false;
  bool _active = false;
  bool _started = false;
  bool _disposed = false;
  int _motionEventsSinceLog = 0;
  DateTime? _lastMotionLogAt;
  DateTime? _startedAt;
  DateTime? _lastHeadingAt;

  @override
  Stream<ImuSensorSample> get samples => _samples.stream;
  @override
  Stream<SensorStatus> get statusChanges => _statuses.stream;

  @override
  Future<void> start() async {
    if (_disposed || _started) return;
    _started = true;
    _hasMotion = false;
    _active = false;
    _heading = null;
    _headingSupported = false;
    _headingUnavailableAnnounced = false;
    _startedAt = DateTime.now();
    _lastHeadingAt = null;
    _motionEventsSinceLog = 0;
    _lastMotionLogAt = null;
    _statuses.add(SensorStatus.starting);
    try {
      _headingSupported = await _headingCapability.hasNorthReferencedHeading();
      if (!_started || _disposed) return;
      NadrDiagnostics.log(
        'NADR_IMU_CAPABILITY',
        'northReferencedHeading=$_headingSupported',
      );
      if (_headingSupported) {
        final compassEvents = _compassEvents();
        if (compassEvents == null) {
          _markHeadingUnavailable('compass_stream_missing');
        } else {
          _compass = compassEvents.listen(
            (event) {
              if (!_started || _disposed) return;
              final value = event.heading;
              final normalized = normalizeCompassHeading(value);
              if (normalized == null) {
                _markHeadingUnavailable('invalid_heading');
                return;
              }
              _heading = normalized;
              _lastHeadingAt = DateTime.now();
              NadrDiagnostics.throttled(
                'NADR_IMU_HEADING',
                'compass',
                'raw=$value normalized=$_heading sensorAt=${_lastHeadingAt!.toIso8601String()}',
              );
              _checkActive();
            },
            onError: (Object error, StackTrace stackTrace) =>
                _fail(SensorStatus.error),
          );
        }
      } else {
        _markHeadingUnavailable('north_referenced_sensor_absent');
      }
      _motion = _motionEvents().listen(
        (event) {
          if (!_started || _disposed) return;
          if (!event.x.isFinite || !event.y.isFinite || !event.z.isFinite) {
            return;
          }
          _hasMotion = true;
          _motionEventsSinceLog++;
          final receivedAt = DateTime.now();
          final previousLogAt = _lastMotionLogAt;
          if (previousLogAt == null ||
              receivedAt.difference(previousLogAt) >=
                  const Duration(seconds: 1)) {
            final magnitude = math.sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z,
            );
            NadrDiagnostics.log(
              'NADR_IMU_SENSOR',
              'events=$_motionEventsSinceLog intervalMs=${previousLogAt == null ? 0 : receivedAt.difference(previousLogAt).inMilliseconds} '
                  'x=${event.x} y=${event.y} z=${event.z} magnitude=$magnitude '
                  'received=${receivedAt.toIso8601String()}',
            );
            _motionEventsSinceLog = 0;
            _lastMotionLogAt = receivedAt;
          }
          _checkActive();
          _samples.add(
            ImuSensorSample(
              linearAccelerationX: event.x,
              linearAccelerationY: event.y,
              linearAccelerationZ: event.z,
              heading: _heading,
              timestamp: DateTime.now(),
            ),
          );
        },
        onError: (Object error, StackTrace stackTrace) =>
            _fail(SensorStatus.error),
      );
      _availabilityTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_started) return;
        final now = DateTime.now();
        if (!_hasMotion &&
            now.difference(_startedAt!) >= const Duration(seconds: 4)) {
          _fail(SensorStatus.unavailable);
          return;
        }
        if (_headingSupported &&
            (_lastHeadingAt == null ||
                now.difference(_lastHeadingAt!) >=
                    const Duration(seconds: 4)) &&
            now.difference(_startedAt!) >= const Duration(seconds: 4)) {
          _markHeadingUnavailable('heading_timeout');
        }
      });
    } on Object {
      _fail(SensorStatus.error);
    }
  }

  void _checkActive() {
    if (_started && !_active && _hasMotion && _heading != null) {
      _active = true;
      _headingUnavailableAnnounced = false;
      _statuses.add(SensorStatus.active);
    }
  }

  void _markHeadingUnavailable(String reason) {
    _heading = null;
    _active = false;
    if (!_started || _headingUnavailableAnnounced) return;
    _headingUnavailableAnnounced = true;
    NadrDiagnostics.log(
      'NADR_IMU_CAPABILITY',
      'heading_unavailable reason=$reason',
    );
    _statuses.add(SensorStatus.headingUnavailable);
  }

  static double? normalizeCompassHeading(double? heading) {
    if (heading == null || !heading.isFinite) return null;
    return ((heading % 360) + 360) % 360;
  }

  void _fail(SensorStatus status) {
    if (!_started || _disposed) return;
    _statuses.add(status);
    unawaited(_stop(emitStatus: false));
  }

  @override
  Future<void> stop() async {
    await _stop(emitStatus: true);
  }

  Future<void> _stop({required bool emitStatus}) async {
    if (!_started) return;
    _started = false;
    _active = false;
    _heading = null;
    _headingSupported = false;
    _availabilityTimer?.cancel();
    await _motion?.cancel();
    await _compass?.cancel();
    _motion = null;
    _compass = null;
    if (!_disposed && emitStatus) _statuses.add(SensorStatus.stopped);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _samples.close();
    await _statuses.close();
  }
}
