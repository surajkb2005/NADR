import 'package:nadr_mobile/core/geo/geo_coordinate.dart';

final class Destination {
  const Destination({required this.coordinate, this.displayLabel});

  final GeoCoordinate coordinate;
  final String? displayLabel;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Destination &&
            coordinate == other.coordinate &&
            displayLabel == other.displayLabel;
  }

  @override
  int get hashCode => Object.hash(coordinate, displayLabel);
}
