import 'dart:math' as math;

import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_sample.dart';
import 'package:nadr_mobile/features/navigation/domain/position_estimator.dart';

/// Ports frontend/src/App.jsx's local IMU speed/position heuristic.
final class WebsiteImuPositionEstimator implements PositionEstimator {
  WebsiteImuPositionEstimator({this.onDiagnostic});

  final void Function(String message)? onDiagnostic;
  static const movementThreshold = 1.0;
  static const accelerationGain = 0.6;
  static const speedCapKilometersPerHour = 20.0;
  static const decayMultiplier = 0.90;
  static const decaySubtraction = 1.0;
  static const lowSpeedCutoff = 2.0;
  static const earthRadiusMeters = 6371000.0;

  PositionSample? _estimate;
  DateTime? _previousTick;
  double? _heading;
  double _speedKilometersPerHour = 0;
  int _eventsSinceTick = 0;
  int _contributingEventsSinceTick = 0;
  double _speedAtWindowStart = 0;

  @override
  PositionSample? get latestEstimate => _estimate;
  double get speedKilometersPerHour => _speedKilometersPerHour;

  @override
  void reset({required GeoCoordinate origin, required DateTime timestamp}) {
    if (!origin.latitude.isFinite ||
        !origin.longitude.isFinite ||
        origin.latitude < -90 ||
        origin.latitude > 90 ||
        origin.longitude < -180 ||
        origin.longitude > 180) {
      throw ArgumentError.value(origin, 'origin', 'Invalid GPS origin');
    }
    _speedKilometersPerHour = 0;
    _eventsSinceTick = 0;
    _contributingEventsSinceTick = 0;
    _speedAtWindowStart = 0;
    _heading = null;
    _previousTick = null;
    _estimate = PositionSample(
      coordinate: origin,
      timestamp: timestamp,
      source: PositionSource.imu,
    );
  }

  @override
  PositionSample clearHeading({required DateTime timestamp}) {
    final current = _estimate;
    if (current == null) throw StateError('A real GPS origin is required.');
    _heading = null;
    // Motion observed without a direction must not move the next valid fix.
    _speedKilometersPerHour = 0;
    _eventsSinceTick = 0;
    _contributingEventsSinceTick = 0;
    _speedAtWindowStart = 0;
    return _update(
      current.coordinate,
      timestamp.isBefore(current.timestamp) ? current.timestamp : timestamp,
    );
  }

  @override
  PositionSample estimate(ImuSensorSample sample) {
    final current = _estimate;
    if (current == null) throw StateError('A real GPS origin is required.');
    if (sample.timestamp.isBefore(current.timestamp)) return current;
    final heading = sample.heading;
    if (heading != null && heading.isFinite && heading >= 0 && heading <= 360) {
      _heading = heading == 360 ? 0 : heading;
    }

    if (!sample.isDecayTick) {
      final x = sample.linearAccelerationX;
      final y = sample.linearAccelerationY;
      final z = sample.linearAccelerationZ;
      if (!x.isFinite || !y.isFinite || !z.isFinite) return current;
      if (_eventsSinceTick == 0) {
        _speedAtWindowStart = _speedKilometersPerHour;
      }
      _eventsSinceTick++;
      final magnitude = math.sqrt(x * x + y * y + z * z);
      final speedBefore = _speedKilometersPerHour;
      if (magnitude.isFinite && magnitude > movementThreshold) {
        _contributingEventsSinceTick++;
        _speedKilometersPerHour = math.min(
          speedCapKilometersPerHour,
          _speedKilometersPerHour + magnitude * accelerationGain,
        );
      }
      onDiagnostic?.call(
        'stage=acceleration x=$x y=$y z=$z magnitude=$magnitude '
        'thresholdCrossed=${magnitude > movementThreshold} '
        'speedBeforeKmh=$speedBefore speedAfterContributionKmh=$_speedKilometersPerHour '
        'heading=$_heading',
      );
      return current;
    }

    final speedBeforeDecay = _speedKilometersPerHour;
    final eventsSinceTick = _eventsSinceTick;
    final contributingEventsSinceTick = _contributingEventsSinceTick;
    final speedAtWindowStart = _eventsSinceTick == 0
        ? _speedKilometersPerHour
        : _speedAtWindowStart;
    _eventsSinceTick = 0;
    _contributingEventsSinceTick = 0;
    if (_speedKilometersPerHour > 0) {
      _speedKilometersPerHour =
          _speedKilometersPerHour * decayMultiplier - decaySubtraction;
      if (_speedKilometersPerHour < lowSpeedCutoff) {
        _speedKilometersPerHour = 0;
      }
    }

    final previousTick = _previousTick;
    _previousTick = sample.timestamp;
    final elapsedSeconds = previousTick == null
        ? 0.1
        : sample.timestamp.difference(previousTick).inMicroseconds / 1000000;
    if (elapsedSeconds < 0 ||
        elapsedSeconds > 2 ||
        !elapsedSeconds.isFinite ||
        _heading == null) {
      onDiagnostic?.call(
        'stage=decay dt=$elapsedSeconds events=$eventsSinceTick contributingEvents=$contributingEventsSinceTick speedAtWindowStartKmh=$speedAtWindowStart speedBeforeDecayKmh=$speedBeforeDecay '
        'speedAfterDecayKmh=$_speedKilometersPerHour heading=$_heading '
        'distanceMeters=0 previous=${current.coordinate} generated=${current.coordinate} reason=invalid_dt_or_heading',
      );
      return _update(current.coordinate, sample.timestamp);
    }

    final distanceMeters = _speedKilometersPerHour / 3.6 * elapsedSeconds;
    if (distanceMeters == 0) {
      onDiagnostic?.call(
        'stage=decay dt=$elapsedSeconds events=$eventsSinceTick contributingEvents=$contributingEventsSinceTick speedAtWindowStartKmh=$speedAtWindowStart speedBeforeDecayKmh=$speedBeforeDecay '
        'speedAfterDecayKmh=$_speedKilometersPerHour heading=$_heading '
        'distanceMeters=0 previous=${current.coordinate} generated=${current.coordinate}',
      );
      return _update(current.coordinate, sample.timestamp);
    }
    final bearing = _heading! * math.pi / 180;
    final latitude = current.coordinate.latitude * math.pi / 180;
    final longitude = current.coordinate.longitude * math.pi / 180;
    final angularDistance = distanceMeters / earthRadiusMeters;
    final nextLatitude = math.asin(
      math.sin(latitude) * math.cos(angularDistance) +
          math.cos(latitude) * math.sin(angularDistance) * math.cos(bearing),
    );
    final nextLongitude =
        longitude +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(latitude),
          math.cos(angularDistance) -
              math.sin(latitude) * math.sin(nextLatitude),
        );
    final nextLatDegrees = nextLatitude * 180 / math.pi;
    final rawLonDegrees = nextLongitude * 180 / math.pi;
    final nextLonDegrees = ((rawLonDegrees + 180) % 360 + 360) % 360 - 180;
    if (!nextLatDegrees.isFinite ||
        !nextLonDegrees.isFinite ||
        nextLatDegrees < -90 ||
        nextLatDegrees > 90) {
      return _update(current.coordinate, sample.timestamp);
    }
    final next = GeoCoordinate(
      latitude: nextLatDegrees,
      longitude: nextLonDegrees,
    );
    onDiagnostic?.call(
      'stage=decay dt=$elapsedSeconds events=$eventsSinceTick contributingEvents=$contributingEventsSinceTick speedAtWindowStartKmh=$speedAtWindowStart speedBeforeDecayKmh=$speedBeforeDecay '
      'speedAfterDecayKmh=$_speedKilometersPerHour heading=$_heading '
      'distanceMeters=$distanceMeters previous=${current.coordinate} generated=$next',
    );
    return _update(next, sample.timestamp);
  }

  PositionSample _update(GeoCoordinate coordinate, DateTime timestamp) {
    return _estimate = PositionSample(
      coordinate: coordinate,
      timestamp: timestamp,
      heading: _heading,
      source: PositionSource.imu,
    );
  }
}
