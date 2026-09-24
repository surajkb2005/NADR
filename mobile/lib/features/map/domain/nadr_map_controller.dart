import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/map/domain/current_location_marker.dart';
import 'package:nadr_mobile/features/map/domain/map_camera.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';

/// A programmatic camera animation was superseded, not a location failure.
final class MapCameraAnimationCancelled implements Exception {
  const MapCameraAnimationCancelled();
}

abstract interface class NadrMapController {
  MapCameraState? get currentCamera;

  MapBounds? get visibleBounds;

  Future<void> moveCamera(MapCameraUpdate update);

  Future<void> animateCamera(
    MapCameraUpdate update, {
    Duration duration = const Duration(milliseconds: 700),
  });

  Future<void> setCenter(GeoCoordinate center, {bool animate = true});

  Future<void> setZoom(double zoom, {bool animate = true});

  Future<void> fitBounds(
    MapBounds bounds, {
    MapViewportPadding padding = const MapViewportPadding(),
    Duration duration = const Duration(milliseconds: 700),
  });

  Future<void> updateCurrentLocationMarker(CurrentLocationMarkerData? marker);

  Future<void> updateDestinationMarker(Destination? destination);

  Future<void> recenter(
    GeoCoordinate center, {
    double zoom = 16.5,
    bool animate = true,
  });
}
