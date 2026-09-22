import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';
import 'package:nadr_mobile/core/network/backend_connectivity_panel.dart';
import 'package:nadr_mobile/core/network/nadr_rest_client.dart';

void main() {
  testWidgets(
    'unconfigured backend is explicit and manual retry stays available',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment(mapStyleUrl: ''),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: BackendConnectivityPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Base URL: Not configured'), findsOneWidget);
      expect(find.text('Status: unconfigured'), findsOneWidget);
      expect(find.text('NADR_API_BASE_URL is not configured.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('backend-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Status: unconfigured'), findsOneWidget);
    },
  );

  testWidgets('configured panel shows healthy response and checks again', (
    tester,
  ) async {
    final adapter = _HealthyAdapter();
    final client = NadrRestClient(
      baseUri: Uri.parse('https://example.test/api'),
      cookieJar: CookieJar(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(
            AppEnvironment(
              apiBaseUrl: 'https://example.test/api',
              mapStyleUrl: '',
            ),
          ),
          nadrRestClientProvider.overrideWith((ref) async => client),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BackendConnectivityPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('backend-base-url'))).data,
      'Base URL: https://example.test/api',
    );
    expect(find.text('Status: healthy'), findsOneWidget);
    expect(adapter.requests, 2);
    await tester.tap(find.byKey(const ValueKey('backend-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Status: healthy'), findsOneWidget);
    expect(adapter.requests, 4);
  });
}

final class _HealthyAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    final data = options.uri.path.endsWith('/health')
        ? {
            'status': 'healthy',
            'timestamp': '2026-01-01T00:00:00',
            'services': {'cache': true, 'redis': true, 'noaa': true},
          }
        : {'message': 'NADR API v2.0', 'status': 'operational'};
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
