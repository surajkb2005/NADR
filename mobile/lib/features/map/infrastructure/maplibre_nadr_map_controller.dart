import 'package:flutter/widgets.dart';
import 'package:maplibre/maplibre.dart' as maplibre;
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/map/domain/current_location_marker.dart';
import 'package:nadr_mobile/features/map/domain/map_camera.dart';
import 'package:nadr_mobile/features/map/domain/nadr_map_controller.dart';
import 'package:nadr_mobile/features/map/infrastructure/maplibre_current_location_layer.dart';
import 'package:nadr_mobile/features/map/infrastructure/maplibre_destination_layer.dart';
import 'package:nadr_mobile/features/map/infrastructure/maplibre_route_layer.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

final class MapLibreNadrMapController implements NadrMapController {
  MapLibreNadrMapController(this._controller);

  final maplibre.MapController _controller;
  final MapLibreCurrentLocationLayer _locationLayer =
      MapLibreCurrentLocationLayer();
  final MapLibreDestinationLayer _destinationLayer = MapLibreDestinationLayer();
  final MapLibreRouteLayer _routeLayer = MapLibreRouteLayer();

  Future<void> onStyleLoaded(maplibre.StyleController style) async {
    await _routeLayer.install(style);
    await _locationLayer.install(style);
    await _destinationLayer.install(style);
  }

  void detachStyle() {
    _routeLayer.detach();
    _locationLayer.detach();
    _destinationLayer.detach();
  }

  @override
  MapCameraState? get currentCamera {
    final camera = _controller.camera;
    if (camera == null) return null;

    return MapCameraState(
      center: _fromGeographic(camera.center),
      zoom: camera.zoom,
      bearing: camera.bearing,
      tilt: camera.pitch,
    );
  }

  @override
  MapBounds? get visibleBounds {
    try {
      final bounds = _controller.getVisibleRegion();
      return MapBounds(
        southWest: GeoCoordinate(
          latitude: bounds.latitudeSouth,
          longitude: bounds.longitudeWest,
        ),
        northEast: GeoCoordinate(
          latitude: bounds.latitudeNorth,
          longitude: bounds.longitudeEast,
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> moveCamera(MapCameraUpdate update) {
    return _controller.moveCamera(
      center: _toGeographicOrNull(update.center),
      zoom: update.zoom,
      bearing: update.bearing,
      pitch: update.tilt,
    );
  }

  @override
  Future<void> animateCamera(
    MapCameraUpdate update, {
    Duration duration = const Duration(milliseconds: 700),
  }) async {
    try {
      await _controller.animateCamera(
        center: _toGeographicOrNull(update.center),
        zoom: update.zoom,
        bearing: update.bearing,
        pitch: update.tilt,
        nativeDuration: duration,
        webMaxDuration: duration,
      );
    } on Exception catch (error) {
      // maplibre_android 0.3.6's CancelableCallback completes with this exact
      // exception when another camera command supersedes an animation.
      if (error.toString() == 'Exception: Map camera movement cancelled.') {
        throw const MapCameraAnimationCancelled();
      }
      rethrow;
    }
  }

  @override
  Future<void> setCenter(GeoCoordinate center, {bool animate = true}) {
    final update = MapCameraUpdate(center: center);
    return animate ? animateCamera(update) : moveCamera(update);
  }

  @override
  Future<void> setZoom(double zoom, {bool animate = true}) {
    final update = MapCameraUpdate(zoom: zoom);
    return animate ? animateCamera(update) : moveCamera(update);
  }

  @override
  Future<void> fitBounds(
    MapBounds bounds, {
    MapViewportPadding padding = const MapViewportPadding(),
    Duration duration = const Duration(milliseconds: 700),
  }) {
    return _controller.fitBounds(
      bounds: maplibre.LngLatBounds(
        longitudeWest: bounds.southWest.longitude,
        longitudeEast: bounds.northEast.longitude,
        latitudeSouth: bounds.southWest.latitude,
        latitudeNorth: bounds.northEast.latitude,
      ),
      nativeDuration: duration,
      webMaxDuration: duration,
      padding: EdgeInsets.fromLTRB(
        padding.left,
        padding.top,
        padding.right,
        padding.bottom,
      ),
    );
  }

  @override
  Future<void> updateCurrentLocationMarker(CurrentLocationMarkerData? marker) =>
      _locationLayer.setMarker(marker);

  @override
  Future<void> updateDestinationMarker(Destination? destination) =>
      _destinationLayer.setDestination(destination);

  @override
  Future<void> updateSelectedRoute(RouteAlternative? route) =>
      _routeLayer.setRoute(route);

  @override
  Future<void> recenter(
    GeoCoordinate center, {
    double zoom = 16.5,
    bool animate = true,
  }) {
    final update = MapCameraUpdate(center: center, zoom: zoom);
    return animate ? animateCamera(update) : moveCamera(update);
  }

  static maplibre.Geographic? _toGeographicOrNull(GeoCoordinate? coordinate) {
    if (coordinate == null) return null;
    return maplibre.Geographic(
      lon: coordinate.longitude,
      lat: coordinate.latitude,
    );
  }

  static GeoCoordinate _fromGeographic(maplibre.Geographic coordinate) {
    return GeoCoordinate(latitude: coordinate.lat, longitude: coordinate.lon);
  }
}
