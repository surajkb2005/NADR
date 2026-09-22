import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nadr_mobile/features/location/infrastructure/gps_fix_quality_gate.dart';

void main() {
  final start = DateTime.utc(2026, 9, 22, 10);
  // Synthetic coordinates preserve the observed ~120 m A-B displacement.
  const anchorLatitude = 12.9716;
  const anchorLongitude = 77.5946;
  const outlierLatitude = 12.972458;
  const outlierLongitude = 77.5939439;

  Position fix(
    int seconds, {
    double latitude = anchorLatitude,
    double longitude = anchorLongitude,
    bool hasAccuracy = false,
    double accuracy = 0,
    double speed = 0,
  }) => Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: start.add(Duration(seconds: seconds)),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
    hasAccuracy: hasAccuracy,
  );

  late GpsOutlierQuarantine quarantine;
  late Position accepted;

  GpsOutlierDecision feed(Position next) {
    final baseline = const GpsFixQualityGate().evaluate(
      next,
      receivedAt: next.timestamp,
      previousAccepted: accepted,
    );
    expect(baseline.accepted, isTrue);
    final decision = quarantine.consider(next, previousAccepted: accepted);
    if (decision.accepted) accepted = next;
    return decision;
  }

  setUp(() {
    quarantine = GpsOutlierQuarantine();
    accepted = fix(0, hasAccuracy: true, accuracy: 8);
  });

  test('Motorola A-B-A outlier never replaces A', () {
    final b = fix(10, latitude: outlierLatitude, longitude: outlierLongitude);
    expect(feed(b).action, GpsOutlierAction.quarantined);
    expect(accepted.latitude, anchorLatitude);
    final returned = feed(fix(20, latitude: 12.971601, longitude: 77.594602));
    expect(returned.action, GpsOutlierAction.accepted);
    expect(returned.rejectedCandidate, b);
    expect(accepted.latitude, closeTo(anchorLatitude, 0.00001));
    expect(quarantine.pendingCandidate, isNull);
  });

  test(
    'three consistent unknown-accuracy fixes confirm genuine relocation',
    () {
      expect(
        feed(fix(10, latitude: outlierLatitude, longitude: outlierLongitude))
            .action,
        GpsOutlierAction.quarantined,
      );
      expect(
        feed(fix(20, latitude: outlierLatitude, longitude: outlierLongitude))
            .action,
        GpsOutlierAction.quarantined,
      );
      final third = feed(
        fix(30, latitude: outlierLatitude, longitude: outlierLongitude),
      );
      expect(third.action, GpsOutlierAction.confirmed);
      expect(third.supportCount, 3);
      expect(accepted.latitude, outlierLatitude);
    },
  );

  test('small unknown-accuracy movement and measured fixes are immediate', () {
    expect(feed(fix(10, latitude: 12.97166)).action, GpsOutlierAction.accepted);
    expect(
      feed(
        fix(
          20,
          latitude: outlierLatitude,
          longitude: outlierLongitude,
          hasAccuracy: true,
          accuracy: 15,
        ),
      ).action,
      GpsOutlierAction.accepted,
    );
    expect(accepted.latitude, outlierLatitude);
  });

  test('ordinary jitter and gradual 15 m convergence are not frozen', () {
    for (final next in [
      fix(10, latitude: 12.97162, accuracy: 20, hasAccuracy: true),
      fix(20, latitude: 12.97165, accuracy: 15, hasAccuracy: true),
      fix(30, latitude: 12.97170, accuracy: 10, hasAccuracy: true),
      fix(40, latitude: 12.97174, accuracy: 5, hasAccuracy: true),
    ]) {
      expect(feed(next).action, GpsOutlierAction.accepted);
    }
    expect(accepted.latitude, 12.97174);
    expect(quarantine.pendingCandidate, isNull);
  });

  test('inconsistent outliers replace candidate instead of confirming it', () {
    expect(
      feed(fix(10, latitude: outlierLatitude, longitude: outlierLongitude))
          .action,
      GpsOutlierAction.quarantined,
    );
    final other = fix(20, latitude: 12.9716, longitude: 77.59339);
    final decision = feed(other);
    expect(decision.action, GpsOutlierAction.quarantined);
    expect(decision.rejectedCandidate?.latitude, outlierLatitude);
    expect(quarantine.pendingCandidate, other);
    expect(accepted.latitude, anchorLatitude);
  });

  test('recurring A-B-A-B-A outliers remain quarantined', () {
    for (var index = 0; index < 3; index++) {
      final offset = index * 20;
      expect(
        feed(
          fix(
            offset + 10,
            latitude: outlierLatitude,
            longitude: outlierLongitude,
          ),
        ).action,
        GpsOutlierAction.quarantined,
      );
      expect(feed(fix(offset + 20)).action, GpsOutlierAction.accepted);
    }
    expect(accepted.latitude, anchorLatitude);
  });

  test('out-of-order candidate evidence is rejected', () {
    feed(fix(10, latitude: outlierLatitude, longitude: outlierLongitude));
    final old = quarantine.consider(
      fix(9, latitude: outlierLatitude, longitude: outlierLongitude),
      previousAccepted: accepted,
    );
    expect(old.action, GpsOutlierAction.rejected);
    expect(old.reason, 'out_of_order_candidate');
    expect(accepted.latitude, anchorLatitude);
  });

  test(
    'missing or nonfinite speed does not imply stillness or high quality',
    () {
      final candidate = fix(
        10,
        latitude: outlierLatitude,
        longitude: outlierLongitude,
        speed: double.nan,
      );
      expect(feed(candidate).action, GpsOutlierAction.quarantined);
      expect(accepted.latitude, anchorLatitude);
    },
  );

  test('pending candidate is cleared on session restart', () {
    feed(fix(10, latitude: outlierLatitude, longitude: outlierLongitude));
    quarantine.reset();
    expect(quarantine.pendingCandidate, isNull);
    expect(
      feed(fix(20, latitude: outlierLatitude, longitude: outlierLongitude))
          .supportCount,
      1,
    );
  });

  test(
    'expired candidate starts fresh rather than confirming stale evidence',
    () {
      feed(fix(10, latitude: outlierLatitude, longitude: outlierLongitude));
      final afterExpiry = feed(
        fix(110, latitude: outlierLatitude, longitude: outlierLongitude),
      );
      expect(afterExpiry.action, GpsOutlierAction.quarantined);
      expect(afterExpiry.supportCount, 1);
    },
  );
}
