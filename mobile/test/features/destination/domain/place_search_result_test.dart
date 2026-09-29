import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_result.dart';

void main() {
  test('valid result maps exact label and coordinate to Destination', () {
    const coordinate = GeoCoordinate(latitude: 12.97, longitude: 77.59);
    final result = PlaceSearchResult(label: 'MG Road', coordinate: coordinate);
    final destination = result.toDestination();
    expect(destination.coordinate, coordinate);
    expect(destination.displayLabel, 'MG Road');
    expect(result.subtitle, isNull);
    expect(result.providerId, isNull);
  });

  test('invalid provider coordinates and blank label are rejected', () {
    expect(
      () => PlaceSearchResult(
        label: 'Place',
        coordinate: GeoCoordinate(latitude: double.nan, longitude: 77),
      ),
      throwsA(anyOf(isA<ArgumentError>(), isA<AssertionError>())),
    );
    expect(
      () => PlaceSearchResult(
        label: 'Place',
        coordinate: GeoCoordinate(latitude: 12, longitude: double.infinity),
      ),
      throwsA(anyOf(isA<ArgumentError>(), isA<AssertionError>())),
    );
    expect(
      () => PlaceSearchResult(
        label: ' ',
        coordinate: const GeoCoordinate(latitude: 12, longitude: 77),
      ),
      throwsArgumentError,
    );
  });

  test('out-of-range coordinates are rejected in all build modes', () {
    expect(
      () => PlaceSearchResult(
        label: 'Place',
        coordinate: GeoCoordinate(latitude: 91, longitude: 77),
      ),
      throwsA(anyOf(isA<ArgumentError>(), isA<AssertionError>())),
    );
    expect(
      () => PlaceSearchResult(
        label: 'Place',
        coordinate: GeoCoordinate(latitude: 12, longitude: 181),
      ),
      throwsA(anyOf(isA<ArgumentError>(), isA<AssertionError>())),
    );
  });
}
