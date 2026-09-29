import 'package:flutter_riverpod/flutter_riverpod.dart';

final appEnvironmentProvider = Provider<AppEnvironment>((ref) {
  throw StateError(
    'AppEnvironment must be supplied by the application bootstrap.',
  );
});

final class AppEnvironment {
  factory AppEnvironment({
    String apiBaseUrl = '',
    String wsBaseUrl = '',
    String placeSearchBaseUrl = 'https://api.maptiler.com',
    String mapTilerApiKey = '',
    required String mapStyleUrl,
  }) {
    final mapStyle = _parseOptionalUri(
      name: 'NADR_MAP_STYLE_URL',
      value: mapStyleUrl,
      allowedSchemes: const {'http', 'https'},
    );
    final placeSearch = _parseOptionalUri(
      name: 'NADR_PLACE_SEARCH_BASE_URL',
      value: placeSearchBaseUrl,
      allowedSchemes: const {'http', 'https'},
      requirePlainBase: true,
    );
    return AppEnvironment._(
      apiBaseUri: _parseConfiguredUri(
        name: 'NADR_API_BASE_URL',
        value: apiBaseUrl,
        allowedSchemes: const {'http', 'https'},
      ),
      wsBaseUri: _parseConfiguredUri(
        name: 'NADR_WS_BASE_URL',
        value: wsBaseUrl,
        allowedSchemes: const {'ws', 'wss'},
      ),
      mapStyleUri: mapStyle.uri,
      mapStyleConfigurationError: mapStyle.error,
      placeSearchBaseUri: placeSearch.uri,
      placeSearchConfigurationError: placeSearch.error,
      mapTilerApiKey: mapTilerApiKey.trim(),
    );
  }

  const AppEnvironment._({
    required this.apiBaseUri,
    required this.wsBaseUri,
    required this.mapStyleUri,
    required this.mapStyleConfigurationError,
    required this.placeSearchBaseUri,
    required this.placeSearchConfigurationError,
    required this.mapTilerApiKey,
  });

  factory AppEnvironment.fromDartDefines() {
    return AppEnvironment(
      apiBaseUrl: const String.fromEnvironment('NADR_API_BASE_URL'),
      wsBaseUrl: const String.fromEnvironment('NADR_WS_BASE_URL'),
      mapStyleUrl: const String.fromEnvironment('NADR_MAP_STYLE_URL'),
      placeSearchBaseUrl: const String.fromEnvironment(
        'NADR_PLACE_SEARCH_BASE_URL',
        defaultValue: 'https://api.maptiler.com',
      ),
      mapTilerApiKey: const String.fromEnvironment('NADR_MAPTILER_API_KEY'),
    );
  }

  final Uri? apiBaseUri;
  final Uri? wsBaseUri;
  final Uri? mapStyleUri;
  final String? mapStyleConfigurationError;
  final Uri? placeSearchBaseUri;
  final String? placeSearchConfigurationError;
  final String mapTilerApiKey;

  bool get isMapStyleConfigured => mapStyleUri != null;
  bool get isApiConfigured => apiBaseUri != null;

  List<String> get missingConfiguration => [
    if (!isApiConfigured) 'NADR_API_BASE_URL',
    if (!isMapStyleConfigured && mapStyleConfigurationError == null)
      'NADR_MAP_STYLE_URL',
  ];

  static _OptionalUriResult _parseOptionalUri({
    required String name,
    required String value,
    required Set<String> allowedSchemes,
    bool requirePlainBase = false,
  }) {
    if (value.trim().isEmpty) {
      return const _OptionalUriResult();
    }

    try {
      final uri = _parseUri(
        name: name,
        value: value,
        allowedSchemes: allowedSchemes,
      );
      if (requirePlainBase &&
          (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment)) {
        throw FormatException(
          '$name must not contain credentials, query, or fragment.',
        );
      }
      return _OptionalUriResult(uri: uri);
    } on FormatException catch (error) {
      return _OptionalUriResult(error: error.message.toString());
    }
  }

  static Uri? _parseConfiguredUri({
    required String name,
    required String value,
    required Set<String> allowedSchemes,
  }) {
    if (value.trim().isEmpty) {
      return null;
    }

    return _parseUri(name: name, value: value, allowedSchemes: allowedSchemes);
  }

  static Uri _parseUri({
    required String name,
    required String value,
    required Set<String> allowedSchemes,
  }) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        !allowedSchemes.contains(uri.scheme)) {
      throw FormatException(
        '$name must be an absolute URL using ${allowedSchemes.join(' or ')}.',
      );
    }

    return uri;
  }
}

final class _OptionalUriResult {
  const _OptionalUriResult({this.uri, this.error});

  final Uri? uri;
  final String? error;
}
