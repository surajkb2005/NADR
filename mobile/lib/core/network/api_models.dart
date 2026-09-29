/// DTOs for the existing FastAPI JSON shapes. Coordinates follow each
/// endpoint's wire order: routes use [latitude, longitude], GeoJSON uses
/// [longitude, latitude]. These DTOs are deliberately independent of the UI.
final class ApiDecodingException implements Exception {
  const ApiDecodingException(this.path, this.expected);

  final String path;
  final String expected;

  @override
  String toString() => 'Invalid backend response at $path: expected $expected.';
}

typedef ApiJson = Map<String, dynamic>;

ApiJson apiObject(Object? value, String path) {
  if (value is Map && value.keys.every((key) => key is String)) {
    return Map<String, dynamic>.from(value);
  }
  throw ApiDecodingException(path, 'object');
}

String apiString(Object? value, String path) {
  if (value is String) return value;
  throw ApiDecodingException(path, 'string');
}

double apiNumber(Object? value, String path) {
  if (value is num && value.isFinite) return value.toDouble();
  throw ApiDecodingException(path, 'finite number');
}

bool apiBool(Object? value, String path) {
  if (value is bool) return value;
  throw ApiDecodingException(path, 'boolean');
}

List<dynamic> apiList(Object? value, String path) {
  if (value is List) return value;
  throw ApiDecodingException(path, 'array');
}

DateTime apiDateTime(Object? value, String path) {
  final raw = apiString(value, path);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw ApiDecodingException(path, 'ISO timestamp');
  return parsed;
}

/// Pair order is retained exactly as received; no implicit coordinate swap.
List<double> apiPair(Object? value, String path) {
  final list = apiList(value, path);
  if (list.length != 2) throw ApiDecodingException(path, 'two coordinates');
  return [apiNumber(list[0], '$path[0]'), apiNumber(list[1], '$path[1]')];
}

final class ApiRootResponse {
  const ApiRootResponse({required this.message, required this.status});
  final String message;
  final String status;

  factory ApiRootResponse.fromJson(Object? value) {
    final json = apiObject(value, r'$');
    return ApiRootResponse(
      message: apiString(json['message'], r'$.message'),
      status: apiString(json['status'], r'$.status'),
    );
  }
}

final class ApiHealthResponse {
  const ApiHealthResponse({
    required this.status,
    required this.timestamp,
    required this.services,
  });
  final String status;
  final DateTime timestamp;
  final Map<String, bool> services;

  factory ApiHealthResponse.fromJson(Object? value) {
    final json = apiObject(value, r'$');
    final rawServices = apiObject(json['services'], r'$.services');
    return ApiHealthResponse(
      status: apiString(json['status'], r'$.status'),
      timestamp: apiDateTime(json['timestamp'], r'$.timestamp'),
      services: {
        for (final entry in rawServices.entries)
          entry.key: apiBool(entry.value, r'$.services.' + entry.key),
      },
    );
  }
}

final class ApiRouteVariant {
  const ApiRouteVariant({
    required this.path,
    this.distanceMeters,
    this.estimatedTimeSeconds,
    this.totalRiskScore,
    this.maxRiskZone,
    this.averageRisk,
    this.riskSegments,
    this.optimization,
    this.riskWeight,
    this.description,
  });

  /// Backend route path order: [latitude, longitude].
  final List<List<double>> path;
  final double? distanceMeters;
  final double? estimatedTimeSeconds;
  final double? totalRiskScore;
  final String? maxRiskZone;
  final double? averageRisk;
  final Map<String, int>? riskSegments;
  final String? optimization;
  final double? riskWeight;
  final String? description;

  factory ApiRouteVariant.fromJson(Object? value, String path) {
    final json = apiObject(value, path);
    final rawPath = apiList(json['path'], '$path.path');
    final rawSegments = json['risk_segments'];
    final segments = rawSegments == null
        ? null
        : apiObject(rawSegments, '$path.risk_segments');
    return ApiRouteVariant(
      path: [
        for (var i = 0; i < rawPath.length; i++)
          apiPair(rawPath[i], '$path.path[$i]'),
      ],
      distanceMeters: _optionalNumber(json, 'distance_m', path),
      estimatedTimeSeconds: _optionalNumber(json, 'estimated_time_s', path),
      totalRiskScore: _optionalNumber(json, 'total_risk_score', path),
      maxRiskZone: _optionalString(json, 'max_risk_zone', path),
      averageRisk: _optionalNumber(json, 'avg_risk', path),
      riskSegments: segments == null
          ? null
          : {
              for (final entry in segments.entries)
                entry.key: _nonnegativeInt(
                  entry.value,
                  '$path.risk_segments.${entry.key}',
                ),
            },
      optimization: _optionalString(json, 'optimization', path),
      riskWeight: _optionalNumber(json, 'risk_weight', path),
      description: _optionalString(json, 'description', path),
    );
  }
}

final class ApiRouteMetadata {
  const ApiRouteMetadata({this.start, this.end, this.source, this.kpIndex});
  final List<double>? start;
  final List<double>? end;
  final String? source;
  final double? kpIndex;

  factory ApiRouteMetadata.fromJson(Object? value) {
    final json = apiObject(value, r'$.metadata');
    return ApiRouteMetadata(
      start: json['start'] == null
          ? null
          : apiPair(json['start'], r'$.metadata.start'),
      end: json['end'] == null ? null : apiPair(json['end'], r'$.metadata.end'),
      source: _optionalString(json, 'source', r'$.metadata'),
      kpIndex: _optionalNumber(json, 'kp_index', r'$.metadata'),
    );
  }
}

final class ApiRouteResponse {
  const ApiRouteResponse({
    required this.alternatives,
    this.route,
    this.metadata,
    this.invalidAlternatives = 0,
  });
  final Map<String, ApiRouteVariant> alternatives;
  final ApiRouteVariant? route;
  final ApiRouteMetadata? metadata;
  final int invalidAlternatives;

  factory ApiRouteResponse.fromJson(Object? value) {
    final json = apiObject(value, r'$');
    if (json['alternatives'] == null && json['route'] == null) {
      throw const ApiDecodingException(r'$', 'route or alternatives');
    }
    final rawAlternatives = json['alternatives'] == null
        ? <String, dynamic>{}
        : apiObject(json['alternatives'], r'$.alternatives');
    final alternatives = <String, ApiRouteVariant>{};
    var invalidAlternatives = 0;
    for (final entry in rawAlternatives.entries) {
      if (!const {'normal', 'safe', 'drifted', 'imu'}.contains(entry.key)) {
        continue;
      }
      try {
        alternatives[entry.key] = ApiRouteVariant.fromJson(
          entry.value,
          r'$.alternatives.' + entry.key,
        );
      } on ApiDecodingException {
        invalidAlternatives++;
      }
    }
    return ApiRouteResponse(
      alternatives: alternatives,
      invalidAlternatives: invalidAlternatives,
      route: json['route'] == null
          ? null
          : ApiRouteVariant.fromJson(json['route'], r'$.route'),
      metadata: json['metadata'] == null
          ? null
          : ApiRouteMetadata.fromJson(json['metadata']),
    );
  }
}

final class ApiSpaceWeatherResponse {
  const ApiSpaceWeatherResponse({
    required this.timestamp,
    required this.kpIndex,
    required this.riskLevel,
    required this.estimatedGpsErrorMeters,
    required this.alerts,
    required this.source,
    this.solarWindSpeed,
    this.solarWindDensity,
  });
  final DateTime timestamp;
  final double kpIndex;
  final double? solarWindSpeed;
  final double? solarWindDensity;
  final String riskLevel;
  final List<double> estimatedGpsErrorMeters;
  final List<String> alerts;
  final String source;

  factory ApiSpaceWeatherResponse.fromJson(Object? value) {
    final json = apiObject(value, r'$');
    final alerts = apiList(json['alerts'], r'$.alerts');
    return ApiSpaceWeatherResponse(
      timestamp: apiDateTime(json['timestamp'], r'$.timestamp'),
      kpIndex: apiNumber(json['kp_index'], r'$.kp_index'),
      solarWindSpeed: _optionalNumber(json, 'solar_wind_speed', r'$'),
      solarWindDensity: _optionalNumber(json, 'solar_wind_density', r'$'),
      riskLevel: apiString(json['risk_level'], r'$.risk_level'),
      estimatedGpsErrorMeters: apiPair(
        json['estimated_gps_error_m'],
        r'$.estimated_gps_error_m',
      ),
      alerts: [
        for (var i = 0; i < alerts.length; i++)
          apiString(alerts[i], '\$.alerts[$i]'),
      ],
      source: apiString(json['source'], r'$.source'),
    );
  }
}

final class ApiHeatmapFeature {
  const ApiHeatmapFeature({required this.rings, required this.properties});

  /// GeoJSON ring positions are [longitude, latitude].
  final List<List<List<double>>> rings;
  final ApiHeatmapProperties properties;

  factory ApiHeatmapFeature.fromJson(Object? value, String path) {
    final json = apiObject(value, path);
    if (apiString(json['type'], '$path.type') != 'Feature') {
      throw ApiDecodingException('$path.type', 'Feature');
    }
    final geometry = apiObject(json['geometry'], '$path.geometry');
    if (apiString(geometry['type'], '$path.geometry.type') != 'Polygon') {
      throw ApiDecodingException('$path.geometry.type', 'Polygon');
    }
    final rawRings = apiList(
      geometry['coordinates'],
      '$path.geometry.coordinates',
    );
    return ApiHeatmapFeature(
      rings: [
        for (var i = 0; i < rawRings.length; i++)
          [
            for (
              var j = 0;
              j < apiList(rawRings[i], '$path.geometry.coordinates[$i]').length;
              j++
            )
              apiPair(
                apiList(rawRings[i], '$path.geometry.coordinates[$i]')[j],
                '$path.geometry.coordinates[$i][$j]',
              ),
          ],
      ],
      properties: ApiHeatmapProperties.fromJson(
        json['properties'],
        '$path.properties',
      ),
    );
  }
}

final class ApiHeatmapProperties {
  const ApiHeatmapProperties({
    required this.riskLevel,
    required this.riskScore,
    required this.color,
    required this.opacity,
    required this.center,
    required this.gpsErrorMin,
    required this.gpsErrorMax,
  });

  final String riskLevel;
  final double riskScore;
  final String color;
  final double opacity;

  /// GeoJSON property order: [longitude, latitude].
  final List<double> center;
  final double gpsErrorMin;
  final double gpsErrorMax;

  factory ApiHeatmapProperties.fromJson(Object? value, String path) {
    final json = apiObject(value, path);
    return ApiHeatmapProperties(
      riskLevel: apiString(json['risk_level'], '$path.risk_level'),
      riskScore: apiNumber(json['risk_score'], '$path.risk_score'),
      color: apiString(json['color'], '$path.color'),
      opacity: apiNumber(json['opacity'], '$path.opacity'),
      center: apiPair(json['center'], '$path.center'),
      gpsErrorMin: apiNumber(json['gps_error_min'], '$path.gps_error_min'),
      gpsErrorMax: apiNumber(json['gps_error_max'], '$path.gps_error_max'),
    );
  }
}

final class ApiHeatmapResponse {
  const ApiHeatmapResponse({required this.features, required this.metadata});
  final List<ApiHeatmapFeature> features;
  final ApiHeatmapMetadata metadata;

  factory ApiHeatmapResponse.fromJson(Object? value) {
    final json = apiObject(value, r'$');
    if (apiString(json['type'], r'$.type') != 'FeatureCollection') {
      throw const ApiDecodingException(r'$.type', 'FeatureCollection');
    }
    final rawFeatures = apiList(json['features'], r'$.features');
    return ApiHeatmapResponse(
      features: [
        for (var i = 0; i < rawFeatures.length; i++)
          ApiHeatmapFeature.fromJson(rawFeatures[i], '\$.features[$i]'),
      ],
      metadata: ApiHeatmapMetadata.fromJson(json['metadata']),
    );
  }
}

final class ApiHeatmapMetadata {
  const ApiHeatmapMetadata({
    required this.bbox,
    required this.resolution,
    required this.gridSize,
    required this.kpIndex,
  });

  /// [minimum longitude, minimum latitude, maximum longitude, maximum latitude].
  final List<double> bbox;
  final double resolution;
  final String gridSize;
  final double kpIndex;

  factory ApiHeatmapMetadata.fromJson(Object? value) {
    final json = apiObject(value, r'$.metadata');
    final rawBbox = apiList(json['bbox'], r'$.metadata.bbox');
    if (rawBbox.length != 4) {
      throw const ApiDecodingException(r'$.metadata.bbox', 'four coordinates');
    }
    return ApiHeatmapMetadata(
      bbox: [
        for (var i = 0; i < 4; i++)
          apiNumber(rawBbox[i], '\$.metadata.bbox[$i]'),
      ],
      resolution: apiNumber(json['resolution'], r'$.metadata.resolution'),
      gridSize: apiString(json['grid_size'], r'$.metadata.grid_size'),
      kpIndex: apiNumber(json['kp_index'], r'$.metadata.kp_index'),
    );
  }
}

final class ApiMessageResponse {
  const ApiMessageResponse(this.message);
  final String message;
  factory ApiMessageResponse.fromJson(Object? value) {
    final json = apiObject(value, r'$');
    return ApiMessageResponse(apiString(json['message'], r'$.message'));
  }
}

final class ApiLoginResponse {
  const ApiLoginResponse({required this.message, required this.userEmail});
  final String message;
  final String userEmail;
  factory ApiLoginResponse.fromJson(Object? value) {
    final json = apiObject(value, r'$');
    return ApiLoginResponse(
      message: apiString(json['message'], r'$.message'),
      userEmail: apiString(json['user_email'], r'$.user_email'),
    );
  }
}

final class ApiAuthStatusResponse {
  const ApiAuthStatusResponse({required this.status, required this.userEmail});
  final String status;
  final String userEmail;
  factory ApiAuthStatusResponse.fromJson(Object? value) {
    final json = apiObject(value, r'$');
    return ApiAuthStatusResponse(
      status: apiString(json['status'], r'$.status'),
      userEmail: apiString(json['user_email'], r'$.user_email'),
    );
  }
}

double? _optionalNumber(ApiJson json, String key, String path) =>
    json[key] == null ? null : apiNumber(json[key], '$path.$key');

String? _optionalString(ApiJson json, String key, String path) =>
    json[key] == null ? null : apiString(json[key], '$path.$key');

int _nonnegativeInt(Object? value, String path) {
  if (value is int && value >= 0) return value;
  throw ApiDecodingException(path, 'non-negative integer');
}
