import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_repository.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_result.dart';
import 'package:nadr_mobile/features/destination/infrastructure/maptiler_place_search_repository.dart';

final placeSearchRepositoryProvider = Provider<PlaceSearchRepository>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  if (environment.placeSearchBaseUri != null &&
      environment.placeSearchConfigurationError == null &&
      environment.mapTilerApiKey.isNotEmpty) {
    final repository = MapTilerPlaceSearchRepository(
      baseUri: environment.placeSearchBaseUri!,
      apiKey: environment.mapTilerApiKey,
    );
    ref.onDispose(repository.dispose);
    return repository;
  }
  return UnconfiguredPlaceSearchRepository(
    configurationError:
        environment.placeSearchConfigurationError ??
        (environment.mapTilerApiKey.isEmpty
            ? 'NADR_MAPTILER_API_KEY is not configured.'
            : null),
    hasEndpoint: environment.placeSearchBaseUri != null,
  );
});

/// Controlled fallback when MapTiler search configuration is unavailable.
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
              ? 'MapTiler place search is not configured.'
              : 'NADR_PLACE_SEARCH_BASE_URL is not configured.'),
    );
  }
}
