import 'package:nadr_mobile/features/destination/domain/place_search_result.dart';

enum PlaceSearchErrorKind {
  unconfigured,
  unavailable,
  invalidResponse,
  providerFailure,
}

final class PlaceSearchException implements Exception {
  const PlaceSearchException(this.kind, this.message);

  final PlaceSearchErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

abstract interface class PlaceSearchRepository {
  Future<List<PlaceSearchResult>> search(String query);
}
