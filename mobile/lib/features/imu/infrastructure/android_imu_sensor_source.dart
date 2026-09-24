import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter/services.dart';
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
    Stream<GyroscopeEvent> Function()? gyroscopeEvents,
    Stream<Object?> Function()? stepEvents,
  }) : _headingCapability =
           headingCapability ?? const AndroidHeadingCapabilitySource(),
       _compassEvents = compassEvents ?? (() => FlutterCompass.events),
       _motionEvents =
           motionEvents ??
           (() => userAccelerometerEventStream(
             samplingPeriod: const Duration(milliseconds: 50),
           )),
       _gyroscopeEvents =
           gyroscopeEvents ??
           (() => gyroscopeEventStream(
             samplingPeriod: const Duration(milliseconds: 50),
           )),
       _stepEvents =
           stepEvents ??
           (() =>
               const EventChannel('nadr/step_detector')
                   .receiveBroadcastStream());

  final HeadingCapabilitySource _headingCapability;
  final Stream<CompassEvent>? Function() _compassEvents;
  final Stream<UserAccelerometerEvent> Function() _motionEvents;
  final Stream<GyroscopeEvent> Function() _gyroscopeEvents;
  final Stream<Object?> Function() _stepEvents;
  final _samples = StreamController<ImuSensorSample>.broadcast();
  final _statuses = StreamController<SensorStatus>.broadcast();
  StreamSubscription<UserAccelerometerEvent>? _motion;
  StreamSubscription<GyroscopeEvent>? _gyroscope;
  StreamSubscription<CompassEvent>? _compass;
  StreamSubscription<Object?>? _steps;
  Timer? _availabilityTimer;
  double? _heading;
  double? _headingAccuracyDegrees;
  double? _angularVelocityRadiansPerSecond;
  bool _hasMotion = false;
  bool _headingSupported = false;
  bool _headingUnavailableAnnounced = false;
  SensorStatus? _operationalStatus;
  bool _started = false;
  bool _disposed = false;
  int _motionEventsSinceLog = 0;
  int _detectedSteps = 0;
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
    _heading = null;
    _headingAccuracyDegrees = null;
    _angularVelocityRadiansPerSecond = null;
    _headingSupported = false;
    _headingUnavailableAnnounced = false;
    _operationalStatus = null;
    _startedAt = DateTime.now();
    _lastHeadingAt = null;
    _motionEventsSinceLog = 0;
    _detectedSteps = 0;
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
              _headingAccuracyDegrees = normalizeHeadingAccuracy(
                event.accuracy,
              );
              _heading = normalized;
              _lastHeadingAt = DateTime.now();
              NadrDiagnostics.throttled(
                'NADR_IMU_HEADING',
                'compass',
                'raw=$value normalized=$_heading accuracyDegrees=$_headingAccuracyDegrees '
                    'quality=${headingQuality(_headingAccuracyDegrees)} '
                    'sensorAt=${_lastHeadingAt!.toIso8601String()}',
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
                  'angularVelocityRadPerSec=$_angularVelocityRadiansPerSecond '
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
              headingAccuracyDegrees: _headingAccuracyDegrees,
              angularVelocityRadiansPerSecond: _angularVelocityRadiansPerSecond,
              timestamp: DateTime.now(),
            ),
          );
        },
        onError: (Object error, StackTrace stackTrace) =>
            _fail(SensorStatus.error),
      );
      _gyroscope = _gyroscopeEvents().listen(
        (event) {
          if (!_started || _disposed) return;
          if (!event.x.isFinite || !event.y.isFinite || !event.z.isFinite) {
            return;
          }
          _angularVelocityRadiansPerSecond = math.sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          _angularVelocityRadiansPerSecond = null;
          NadrDiagnostics.log(
            'NADR_IMU_CAPABILITY',
            'gyroscope=false error=$error',
          );
        },
      );
      _steps = _stepEvents().listen(
        (event) {
          if (!_started || _disposed || event is! Map) return;
          final type = event['type'];
          if (type == 'ready') {
            NadrDiagnostics.log('NADR_IMU_CAPABILITY', 'stepDetector=true');
            _checkActive();
            return;
          }
          if (type != 'step') return;
          _detectedSteps++;
          final receivedAt = DateTime.now();
          NadrDiagnostics.log(
            'NADR_IMU_STEP',
            'detected=true sessionSteps=$_detectedSteps '
                'heading=$_heading accuracyDegrees=$_headingAccuracyDegrees '
                'received=${receivedAt.toIso8601String()}',
          );
          _samples.add(
            ImuSensorSample(
              linearAccelerationX: 0,
              linearAccelerationY: 0,
              linearAccelerationZ: 0,
              heading: _heading,
              headingAccuracyDegrees: _headingAccuracyDegrees,
              angularVelocityRadiansPerSecond: _angularVelocityRadiansPerSecond,
              timestamp: receivedAt,
              stepDetected: true,
            ),
          );
          _checkActive();
        },
        onError: (Object error, StackTrace stackTrace) {
          NadrDiagnostics.log(
            'NADR_IMU_CAPABILITY',
            'stepDetector=false error=$error',
          );
        },
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
    if (!_started || !_hasMotion || _heading == null) return;
    final nextStatus = headingQuality(_headingAccuracyDegrees) == 'low'
        ? SensorStatus.calibrating
        : SensorStatus.active;
    if (_operationalStatus == nextStatus) return;
    _headingUnavailableAnnounced = false;
    _operationalStatus = nextStatus;
    _statuses.add(nextStatus);
  }

  void _markHeadingUnavailable(String reason) {
    _heading = null;
    _operationalStatus = null;
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

  static double? normalizeHeadingAccuracy(double? accuracy) {
    if (accuracy == null || !accuracy.isFinite || accuracy < 0) return null;
    return accuracy;
  }

  static String headingQuality(double? accuracyDegrees) {
    if (accuracyDegrees == null) return 'unknown';
    if (accuracyDegrees <= 15) return 'high';
    if (accuracyDegrees <= 30) return 'medium';
    return 'low';
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
    _heading = null;
    _headingAccuracyDegrees = null;
    _angularVelocityRadiansPerSecond = null;
    _headingSupported = false;
    _operationalStatus = null;
    _availabilityTimer?.cancel();
    await _motion?.cancel();
    await _gyroscope?.cancel();
    await _compass?.cancel();
    await _steps?.cancel();
    _motion = null;
    _gyroscope = null;
    _compass = null;
    _steps = null;
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
