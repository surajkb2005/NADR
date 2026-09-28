import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';

/// A provider-independent, validated place suggestion.
final class PlaceSearchResult {
  PlaceSearchResult({
    required String label,
    required GeoCoordinate coordinate,
    this.subtitle,
    this.providerId,
  }) : label = label.trim(),
       coordinate = coordinate {
    if (this.label.isEmpty ||
        !coordinate.latitude.isFinite ||
        coordinate.latitude < -90 ||
        coordinate.latitude > 90 ||
        !coordinate.longitude.isFinite ||
        coordinate.longitude < -180 ||
        coordinate.longitude > 180) {
      throw ArgumentError(
        'Place search result requires a label and valid coordinate.',
      );
    }
  }

  final String label;
  final String? subtitle;
  final String? providerId;
  final GeoCoordinate coordinate;

  Destination toDestination() =>
      Destination(coordinate: coordinate, displayLabel: label);
}
