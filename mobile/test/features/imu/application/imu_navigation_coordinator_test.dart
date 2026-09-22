import 'dart:convert';

import 'package:flutter/widgets.dart' hide NavigationMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/imu/application/imu_navigation_coordinator.dart';
import 'package:nadr_mobile/features/imu/application/imu_navigation_state.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_sample.dart';
import 'package:nadr_mobile/features/map/presentation/current_location_marker_mapper.dart';
import 'package:nadr_mobile/features/map/infrastructure/maplibre_current_location_layer.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/features/navigation/domain/connection_status.dart';
import 'package:nadr_mobile/features/navigation/infrastructure/website_imu_position_estimator.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

import '../../../support/fake_imu_sensor_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late FakeImuSensorSource sensors;
  late WebsiteImuPositionEstimator estimator;

  setUp(() {
    sensors = FakeImuSensorSource();
    estimator = WebsiteImuPositionEstimator();
    container = ProviderContainer(
      overrides: [
        imuSensorSourceProvider.overrideWithValue(sensors),
        imuPositionEstimatorProvider.overrideWithValue(estimator),
      ],
    );
    container.read(imuNavigationCoordinatorProvider);
  });

  tearDown(() async {
    container.dispose();
    await sensors.dispose();
  });

  PositionSample gps(double latitude, double longitude) => PositionSample(
    coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
    timestamp: DateTime.now(),
    source: PositionSource.gps,
  );

  test('GPS is default and IMU waits for a real GPS fix', () async {
    final coordinator = container.read(
      imuNavigationCoordinatorProvider.notifier,
    );
    expect(
      container.read(navigationSessionProvider).navigationMode,
      NavigationMode.gps,
    );
    coordinator.setNavigationMode(NavigationMode.imu);
    await pumpEventQueue();
    expect(sensors.startCalls, 0);
    expect(
      container.read(imuNavigationCoordinatorProvider).phase,
      ImuNavigationPhase.waitingForGps,
    );
    expect(container.read(navigationSessionProvider).displayedPosition, isNull);
  });

  test('GPS to IMU starts at latest real fix and GPS keeps updating', () async {
    final navigation = container.read(navigationSessionProvider.notifier);
    final coordinator = container.read(
      imuNavigationCoordinatorProvider.notifier,
    );
    final first = gps(12.97, 77.59);
    navigation.updateGpsPosition(first);
    coordinator.setNavigationMode(NavigationMode.imu);
    await pumpEventQueue();
    expect(sensors.startCalls, 1);
    expect(
      container.read(navigationSessionProvider).displayedPosition?.coordinate,
      first.coordinate,
    );
    expect(
      container.read(navigationSessionProvider).displayedPosition?.source,
      PositionSource.imu,
    );

    final newer = gps(12.98, 77.60);
    navigation.updateGpsPosition(newer);
    expect(container.read(navigationSessionProvider).latestGpsPosition, newer);
    expect(
      container.read(navigationSessionProvider).displayedPosition?.coordinate,
      first.coordinate,
    );

    coordinator.setNavigationMode(NavigationMode.gps);
    await pumpEventQueue();
    expect(container.read(navigationSessionProvider).displayedPosition, newer);
    expect(sensors.stopCalls, greaterThanOrEqualTo(1));

    coordinator.setNavigationMode(NavigationMode.imu);
    await pumpEventQueue();
    expect(
      container.read(navigationSessionProvider).displayedPosition?.coordinate,
      newer.coordinate,
    );
    expect(sensors.startCalls, 2);
  });

  testWidgets('sensor reading produces an IMU position on the 200 ms tick', (
    tester,
  ) async {
    final navigation = container.read(navigationSessionProvider.notifier);
    final coordinator = container.read(
      imuNavigationCoordinatorProvider.notifier,
    );
    final origin = gps(12.97, 77.59);
    navigation.updateGpsPosition(origin);
    coordinator.setNavigationMode(NavigationMode.imu);
    await tester.pump();
    sensors.emitStatus(SensorStatus.active);
    sensors.emitSample(
      ImuSensorSample(
        linearAccelerationX: 20,
        linearAccelerationY: 0,
        linearAccelerationZ: 0,
        heading: 90,
        timestamp: DateTime.now(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 210));
    expect(
      container.read(imuNavigationCoordinatorProvider).phase,
      ImuNavigationPhase.active,
    );
    expect(
      container
          .read(navigationSessionProvider)
          .latestImuPosition
          ?.coordinate
          .longitude,
      greaterThan(origin.coordinate.longitude),
    );
    coordinator.setNavigationMode(NavigationMode.gps);
    await tester.pump();
  });

  testWidgets(
    'every sensor event contributes before the independent decay tick',
    (tester) async {
      final navigation = container.read(navigationSessionProvider.notifier);
      final coordinator = container.read(
        imuNavigationCoordinatorProvider.notifier,
      );
      navigation.updateGpsPosition(gps(12.97, 77.59));
      coordinator.setNavigationMode(NavigationMode.imu);
      await tester.pump();
      sensors.emitStatus(SensorStatus.active);
      for (var i = 0; i < 50; i++) {
        sensors.emitSample(
          ImuSensorSample(
            linearAccelerationX: 20,
            linearAccelerationY: 0,
            linearAccelerationZ: 0,
            heading: 90,
            timestamp: DateTime.now(),
          ),
        );
      }
      await tester.pump();
      expect(estimator.speedKilometersPerHour, 20);
      await tester.pump(const Duration(milliseconds: 210));
      expect(estimator.speedKilometersPerHour, closeTo(17, 0.001));
      coordinator.setNavigationMode(NavigationMode.gps);
      await tester.pump();
    },
  );

  testWidgets('mixed walking events accumulate at event rate across ticks', (
    tester,
  ) async {
    final navigation = container.read(navigationSessionProvider.notifier);
    final coordinator = container.read(
      imuNavigationCoordinatorProvider.notifier,
    );
    navigation.updateGpsPosition(gps(12.97, 77.59));
    coordinator.setNavigationMode(NavigationMode.imu);
    await tester.pump();
    sensors.emitStatus(SensorStatus.active);
    for (final magnitude in [1.2, 1.5, 1.8, 2.0, 2.5]) {
      sensors.emitSample(
        ImuSensorSample(
          linearAccelerationX: magnitude,
          linearAccelerationY: 0,
          linearAccelerationZ: 0,
          heading: 90,
          timestamp: DateTime.now(),
        ),
      );
    }
    await tester.pump();
    expect(estimator.speedKilometersPerHour, closeTo(5.4, 0.001));
    await tester.pump(const Duration(milliseconds: 210));
    expect(estimator.speedKilometersPerHour, closeTo(3.86, 0.001));
    coordinator.setNavigationMode(NavigationMode.gps);
    await tester.pump();
  });

  testWidgets('mode switching does not duplicate sensor contributions', (
    tester,
  ) async {
    final navigation = container.read(navigationSessionProvider.notifier);
    final coordinator = container.read(
      imuNavigationCoordinatorProvider.notifier,
    );
    navigation.updateGpsPosition(gps(12.97, 77.59));
    for (var session = 0; session < 2; session++) {
      coordinator.setNavigationMode(NavigationMode.imu);
      await tester.pump();
      sensors.emitStatus(SensorStatus.active);
      sensors.emitSample(
        ImuSensorSample(
          linearAccelerationX: 5,
          linearAccelerationY: 0,
          linearAccelerationZ: 0,
          heading: 90,
          timestamp: DateTime.now(),
        ),
      );
      await tester.pump();
      expect(estimator.speedKilometersPerHour, closeTo(3, 0.001));
      coordinator.setNavigationMode(NavigationMode.gps);
      await tester.pump();
    }
    expect(sensors.startCalls, 2);
  });

  testWidgets(
    'a threshold-crossing sample is not lost before the 200 ms tick',
    (tester) async {
      final navigation = container.read(navigationSessionProvider.notifier);
      final coordinator = container.read(
        imuNavigationCoordinatorProvider.notifier,
      );
      final origin = gps(12.97, 77.59);
      navigation.updateGpsPosition(origin);
      coordinator.setNavigationMode(NavigationMode.imu);
      await tester.pump();
      sensors.emitStatus(SensorStatus.active);
      sensors.emitSample(
        ImuSensorSample(
          linearAccelerationX: 20,
          linearAccelerationY: 0,
          linearAccelerationZ: 0,
          heading: 90,
          timestamp: DateTime.now(),
        ),
      );
      sensors.emitSample(
        ImuSensorSample(
          linearAccelerationX: 0,
          linearAccelerationY: 0,
          linearAccelerationZ: 0,
          heading: 90,
          timestamp: DateTime.now(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 210));
      final session = container.read(navigationSessionProvider);
      expect(
        session.latestImuPosition?.coordinate.longitude,
        greaterThan(origin.coordinate.longitude),
      );
      expect(session.displayedPosition, session.latestImuPosition);
      final marker = currentLocationMarkerFromSession(session)!;
      final feature =
          (jsonDecode(MapLibreCurrentLocationLayer.geoJsonFor(marker))
                  as Map<String, dynamic>)['features']
              as List<dynamic>;
      final coordinates = feature.single['geometry']['coordinates'] as List;
      expect(coordinates.first, greaterThan(origin.coordinate.longitude));
      expect(feature.single['properties']['icon'], contains('imu-direction'));
      coordinator.setNavigationMode(NavigationMode.gps);
      await tester.pump();
    },
  );

  testWidgets(
    'unavailable heading keeps neutral IMU origin and GPS switch works',
    (tester) async {
      final navigation = container.read(navigationSessionProvider.notifier);
      final coordinator = container.read(
        imuNavigationCoordinatorProvider.notifier,
      );
      final origin = gps(12.97, 77.59);
      navigation.updateGpsPosition(origin);
      coordinator.setNavigationMode(NavigationMode.imu);
      await tester.pump();
      sensors.emitStatus(SensorStatus.headingUnavailable);
      sensors.emitSample(
        ImuSensorSample(
          linearAccelerationX: 20,
          linearAccelerationY: 0,
          linearAccelerationZ: 0,
          heading: 0, // Even a bad source claiming north cannot bypass status.
          timestamp: DateTime.now(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 410));
      final session = container.read(navigationSessionProvider);
      expect(
        container.read(imuNavigationCoordinatorProvider).phase,
        ImuNavigationPhase.headingUnavailable,
      );
      expect(session.displayedPosition?.coordinate, origin.coordinate);
      expect(session.displayedPosition?.heading, isNull);
      expect(currentLocationMarkerFromSession(session)?.heading, isNull);
      expect(estimator.speedKilometersPerHour, 0);

      coordinator.setNavigationMode(NavigationMode.gps);
      await tester.pump();
      expect(
        container.read(navigationSessionProvider).displayedPosition,
        origin,
      );
    },
  );

  testWidgets('temporarily unavailable heading resumes on valid north zero', (
    tester,
  ) async {
    final navigation = container.read(navigationSessionProvider.notifier);
    final coordinator = container.read(
      imuNavigationCoordinatorProvider.notifier,
    );
    final origin = gps(12.97, 77.59);
    navigation.updateGpsPosition(origin);
    coordinator.setNavigationMode(NavigationMode.imu);
    await tester.pump();
    sensors.emitStatus(SensorStatus.headingUnavailable);
    await tester.pump();
    expect(
      container.read(imuNavigationCoordinatorProvider).phase,
      ImuNavigationPhase.headingUnavailable,
    );

    sensors.emitStatus(SensorStatus.active);
    sensors.emitSample(
      ImuSensorSample(
        linearAccelerationX: 20,
        linearAccelerationY: 0,
        linearAccelerationZ: 0,
        heading: 0,
        timestamp: DateTime.now(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 210));
    final session = container.read(navigationSessionProvider);
    expect(
      container.read(imuNavigationCoordinatorProvider).phase,
      ImuNavigationPhase.active,
    );
    expect(session.displayedPosition?.heading, 0);
    expect(
      session.displayedPosition?.coordinate.latitude,
      greaterThan(origin.coordinate.latitude),
    );
    expect(currentLocationMarkerFromSession(session)?.heading, 0);
    coordinator.setNavigationMode(NavigationMode.gps);
    await tester.pump();
  });

  test('destination and route selection survive switching', () async {
    final navigation = container.read(navigationSessionProvider.notifier);
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 19.07, longitude: 72.87),
    );
    final route = RouteAlternative(
      mode: RouteMode.normal,
      path: const [GeoCoordinate(latitude: 12.97, longitude: 77.59)],
      metrics: const RouteMetrics(),
      optimization: 'normal',
    );
    final routes = RouteAlternatives(byMode: {RouteMode.normal: route});
    navigation.setDestination(destination);
    navigation.setRouteAlternatives(routes);
    navigation.selectRoute(RouteMode.normal);
    navigation.updateGpsPosition(gps(12.97, 77.59));
    final coordinator = container.read(
      imuNavigationCoordinatorProvider.notifier,
    );
    coordinator.setNavigationMode(NavigationMode.imu);
    await pumpEventQueue();
    coordinator.setNavigationMode(NavigationMode.gps);
    await pumpEventQueue();
    final state = container.read(navigationSessionProvider);
    expect(state.destination, destination);
    expect(state.routeAlternatives, same(routes));
    expect(state.selectedRoute, same(route));
  });

  test(
    'sensor failure is visible and does not crash or keep timer active',
    () async {
      final navigation = container.read(navigationSessionProvider.notifier);
      navigation.updateGpsPosition(gps(12.97, 77.59));
      container
          .read(imuNavigationCoordinatorProvider.notifier)
          .setNavigationMode(NavigationMode.imu);
      await pumpEventQueue();
      sensors.emitStatus(SensorStatus.unavailable);
      await pumpEventQueue();
      expect(
        container.read(imuNavigationCoordinatorProvider).phase,
        ImuNavigationPhase.unavailable,
      );
      expect(
        container.read(navigationSessionProvider).sensorStatus,
        SensorStatus.unavailable,
      );
      expect(sensors.stopCalls, greaterThanOrEqualTo(1));
    },
  );

  test('pause stops IMU; resume restarts from newest GPS fix', () async {
    final navigation = container.read(navigationSessionProvider.notifier);
    navigation.updateGpsPosition(gps(12.97, 77.59));
    final coordinator = container.read(
      imuNavigationCoordinatorProvider.notifier,
    );
    coordinator.setNavigationMode(NavigationMode.imu);
    await pumpEventQueue();
    coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
    await pumpEventQueue();
    expect(
      container.read(imuNavigationCoordinatorProvider).phase,
      ImuNavigationPhase.paused,
    );
    navigation.updateGpsPosition(gps(12.98, 77.60));
    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(
      container.read(navigationSessionProvider).displayedPosition?.coordinate,
      const GeoCoordinate(latitude: 12.98, longitude: 77.60),
    );
  });

  test('disposal cancels sensor subscriptions', () async {
    final navigation = container.read(navigationSessionProvider.notifier);
    navigation.updateGpsPosition(gps(12.97, 77.59));
    container
        .read(imuNavigationCoordinatorProvider.notifier)
        .setNavigationMode(NavigationMode.imu);
    await pumpEventQueue();
    container.dispose();
    await pumpEventQueue();
    expect(sensors.stopCalls, greaterThanOrEqualTo(1));
  });
}
