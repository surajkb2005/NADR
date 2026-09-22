import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_sample.dart';
import 'package:nadr_mobile/features/navigation/infrastructure/website_imu_position_estimator.dart';

void main() {
  const origin = GeoCoordinate(latitude: 12.9716, longitude: 77.5946);
  final time = DateTime.utc(2026, 9, 22, 10);
  late WebsiteImuPositionEstimator estimator;

  setUp(() {
    estimator = WebsiteImuPositionEstimator();
  });

  ImuSensorSample acceleration(
    double x,
    double y,
    double z, {
    double? heading,
  }) => ImuSensorSample(
    linearAccelerationX: x,
    linearAccelerationY: y,
    linearAccelerationZ: z,
    heading: heading,
    timestamp: time,
  );

  ImuSensorSample tick(int milliseconds, {double? heading}) => ImuSensorSample(
    linearAccelerationX: 0,
    linearAccelerationY: 0,
    linearAccelerationZ: 0,
    heading: heading,
    timestamp: time.add(Duration(milliseconds: milliseconds)),
    isDecayTick: true,
  );

  test('requires real origin and resets to it without movement', () {
    expect(() => estimator.estimate(tick(200)), throwsStateError);
    estimator.reset(origin: origin, timestamp: time);
    expect(estimator.latestEstimate?.coordinate, origin);
    expect(estimator.speedKilometersPerHour, 0);
  });

  test(
    'magnitude, strict threshold, increment and 20 km/h cap match React',
    () {
      estimator.reset(origin: origin, timestamp: time);
      estimator.estimate(acceleration(1, 0, 0));
      expect(estimator.speedKilometersPerHour, 0);
      estimator.estimate(acceleration(3, 4, 0));
      expect(estimator.speedKilometersPerHour, 3);
      for (var i = 0; i < 20; i++) {
        estimator.estimate(acceleration(3, 4, 0));
      }
      expect(estimator.speedKilometersPerHour, 20);
    },
  );

  test('200 ms decay applies multiply, subtract and low-speed snap', () {
    estimator.reset(origin: origin, timestamp: time);
    estimator.estimate(acceleration(6, 0, 0, heading: 90));
    estimator.estimate(tick(200));
    expect(estimator.speedKilometersPerHour, closeTo(0.90 * 3.6 - 1, 1e-10));
    estimator.estimate(tick(400));
    expect(estimator.speedKilometersPerHour, 0);
  });

  test('first tick uses 0.1 s and later ticks use elapsed time', () {
    estimator.reset(origin: origin, timestamp: time);
    estimator.estimate(acceleration(10, 0, 0, heading: 90));
    final first = estimator.estimate(tick(200));
    expect(first.coordinate.longitude, greaterThan(origin.longitude));
    final firstDistance = first.coordinate.longitude - origin.longitude;
    final second = estimator.estimate(tick(400));
    expect(
      second.coordinate.longitude - first.coordinate.longitude,
      greaterThan(firstDistance),
    );
  });

  test(
    'heading is north-clockwise and geographic propagation is spherical',
    () {
      estimator.reset(origin: origin, timestamp: time);
      estimator.estimate(acceleration(20, 0, 0, heading: 0));
      final north = estimator.estimate(tick(200));
      expect(north.coordinate.latitude, greaterThan(origin.latitude));
      expect(north.coordinate.longitude, closeTo(origin.longitude, 1e-8));
      expect(north.heading, 0);
    },
  );

  test('invalid acceleration and missing heading do not invent movement', () {
    estimator.reset(origin: origin, timestamp: time);
    estimator.estimate(acceleration(double.nan, 4, 0, heading: 361));
    final result = estimator.estimate(tick(200));
    expect(estimator.speedKilometersPerHour, 0);
    expect(result.coordinate, origin);
    expect(result.heading, isNull);
  });

  test('large elapsed gaps and old samples do not cause jumps', () {
    estimator.reset(origin: origin, timestamp: time);
    estimator.estimate(acceleration(10, 0, 0, heading: 90));
    final first = estimator.estimate(tick(200));
    final gap = estimator.estimate(tick(5000));
    expect(gap.coordinate, first.coordinate);
    final old = estimator.estimate(tick(100));
    expect(old.coordinate, first.coordinate);
  });

  test('stationary input stays at origin and speed returns to zero', () {
    estimator.reset(origin: origin, timestamp: time);
    estimator.estimate(acceleration(0, 0, 0, heading: 90));
    for (var i = 1; i <= 10; i++) {
      estimator.estimate(tick(i * 200));
    }
    expect(estimator.latestEstimate?.coordinate, origin);
    expect(estimator.speedKilometersPerHour, 0);
  });

  test('a mild single-window impulse can decay below movement cutoff', () {
    estimator.reset(origin: origin, timestamp: time);
    estimator.estimate(acceleration(2, 0, 0, heading: 90));
    expect(estimator.speedKilometersPerHour, closeTo(1.2, 1e-10));
    final next = estimator.estimate(tick(200));
    expect(estimator.speedKilometersPerHour, 0);
    expect(next.coordinate, origin);
  });

  test('lost heading clears direction and speed without moving position', () {
    estimator.reset(origin: origin, timestamp: time);
    estimator.estimate(acceleration(20, 0, 0, heading: 90));
    final moved = estimator.estimate(tick(200));
    expect(moved.coordinate.longitude, greaterThan(origin.longitude));
    final neutral = estimator.clearHeading(
      timestamp: time.add(const Duration(milliseconds: 250)),
    );
    expect(neutral.coordinate, moved.coordinate);
    expect(neutral.heading, isNull);
    expect(estimator.speedKilometersPerHour, 0);
    final noDirection = estimator.estimate(tick(400));
    expect(noDirection.coordinate, moved.coordinate);
    expect(noDirection.heading, isNull);
  });
}
