import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/network/nadr_rest_client.dart';

void main() {
  test(
    'normalizes direct and /api proxy base paths without duplication',
    () async {
      final direct = NadrRestClient(
        baseUri: Uri.parse('http://example.test:8000'),
        cookieJar: CookieJar(),
      );
      final proxied = NadrRestClient(
        baseUri: Uri.parse('https://example.test/api'),
        cookieJar: CookieJar(),
      );
      addTearDown(direct.dispose);
      addTearDown(proxied.dispose);
      expect(direct.displayBaseUrl, 'http://example.test:8000/');
      expect(proxied.displayBaseUrl, 'https://example.test/api/');
      expect(direct.dio.options.connectTimeout, const Duration(seconds: 10));
      expect(direct.dio.options.sendTimeout, const Duration(seconds: 10));
      expect(direct.dio.options.receiveTimeout, const Duration(seconds: 10));
      expect(
        () => NadrRestClient.normalizeApiBaseUri(
          Uri.parse('https://example.test/api/api'),
        ),
        throwsFormatException,
      );
      expect(
        () => NadrRestClient.normalizeApiBaseUri(
          Uri.parse('https://secret@example.test/api'),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'root and health use exact proxy paths and distinguish healthy/degraded',
    () async {
      final adapter = FixtureAdapter([
        FixtureReply(200, {
          'message': 'NADR API v2.0',
          'status': 'operational',
        }),
        FixtureReply(200, {
          'status': 'healthy',
          'timestamp': '2026-01-01T00:00:00',
          'services': {'cache': true, 'redis': true, 'noaa': true},
        }),
        FixtureReply(200, {
          'message': 'NADR API v2.0',
          'status': 'operational',
        }),
        FixtureReply(200, {
          'status': 'degraded',
          'timestamp': '2026-01-01T00:00:00',
          'services': {'cache': true, 'redis': true, 'noaa': false},
        }),
      ]);
      final client = NadrRestClient(
        baseUri: Uri.parse('https://example.test/api'),
        cookieJar: CookieJar(),
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(client.dispose);
      expect(
        (await client.checkConnectivity()).state,
        BackendConnectivityState.healthy,
      );
      expect(
        (await client.checkConnectivity()).state,
        BackendConnectivityState.degraded,
      );
      expect(adapter.requests.map((request) => request.uri.path).toList(), [
        '/api/',
        '/api/health',
        '/api/',
        '/api/health',
      ]);
    },
  );

  test(
    'health 503 is reachable degradation, connection and timeout are distinct',
    () async {
      final server = FixtureAdapter([
        FixtureReply(200, {
          'message': 'NADR API v2.0',
          'status': 'operational',
        }),
        FixtureReply(503, {'detail': 'Service unavailable'}),
      ]);
      final serverClient = NadrRestClient(
        baseUri: Uri.parse('https://example.test'),
        cookieJar: CookieJar(),
        dio: Dio()..httpClientAdapter = server,
      );
      addTearDown(serverClient.dispose);
      expect(
        (await serverClient.checkConnectivity()).state,
        BackendConnectivityState.degraded,
      );

      for (final failure in [
        DioExceptionType.connectionError,
        DioExceptionType.receiveTimeout,
      ]) {
        final adapter = FixtureAdapter([FixtureReply.failure(failure)]);
        final client = NadrRestClient(
          baseUri: Uri.parse('https://example.test'),
          cookieJar: CookieJar(),
          dio: Dio()..httpClientAdapter = adapter,
        );
        addTearDown(client.dispose);
        expect(
          (await client.checkConnectivity()).state,
          failure == DioExceptionType.connectionError
              ? BackendConnectivityState.unreachable
              : BackendConnectivityState.timedOut,
        );
      }
    },
  );

  test('typed errors preserve only safe fixed backend details', () async {
    final adapter = FixtureAdapter([
      FixtureReply(401, {'detail': 'Not authenticated'}),
      FixtureReply(422, {
        'detail': [
          {
            'loc': ['body', 'otp'],
            'input': '123456',
          },
        ],
      }),
      FixtureReply(429, {
        'detail': 'Too many OTP requests. Please wait a minute and try again.',
      }),
      FixtureReply(500, {'detail': 'secret internal OTP 123456'}),
      FixtureReply(200, {
        'status': 'healthy',
        'timestamp': 'bad',
        'services': {},
      }),
    ]);
    final client = NadrRestClient(
      baseUri: Uri.parse('https://example.test'),
      cookieJar: CookieJar(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(client.dispose);
    Future<void> expectKind(
      NadrNetworkErrorKind kind,
      Future<Object> Function() call,
    ) async {
      try {
        await call();
        fail('Expected typed network failure');
      } on NadrNetworkException catch (error) {
        expect(error.kind, kind);
        expect(error.message, isNot(contains('123456')));
      }
    }

    await expectKind(NadrNetworkErrorKind.unauthorized, client.getAuthStatus);
    await expectKind(NadrNetworkErrorKind.validation, client.getAuthStatus);
    await expectKind(NadrNetworkErrorKind.rateLimited, client.getAuthStatus);
    await expectKind(NadrNetworkErrorKind.serverFailure, client.getAuthStatus);
    await expectKind(NadrNetworkErrorKind.invalidResponse, client.getHealth);
  });

  test(
    'existing route, heatmap, weather, and auth contracts use one client',
    () async {
      final adapter = FixtureAdapter([
        FixtureReply(200, {
          'alternatives': {
            'normal': {
              'path': [
                [1, 2],
                [3, 4],
              ],
            },
          },
          'metadata': {'source': 'OSRM Public API'},
        }),
        FixtureReply(200, {
          'type': 'FeatureCollection',
          'features': [],
          'metadata': {
            'bbox': [2, 1, 4, 3],
            'resolution': 0.05,
            'grid_size': '0x0',
            'kp_index': 2,
          },
        }),
        FixtureReply(200, {
          'timestamp': '2026-01-01T00:00:00',
          'kp_index': 2,
          'risk_level': 'low',
          'estimated_gps_error_m': [5, 15],
          'alerts': [],
          'source': 'NOAA',
        }),
        FixtureReply(202, {'message': 'OTP sent successfully.'}),
        FixtureReply(200, {
          'message': 'Login successful.',
          'user_email': 'test@example.test',
        }),
        FixtureReply(200, {
          'status': 'authenticated',
          'user_email': 'test@example.test',
        }),
        FixtureReply(200, {'message': 'Logout successful'}),
      ]);
      final jar = CookieJar();
      final client = NadrRestClient(
        baseUri: Uri.parse('https://example.test/api/'),
        cookieJar: jar,
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(client.dispose);
      expect(
        (await client.calculateRoute(
          start: [1, 2],
          end: [3, 4],
        )).alternatives['normal']!.path.first,
        [1, 2],
      );
      expect((await client.getHeatmap(bbox: [2, 1, 4, 3])).features, isEmpty);
      expect(
        (await client.getCurrentSpaceWeather(
          latitude: 1,
          longitude: 2,
        )).riskLevel,
        'low',
      );
      expect(
        (await client.requestOtp('test@example.test')).message,
        'OTP sent successfully.',
      );
      expect(
        (await client.verifyOtp(
          email: 'test@example.test',
          otp: '000000',
        )).userEmail,
        'test@example.test',
      );
      expect((await client.getAuthStatus()).status, 'authenticated');
      expect((await client.logout()).message, 'Logout successful');
      expect(
        adapter.requests
            .map((request) => '${request.method} ${request.uri.path}')
            .toList(),
        [
          'POST /api/route',
          'POST /api/heatmap',
          'GET /api/space-weather/current',
          'POST /api/auth/request-otp',
          'POST /api/auth/verify-otp',
          'GET /api/auth/status',
          'POST /api/auth/logout',
        ],
      );
      expect(adapter.requests[0].data, {
        'start': [1, 2],
        'end': [3, 4],
        'mode': 'normal',
      });
      expect(adapter.requests[1].data, {
        'bbox': [2, 1, 4, 3],
        'resolution': 0.05,
      });
      expect(adapter.requests[2].uri.queryParameters, {
        'latitude': '1.0',
        'longitude': '2.0',
      });
    },
  );

  test(
    'cookie manager retains the existing session_id cookie for HTTPS',
    () async {
      final adapter = FixtureAdapter([
        FixtureReply(
          200,
          {'message': 'Login successful.', 'user_email': 'test@example.test'},
          headers: {
            'set-cookie': [
              'session_id=dummy; Path=/; HttpOnly; Secure; SameSite=Lax',
            ],
          },
        ),
        FixtureReply(200, {
          'status': 'authenticated',
          'user_email': 'test@example.test',
        }),
      ]);
      final jar = CookieJar();
      final client = NadrRestClient(
        baseUri: Uri.parse('https://example.test/api'),
        cookieJar: jar,
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(client.dispose);
      await client.verifyOtp(email: 'test@example.test', otp: '000000');
      await client.getAuthStatus();
      expect(
        adapter.requests.last.headers['cookie'],
        contains('session_id=dummy'),
      );
    },
  );

  test('session cookie storage survives a jar instance restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nadr-cookie-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final url = Uri.parse('https://example.test/api/auth/status');
    final first = PersistCookieJar(storage: FileStorage(directory.path));
    await first.saveFromResponse(url, [
      Cookie('session_id', 'dummy')
        ..httpOnly = true
        ..secure = true,
    ]);
    final reopened = PersistCookieJar(storage: FileStorage(directory.path));
    expect(
      (await reopened.loadForRequest(url)).map((cookie) => cookie.name),
      contains('session_id'),
    );
  });
}

final class FixtureReply {
  const FixtureReply(this.status, this.data, {this.headers = const {}})
    : failureType = null;
  const FixtureReply.failure(this.failureType)
    : status = 0,
      data = null,
      headers = const {};
  final int status;
  final Object? data;
  final Map<String, List<String>> headers;
  final DioExceptionType? failureType;
}

final class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this.replies);
  final List<FixtureReply> replies;
  final List<RequestOptions> requests = [];
  int _next = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = replies[_next++];
    if (reply.failureType != null) {
      throw DioException(requestOptions: options, type: reply.failureType!);
    }
    return ResponseBody.fromString(
      jsonEncode(reply.data),
      reply.status,
      headers: {
        'content-type': ['application/json'],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
