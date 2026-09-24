import 'dart:math' as math;

import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_sample.dart';
import 'package:nadr_mobile/features/navigation/domain/position_estimator.dart';

/// Android walking estimator driven by discrete walking events.
///
/// Unlike the website reference heuristic, raw accelerometer event count does
/// not accumulate speed. A platform step event is preferred; on devices whose
/// advertised detector emits no events while carried, a hysteretic magnitude
/// peak must repeat at walking cadence before it is accepted. One accepted step
/// advances exactly [stepLengthMeters] along the latest north-referenced device
/// heading. Heading describes the top of the display, not independently
/// measured user travel direction.
final class StepBasedImuPositionEstimator implements PositionEstimator {
  StepBasedImuPositionEstimator({
    this.stepLengthMeters = defaultStepLengthMeters,
    this.onDiagnostic,
  }) {
    if (!stepLengthMeters.isFinite ||
        stepLengthMeters < minimumConfiguredStepLengthMeters ||
        stepLengthMeters > maximumConfiguredStepLengthMeters) {
      throw ArgumentError.value(
        stepLengthMeters,
        'stepLengthMeters',
        'Must be between $minimumConfiguredStepLengthMeters and '
            '$maximumConfiguredStepLengthMeters meters.',
      );
    }
  }

  final double stepLengthMeters;
  final void Function(String message)? onDiagnostic;

  /// Conservative adult walking default. It is configurable at build time
  /// because stride length is personal and cannot be inferred by these sensors.
  static const defaultStepLengthMeters = 0.65;
  static const minimumConfiguredStepLengthMeters = 0.30;
  static const maximumConfiguredStepLengthMeters = 1.50;

  /// Reject duplicate/non-walking step events above four steps per second.
  static const minimumStepInterval = Duration(milliseconds: 250);

  /// A cadence gap above this duration starts a new two-peak confirmation.
  static const maximumWalkingStepInterval = Duration(milliseconds: 1500);

  /// Evidence-based hysteresis for the OnePlus Pad user-acceleration signal.
  /// The physical stationary trace peaked at 0.11 m/s²; walking/handling
  /// samples reached 1.92 m/s². A low crossing re-arms one high crossing.
  static const softwareStepPeakThresholdMetersPerSecondSquared = 0.80;
  static const softwareStepRearmThresholdMetersPerSecondSquared = 0.30;

  /// A deliberate device-only turn is not evidence of walking. Peaks observed
  /// while angular speed is at least about 46°/s are excluded and cadence must
  /// be re-established after the turn.
  static const rotationSuppressionThresholdRadiansPerSecond = 0.80;

  /// Android maps its low compass status to a coarse 45° estimate. The marker
  /// may display that measurement, but a walking step must not be projected
  /// along it until sensor quality improves.
  static const maximumMovementHeadingAccuracyDegrees = 30.0;

  /// After this gap the user is considered stopped and cadence speed is zero.
  static const stationaryTimeout = Duration(seconds: 2);
  static const earthRadiusMeters = 6371000.0;

  PositionSample? _estimate;
  DateTime? _previousAcceptedStepAt;
  DateTime? _pendingSoftwarePeakAt;
  double? _pendingSoftwarePeakHeading;
  bool _softwarePeakArmed = true;
  double? _heading;
  double? _headingAccuracyDegrees;
  double _speedKilometersPerHour = 0;
  double _cumulativeDistanceMeters = 0;
  int _acceptedSteps = 0;
  int _rejectedSteps = 0;

  @override
  PositionSample? get latestEstimate => _estimate;
  double get speedKilometersPerHour => _speedKilometersPerHour;
  double get cumulativeDistanceMeters => _cumulativeDistanceMeters;
  int get acceptedSteps => _acceptedSteps;
  int get rejectedSteps => _rejectedSteps;

  @override
  void reset({required GeoCoordinate origin, required DateTime timestamp}) {
    _validateOrigin(origin);
    _previousAcceptedStepAt = null;
    _pendingSoftwarePeakAt = null;
    _pendingSoftwarePeakHeading = null;
    _softwarePeakArmed = true;
    _heading = null;
    _headingAccuracyDegrees = null;
    _speedKilometersPerHour = 0;
    _cumulativeDistanceMeters = 0;
    _acceptedSteps = 0;
    _rejectedSteps = 0;
    _estimate = PositionSample(
      coordinate: origin,
      timestamp: timestamp,
      source: PositionSource.imu,
    );
  }

  @override
  PositionSample clearHeading({required DateTime timestamp}) {
    final current = _requireEstimate();
    _heading = null;
    _headingAccuracyDegrees = null;
    _previousAcceptedStepAt = null;
    _pendingSoftwarePeakAt = null;
    _pendingSoftwarePeakHeading = null;
    _softwarePeakArmed = true;
    _speedKilometersPerHour = 0;
    return _update(
      current.coordinate,
      timestamp.isBefore(current.timestamp) ? current.timestamp : timestamp,
    );
  }

  @override
  PositionSample estimate(ImuSensorSample sample) {
    final current = _requireEstimate();
    if (sample.timestamp.isBefore(current.timestamp)) return current;
    _acceptHeading(sample.heading, sample.headingAccuracyDegrees);

    if (sample.isDecayTick) {
      final lastStep = _previousAcceptedStepAt;
      if (lastStep == null ||
          sample.timestamp.difference(lastStep) >= stationaryTimeout) {
        _speedKilometersPerHour = 0;
      }
      onDiagnostic?.call(
        'stage=tick speedKmh=$_speedKilometersPerHour '
        'cumulativeDistanceMeters=$_cumulativeDistanceMeters '
        'heading=$_heading headingAccuracyDegrees=$_headingAccuracyDegrees '
        'acceptedSteps=$_acceptedSteps rejectedSteps=$_rejectedSteps '
        'position=${current.coordinate}',
      );
      return _update(current.coordinate, sample.timestamp);
    }

    if (!sample.stepDetected) {
      _processSoftwareAcceleration(sample);
      return _estimate!;
    }
    _pendingSoftwarePeakAt = null;
    _pendingSoftwarePeakHeading = null;
    return _acceptStepBatch(
      timestamp: sample.timestamp,
      headings: [_heading],
      source: 'hardware',
    );
  }

  void _processSoftwareAcceleration(ImuSensorSample sample) {
    final x = sample.linearAccelerationX;
    final y = sample.linearAccelerationY;
    final z = sample.linearAccelerationZ;
    if (!x.isFinite || !y.isFinite || !z.isFinite) return;
    final magnitude = math.sqrt(x * x + y * y + z * z);
    if (magnitude <= softwareStepRearmThresholdMetersPerSecondSquared) {
      _softwarePeakArmed = true;
      return;
    }
    if (!_softwarePeakArmed ||
        magnitude < softwareStepPeakThresholdMetersPerSecondSquared) {
      return;
    }
    _softwarePeakArmed = false;
    final angularVelocity = sample.angularVelocityRadiansPerSecond;
    if (angularVelocity != null &&
        angularVelocity.isFinite &&
        angularVelocity >= rotationSuppressionThresholdRadiansPerSecond) {
      _pendingSoftwarePeakAt = null;
      _pendingSoftwarePeakHeading = null;
      _rejectedSteps++;
      onDiagnostic?.call(
        'stage=step accepted=false source=software reason=device_rotation '
        'magnitude=$magnitude angularVelocityRadPerSec=$angularVelocity',
      );
      return;
    }
    final heading = _heading;
    if (heading == null) {
      _rejectedSteps++;
      onDiagnostic?.call(
        'stage=step accepted=false source=software reason=heading_unavailable '
        'magnitude=$magnitude cumulativeDistanceMeters=$_cumulativeDistanceMeters',
      );
      return;
    }
    if (_isHeadingCalibrating) {
      _pendingSoftwarePeakAt = null;
      _pendingSoftwarePeakHeading = null;
      _rejectedSteps++;
      onDiagnostic?.call(
        'stage=step accepted=false source=software '
        'reason=heading_calibrating magnitude=$magnitude '
        'heading=$heading headingAccuracyDegrees=$_headingAccuracyDegrees',
      );
      final current = _requireEstimate();
      _update(current.coordinate, sample.timestamp);
      return;
    }

    final previousAccepted = _previousAcceptedStepAt;
    final acceptedInterval = previousAccepted == null
        ? null
        : sample.timestamp.difference(previousAccepted);
    if (acceptedInterval != null) {
      if (acceptedInterval < minimumStepInterval) {
        _rejectedSteps++;
        onDiagnostic?.call(
          'stage=step accepted=false source=software reason=duplicate '
          'intervalMs=${acceptedInterval.inMilliseconds} magnitude=$magnitude',
        );
        return;
      }
      if (acceptedInterval <= maximumWalkingStepInterval) {
        _pendingSoftwarePeakAt = null;
        _pendingSoftwarePeakHeading = null;
        _acceptStepBatch(
          timestamp: sample.timestamp,
          headings: [heading],
          source: 'software',
          magnitude: magnitude,
        );
        return;
      }
    }

    final pendingAt = _pendingSoftwarePeakAt;
    final pendingInterval = pendingAt == null
        ? null
        : sample.timestamp.difference(pendingAt);
    if (pendingInterval != null && pendingInterval < minimumStepInterval) {
      _rejectedSteps++;
      onDiagnostic?.call(
        'stage=step accepted=false source=software reason=duplicate '
        'intervalMs=${pendingInterval.inMilliseconds} magnitude=$magnitude',
      );
      return;
    }
    if (pendingInterval != null &&
        pendingInterval <= maximumWalkingStepInterval) {
      final pendingHeading = _pendingSoftwarePeakHeading;
      _pendingSoftwarePeakAt = null;
      _pendingSoftwarePeakHeading = null;
      _acceptStepBatch(
        timestamp: sample.timestamp,
        headings: [pendingHeading, heading],
        source: 'software_confirmed',
        cadenceInterval: pendingInterval,
        magnitude: magnitude,
      );
      return;
    }

    _pendingSoftwarePeakAt = sample.timestamp;
    _pendingSoftwarePeakHeading = heading;
    onDiagnostic?.call(
      'stage=step accepted=false source=software reason=awaiting_cadence '
      'magnitude=$magnitude heading=$heading',
    );
  }

  PositionSample _acceptStepBatch({
    required DateTime timestamp,
    required List<double?> headings,
    required String source,
    Duration? cadenceInterval,
    double? magnitude,
  }) {
    final current = _requireEstimate();
    final heading = _heading;
    if (heading == null || headings.any((value) => value == null)) {
      _rejectedSteps++;
      _speedKilometersPerHour = 0;
      onDiagnostic?.call(
        'stage=step accepted=false source=$source reason=heading_unavailable '
        'cumulativeDistanceMeters=$_cumulativeDistanceMeters',
      );
      return _update(current.coordinate, timestamp);
    }
    if (_isHeadingCalibrating) {
      _rejectedSteps++;
      _speedKilometersPerHour = 0;
      onDiagnostic?.call(
        'stage=step accepted=false source=$source '
        'reason=heading_calibrating heading=$heading '
        'headingAccuracyDegrees=$_headingAccuracyDegrees '
        'cumulativeDistanceMeters=$_cumulativeDistanceMeters',
      );
      return _update(current.coordinate, timestamp);
    }

    final previousStep = _previousAcceptedStepAt;
    final interval =
        cadenceInterval ??
        (previousStep == null ? null : timestamp.difference(previousStep));
    if (interval != null && interval < minimumStepInterval) {
      _rejectedSteps++;
      onDiagnostic?.call(
        'stage=step accepted=false source=$source reason=duplicate intervalMs=${interval.inMilliseconds} '
        'heading=$heading cumulativeDistanceMeters=$_cumulativeDistanceMeters',
      );
      return current;
    }

    _previousAcceptedStepAt = timestamp;
    _acceptedSteps += headings.length;
    final distanceMeters = stepLengthMeters * headings.length;
    _cumulativeDistanceMeters += distanceMeters;
    if (interval == null || interval > maximumWalkingStepInterval) {
      _speedKilometersPerHour = 0;
    } else {
      final seconds = interval.inMicroseconds / Duration.microsecondsPerSecond;
      _speedKilometersPerHour = stepLengthMeters / seconds * 3.6;
    }

    var next = current.coordinate;
    for (final stepHeading in headings.cast<double>()) {
      next = propagate(
        origin: next,
        distanceMeters: stepLengthMeters,
        headingDegrees: stepHeading,
      );
    }
    onDiagnostic?.call(
      'stage=step accepted=true source=$source steps=${headings.length} '
      'intervalMs=${interval?.inMilliseconds} magnitude=$magnitude '
      'stepLengthMeters=$stepLengthMeters speedKmh=$_speedKilometersPerHour '
      'cumulativeDistanceMeters=$_cumulativeDistanceMeters '
      'heading=$heading headingAccuracyDegrees=$_headingAccuracyDegrees '
      'generated=$next',
    );
    return _update(next, timestamp);
  }

  static GeoCoordinate propagate({
    required GeoCoordinate origin,
    required double distanceMeters,
    required double headingDegrees,
  }) {
    if (!distanceMeters.isFinite || distanceMeters < 0) {
      throw ArgumentError.value(distanceMeters, 'distanceMeters');
    }
    if (!headingDegrees.isFinite ||
        headingDegrees < 0 ||
        headingDegrees >= 360) {
      throw ArgumentError.value(headingDegrees, 'headingDegrees');
    }
    final bearing = headingDegrees * math.pi / 180;
    final latitude = origin.latitude * math.pi / 180;
    final longitude = origin.longitude * math.pi / 180;
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
    final rawLongitudeDegrees = nextLongitude * 180 / math.pi;
    return GeoCoordinate(
      latitude: nextLatitude * 180 / math.pi,
      longitude: ((rawLongitudeDegrees + 180) % 360 + 360) % 360 - 180,
    );
  }

  void _acceptHeading(double? heading, double? accuracy) {
    if (heading == null || !heading.isFinite || heading < 0 || heading > 360) {
      return;
    }
    _headingAccuracyDegrees = accuracy != null && accuracy.isFinite
        ? accuracy
        : null;
    if (_isHeadingCalibrating) {
      _previousAcceptedStepAt = null;
      _pendingSoftwarePeakAt = null;
      _pendingSoftwarePeakHeading = null;
      _speedKilometersPerHour = 0;
    }
    _heading = heading == 360 ? 0 : heading;
  }

  bool get _isHeadingCalibrating =>
      _headingAccuracyDegrees != null &&
      _headingAccuracyDegrees! > maximumMovementHeadingAccuracyDegrees;

  PositionSample _requireEstimate() {
    return _estimate ?? (throw StateError('A real GPS origin is required.'));
  }

  PositionSample _update(GeoCoordinate coordinate, DateTime timestamp) {
    return _estimate = PositionSample(
      coordinate: coordinate,
      timestamp: timestamp,
      heading: _heading,
      source: PositionSource.imu,
    );
  }

  static void _validateOrigin(GeoCoordinate origin) {
    if (!origin.latitude.isFinite ||
        !origin.longitude.isFinite ||
        origin.latitude < -90 ||
        origin.latitude > 90 ||
        origin.longitude < -180 ||
        origin.longitude > 180) {
      throw ArgumentError.value(origin, 'origin', 'Invalid GPS origin');
    }
  }
}
