import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/map/domain/current_location_marker.dart';
import 'package:nadr_mobile/features/map/domain/map_camera.dart';
import 'package:nadr_mobile/features/map/domain/nadr_map_controller.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';

void main() {
  test('controller contract represents camera and bounds operations', () async {
    final controller = _RecordingMapController();
    const center = GeoCoordinate(latitude: 12.9716, longitude: 77.5946);
    const bounds = MapBounds(
      southWest: GeoCoordinate(latitude: 12.8, longitude: 77.4),
      northEast: GeoCoordinate(latitude: 13.1, longitude: 77.8),
    );

    await controller.moveCamera(const MapCameraUpdate(zoom: 11));
    await controller.animateCamera(const MapCameraUpdate(center: center));
    await controller.setCenter(center, animate: false);
    await controller.setZoom(15);
    await controller.fitBounds(
      bounds,
      padding: const MapViewportPadding(left: 12, bottom: 80),
    );
    await controller.updateCurrentLocationMarker(
      const CurrentLocationMarkerData(
        coordinate: center,
        visualMode: CurrentLocationVisualMode.gps,
      ),
    );
    await controller.recenter(center);

    expect(controller.operations, [
      'move:11.0',
      'animate:$center',
      'center:$center:false',
      'zoom:15.0:true',
      'bounds:$bounds:12.0:80.0',
      'marker:$center:gps',
      'recenter:$center:16.5:true',
    ]);
    expect(controller.currentCamera?.center, center);
    expect(controller.visibleBounds, bounds);
  });
}

final class _RecordingMapController implements NadrMapController {
  final operations = <String>[];

  @override
  MapCameraState? currentCamera = const MapCameraState(
    center: GeoCoordinate(latitude: 12.9716, longitude: 77.5946),
    zoom: 13,
  );

  @override
  MapBounds? visibleBounds = const MapBounds(
    southWest: GeoCoordinate(latitude: 12.8, longitude: 77.4),
    northEast: GeoCoordinate(latitude: 13.1, longitude: 77.8),
  );

  @override
  Future<void> animateCamera(
    MapCameraUpdate update, {
    Duration duration = const Duration(milliseconds: 700),
  }) async {
    operations.add('animate:${update.center}');
  }

  @override
  Future<void> fitBounds(
    MapBounds bounds, {
    MapViewportPadding padding = const MapViewportPadding(),
    Duration duration = const Duration(milliseconds: 700),
  }) async {
    operations.add('bounds:$bounds:${padding.left}:${padding.bottom}');
  }

  @override
  Future<void> moveCamera(MapCameraUpdate update) async {
    operations.add('move:${update.zoom}');
  }

  @override
  Future<void> recenter(
    GeoCoordinate center, {
    double zoom = 16.5,
    bool animate = true,
  }) async {
    operations.add('recenter:$center:$zoom:$animate');
  }

  @override
  Future<void> setCenter(GeoCoordinate center, {bool animate = true}) async {
    operations.add('center:$center:$animate');
  }

  @override
  Future<void> setZoom(double zoom, {bool animate = true}) async {
    operations.add('zoom:$zoom:$animate');
  }

  @override
  Future<void> updateCurrentLocationMarker(
    CurrentLocationMarkerData? marker,
  ) async {
    operations.add('marker:${marker?.coordinate}:${marker?.visualMode.name}');
  }

  @override
  Future<void> updateDestinationMarker(Destination? destination) async {}
}
