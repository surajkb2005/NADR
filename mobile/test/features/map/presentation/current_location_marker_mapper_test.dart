import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/map/domain/current_location_marker.dart';
import 'package:nadr_mobile/features/map/presentation/current_location_marker_mapper.dart';
import 'package:nadr_mobile/features/navigation/domain/navigation_session_state.dart';

void main() {
  test('no marker data exists before displayedPosition exists', () {
    expect(
      currentLocationMarkerFromSession(NavigationSessionState.initial()),
      isNull,
    );
  });

  test('real GPS displayed position produces blue-mode marker data', () {
    final gps = sample(PositionSource.gps, 12.97, 77.59, heading: 42);
    final marker = currentLocationMarkerFromSession(
      NavigationSessionState(latestGpsPosition: gps),
    );

    expect(marker?.coordinate, gps.coordinate);
    expect(marker?.visualMode, CurrentLocationVisualMode.gps);
    expect(marker?.heading, 42);
  });

  test('marker consumes displayedPosition rather than latest GPS directly', () {
    final gps = sample(PositionSource.gps, 12.97, 77.59);
    final imu = sample(PositionSource.imu, 13.01, 77.61);
    final marker = currentLocationMarkerFromSession(
      NavigationSessionState(
        navigationMode: NavigationMode.imu,
        latestGpsPosition: gps,
        latestImuPosition: imu,
      ),
    );

    expect(marker?.coordinate, imu.coordinate);
    expect(marker?.visualMode, CurrentLocationVisualMode.imu);
  });

  test('IMU mode without an IMU displayed position creates no marker', () {
    final gps = sample(PositionSource.gps, 12.97, 77.59);
    final marker = currentLocationMarkerFromSession(
      NavigationSessionState(
        navigationMode: NavigationMode.imu,
        latestGpsPosition: gps,
      ),
    );

    expect(marker, isNull);
  });

  test('heading is applied only when finite and in the valid range', () {
    for (final invalid in <double>[double.nan, double.infinity, -1, 361]) {
      final marker = currentLocationMarkerFromSession(
        NavigationSessionState(
          latestGpsPosition: sample(
            PositionSource.gps,
            12.97,
            77.59,
            heading: invalid,
          ),
        ),
      );
      expect(marker?.heading, isNull);
    }

    final north = currentLocationMarkerFromSession(
      NavigationSessionState(
        latestGpsPosition: sample(
          PositionSource.gps,
          12.97,
          77.59,
          heading: 360,
        ),
      ),
    );
    expect(north?.heading, 0);
  });
}

PositionSample sample(
  PositionSource source,
  double latitude,
  double longitude, {
  double? heading,
}) {
  return PositionSample(
    coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
    heading: heading,
    timestamp: DateTime.utc(2026, 9, 22),
    source: source,
  );
}
