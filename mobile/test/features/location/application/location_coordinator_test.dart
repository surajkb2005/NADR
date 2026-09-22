import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/location/application/location_coordinator.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

import '../../../support/fake_device_location_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDeviceLocationSource source;
  late ProviderContainer container;

  setUp(() async {
    source = FakeDeviceLocationSource();
    container = ProviderContainer(
      overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
    );
    container.read(locationCoordinatorProvider);
    await pumpEventQueue();
  });

  tearDown(() {
    container.dispose();
    source.dispose();
  });

  test('first GPS sample updates latest and displayed GPS position', () {
    final gps = sample(PositionSource.gps, 12.9716, 77.5946);

    source.emitPosition(gps);

    final session = container.read(navigationSessionProvider);
    expect(session.latestGpsPosition, gps);
    expect(session.displayedPosition, gps);
    expect(session.hasGpsFix, isTrue);
  });

  test('GPS continues updating in IMU mode without overriding display', () {
    final navigation = container.read(navigationSessionProvider.notifier);
    final imu = sample(PositionSource.imu, 12.9, 77.5);
    final gps = sample(PositionSource.gps, 13.0, 77.6);
    navigation.updateImuPosition(imu);
    navigation.setNavigationMode(NavigationMode.imu);

    source.emitPosition(gps);

    final session = container.read(navigationSessionProvider);
    expect(session.latestGpsPosition, gps);
    expect(session.displayedPosition, imu);
  });

  test('switching IMU to GPS reveals the latest streamed GPS sample', () {
    final navigation = container.read(navigationSessionProvider.notifier);
    final imu = sample(PositionSource.imu, 12.9, 77.5);
    final gps = sample(PositionSource.gps, 13.0, 77.6);
    navigation.updateImuPosition(imu);
    navigation.setNavigationMode(NavigationMode.imu);
    source.emitPosition(gps);

    navigation.setNavigationMode(NavigationMode.gps);

    expect(container.read(navigationSessionProvider).displayedPosition, gps);
  });

  test('location stream errors become coordinator errors', () async {
    source.emitPositionError(StateError('receiver stopped'));
    await pumpEventQueue();

    final state = container.read(locationCoordinatorProvider);
    expect(state.trackingStatus, LocationTrackingStatus.error);
    expect(state.errorMessage, contains('receiver stopped'));
  });

  test('no fake initial GPS coordinate exists', () {
    expect(container.read(navigationSessionProvider).latestGpsPosition, isNull);
    expect(container.read(navigationSessionProvider).hasGpsFix, isFalse);
  });

  test('GPS updates preserve destination and route state', () {
    final navigation = container.read(navigationSessionProvider.notifier);
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 19.076, longitude: 72.8777),
      displayLabel: 'Mumbai',
    );
    final alternatives = routeAlternatives();
    navigation.setDestination(destination);
    navigation.setRouteAlternatives(alternatives);
    navigation.selectRoute(RouteMode.safe);
    final selected = container.read(navigationSessionProvider).selectedRoute;

    source.emitPosition(sample(PositionSource.gps, 13.0, 77.6));

    final session = container.read(navigationSessionProvider);
    expect(session.destination, destination);
    expect(session.routeAlternatives, same(alternatives));
    expect(session.selectedRoute, same(selected));
    expect(session.selectedRouteMode, RouteMode.safe);
  });

  test('coordinator disposal stops the source', () async {
    container.dispose();
    await pumpEventQueue();

    expect(source.stopCalls, 1);
  });

  test('app lifecycle pauses and resumes foreground tracking', () async {
    final coordinator = container.read(locationCoordinatorProvider.notifier);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
    await pumpEventQueue();
    expect(source.stopCalls, 1);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(source.startCalls, 2);
  });
}

PositionSample sample(
  PositionSource source,
  double latitude,
  double longitude,
) {
  return PositionSample(
    coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
    timestamp: DateTime.utc(2026, 9, 22, 10),
    source: source,
  );
}

RouteAlternatives routeAlternatives() {
  const path = [
    GeoCoordinate(latitude: 12.9716, longitude: 77.5946),
    GeoCoordinate(latitude: 13.0, longitude: 77.6),
  ];
  return RouteAlternatives(
    byMode: {
      RouteMode.normal: RouteAlternative(
        mode: RouteMode.normal,
        path: path,
        metrics: RouteMetrics(),
        optimization: 'normal',
      ),
      RouteMode.safe: RouteAlternative(
        mode: RouteMode.safe,
        path: path,
        metrics: RouteMetrics(),
        optimization: 'safe',
      ),
    },
    metadata: const RouteMetadata(
      start: GeoCoordinate(latitude: 12.9716, longitude: 77.5946),
      end: GeoCoordinate(latitude: 13.0, longitude: 77.6),
      source: 'test',
    ),
  );
}
