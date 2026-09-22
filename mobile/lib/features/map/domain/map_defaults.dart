import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/map/domain/map_camera.dart';

abstract final class MapDefaults {
  // The web app's existing Bengaluru demo coordinate. This is a camera target,
  // never a claim about the device's physical location.
  static const initialCamera = MapCameraState(
    center: GeoCoordinate(latitude: 12.9716, longitude: 77.5946),
    zoom: 13,
  );
}
