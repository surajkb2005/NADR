import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_sample.dart';
import 'package:nadr_mobile/features/navigation/infrastructure/step_based_imu_position_estimator.dart';

void main() {
  const origin = GeoCoordinate(latitude: 12.9716, longitude: 77.5946);
  final start = DateTime.utc(2026, 9, 24, 10);
  late StepBasedImuPositionEstimator estimator;

  setUp(() {
    estimator = StepBasedImuPositionEstimator(stepLengthMeters: 0.70);
    estimator.reset(origin: origin, timestamp: start);
  });

  ImuSensorSample sample({
    required int milliseconds,
    double? heading = 90,
    double x = 0,
    double y = 0,
    double z = 0,
    bool step = false,
    bool tick = false,
  }) => ImuSensorSample(
    linearAccelerationX: x,
    linearAccelerationY: y,
    linearAccelerationZ: z,
    heading: heading,
    timestamp: start.add(Duration(milliseconds: milliseconds)),
    stepDetected: step,
    isDecayTick: tick,
  );

  test('requires a valid real GPS origin', () {
    final empty = StepBasedImuPositionEstimator();
    expect(() => empty.estimate(sample(milliseconds: 500)), throwsStateError);
  });

  test('raw acceleration cadence cannot create speed or distance', () {
    for (var i = 1; i <= 100; i++) {
      estimator.estimate(
        sample(milliseconds: i * 20, x: i.isEven ? 12 : -12, y: 8, z: 4),
      );
    }
    estimator.estimate(sample(milliseconds: 2200, tick: true));
    expect(estimator.latestEstimate?.coordinate, origin);
    expect(estimator.speedKilometersPerHour, 0);
    expect(estimator.cumulativeDistanceMeters, 0);
  });

  test('valid zero-degree heading advances north', () {
    final result = estimator.estimate(
      sample(milliseconds: 500, heading: 0, step: true),
    );
    expect(result.heading, 0);
    expect(result.coordinate.latitude, greaterThan(origin.latitude));
    expect(result.coordinate.longitude, closeTo(origin.longitude, 1e-9));
    expect(_distanceMeters(origin, result.coordinate), closeTo(0.70, 0.001));
  });

  test('missing heading rejects a step rather than fabricating north', () {
    final result = estimator.estimate(
      sample(milliseconds: 500, heading: null, step: true),
    );
    expect(result.coordinate, origin);
    expect(result.heading, isNull);
    expect(estimator.acceptedSteps, 0);
    expect(estimator.rejectedSteps, 1);
  });

  test('low-quality heading remains visible but cannot create travel', () {
    final result = estimator.estimate(
      ImuSensorSample(
        linearAccelerationX: 0,
        linearAccelerationY: 0,
        linearAccelerationZ: 0,
        heading: 90,
        headingAccuracyDegrees: 45,
        timestamp: start.add(const Duration(milliseconds: 500)),
        stepDetected: true,
      ),
    );
    expect(result.coordinate, origin);
    expect(result.heading, 90);
    expect(estimator.acceptedSteps, 0);
    expect(estimator.rejectedSteps, 1);
  });

  test('ordinary walking steps produce event-rate-independent distance', () {
    for (var step = 1; step <= 20; step++) {
      estimator.estimate(
        sample(milliseconds: step * 500, heading: 90, step: true),
      );
      for (var event = 1; event <= 8; event++) {
        estimator.estimate(
          sample(
            milliseconds: step * 500 + event * 20,
            heading: 90,
            x: 3,
            y: -2,
            z: 1,
          ),
        );
      }
    }
    expect(estimator.acceptedSteps, 20);
    expect(estimator.cumulativeDistanceMeters, closeTo(14, 1e-9));
    expect(
      _distanceMeters(origin, estimator.latestEstimate!.coordinate),
      closeTo(14, 0.01),
    );
    expect(estimator.speedKilometersPerHour, closeTo(5.04, 0.001));
  });

  test('walking-like acceleration peaks require cadence before movement', () {
    for (var step = 1; step <= 20; step++) {
      estimator.estimate(
        sample(milliseconds: step * 500 - 100, heading: 90, x: 0.1),
      );
      estimator.estimate(sample(milliseconds: step * 500, heading: 90, x: 1.2));
    }
    expect(estimator.acceptedSteps, 20);
    expect(estimator.cumulativeDistanceMeters, closeTo(14, 1e-9));
    expect(
      _distanceMeters(origin, estimator.latestEstimate!.coordinate),
      closeTo(14, 0.01),
    );
    expect(estimator.speedKilometersPerHour, closeTo(5.04, 0.001));
  });

  test('one handling impulse cannot prove geographic travel', () {
    estimator.estimate(sample(milliseconds: 400, x: 0.1));
    estimator.estimate(sample(milliseconds: 500, x: 1.5));
    estimator.estimate(sample(milliseconds: 600, x: 0.1));
    estimator.estimate(sample(milliseconds: 2500, tick: true));
    expect(estimator.latestEstimate!.coordinate, origin);
    expect(estimator.acceptedSteps, 0);
    expect(estimator.cumulativeDistanceMeters, 0);
  });

  test('rotation-rate suppression rejects repeated device-only peaks', () {
    for (var peak = 1; peak <= 4; peak++) {
      estimator.estimate(sample(milliseconds: peak * 500 - 100, x: 0.1));
      estimator.estimate(
        ImuSensorSample(
          linearAccelerationX: 1.5,
          linearAccelerationY: 0,
          linearAccelerationZ: 0,
          heading: peak * 45,
          angularVelocityRadiansPerSecond: 1.2,
          timestamp: start.add(Duration(milliseconds: peak * 500)),
        ),
      );
    }
    expect(estimator.latestEstimate!.coordinate, origin);
    expect(estimator.acceptedSteps, 0);
    expect(estimator.rejectedSteps, 4);
  });

  test('duplicate step events are rejected', () {
    estimator.estimate(sample(milliseconds: 500, step: true));
    final first = estimator.latestEstimate!.coordinate;
    estimator.estimate(sample(milliseconds: 600, step: true));
    expect(estimator.latestEstimate!.coordinate, first);
    expect(estimator.acceptedSteps, 1);
    expect(estimator.rejectedSteps, 1);
  });

  test('close software peak cannot seed a later double count', () {
    for (final milliseconds in [500, 1000]) {
      estimator.estimate(sample(milliseconds: milliseconds - 100, x: 0.1));
      estimator.estimate(sample(milliseconds: milliseconds, x: 1.2));
    }
    expect(estimator.acceptedSteps, 2);

    estimator.estimate(sample(milliseconds: 1100, x: 0.1));
    estimator.estimate(sample(milliseconds: 1150, x: 1.2));
    estimator.estimate(sample(milliseconds: 1300, x: 0.1));
    estimator.estimate(sample(milliseconds: 1500, x: 1.2));

    expect(estimator.acceptedSteps, 3);
    expect(estimator.cumulativeDistanceMeters, closeTo(2.1, 1e-9));
  });

  test('turning changes only subsequent step direction', () {
    for (var step = 1; step <= 5; step++) {
      estimator.estimate(
        sample(milliseconds: step * 500, heading: 0, step: true),
      );
    }
    final corner = estimator.latestEstimate!.coordinate;
    for (var step = 6; step <= 10; step++) {
      estimator.estimate(
        sample(milliseconds: step * 500, heading: 90, step: true),
      );
    }
    final end = estimator.latestEstimate!.coordinate;
    expect(corner.latitude, greaterThan(origin.latitude));
    expect(corner.longitude, closeTo(origin.longitude, 1e-9));
    expect(end.latitude, closeTo(corner.latitude, 1e-9));
    expect(end.longitude, greaterThan(corner.longitude));
    expect(estimator.cumulativeDistanceMeters, closeTo(7, 1e-9));
  });

  test('device rotation without steps changes heading but not position', () {
    for (final entry in <(int, double)>[
      (100, 0),
      (200, 90),
      (300, 180),
      (400, 270),
    ]) {
      estimator.estimate(
        sample(milliseconds: entry.$1, heading: entry.$2, x: 2),
      );
    }
    final result = estimator.estimate(
      sample(milliseconds: 500, heading: 270, tick: true),
    );
    expect(result.coordinate, origin);
    expect(result.heading, 270);
    expect(estimator.cumulativeDistanceMeters, 0);
  });

  test('stop clears cadence speed and resume needs a fresh interval', () {
    estimator.estimate(sample(milliseconds: 500, step: true));
    estimator.estimate(sample(milliseconds: 1000, step: true));
    expect(estimator.speedKilometersPerHour, closeTo(5.04, 0.001));
    estimator.estimate(sample(milliseconds: 3000, tick: true));
    expect(estimator.speedKilometersPerHour, 0);
    estimator.estimate(sample(milliseconds: 4000, step: true));
    expect(estimator.speedKilometersPerHour, 0);
    estimator.estimate(sample(milliseconds: 4500, step: true));
    expect(estimator.speedKilometersPerHour, closeTo(5.04, 0.001));
    expect(estimator.cumulativeDistanceMeters, closeTo(2.8, 1e-9));
  });

  test('software cadence can re-establish after stopping', () {
    for (final milliseconds in [500, 1000]) {
      estimator.estimate(sample(milliseconds: milliseconds - 100, x: 0.1));
      estimator.estimate(sample(milliseconds: milliseconds, x: 1.2));
    }
    expect(estimator.acceptedSteps, 2);

    estimator.estimate(sample(milliseconds: 3000, tick: true));
    expect(estimator.speedKilometersPerHour, 0);
    for (final milliseconds in [4000, 4500]) {
      estimator.estimate(sample(milliseconds: milliseconds - 100, x: 0.1));
      estimator.estimate(
        sample(milliseconds: milliseconds, heading: 180, x: 1.2),
      );
    }

    expect(estimator.acceptedSteps, 4);
    expect(estimator.cumulativeDistanceMeters, closeTo(2.8, 1e-9));
    expect(estimator.speedKilometersPerHour, closeTo(5.04, 0.001));
    expect(
      estimator.latestEstimate!.coordinate.latitude,
      lessThan(origin.latitude),
    );
  });

  test('step length calibration is bounded and applied exactly', () {
    expect(
      StepBasedImuPositionEstimator().stepLengthMeters,
      StepBasedImuPositionEstimator.defaultStepLengthMeters,
    );
    final calibrated = StepBasedImuPositionEstimator(stepLengthMeters: 0.82)
      ..reset(origin: origin, timestamp: start);
    calibrated.estimate(sample(milliseconds: 500, step: true));
    expect(calibrated.cumulativeDistanceMeters, 0.82);
    expect(
      _distanceMeters(origin, calibrated.latestEstimate!.coordinate),
      closeTo(0.82, 0.001),
    );
    expect(
      () => StepBasedImuPositionEstimator(stepLengthMeters: 0.2),
      throwsArgumentError,
    );
    expect(
      () => StepBasedImuPositionEstimator(stepLengthMeters: double.nan),
      throwsArgumentError,
    );
  });

  test('cardinal coordinate propagation uses north-clockwise bearings', () {
    final north = StepBasedImuPositionEstimator.propagate(
      origin: origin,
      distanceMeters: 10,
      headingDegrees: 0,
    );
    final east = StepBasedImuPositionEstimator.propagate(
      origin: origin,
      distanceMeters: 10,
      headingDegrees: 90,
    );
    final south = StepBasedImuPositionEstimator.propagate(
      origin: origin,
      distanceMeters: 10,
      headingDegrees: 180,
    );
    final west = StepBasedImuPositionEstimator.propagate(
      origin: origin,
      distanceMeters: 10,
      headingDegrees: 270,
    );
    expect(north.latitude, greaterThan(origin.latitude));
    expect(east.longitude, greaterThan(origin.longitude));
    expect(south.latitude, lessThan(origin.latitude));
    expect(west.longitude, lessThan(origin.longitude));
    for (final coordinate in [north, east, south, west]) {
      expect(_distanceMeters(origin, coordinate), closeTo(10, 0.001));
    }
  });
}

double _distanceMeters(GeoCoordinate a, GeoCoordinate b) {
  const radius = 6371000.0;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLon = (b.longitude - a.longitude) * math.pi / 180;
  final value =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return radius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value));
}
