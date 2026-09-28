import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_repository.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_result.dart';

final placeSearchRepositoryProvider = Provider<PlaceSearchRepository>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  return UnconfiguredPlaceSearchRepository(
    configurationError: environment.placeSearchConfigurationError,
    hasEndpoint: environment.placeSearchBaseUri != null,
  );
});

/// Controlled placeholder until the project's search provider contract is chosen.
final class UnconfiguredPlaceSearchRepository implements PlaceSearchRepository {
  const UnconfiguredPlaceSearchRepository({
    this.configurationError,
    this.hasEndpoint = false,
  });

  final String? configurationError;
  final bool hasEndpoint;

  @override
  Future<List<PlaceSearchResult>> search(String query) async {
    throw PlaceSearchException(
      PlaceSearchErrorKind.unconfigured,
      configurationError ??
          (hasEndpoint
              ? 'Place search provider adapter is not configured.'
              : 'Place search provider and NADR_PLACE_SEARCH_BASE_URL are not configured.'),
    );
  }
}
