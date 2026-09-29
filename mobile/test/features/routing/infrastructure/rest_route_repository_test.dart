import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/network/nadr_rest_client.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/features/routing/infrastructure/rest_route_repository.dart';

void main() {
  test(
    'POST /route uses exact lat-lon request and decodes alternatives',
    () async {
      final adapter = _SingleReplyAdapter({
        'alternatives': {
          'normal': _variant('fastest_road', riskWeight: 0),
          'safe': _variant('safe_road', riskWeight: 1),
          'drifted': {
            ..._variant('gps_error_simulation'),
            'description': 'Simulated GPS path',
          },
          'imu': _variant('fastest_road'),
          'future_alternative': _variant('future'),
        },
        'metadata': {
          'start': [12.1, 77.2],
          'end': [12.3, 77.4],
          'source': 'OSRM Public API',
          'kp_index': 2,
          'future_metadata': true,
        },
        'future_top_level': 'ignored',
      });
      final client = NadrRestClient(
        baseUri: Uri.parse('https://example.test/api'),
        cookieJar: CookieJar(),
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(client.dispose);
      final repository = RestRouteRepository(client);

      final result = await repository.calculateRoute(
        start: const GeoCoordinate(latitude: 12.1, longitude: 77.2),
        end: const GeoCoordinate(latitude: 12.3, longitude: 77.4),
      );

      expect(adapter.request!.method, 'POST');
      expect(adapter.request!.uri.path, '/api/route');
      expect(adapter.request!.data, {
        'start': [12.1, 77.2],
        'end': [12.3, 77.4],
        'mode': 'normal',
      });
      expect(result.byMode.keys, {
        RouteMode.normal,
        RouteMode.safe,
        RouteMode.drifted,
        RouteMode.imu,
      });
      expect(result[RouteMode.normal]!.path.first.latitude, 12.1);
      expect(result[RouteMode.normal]!.path.first.longitude, 77.2);
      expect(result[RouteMode.normal]!.metrics.distanceMeters, 1234.5);
      expect(result[RouteMode.normal]!.metrics.estimatedTimeSeconds, 82.3);
      expect(result[RouteMode.normal]!.metrics.totalRiskScore, 18.5);
      expect(
        result[RouteMode.normal]!.metrics.maximumRiskZone,
        RiskZone.medium,
      );
      expect(result[RouteMode.normal]!.metrics.averageRisk, 0.185);
      expect(result[RouteMode.normal]!.metrics.riskSegments!.low, 2);
      expect(result[RouteMode.safe]!.riskWeight, 1);
      expect(result[RouteMode.drifted]!.description, 'Simulated GPS path');
      expect(result.metadata!.source, 'OSRM Public API');
      expect(result.metadata!.kpIndex, 2);
    },
  );

  test('safe mode is the only non-normal request mode', () async {
    final adapter = _SingleReplyAdapter({
      'alternatives': {'safe': _variant('safe_road')},
    });
    final client = NadrRestClient(
      baseUri: Uri.parse('https://example.test'),
      cookieJar: CookieJar(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(client.dispose);

    await RestRouteRepository(client).calculateRoute(
      start: const GeoCoordinate(latitude: 1, longitude: 2),
      end: const GeoCoordinate(latitude: 3, longitude: 4),
      mode: RouteMode.safe,
    );

    expect((adapter.request!.data as Map)['mode'], 'safe');
  });

  test('missing optional metadata remains absent', () async {
    final adapter = _SingleReplyAdapter({
      'alternatives': {
        'normal': {
          'path': [
            [1, 2],
            [3, 4],
          ],
        },
      },
    });
    final client = NadrRestClient(
      baseUri: Uri.parse('https://example.test'),
      cookieJar: CookieJar(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(client.dispose);

    final result = await RestRouteRepository(client).calculateRoute(
      start: const GeoCoordinate(latitude: 1, longitude: 2),
      end: const GeoCoordinate(latitude: 3, longitude: 4),
    );

    expect(result.metadata, isNull);
    expect(result[RouteMode.normal]!.metrics.distanceMeters, isNull);
    expect(result[RouteMode.normal]!.optimization, isNull);
  });

  test('empty alternatives are reported as no route', () async {
    final adapter = _SingleReplyAdapter({'alternatives': <String, Object>{}});
    final client = NadrRestClient(
      baseUri: Uri.parse('https://example.test'),
      cookieJar: CookieJar(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(client.dispose);

    expect(
      () => RestRouteRepository(client).calculateRoute(
        start: const GeoCoordinate(latitude: 1, longitude: 2),
        end: const GeoCoordinate(latitude: 3, longitude: 4),
      ),
      throwsA(
        isA<NadrNetworkException>().having(
          (error) => error.kind,
          'kind',
          NadrNetworkErrorKind.noRoute,
        ),
      ),
    );
  });

  test('malformed and out-of-range route coordinates are rejected', () async {
    for (final path in [
      [
        [1],
      ],
      [
        [91, 2],
      ],
    ]) {
      final adapter = _SingleReplyAdapter({
        'alternatives': {
          'normal': {'path': path},
        },
      });
      final client = NadrRestClient(
        baseUri: Uri.parse('https://example.test'),
        cookieJar: CookieJar(),
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(client.dispose);
      expect(
        () => RestRouteRepository(client).calculateRoute(
          start: const GeoCoordinate(latitude: 1, longitude: 2),
          end: const GeoCoordinate(latitude: 3, longitude: 4),
        ),
        throwsA(isA<NadrNetworkException>()),
      );
    }
  });

  test('valid alternatives survive malformed and fallback siblings', () async {
    final result = await _response({
      'alternatives': {
        'normal': {
          'path': [
            [1, 2],
            [91, 3],
          ],
        },
        'safe': {
          'path': [
            [1, 2],
            [2, 3],
            [3, 4],
          ],
          'optimization': 'safe_road',
        },
        'drifted': {
          'path': [
            [1],
            [2, 3],
          ],
        },
        'imu': {
          'path': [
            [1, 2],
            [3, 4],
          ],
          'optimization': 'fallback',
        },
      },
    });
    expect(result.byMode.keys, {RouteMode.safe});
    expect(result[RouteMode.safe]!.path, [
      const GeoCoordinate(latitude: 1, longitude: 2),
      const GeoCoordinate(latitude: 2, longitude: 3),
      const GeoCoordinate(latitude: 3, longitude: 4),
    ]);
  });

  test(
    'empty, one-point, repeated, and invalid paths cannot be routes',
    () async {
      for (final path in [
        <Object>[],
        <Object>[
          [1, 2],
        ],
        <Object>[
          [1, 2],
          [1, 2],
        ],
        <Object>[
          [1, 181],
          [2, 3],
        ],
        <Object>[
          [1, 'bad'],
          [2, 3],
        ],
        <Object>[
          [1, null],
          [2, 3],
        ],
      ]) {
        await expectLater(
          _response({
            'alternatives': {
              'normal': {'path': path},
            },
          }),
          throwsA(
            isA<NadrNetworkException>().having(
              (error) => error.kind,
              'kind',
              NadrNetworkErrorKind.invalidResponse,
            ),
          ),
        );
      }
    },
  );

  test(
    'backend straight-line fallback is not accepted as a road route',
    () async {
      await expectLater(
        _response({
          'alternatives': {
            'normal': {
              'path': [
                [1, 2],
                [3, 4],
              ],
              'optimization': 'fallback',
            },
            'safe': {
              'path': [
                [1, 2],
                [3, 4],
              ],
              'optimization': 'fallback',
            },
          },
        }),
        throwsA(
          isA<NadrNetworkException>().having(
            (error) => error.kind,
            'kind',
            NadrNetworkErrorKind.fallbackRoute,
          ),
        ),
      );
    },
  );
}

Future<RouteAlternatives> _response(Object response) async {
  final client = NadrRestClient(
    baseUri: Uri.parse('https://example.test'),
    cookieJar: CookieJar(),
    dio: Dio()..httpClientAdapter = _SingleReplyAdapter(response),
  );
  try {
    return await RestRouteRepository(client).calculateRoute(
      start: const GeoCoordinate(latitude: 1, longitude: 2),
      end: const GeoCoordinate(latitude: 3, longitude: 4),
    );
  } finally {
    client.dispose();
  }
}

Map<String, Object> _variant(String optimization, {double? riskWeight}) => {
  'path': [
    [12.1, 77.2],
    [12.3, 77.4],
  ],
  'distance_m': 1234.5,
  'estimated_time_s': 82.3,
  'total_risk_score': 18.5,
  'max_risk_zone': 'medium',
  'avg_risk': 0.185,
  'risk_segments': {'low': 2, 'medium': 1, 'high': 0},
  'optimization': optimization,
  'risk_weight': riskWeight ?? 0,
};

final class _SingleReplyAdapter implements HttpClientAdapter {
  _SingleReplyAdapter(this.response);

  final Object response;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
