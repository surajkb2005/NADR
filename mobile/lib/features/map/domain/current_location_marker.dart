import 'package:nadr_mobile/core/geo/geo_coordinate.dart';

enum CurrentLocationVisualMode { gps, imu }

final class CurrentLocationMarkerData {
  const CurrentLocationMarkerData({
    required this.coordinate,
    required this.visualMode,
    this.heading,
  });

  final GeoCoordinate coordinate;
  final CurrentLocationVisualMode visualMode;
  final double? heading;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CurrentLocationMarkerData &&
            coordinate == other.coordinate &&
            visualMode == other.visualMode &&
            heading == other.heading;
  }

  @override
  int get hashCode => Object.hash(coordinate, visualMode, heading);
}
