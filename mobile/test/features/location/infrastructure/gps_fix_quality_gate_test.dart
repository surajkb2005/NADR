import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nadr_mobile/features/location/infrastructure/gps_fix_quality_gate.dart';

void main() {
  const gate = GpsFixQualityGate();
  final now = DateTime.utc(2026, 9, 22, 12);

  Position fix({
    double lat = 12.9716,
    double lon = 77.5946,
    DateTime? at,
    double accuracy = 4,
    double speed = 0,
  }) => Position(
    latitude: lat,
    longitude: lon,
    timestamp: at ?? now,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
    hasAccuracy: true,
  );

  String? rejection(Position candidate, {Position? prior}) =>
      gate.evaluate(candidate, receivedAt: now, previousAccepted: prior).reason;

  test('invalid and non-finite coordinates are rejected', () {
    expect(rejection(fix(lat: 91)), 'invalid_coordinate');
    expect(rejection(fix(lon: -181)), 'invalid_coordinate');
    expect(rejection(fix(lat: double.nan)), 'invalid_coordinate');
    expect(rejection(fix(lon: double.infinity)), 'invalid_coordinate');
  });

  test('stale, future and imprecise fixes are rejected', () {
    expect(
      rejection(fix(at: now.subtract(const Duration(minutes: 3)))),
      'stale_timestamp',
    );
    expect(
      rejection(fix(at: now.add(const Duration(seconds: 31)))),
      'future_timestamp',
    );
    expect(rejection(fix(accuracy: 151)), 'poor_accuracy');
  });

  test('older and equal fixes cannot replace an accepted fix', () {
    final accepted = fix(at: now.subtract(const Duration(seconds: 2)));
    expect(
      rejection(fix(at: accepted.timestamp), prior: accepted),
      'out_of_order_timestamp',
    );
    expect(
      rejection(
        fix(at: accepted.timestamp.subtract(const Duration(seconds: 1))),
        prior: accepted,
      ),
      'out_of_order_timestamp',
    );
  });

  test(
    'physically impossible jumps are rejected but ordinary movement passes',
    () {
      final accepted = fix(at: now.subtract(const Duration(seconds: 2)));
      expect(
        rejection(fix(lat: 13.9716), prior: accepted),
        'implausible_displacement',
      );
      expect(rejection(fix(lat: 12.972), prior: accepted), isNull);
      expect(rejection(fix(speed: 101)), 'implausible_reported_speed');
    },
  );
}
