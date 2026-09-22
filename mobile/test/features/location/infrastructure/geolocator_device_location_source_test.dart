import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/location/application/location_coordinator.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';
import 'package:nadr_mobile/features/location/infrastructure/geolocator_device_location_source.dart';
import 'package:nadr_mobile/features/location/infrastructure/gps_accuracy.dart';
import 'package:nadr_mobile/features/location/infrastructure/gps_fix_quality_gate.dart';
import 'package:nadr_mobile/features/map/presentation/current_location_marker_mapper.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('permission granted obtains a fix and starts streaming', () async {
    final initialPosition = platformPosition(
      latitude: 12.9716,
      longitude: 77.5946,
    );
    final client = _FakeGeolocatorClient(
      permission: LocationPermission.whileInUse,
      currentPosition: initialPosition,
    );
    final source = GeolocatorDeviceLocationSource(client: client);
    addTearDown(source.dispose);
    final samples = <Object>[];
    final subscription = source.positions.listen(samples.add);
    addTearDown(subscription.cancel);

    await source.start();
    client.emit(
      platformPosition(
        latitude: 12.9720,
        longitude: 77.5950,
        timestamp: initialPosition.timestamp.add(const Duration(seconds: 2)),
      ),
    );

    expect(client.requestPermissionCalls, 0);
    expect(client.positionStreamCalls, 1);
    expect(samples, hasLength(2));
    expect(source.state.trackingStatus, LocationTrackingStatus.active);
    expect(source.state.permissionStatus, LocationPermissionStatus.granted);
  });

  test(
    'permission denied is controlled and not requested repeatedly',
    () async {
      final client = _FakeGeolocatorClient(
        permission: LocationPermission.denied,
        requestedPermission: LocationPermission.denied,
      );
      final source = GeolocatorDeviceLocationSource(client: client);
      addTearDown(source.dispose);

      await source.start();
      await source.start();

      expect(client.requestPermissionCalls, 1);
      expect(client.positionStreamCalls, 0);
      expect(source.state.permissionStatus, LocationPermissionStatus.denied);
      expect(source.state.trackingStatus, LocationTrackingStatus.stopped);
    },
  );

  test('permission denied forever is exposed without starting GPS', () async {
    final client = _FakeGeolocatorClient(
      permission: LocationPermission.denied,
      requestedPermission: LocationPermission.deniedForever,
    );
    final source = GeolocatorDeviceLocationSource(client: client);
    addTearDown(source.dispose);

    await source.start();

    expect(
      source.state.permissionStatus,
      LocationPermissionStatus.deniedForever,
    );
    expect(source.state.trackingStatus, LocationTrackingStatus.stopped);
    expect(client.positionStreamCalls, 0);
  });

  test(
    'disabled location services are exposed before permission request',
    () async {
      final client = _FakeGeolocatorClient(serviceEnabled: false);
      final source = GeolocatorDeviceLocationSource(client: client);
      addTearDown(source.dispose);

      await source.start();

      expect(source.state.serviceStatus, LocationServiceStatus.disabled);
      expect(source.state.trackingStatus, LocationTrackingStatus.stopped);
      expect(client.checkPermissionCalls, 0);
      expect(client.requestPermissionCalls, 0);
    },
  );

  test('platform position conversion uses only reported heading', () {
    final withHeading = GeolocatorDeviceLocationSource.toPositionSample(
      platformPosition(
        latitude: 12.9716,
        longitude: 77.5946,
        heading: 42,
        hasHeading: true,
      ),
    );
    final withoutHeading = GeolocatorDeviceLocationSource.toPositionSample(
      platformPosition(latitude: 12.9716, longitude: 77.5946, heading: 0),
    );

    expect(withHeading.source, PositionSource.gps);
    expect(withHeading.heading, 42);
    expect(withoutHeading.heading, isNull);
  });

  test('Android accuracy presence, not a numeric fallback, reaches domain', () {
    final time = DateTime.now().millisecondsSinceEpoch;
    Map<String, Object> raw([Object? accuracy]) {
      final values = <String, Object>{
        'latitude': 12.9716,
        'longitude': 77.5946,
        'timestamp': time,
      };
      if (accuracy != null) values['accuracy'] = accuracy;
      return values;
    }

    final measured10 = Position.fromMap(raw(10.0));
    final measured20 = Position.fromMap(raw(20.0));
    final unavailable = Position.fromMap(raw());
    final explicitMissing = Position.fromMap({
      ...raw(12.0),
      'has_accuracy': false,
    });

    expect(measured10.hasAccuracy, isTrue);
    expect(measured20.hasAccuracy, isTrue);
    expect(unavailable.hasAccuracy, isFalse);
    expect(unavailable.accuracy, 0); // Plugin fallback, not perfect accuracy.
    expect(explicitMissing.hasAccuracy, isFalse);
    expect(explicitMissing.accuracy, 12);
    expect(
      GeolocatorDeviceLocationSource.toPositionSample(measured10)
          .horizontalAccuracyMeters,
      10,
    );
    expect(
      GeolocatorDeviceLocationSource.toPositionSample(measured20)
          .horizontalAccuracyMeters,
      20,
    );
    expect(
      GeolocatorDeviceLocationSource.toPositionSample(unavailable)
          .horizontalAccuracyMeters,
      isNull,
    );
    expect(
      GeolocatorDeviceLocationSource.toPositionSample(explicitMissing)
          .horizontalAccuracyMeters,
      isNull,
    );

    // The pinned Android wrapper reconstructs Position without forwarding
    // hasAccuracy, even though the native map contained measured accuracy.
    final wrapped = AndroidPosition.fromMap(raw(12.0));
    final wrappedMissing = AndroidPosition.fromMap(raw());
    expect(wrapped.hasAccuracy, isFalse);
    expect(wrapped.accuracy, 12);
    expect(GpsAccuracy.isReported(wrapped), isTrue);
    expect(GpsAccuracy.isReported(wrappedMissing), isFalse);
    expect(GpsAccuracy.measuredMeters(wrappedMissing), isNull);
    expect(
      GeolocatorDeviceLocationSource.toPositionSample(wrapped)
          .horizontalAccuracyMeters,
      12,
    );
    final tooPoor = AndroidPosition.fromMap(raw(180.0));
    expect(
      const GpsFixQualityGate()
          .evaluate(tooPoor, receivedAt: DateTime.now())
          .reason,
      'poor_accuracy',
    );

    final b = AndroidPosition.fromMap({
      ...raw(12.0),
      'latitude': 12.972458,
      'longitude': 77.5939439,
      'timestamp': time + 2000,
    });
    expect(
      GpsOutlierQuarantine().consider(b, previousAccepted: wrapped).action,
      GpsOutlierAction.quarantined,
    );
  });

  test('stream errors transition to a controlled error state', () async {
    final client = _FakeGeolocatorClient(
      permission: LocationPermission.whileInUse,
      currentPosition: platformPosition(latitude: 12.9716, longitude: 77.5946),
    );
    final source = GeolocatorDeviceLocationSource(client: client);
    addTearDown(source.dispose);

    await source.start();
    client.emitError(StateError('GPS unavailable'));
    await pumpEventQueue();

    expect(source.state.trackingStatus, LocationTrackingStatus.error);
    expect(source.state.errorMessage, contains('GPS unavailable'));
  });

  test('stop cancels the active platform stream', () async {
    final client = _FakeGeolocatorClient(
      permission: LocationPermission.whileInUse,
      currentPosition: platformPosition(latitude: 12.9716, longitude: 77.5946),
    );
    final source = GeolocatorDeviceLocationSource(client: client);
    addTearDown(source.dispose);

    await source.start();
    await source.stop();

    expect(client.streamCancelCount, 1);
    expect(source.state.trackingStatus, LocationTrackingStatus.stopped);
  });

  test('rejected raw fix preserves the accepted GPS position', () async {
    final initial = platformPosition(latitude: 12.9716, longitude: 77.5946);
    final client = _FakeGeolocatorClient(
      permission: LocationPermission.whileInUse,
      currentPosition: initial,
    );
    final source = GeolocatorDeviceLocationSource(client: client);
    addTearDown(source.dispose);
    final samples = <Object>[];
    final subscription = source.positions.listen(samples.add);
    addTearDown(subscription.cancel);

    await source.start();
    client.emit(
      platformPosition(
        latitude: 20,
        longitude: 80,
        timestamp: initial.timestamp.add(const Duration(seconds: 1)),
        accuracy: 200,
      ),
    );
    client.emit(
      platformPosition(
        latitude: 13,
        longitude: 78,
        timestamp: initial.timestamp.subtract(const Duration(seconds: 1)),
      ),
    );

    expect(samples, hasLength(1));
    expect(source.state.trackingStatus, LocationTrackingStatus.active);
  });

  test('a delayed initial fix from a stopped session is ignored', () async {
    final delayed = Completer<Position>();
    final client = _FakeGeolocatorClient(
      permission: LocationPermission.whileInUse,
      currentPositionProvider: () => delayed.future,
    );
    final source = GeolocatorDeviceLocationSource(client: client);
    addTearDown(source.dispose);
    final samples = <Object>[];
    final subscription = source.positions.listen(samples.add);
    addTearDown(subscription.cancel);

    final starting = source.start();
    await pumpEventQueue();
    await source.stop();
    delayed.complete(platformPosition(latitude: 12.9716, longitude: 77.5946));
    await starting;

    expect(samples, isEmpty);
    expect(client.positionStreamCalls, 0);
  });

  test('repeated start has one authoritative GPS stream', () async {
    final client = _FakeGeolocatorClient(
      permission: LocationPermission.whileInUse,
    );
    final source = GeolocatorDeviceLocationSource(client: client);
    addTearDown(source.dispose);
    await Future.wait([source.start(), source.start(), source.start()]);
    expect(client.positionStreamCalls, 1);
    await source.stop();
    await source.start();
    expect(client.positionStreamCalls, 2);
    expect(client.streamCancelCount, 1);
  });

  test(
    'rejected raw GPS never becomes the displayed navigation position',
    () async {
      final accepted = platformPosition(latitude: 12.9716, longitude: 77.5946);
      final client = _FakeGeolocatorClient(
        permission: LocationPermission.whileInUse,
        currentPosition: accepted,
      );
      final source = GeolocatorDeviceLocationSource(client: client);
      final container = ProviderContainer(
        overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
      );
      addTearDown(() async {
        container.dispose();
        await source.dispose();
      });
      container.read(locationCoordinatorProvider);
      await pumpEventQueue();
      final before = container
          .read(navigationSessionProvider)
          .displayedPosition;
      expect(before?.coordinate.latitude, 12.9716);

      client.emit(
        platformPosition(
          latitude: 40,
          longitude: -73,
          accuracy: 300,
          timestamp: accepted.timestamp.add(const Duration(seconds: 2)),
        ),
      );

      final after = container.read(navigationSessionProvider);
      expect(after.latestGpsPosition, before);
      expect(after.displayedPosition, before);
    },
  );

  test('Motorola A-B-A keeps navigation and marker at A', () async {
    final a = platformPosition(
      latitude: 12.9716,
      longitude: 77.5946,
      hasAccuracy: false,
      accuracy: 0,
    );
    final client = _FakeGeolocatorClient(
      permission: LocationPermission.whileInUse,
      currentPosition: a,
    );
    final source = GeolocatorDeviceLocationSource(client: client);
    final container = ProviderContainer(
      overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
    );
    addTearDown(() async {
      container.dispose();
      await source.dispose();
    });
    container.read(locationCoordinatorProvider);
    await pumpEventQueue();
    final accepted = container
        .read(navigationSessionProvider)
        .displayedPosition;
    expect(accepted?.coordinate.latitude, a.latitude);

    client.emit(
      platformPosition(
        latitude: 12.972458,
        longitude: 77.5939439,
        hasAccuracy: false,
        accuracy: 0,
        timestamp: a.timestamp.add(const Duration(seconds: 2)),
      ),
    );
    expect(
      container.read(navigationSessionProvider).latestGpsPosition,
      accepted,
    );
    expect(
      container.read(navigationSessionProvider).displayedPosition,
      accepted,
    );
    expect(
      currentLocationMarkerFromSession(
        container.read(navigationSessionProvider),
      )?.coordinate,
      accepted?.coordinate,
    );

    client.emit(
      platformPosition(
        latitude: 12.971601,
        longitude: 77.594601,
        hasAccuracy: false,
        accuracy: 0,
        timestamp: a.timestamp.add(const Duration(seconds: 4)),
      ),
    );
    final afterReturn = container.read(navigationSessionProvider);
    expect(
      afterReturn.displayedPosition?.coordinate.latitude,
      closeTo(12.971601, 0.000001),
    );
    expect(
      currentLocationMarkerFromSession(afterReturn)?.coordinate,
      afterReturn.displayedPosition?.coordinate,
    );
  });

  test('pending GPS candidate never contaminates mode switching', () async {
    final a = platformPosition(
      latitude: 12.9716,
      longitude: 77.5946,
      hasAccuracy: false,
      accuracy: 0,
    );
    final client = _FakeGeolocatorClient(
      permission: LocationPermission.whileInUse,
      currentPosition: a,
    );
    final source = GeolocatorDeviceLocationSource(client: client);
    final container = ProviderContainer(
      overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
    );
    addTearDown(() async {
      container.dispose();
      await source.dispose();
    });
    container.read(locationCoordinatorProvider);
    await pumpEventQueue();
    final navigation = container.read(navigationSessionProvider.notifier);
    final accepted = container
        .read(navigationSessionProvider)
        .latestGpsPosition!;
    client.emit(
      platformPosition(
        latitude: 12.972458,
        longitude: 77.5939439,
        hasAccuracy: false,
        accuracy: 0,
        timestamp: a.timestamp.add(const Duration(seconds: 2)),
      ),
    );
    navigation.updateImuPosition(
      PositionSample(
        coordinate: accepted.coordinate,
        timestamp: DateTime.now(),
        source: PositionSource.imu,
      ),
    );
    navigation.setNavigationMode(NavigationMode.imu);
    expect(
      container.read(navigationSessionProvider).displayedPosition?.coordinate,
      accepted.coordinate,
    );
    navigation.setNavigationMode(NavigationMode.gps);
    expect(
      container.read(navigationSessionProvider).latestGpsPosition,
      accepted,
    );
    expect(
      container.read(navigationSessionProvider).displayedPosition,
      accepted,
    );
  });

  test('restart discards candidate support from the old GPS session', () async {
    final time = DateTime.now().subtract(const Duration(seconds: 10));
    final a = platformPosition(
      latitude: 12.9716,
      longitude: 77.5946,
      hasAccuracy: false,
      accuracy: 0,
      timestamp: time,
    );
    final aAfterRestart = platformPosition(
      latitude: a.latitude,
      longitude: a.longitude,
      hasAccuracy: false,
      accuracy: 0,
      timestamp: time.add(const Duration(seconds: 3)),
    );
    var initialFixCalls = 0;
    final client = _FakeGeolocatorClient(
      permission: LocationPermission.whileInUse,
      currentPositionProvider: () async =>
          initialFixCalls++ == 0 ? a : aAfterRestart,
    );
    final source = GeolocatorDeviceLocationSource(client: client);
    addTearDown(source.dispose);
    final accepted = <PositionSample>[];
    final subscription = source.positions.listen(accepted.add);
    addTearDown(subscription.cancel);

    Position outlier(int seconds) => platformPosition(
      latitude: 12.972458,
      longitude: 77.5939439,
      hasAccuracy: false,
      accuracy: 0,
      timestamp: time.add(Duration(seconds: seconds)),
    );

    await source.start();
    client.emit(outlier(2)); // One supporting fix in the first session.
    expect(accepted, hasLength(1));
    await source.stop();
    await source.start();
    expect(accepted, hasLength(2));
    client.emit(outlier(5));
    client.emit(outlier(7));
    expect(accepted, hasLength(2));
    client.emit(outlier(9));
    expect(accepted, hasLength(3));
    expect(accepted.last.coordinate.latitude, closeTo(12.972458, 0.000001));
  });
}

Position platformPosition({
  required double latitude,
  required double longitude,
  double heading = 0,
  bool hasHeading = false,
  DateTime? timestamp,
  double accuracy = 4,
  double speed = 0,
  bool hasAccuracy = true,
}) {
  return Position(
    longitude: longitude,
    latitude: latitude,
    timestamp: timestamp ?? DateTime.now(),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: heading,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
    hasAccuracy: hasAccuracy,
    hasHeading: hasHeading,
  );
}

final class _FakeGeolocatorClient implements GeolocatorClient {
  _FakeGeolocatorClient({
    this.serviceEnabled = true,
    this.permission = LocationPermission.denied,
    this.requestedPermission = LocationPermission.whileInUse,
    Position? currentPosition,
    this.currentPositionProvider,
  }) : currentPosition =
           currentPosition ??
           platformPosition(latitude: 12.9716, longitude: 77.5946),
       _positions = StreamController<Position>.broadcast(sync: true);

  final bool serviceEnabled;
  final LocationPermission permission;
  final LocationPermission requestedPermission;
  final Position currentPosition;
  final Future<Position> Function()? currentPositionProvider;
  final StreamController<Position> _positions;

  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;
  int positionStreamCalls = 0;
  int streamCancelCount = 0;

  @override
  Future<LocationPermission> checkPermission() async {
    checkPermissionCalls += 1;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition(LocationSettings settings) async {
    if (currentPositionProvider case final provider?) return provider();
    return currentPosition;
  }

  @override
  Stream<Position> getPositionStream(LocationSettings settings) {
    positionStreamCalls += 1;
    return _positions.stream.doOnCancel(() => streamCancelCount += 1);
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls += 1;
    return requestedPermission;
  }

  void emit(Position position) => _positions.add(position);

  void emitError(Object error) => _positions.addError(error);
}

extension<T> on Stream<T> {
  Stream<T> doOnCancel(void Function() callback) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    controller = StreamController<T>(
      sync: true,
      onListen: () {
        subscription = listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        callback();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
