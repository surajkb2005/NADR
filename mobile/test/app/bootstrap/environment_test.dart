import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';

void main() {
  group('AppEnvironment', () {
    test('requires explicit backend configuration without a device-specific default', () {
      final environment = AppEnvironment.fromDartDefines();

      expect(environment.apiBaseUri, isNull);
      expect(environment.wsBaseUri, isNull);
      expect(environment.mapStyleUri, isNull);
      expect(environment.mapStyleConfigurationError, isNull);
      expect(environment.missingConfiguration, [
        'NADR_API_BASE_URL',
        'NADR_MAP_STYLE_URL',
      ]);
    });

    test('accepts valid configured URLs', () {
      final environment = AppEnvironment(
        apiBaseUrl: 'https://api.example.test',
        wsBaseUrl: 'wss://api.example.test/ws',
        mapStyleUrl: 'https://maps.example.test/style.json',
      );

      expect(environment.missingConfiguration, isEmpty);
      expect(environment.isMapStyleConfigured, isTrue);
      expect(environment.mapStyleConfigurationError, isNull);
    });

    test('reports an invalid map style URL without crashing bootstrap', () {
      final environment = AppEnvironment(
        apiBaseUrl: 'https://api.example.test',
        wsBaseUrl: 'wss://api.example.test/ws',
        mapStyleUrl: 'not-a-style-url',
      );

      expect(environment.mapStyleUri, isNull);
      expect(environment.missingConfiguration, isEmpty);
      expect(
        environment.mapStyleConfigurationError,
        contains('NADR_MAP_STYLE_URL'),
      );
    });

    test('rejects an invalid API URL', () {
      expect(
        () => AppEnvironment(
          apiBaseUrl: 'not-a-url',
          wsBaseUrl: 'ws://localhost:8000',
          mapStyleUrl: '',
        ),
        throwsFormatException,
      );
    });

    test('rejects the wrong WebSocket scheme', () {
      expect(
        () => AppEnvironment(
          apiBaseUrl: 'http://localhost:8000',
          wsBaseUrl: 'http://localhost:8000',
          mapStyleUrl: '',
        ),
        throwsFormatException,
      );
    });

    test(
      'place search URL is optional and validated without crashing bootstrap',
      () {
        final missing = AppEnvironment(mapStyleUrl: '');
        expect(missing.placeSearchBaseUri?.host, 'api.maptiler.com');
        expect(missing.placeSearchConfigurationError, isNull);

        final configured = AppEnvironment(
          mapStyleUrl: '',
          placeSearchBaseUrl: 'https://search.example.test/api',
        );
        expect(configured.placeSearchBaseUri?.host, 'search.example.test');

        final invalid = AppEnvironment(
          mapStyleUrl: '',
          placeSearchBaseUrl: 'not-a-url',
        );
        expect(invalid.placeSearchBaseUri, isNull);
        expect(
          invalid.placeSearchConfigurationError,
          contains('NADR_PLACE_SEARCH_BASE_URL'),
        );
      },
    );

    test('MapTiler key is optional and base rejects embedded credentials', () {
      final configured = AppEnvironment(
        mapStyleUrl: '',
        mapTilerApiKey: '  configured-key  ',
      );
      expect(configured.mapTilerApiKey, 'configured-key');
      final invalid = AppEnvironment(
        mapStyleUrl: '',
        placeSearchBaseUrl: 'https://user:password@example.test/?key=hidden',
      );
      expect(invalid.placeSearchBaseUri, isNull);
      expect(
        invalid.placeSearchConfigurationError,
        contains('NADR_PLACE_SEARCH_BASE_URL'),
      );
    });
  });
}
