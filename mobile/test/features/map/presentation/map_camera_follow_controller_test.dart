import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/map/domain/current_location_marker.dart';
import 'package:nadr_mobile/features/map/domain/map_camera.dart';
import 'package:nadr_mobile/features/map/domain/nadr_map_controller.dart';
import 'package:nadr_mobile/features/map/presentation/map_camera_follow_controller.dart';
import 'package:nadr_mobile/features/navigation/domain/navigation_session_state.dart';

void main() {
  late RecordingMapController map;
  late MapCameraFollowController follow;

  setUp(() async {
    map = RecordingMapController();
    follow = MapCameraFollowController();
    await follow.attachMapController(map);
    map.clear();
  });

  tearDown(() => follow.dispose());

  test(
    'first real GPS position adds marker and positions camera once',
    () async {
      final first = sample(PositionSource.gps, 12.97, 77.59);

      await follow.updateFromSession(
        NavigationSessionState(latestGpsPosition: first),
      );

      expect(map.markerUpdates.single?.coordinate, first.coordinate);
      expect(map.cameraUpdates.single.center, first.coordinate);
      expect(
        map.cameraUpdates.single.zoom,
        MapCameraFollowController.navigationZoom,
      );

      map.clear();
      final second = sample(PositionSource.gps, 12.98, 77.60);
      await follow.updateFromSession(
        NavigationSessionState(latestGpsPosition: second),
      );
      await Future<void>.delayed(const Duration(milliseconds: 560));
      expect(map.cameraUpdates.single.zoom, isNull);
    },
  );

  test('position updates move camera while following', () async {
    await follow.updateFromSession(
      NavigationSessionState(
        latestGpsPosition: sample(PositionSource.gps, 12.97, 77.59),
      ),
    );
    map.clear();
    final next = sample(PositionSource.gps, 12.98, 77.60);

    await follow.updateFromSession(
      NavigationSessionState(latestGpsPosition: next),
    );

    await Future<void>.delayed(const Duration(milliseconds: 560));

    expect(map.cameraUpdates.single.center, next.coordinate);
  });

  test('rapid positions coalesce to the latest camera target', () async {
    await follow.updateFromSession(
      NavigationSessionState(
        latestGpsPosition: sample(PositionSource.gps, 12.97, 77.59),
      ),
    );
    map.clear();
    for (var index = 0; index < 20; index++) {
      await follow.updateFromSession(
        NavigationSessionState(
          latestGpsPosition: sample(
            PositionSource.gps,
            12.98 + index * 0.0001,
            77.60,
          ),
        ),
      );
    }
    expect(map.cameraUpdates, isEmpty);
    expect(map.markerUpdates, hasLength(20));
    await Future<void>.delayed(const Duration(milliseconds: 560));
    expect(map.cameraUpdates, hasLength(1));
    expect(
      map.cameraUpdates.single.center?.latitude,
      closeTo(12.9819, 0.000001),
    );
  });

  test(
    'manual gesture disables camera follow but marker keeps moving',
    () async {
      await follow.updateFromSession(
        NavigationSessionState(
          latestGpsPosition: sample(PositionSource.gps, 12.97, 77.59),
        ),
      );
      follow.handleUserGesture();
      map.clear();
      final next = sample(PositionSource.gps, 12.98, 77.60);

      await follow.updateFromSession(
        NavigationSessionState(latestGpsPosition: next),
      );

      expect(follow.followMode, MapCameraFollowMode.userExplore);
      expect(map.cameraUpdates, isEmpty);
      expect(map.markerUpdates.single?.coordinate, next.coordinate);
    },
  );

  test('recenter targets displayed position and re-enables follow', () async {
    final gps = sample(PositionSource.gps, 12.97, 77.59);
    await follow.updateFromSession(
      NavigationSessionState(latestGpsPosition: gps),
    );
    follow.handleUserGesture();
    map.clear();

    final result = await follow.recenter();

    expect(result, RecenterOutcome.success);
    expect(follow.followMode, MapCameraFollowMode.following);
    expect(map.recenterTargets.single, gps.coordinate);
    expect(map.recenterZooms.single, 16.5);
  });

  test('recenter preserves an already useful zoom and current mode', () async {
    final gps = sample(PositionSource.gps, 12.97, 77.59);
    final imu = sample(PositionSource.imu, 12.98, 77.60);
    map.camera = const MapCameraState(
      center: GeoCoordinate(latitude: 12.9716, longitude: 77.5946),
      zoom: 18.2,
    );
    await follow.updateFromSession(
      NavigationSessionState(
        navigationMode: NavigationMode.imu,
        latestGpsPosition: gps,
        latestImuPosition: imu,
      ),
    );
    follow.handleUserGesture();
    map.clear();

    expect(await follow.recenter(), RecenterOutcome.success);
    expect(map.recenterTargets.single, imu.coordinate);
    expect(map.recenterZooms.single, 18.2);
    expect(follow.followMode, MapCameraFollowMode.following);
    expect(follow.marker?.visualMode, CurrentLocationVisualMode.imu);
    expect(map.markerUpdates, isEmpty);
  });

  test('recenter restores navigation zoom after exploring far out', () async {
    final gps = sample(PositionSource.gps, 12.98, 77.60);
    await follow.updateFromSession(
      NavigationSessionState(latestGpsPosition: gps),
    );
    map.camera = const MapCameraState(
      center: GeoCoordinate(latitude: 12.9716, longitude: 77.5946),
      zoom: 13,
    );
    follow.handleUserGesture();
    map.clear();

    await follow.recenter();
    expect(map.recenterTargets.single, gps.coordinate);
    expect(map.recenterZooms.single, MapCameraFollowController.navigationZoom);
  });

  test('recenter is safe before displayed position exists', () async {
    final result = await follow.recenter();

    expect(result, RecenterOutcome.noPosition);
    expect(map.recenterTargets, isEmpty);
  });

  test('rapid recenter taps share one camera animation', () async {
    final gps = sample(PositionSource.gps, 12.97, 77.59);
    await follow.updateFromSession(
      NavigationSessionState(latestGpsPosition: gps),
    );
    follow.handleUserGesture();
    map.clear();
    final animation = Completer<void>();
    map.recenterAction = () => animation.future;

    final first = follow.recenter();
    final others = List.generate(14, (_) => follow.recenter());
    expect(map.recenterTargets, [gps.coordinate]);
    expect(await Future.wait(others), everyElement(RecenterOutcome.coalesced));
    animation.complete();
    expect(await first, RecenterOutcome.success);
    expect(follow.followMode, MapCameraFollowMode.following);
  });

  test(
    'already centered recenter succeeds without another animation',
    () async {
      final gps = sample(PositionSource.gps, 12.97, 77.59);
      await follow.updateFromSession(
        NavigationSessionState(latestGpsPosition: gps),
      );
      map.camera = MapCameraState(center: gps.coordinate, zoom: 16.5);
      map.clear();

      expect(await follow.recenter(), RecenterOutcome.alreadyCentered);
      expect(map.recenterTargets, isEmpty);
    },
  );

  test('cancelled animation is not a recenter failure', () async {
    final gps = sample(PositionSource.gps, 12.97, 77.59);
    await follow.updateFromSession(
      NavigationSessionState(latestGpsPosition: gps),
    );
    map.clear();
    map.recenterAction = () async => throw const MapCameraAnimationCancelled();

    expect(await follow.recenter(), RecenterOutcome.cancelled);
    expect(map.recenterTargets, [gps.coordinate]);
  });

  test('real camera error still propagates', () async {
    final gps = sample(PositionSource.gps, 12.97, 77.59);
    await follow.updateFromSession(
      NavigationSessionState(latestGpsPosition: gps),
    );
    map.clear();
    map.recenterAction = () async => throw StateError('camera failed');

    await expectLater(follow.recenter(), throwsStateError);
  });

  test('style reload restores latest marker', () async {
    final gps = sample(PositionSource.gps, 12.97, 77.59);
    await follow.updateFromSession(
      NavigationSessionState(latestGpsPosition: gps),
    );
    map.clear();

    await follow.restoreMarkerAfterStyleReload();

    expect(map.markerUpdates.single?.coordinate, gps.coordinate);
  });

  test('same-coordinate GPS and IMU style changes need no recenter', () async {
    final gps = sample(PositionSource.gps, 12.97, 77.59);
    final imuNeutral = sample(PositionSource.imu, 12.97, 77.59);
    final imuHeading = PositionSample(
      coordinate: imuNeutral.coordinate,
      timestamp: imuNeutral.timestamp,
      source: PositionSource.imu,
      heading: 90,
    );
    await follow.updateFromSession(
      NavigationSessionState(latestGpsPosition: gps),
    );
    map.clear();
    await follow.updateFromSession(
      NavigationSessionState(
        navigationMode: NavigationMode.imu,
        latestGpsPosition: gps,
        latestImuPosition: imuNeutral,
      ),
    );
    expect(map.markerUpdates.single?.visualMode, CurrentLocationVisualMode.imu);
    expect(map.markerUpdates.single?.heading, isNull);
    expect(map.recenterTargets, isEmpty);

    map.clear();
    await follow.updateFromSession(
      NavigationSessionState(
        navigationMode: NavigationMode.imu,
        latestGpsPosition: gps,
        latestImuPosition: imuHeading,
      ),
    );
    expect(map.markerUpdates.single?.heading, 90);
    expect(map.recenterTargets, isEmpty);

    map.clear();
    await follow.updateFromSession(
      NavigationSessionState(
        latestGpsPosition: gps,
        latestImuPosition: imuHeading,
      ),
    );
    expect(map.markerUpdates.single?.visualMode, CurrentLocationVisualMode.gps);
    expect(map.recenterTargets, isEmpty);

    map.clear();
    await follow.restoreMarkerAfterStyleReload();
    expect(map.markerUpdates.single?.visualMode, CurrentLocationVisualMode.gps);
  });

  test(
    'IMU without displayed position removes marker without fake data',
    () async {
      final gps = sample(PositionSource.gps, 12.97, 77.59);
      await follow.updateFromSession(
        NavigationSessionState(latestGpsPosition: gps),
      );
      map.clear();

      await follow.updateFromSession(
        NavigationSessionState(
          navigationMode: NavigationMode.imu,
          latestGpsPosition: gps,
        ),
      );

      expect(follow.marker, isNull);
      expect(map.markerUpdates, [null]);
    },
  );

  test(
    'controller attachment restores position received before map ready',
    () async {
      final delayed = MapCameraFollowController();
      final gps = sample(PositionSource.gps, 12.97, 77.59);
      await delayed.updateFromSession(
        NavigationSessionState(latestGpsPosition: gps),
      );
      final delayedMap = RecordingMapController();

      await delayed.attachMapController(delayedMap);

      expect(delayedMap.markerUpdates.single?.coordinate, gps.coordinate);
      expect(delayedMap.cameraUpdates.single.center, gps.coordinate);
      delayed.dispose();
    },
  );
}

PositionSample sample(
  PositionSource source,
  double latitude,
  double longitude,
) {
  return PositionSample(
    coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
    timestamp: DateTime.utc(2026, 9, 22),
    source: source,
  );
}

final class RecordingMapController implements NadrMapController {
  MapCameraState? camera;
  Future<void> Function()? recenterAction;
  final markerUpdates = <CurrentLocationMarkerData?>[];
  final cameraUpdates = <MapCameraUpdate>[];
  final recenterTargets = <GeoCoordinate>[];
  final recenterZooms = <double>[];

  void clear() {
    markerUpdates.clear();
    cameraUpdates.clear();
    recenterTargets.clear();
    recenterZooms.clear();
  }

  @override
  MapCameraState? get currentCamera => camera;

  @override
  MapBounds? get visibleBounds => null;

  @override
  Future<void> animateCamera(
    MapCameraUpdate update, {
    Duration duration = const Duration(milliseconds: 700),
  }) async {
    cameraUpdates.add(update);
  }

  @override
  Future<void> fitBounds(
    MapBounds bounds, {
    MapViewportPadding padding = const MapViewportPadding(),
    Duration duration = const Duration(milliseconds: 700),
  }) async {}

  @override
  Future<void> moveCamera(MapCameraUpdate update) async {}

  @override
  Future<void> recenter(
    GeoCoordinate center, {
    double zoom = 16.5,
    bool animate = true,
  }) async {
    recenterTargets.add(center);
    recenterZooms.add(zoom);
    await recenterAction?.call();
  }

  @override
  Future<void> setCenter(GeoCoordinate center, {bool animate = true}) async {}

  @override
  Future<void> setZoom(double zoom, {bool animate = true}) async {}

  @override
  Future<void> updateCurrentLocationMarker(
    CurrentLocationMarkerData? marker,
  ) async {
    markerUpdates.add(marker);
  }
}
