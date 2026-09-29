import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_repository.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_result.dart';

/// MapTiler's forward geocoding contract. No credentials are logged or exposed
/// through user-facing exceptions.
final class MapTilerPlaceSearchRepository implements PlaceSearchRepository {
  MapTilerPlaceSearchRepository({
    required Uri baseUri,
    required String apiKey,
    Dio? dio,
  }) : // Keep the public parameter names while storing credentials privately.
       // ignore: prefer_initializing_formals
       _baseUri = baseUri,
       // ignore: prefer_initializing_formals
       _apiKey = apiKey,
       _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
    _dio.options.responseType = ResponseType.json;
    _dio.options.headers['Accept'] = Headers.jsonContentType;
  }

  final Uri _baseUri;
  final String _apiKey;
  final Dio _dio;

  void dispose() => _dio.close(force: true);

  @override
  Future<List<PlaceSearchResult>> search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    if (_apiKey.isEmpty) {
      throw const PlaceSearchException(
        PlaceSearchErrorKind.unconfigured,
        'NADR_MAPTILER_API_KEY is not configured.',
      );
    }
    final baseSegments = _baseUri.pathSegments.where((part) => part.isNotEmpty);
    final uri = _baseUri.replace(
      pathSegments: [...baseSegments, 'geocoding', '$normalized.json'],
      queryParameters: {'key': _apiKey, 'autocomplete': 'true', 'limit': '5'},
    );
    try {
      final response = await _dio.getUri<Object?>(uri);
      return _parse(response.data);
    } on DioException catch (error) {
      if (error.error is FormatException) {
        throw const PlaceSearchException(
          PlaceSearchErrorKind.invalidResponse,
          'MapTiler returned invalid place search data.',
        );
      }
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        throw const PlaceSearchException(
          PlaceSearchErrorKind.providerFailure,
          'MapTiler search key was rejected. Check search configuration.',
        );
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        throw const PlaceSearchException(
          PlaceSearchErrorKind.unavailable,
          'Place search timed out. Try again.',
        );
      }
      if (error.type == DioExceptionType.connectionError) {
        throw const PlaceSearchException(
          PlaceSearchErrorKind.unavailable,
          'Place search is offline. Check your connection.',
        );
      }
      throw const PlaceSearchException(
        PlaceSearchErrorKind.providerFailure,
        'MapTiler place search is unavailable. Try again.',
      );
    } on PlaceSearchException {
      rethrow;
    } on Object {
      throw const PlaceSearchException(
        PlaceSearchErrorKind.invalidResponse,
        'MapTiler returned invalid place search data.',
      );
    }
  }

  static List<PlaceSearchResult> _parse(Object? data) {
    final Object? decoded;
    if (data is String) {
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        throw const PlaceSearchException(
          PlaceSearchErrorKind.invalidResponse,
          'MapTiler returned invalid place search data.',
        );
      }
    } else {
      decoded = data;
    }
    if (decoded is! Map ||
        decoded['type'] != 'FeatureCollection' ||
        decoded['features'] is! List) {
      throw const PlaceSearchException(
        PlaceSearchErrorKind.invalidResponse,
        'MapTiler returned invalid place search data.',
      );
    }
    final results = <PlaceSearchResult>[];
    for (final feature in decoded['features'] as List) {
      final result = _parseFeature(feature);
      if (result != null) results.add(result);
    }
    return results;
  }

  static PlaceSearchResult? _parseFeature(Object? raw) {
    if (raw is! Map || raw['type'] != 'Feature') return null;
    final text = _nonblank(raw['text']);
    final placeName = _nonblank(raw['place_name']);
    final label = text ?? placeName;
    if (label == null) return null;

    Object? coordinates;
    final geometry = raw['geometry'];
    if (geometry is Map && geometry['type'] == 'Point') {
      coordinates = geometry['coordinates'];
    } else {
      coordinates = raw['center'];
    }
    if (coordinates is! List || coordinates.length < 2) return null;
    final longitude = coordinates[0];
    final latitude = coordinates[1];
    if (longitude is! num || latitude is! num) return null;
    final lon = longitude.toDouble();
    final lat = latitude.toDouble();
    if (!lon.isFinite ||
        !lat.isFinite ||
        lon < -180 ||
        lon > 180 ||
        lat < -90 ||
        lat > 90) {
      return null;
    }

    final subtitle = placeName != null && placeName != label
        ? placeName
        : _nonblank(raw['address']);
    return PlaceSearchResult(
      label: label,
      subtitle: subtitle,
      providerId: _nonblank(raw['id']),
      coordinate: GeoCoordinate(latitude: lat, longitude: lon),
    );
  }

  static String? _nonblank(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
