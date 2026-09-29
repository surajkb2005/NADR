import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/network/api_models.dart';
import 'package:nadr_mobile/core/network/nadr_rest_client.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/features/routing/domain/route_repository.dart';

final routeRepositoryProvider = FutureProvider<RouteRepository>((ref) async {
  final client = await ref.watch(nadrRestClientProvider.future);
  return RestRouteRepository(client);
});

final class RestRouteRepository implements RouteRepository {
  const RestRouteRepository(this._client);

  final NadrRestClient _client;

  @override
  Future<RouteAlternatives> calculateRoute({
    required GeoCoordinate start,
    required GeoCoordinate end,
    RouteMode mode = RouteMode.normal,
  }) async {
    final response = await _client.calculateRoute(
      start: [start.latitude, start.longitude],
      end: [end.latitude, end.longitude],
      mode: _requestMode(mode),
    );
    return _toDomain(response);
  }

  static RouteAlternatives _toDomain(ApiRouteResponse response) {
    final alternatives = <RouteMode, RouteAlternative>{};
    var invalidAlternatives = response.invalidAlternatives;
    var fallbackAlternatives = 0;
    for (final entry in response.alternatives.entries) {
      final mode = _responseMode(entry.key);
      if (mode == null) continue;
      try {
        final alternative = _alternative(mode, entry.value);
        if (alternative.isBackendFallback) {
          fallbackAlternatives++;
        } else if (alternative.hasUsableGeometry) {
          alternatives[mode] = alternative;
        } else {
          invalidAlternatives++;
        }
      } on NadrNetworkException {
        invalidAlternatives++;
      }
    }
    if (alternatives.isEmpty) {
      if (fallbackAlternatives > 0 && invalidAlternatives == 0) {
        throw const NadrNetworkException(
          NadrNetworkErrorKind.fallbackRoute,
          'Backend returned only straight-line fallback routes.',
        );
      }
      if (invalidAlternatives > 0) {
        throw const NadrNetworkException(
          NadrNetworkErrorKind.invalidResponse,
          'Backend returned unusable route geometry.',
        );
      }
      throw const NadrNetworkException(
        NadrNetworkErrorKind.noRoute,
        'Backend returned no route alternatives.',
      );
    }

    final metadata = response.metadata;
    return RouteAlternatives(
      byMode: alternatives,
      metadata: metadata == null
          ? null
          : RouteMetadata(
              start: _optionalCoordinate(metadata.start),
              end: _optionalCoordinate(metadata.end),
              source: metadata.source,
              kpIndex: metadata.kpIndex,
            ),
    );
  }

  static RouteAlternative _alternative(
    RouteMode mode,
    ApiRouteVariant variant,
  ) {
    final segments = variant.riskSegments;
    return RouteAlternative(
      mode: mode,
      path: [for (final pair in variant.path) _coordinate(pair)],
      metrics: RouteMetrics(
        distanceMeters: variant.distanceMeters,
        estimatedTimeSeconds: variant.estimatedTimeSeconds,
        totalRiskScore: variant.totalRiskScore,
        maximumRiskZone: _riskZone(variant.maxRiskZone),
        averageRisk: variant.averageRisk,
        riskSegments: segments == null
            ? null
            : RiskSegmentCounts(
                low: segments['low'] ?? 0,
                medium: segments['medium'] ?? 0,
                high: segments['high'] ?? 0,
              ),
      ),
      optimization: variant.optimization,
      riskWeight: variant.riskWeight,
      description: variant.description,
    );
  }

  static GeoCoordinate _coordinate(List<double> pair) {
    final latitude = pair[0];
    final longitude = pair[1];
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const NadrNetworkException(
        NadrNetworkErrorKind.invalidResponse,
        'Backend returned an invalid route coordinate.',
      );
    }
    return GeoCoordinate(latitude: latitude, longitude: longitude);
  }

  static GeoCoordinate? _optionalCoordinate(List<double>? pair) =>
      pair == null ? null : _coordinate(pair);

  static String _requestMode(RouteMode mode) => switch (mode) {
    RouteMode.safe => 'safe',
    _ => 'normal',
  };

  static RouteMode? _responseMode(String value) => switch (value) {
    'normal' => RouteMode.normal,
    'safe' => RouteMode.safe,
    'drifted' => RouteMode.drifted,
    'imu' => RouteMode.imu,
    _ => null,
  };

  static RiskZone? _riskZone(String? value) => switch (value) {
    'low' => RiskZone.low,
    'medium' => RiskZone.medium,
    'high' => RiskZone.high,
    _ => null,
  };
}
