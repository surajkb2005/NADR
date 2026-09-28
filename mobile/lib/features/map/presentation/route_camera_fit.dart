import 'dart:math' as math;

import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/map/domain/map_camera.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

/// Camera inputs for a validated selected road route.
final class RouteCameraFit {
  const RouteCameraFit({required this.bounds, required this.padding});

  final MapBounds bounds;
  final MapViewportPadding padding;

  static RouteCameraFit? forRoute({
    required RouteAlternative? route,
    required GeoCoordinate? start,
    required GeoCoordinate? destination,
    required double viewportWidth,
    required double viewportHeight,
    required double topInset,
    required double bottomInset,
  }) {
    if (route == null || !route.isRenderableRoadRoute) return null;
    final points = [
      ...route.path,
      if (start != null && _valid(start)) start,
      if (destination != null && _valid(destination)) destination,
    ];
    var south = points.first.latitude;
    var north = south;
    var west = points.first.longitude;
    var east = west;
    for (final point in points.skip(1)) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    // Keep very short valid paths from fitting flush against the viewport.
    const minimumSpan = 0.001;
    if (north - south < minimumSpan) {
      final center = (north + south) / 2;
      south = math.max(-90, center - minimumSpan / 2);
      north = math.min(90, center + minimumSpan / 2);
    }
    if (east - west < minimumSpan) {
      final center = (east + west) / 2;
      west = math.max(-180, center - minimumSpan / 2);
      east = math.min(180, center + minimumSpan / 2);
    }
    final height = math.max(1.0, viewportHeight);
    final width = math.max(1.0, viewportWidth);
    final side = math.min(32.0, width * 0.07);
    // Search occupies the safe top area; the sheet starts at 20% height and
    // the mode/recenter controls sit immediately above it.
    final top = math.min(height * 0.35, topInset + 96);
    final bottom = math.min(height * 0.42, bottomInset + height * 0.20 + 82);
    return RouteCameraFit(
      bounds: MapBounds(
        southWest: GeoCoordinate(latitude: south, longitude: west),
        northEast: GeoCoordinate(latitude: north, longitude: east),
      ),
      padding: MapViewportPadding(
        left: side,
        top: top,
        right: side,
        bottom: bottom,
      ),
    );
  }

  static bool _valid(GeoCoordinate point) =>
      point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude >= -90 &&
      point.latitude <= 90 &&
      point.longitude >= -180 &&
      point.longitude <= 180;
}
