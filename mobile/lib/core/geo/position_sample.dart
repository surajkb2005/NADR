import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';

final class PositionSample {
  const PositionSample({
    required this.coordinate,
    required this.timestamp,
    required this.source,
    this.heading,
    this.horizontalAccuracyMeters,
  });

  final GeoCoordinate coordinate;
  final double? heading;

  /// Android's measured horizontal accuracy radius, or null if unavailable.
  final double? horizontalAccuracyMeters;
  final DateTime timestamp;
  final PositionSource source;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PositionSample &&
            coordinate == other.coordinate &&
            heading == other.heading &&
            horizontalAccuracyMeters == other.horizontalAccuracyMeters &&
            timestamp == other.timestamp &&
            source == other.source;
  }

  @override
  int get hashCode => Object.hash(
    coordinate,
    heading,
    horizontalAccuracyMeters,
    timestamp,
    source,
  );
}
