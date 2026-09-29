import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/features/navigation/domain/navigation_session_state.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

void main() {
  late ProviderContainer container;
  late NavigationSessionController controller;

  NavigationSessionState readState() =>
      container.read(navigationSessionProvider);

  setUp(() {
    container = ProviderContainer();
    controller = container.read(navigationSessionProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('1. initial mode is GPS', () {
    expect(readState().navigationMode, NavigationMode.gps);
    expect(readState().displayedPosition, isNull);
  });

  test('2. GPS position is displayed in GPS mode', () {
    final gps = position(PositionSource.gps, 12.9716, 77.5946, heading: 40);

    controller.updateGpsPosition(gps);

    expect(readState().latestGpsPosition, gps);
    expect(readState().displayedPosition, gps);
    expect(readState().currentHeading, 40);
  });

  test('older and equal GPS samples cannot overwrite newer accepted state', () {
    final newer = position(PositionSource.gps, 12.98, 77.60);
    final older = PositionSample(
      coordinate: const GeoCoordinate(latitude: 13, longitude: 78),
      timestamp: newer.timestamp.subtract(const Duration(seconds: 1)),
      source: PositionSource.gps,
    );
    expect(controller.updateGpsPosition(newer), isTrue);
    expect(controller.updateGpsPosition(older), isFalse);
    expect(controller.updateGpsPosition(newer), isFalse);
    expect(readState().latestGpsPosition, newer);
    expect(readState().displayedPosition, newer);
  });

  test('newest accepted GPS is restored after IMU mode', () {
    final first = position(PositionSource.gps, 12.97, 77.59);
    final newer = PositionSample(
      coordinate: const GeoCoordinate(latitude: 12.98, longitude: 77.60),
      timestamp: first.timestamp.add(const Duration(seconds: 1)),
      source: PositionSource.gps,
    );
    final imu = position(PositionSource.imu, 12.975, 77.595);
    controller.updateGpsPosition(first);
    controller.updateImuPosition(imu);
    controller.setNavigationMode(NavigationMode.imu);
    controller.updateGpsPosition(newer);
    expect(readState().displayedPosition, imu);
    controller.setNavigationMode(NavigationMode.gps);
    expect(readState().displayedPosition, newer);
  });

  test('3. IMU position does not override display in GPS mode', () {
    final gps = position(PositionSource.gps, 12.9716, 77.5946);
    final imu = position(PositionSource.imu, 12.9720, 77.5950);
    controller.updateGpsPosition(gps);

    controller.updateImuPosition(imu);

    expect(readState().latestImuPosition, imu);
    expect(readState().displayedPosition, gps);
  });

  test('4. switching to IMU makes latest IMU position authoritative', () {
    final gps = position(PositionSource.gps, 12.9716, 77.5946, heading: 10);
    final imu = position(PositionSource.imu, 12.9720, 77.5950, heading: 95);
    controller.updateGpsPosition(gps);
    controller.updateImuPosition(imu);

    controller.setNavigationMode(NavigationMode.imu);

    expect(readState().displayedPosition, imu);
    expect(readState().currentHeading, 95);
  });

  test('5. switching back to GPS restores latest GPS authority', () {
    final gps = position(PositionSource.gps, 12.9716, 77.5946);
    final imu = position(PositionSource.imu, 12.9720, 77.5950);
    controller.updateGpsPosition(gps);
    controller.updateImuPosition(imu);
    controller.setNavigationMode(NavigationMode.imu);

    controller.setNavigationMode(NavigationMode.gps);

    expect(readState().displayedPosition, gps);
  });

  test('6. destination survives GPS to IMU to GPS', () {
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 19.0760, longitude: 72.8777),
      displayLabel: 'Mumbai',
    );
    controller.setDestination(destination);

    switchModes(controller);

    expect(readState().destination, destination);
  });

  test('7. route alternatives survive GPS to IMU to GPS', () {
    final alternatives = routeAlternatives();
    controller.setRouteAlternatives(alternatives);

    switchModes(controller);

    expect(readState().routeAlternatives, same(alternatives));
    expect(readState().routeAlternatives[RouteMode.normal], isNotNull);
  });

  test('8. selected route survives GPS to IMU to GPS', () {
    final alternatives = routeAlternatives();
    controller.setRouteAlternatives(alternatives);
    controller.selectRoute(RouteMode.safe);
    final selected = readState().selectedRoute;

    switchModes(controller);

    expect(readState().selectedRoute, same(selected));
    expect(readState().selectedRouteMode, RouteMode.safe);
  });

  test('9. clearing destination invalidates route but preserves mode', () {
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 15.2993, longitude: 74.1240),
    );
    final alternatives = routeAlternatives();
    controller.setDestination(destination);
    controller.setRouteAlternatives(alternatives);
    controller.selectRoute(RouteMode.normal);
    controller.setNavigationMode(NavigationMode.imu);

    controller.clearDestination();

    expect(readState().destination, isNull);
    expect(readState().navigationMode, NavigationMode.imu);
    expect(readState().routeAlternatives.isEmpty, isTrue);
    expect(readState().selectedRoute, isNull);
  });

  test('10. loading and error updates preserve navigation state', () {
    final gps = position(PositionSource.gps, 12.9716, 77.5946);
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 19.0760, longitude: 72.8777),
    );
    final alternatives = routeAlternatives();
    controller.updateGpsPosition(gps);
    controller.setDestination(destination);
    controller.setRouteAlternatives(alternatives);
    controller.selectRoute(RouteMode.safe);

    controller.setLoading(true);
    controller.setError('Route unavailable');

    expect(readState().isLoading, isTrue);
    expect(readState().errorMessage, 'Route unavailable');
    expect(readState().displayedPosition, gps);
    expect(readState().destination, destination);
    expect(readState().routeAlternatives, same(alternatives));
    expect(readState().selectedRouteMode, RouteMode.safe);

    controller.setLoading(false);
    controller.clearError();
    expect(readState().isLoading, isFalse);
    expect(readState().errorMessage, isNull);
  });

  test('11. updating GPS does not change route state', () {
    final alternatives = routeAlternatives();
    controller.setRouteAlternatives(alternatives);
    controller.selectRoute(RouteMode.drifted);
    final selected = readState().selectedRoute;

    controller.updateGpsPosition(
      position(PositionSource.gps, 13.0000, 77.6000),
    );

    expect(readState().routeAlternatives, same(alternatives));
    expect(readState().selectedRoute, same(selected));
    expect(readState().selectedRouteMode, RouteMode.drifted);
  });

  test('12. updating IMU does not change destination or route state', () {
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 19.0760, longitude: 72.8777),
    );
    final alternatives = routeAlternatives();
    controller.setDestination(destination);
    controller.setRouteAlternatives(alternatives);
    controller.selectRoute(RouteMode.imu);
    final selected = readState().selectedRoute;

    controller.updateImuPosition(
      position(PositionSource.imu, 12.9720, 77.5950),
    );

    expect(readState().destination, destination);
    expect(readState().routeAlternatives, same(alternatives));
    expect(readState().selectedRoute, same(selected));
  });

  test('position update methods reject a mismatched source', () {
    final imu = position(PositionSource.imu, 12.9720, 77.5950);

    expect(() => controller.updateGpsPosition(imu), throwsArgumentError);
  });

  test('route updates never change the location source', () {
    controller.setNavigationMode(NavigationMode.imu);

    controller.setRouteAlternatives(routeAlternatives());
    controller.selectRoute(RouteMode.normal);
    controller.clearRoute();

    expect(readState().navigationMode, NavigationMode.imu);
  });

  test('switching GPS to IMU and back never clears the latest GPS fix', () {
    final gps = position(PositionSource.gps, 12.9716, 77.5946);
    controller.updateGpsPosition(gps);

    controller.setNavigationMode(NavigationMode.imu);
    expect(readState().displayedPosition, isNull);
    expect(readState().latestGpsPosition, same(gps));

    controller.setNavigationMode(NavigationMode.gps);
    expect(readState().displayedPosition, same(gps));
    expect(readState().latestGpsPosition, same(gps));
  });

  test('Prompt 10 route start follows the active navigation position', () {
    final gps = position(PositionSource.gps, 12.9716, 77.5946);
    final imu = position(PositionSource.imu, 12.9722, 77.5953);
    controller.updateGpsPosition(gps);
    controller.updateImuPosition(imu);

    expect(readState().currentRouteStart, gps.coordinate);
    controller.setNavigationMode(NavigationMode.imu);
    expect(readState().currentRouteStart, imu.coordinate);
    controller.setNavigationMode(NavigationMode.gps);
    expect(readState().currentRouteStart, gps.coordinate);
  });

  test('route endpoint readiness is safe when current position is absent', () {
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 19.076, longitude: 72.8777),
    );
    expect(readState().currentRouteStart, isNull);
    expect(readState().hasRouteEndpoints, isFalse);

    controller.setDestination(destination);
    expect(readState().destination, destination);
    expect(readState().currentRouteStart, isNull);
    expect(readState().hasRouteEndpoints, isFalse);

    controller.updateGpsPosition(
      position(PositionSource.gps, 12.9716, 77.5946),
    );
    expect(readState().hasRouteEndpoints, isTrue);
  });

  test('GPS and IMU updates preserve a confirmed destination', () {
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 18.5204, longitude: 73.8567),
    );
    controller.setDestination(destination);
    controller.updateGpsPosition(
      position(PositionSource.gps, 12.9716, 77.5946),
    );
    controller.updateImuPosition(position(PositionSource.imu, 12.972, 77.595));
    controller.setNavigationMode(NavigationMode.imu);
    controller.updateImuPosition(
      PositionSample(
        coordinate: const GeoCoordinate(latitude: 12.973, longitude: 77.596),
        timestamp: DateTime.utc(2026, 9, 21, 12, 0, 1),
        source: PositionSource.imu,
      ),
    );

    expect(readState().destination, destination);
  });
}

PositionSample position(
  PositionSource source,
  double latitude,
  double longitude, {
  double? heading,
}) {
  return PositionSample(
    coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
    heading: heading,
    timestamp: DateTime.utc(2026, 9, 21, 12),
    source: source,
  );
}

RouteAlternatives routeAlternatives() {
  const metrics = RouteMetrics(
    distanceMeters: 1200,
    estimatedTimeSeconds: 80,
    totalRiskScore: 22,
    maximumRiskZone: RiskZone.low,
    averageRisk: 0.22,
    riskSegments: RiskSegmentCounts(low: 2, medium: 0, high: 0),
  );
  const path = [
    GeoCoordinate(latitude: 12.9716, longitude: 77.5946),
    GeoCoordinate(latitude: 12.9800, longitude: 77.6000),
  ];

  return RouteAlternatives(
    byMode: {
      for (final mode in RouteMode.values)
        mode: RouteAlternative(
          mode: mode,
          path: path,
          metrics: metrics,
          optimization: mode.name,
        ),
    },
    metadata: const RouteMetadata(
      start: GeoCoordinate(latitude: 12.9716, longitude: 77.5946),
      end: GeoCoordinate(latitude: 12.9800, longitude: 77.6000),
      source: 'OSRM Public API',
      kpIndex: 2,
    ),
  );
}

void switchModes(NavigationSessionController controller) {
  controller.setNavigationMode(NavigationMode.imu);
  controller.setNavigationMode(NavigationMode.gps);
}
