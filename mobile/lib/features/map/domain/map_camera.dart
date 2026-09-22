import 'package:nadr_mobile/core/geo/geo_coordinate.dart';

final class MapCameraState {
  const MapCameraState({
    required this.center,
    required this.zoom,
    this.bearing = 0,
    this.tilt = 0,
  });

  final GeoCoordinate center;
  final double zoom;
  final double bearing;
  final double tilt;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MapCameraState &&
            center == other.center &&
            zoom == other.zoom &&
            bearing == other.bearing &&
            tilt == other.tilt;
  }

  @override
  int get hashCode => Object.hash(center, zoom, bearing, tilt);
}

final class MapCameraUpdate {
  const MapCameraUpdate({this.center, this.zoom, this.bearing, this.tilt})
    : assert(
        center != null || zoom != null || bearing != null || tilt != null,
        'A camera update must change at least one value.',
      );

  final GeoCoordinate? center;
  final double? zoom;
  final double? bearing;
  final double? tilt;
}

final class MapBounds {
  const MapBounds({required this.southWest, required this.northEast});

  final GeoCoordinate southWest;
  final GeoCoordinate northEast;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MapBounds &&
            southWest == other.southWest &&
            northEast == other.northEast;
  }

  @override
  int get hashCode => Object.hash(southWest, northEast);
}

final class MapViewportPadding {
  const MapViewportPadding({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}
