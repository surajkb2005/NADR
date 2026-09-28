import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/network/api_models.dart';

void main() {
  test('root and health match FastAPI response construction', () {
    final root = ApiRootResponse.fromJson({
      'message': 'NADR API v2.0',
      'status': 'operational',
      'future_flag': true,
    });
    expect(root.status, 'operational');
    final health = ApiHealthResponse.fromJson({
      'status': 'degraded',
      'timestamp': '2026-01-01T00:00:00',
      'services': {'cache': true, 'redis': true, 'noaa': false},
    });
    expect(health.services['noaa'], isFalse);
    expect(
      () => ApiHealthResponse.fromJson({
        'status': 'healthy',
        'timestamp': 'not-a-date',
        'services': {'cache': true},
      }),
      throwsA(isA<ApiDecodingException>()),
    );
  });

  test('actual router alternatives retain lat/lon path and metadata', () {
    final route = ApiRouteResponse.fromJson({
      'alternatives': {
        'normal': {
          'path': [
            [1.0, 2.0],
            [1.1, 2.1],
          ],
          'distance_m': 150.0,
          'estimated_time_s': 10.0,
          'total_risk_score': 12.0,
          'max_risk_zone': 'low',
          'avg_risk': 0.12,
          'risk_segments': {'low': 2, 'medium': 0, 'high': 0},
          'optimization': 'fastest_road',
          'risk_weight': 0.0,
          'future_metric': 7,
        },
        'safe': {'path': <Object>[], 'optimization': 'fallback'},
      },
      'metadata': {
        'start': [1, 2],
        'end': [1.1, 2.1],
        'source': 'OSRM Public API',
        'kp_index': 2.0,
      },
    });
    expect(route.alternatives['normal']!.path.first, [1, 2]);
    expect(route.alternatives['normal']!.riskSegments!['low'], 2);
    expect(route.alternatives['safe']!.path, isEmpty);
    expect(route.alternatives['safe']!.distanceMeters, isNull);
    expect(route.metadata!.source, 'OSRM Public API');
    final malformed = ApiRouteResponse.fromJson({
      'alternatives': {
        'normal': {
          'path': [
            [1.0],
          ],
        },
      },
    });
    expect(malformed.alternatives, isEmpty);
    expect(malformed.invalidAlternatives, 1);
    expect(
      () => ApiRouteResponse.fromJson({'metadata': {}}),
      throwsA(isA<ApiDecodingException>()),
    );
  });

  test('space weather preserves nullable values and error pair', () {
    final weather = ApiSpaceWeatherResponse.fromJson({
      'timestamp': '2026-01-01T00:00:00Z',
      'kp_index': 2.0,
      'solar_wind_speed': null,
      'solar_wind_density': null,
      'risk_level': 'low',
      'estimated_gps_error_m': [5.0, 15.0],
      'alerts': <String>[],
      'source': 'FALLBACK',
      'future_field': 'ignored',
    });
    expect(weather.solarWindSpeed, isNull);
    expect(weather.estimatedGpsErrorMeters, [5, 15]);
    expect(weather.alerts, isEmpty);
    expect(
      () => ApiSpaceWeatherResponse.fromJson({
        'timestamp': '2026-01-01T00:00:00Z',
        'kp_index': 'invalid',
        'risk_level': 'low',
        'estimated_gps_error_m': [5.0, 15.0],
        'alerts': <String>[],
        'source': 'NOAA',
      }),
      throwsA(isA<ApiDecodingException>()),
    );
  });

  test('heatmap GeoJSON keeps longitude first and accepts empty features', () {
    final heatmap = ApiHeatmapResponse.fromJson({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [2.0, 1.0],
                [2.0, 1.1],
                [2.1, 1.1],
                [2.0, 1.0],
              ],
            ],
          },
          'properties': {
            'risk_level': 'low',
            'risk_score': 12.0,
            'color': '#4CAF50',
            'opacity': 0.1,
            'center': [2.05, 1.05],
            'gps_error_min': 5.0,
            'gps_error_max': 15.0,
            'future_property': true,
          },
        },
      ],
      'metadata': {
        'bbox': [2.0, 1.0, 2.1, 1.1],
        'resolution': 0.05,
        'grid_size': '1x1',
        'kp_index': 2.0,
      },
    });
    expect(heatmap.features.single.rings.first.first, [2, 1]);
    expect(heatmap.features.single.properties.center, [2.05, 1.05]);
    expect(heatmap.metadata.bbox, [2, 1, 2.1, 1.1]);
    final empty = ApiHeatmapResponse.fromJson({
      'type': 'FeatureCollection',
      'features': <Object>[],
      'metadata': {
        'bbox': [2.0, 1.0, 2.1, 1.1],
        'resolution': 0.05,
        'grid_size': '0x0',
        'kp_index': 2.0,
      },
    });
    expect(empty.features, isEmpty);
    expect(
      () => ApiHeatmapResponse.fromJson({
        'type': 'FeatureCollection',
        'features': <Object>[],
        'metadata': {
          'bbox': [1, 2],
        },
      }),
      throwsA(isA<ApiDecodingException>()),
    );
  });

  test('authentication responses match current backend fields', () {
    expect(
      ApiMessageResponse.fromJson({'message': 'OTP sent successfully.'})
          .message,
      'OTP sent successfully.',
    );
    expect(
      ApiLoginResponse.fromJson({
        'message': 'Login successful.',
        'user_email': 'test@example.test',
      }).userEmail,
      'test@example.test',
    );
    expect(
      ApiAuthStatusResponse.fromJson({
        'status': 'authenticated',
        'user_email': 'test@example.test',
      }).status,
      'authenticated',
    );
  });
}
