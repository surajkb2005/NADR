import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_repository.dart';
import 'package:nadr_mobile/features/destination/infrastructure/maptiler_place_search_repository.dart';
import 'package:nadr_mobile/features/destination/infrastructure/unconfigured_place_search_repository.dart';

const _point = {
  'type': 'Feature',
  'id': 'poi.42',
  'text': 'Cubbon Park',
  'place_name': 'Cubbon Park, Bengaluru, Karnataka, India',
  'geometry': {
    'type': 'Point',
    'coordinates': [77.59, 12.97],
  },
};

Object _collection(List<Object?> features) => {
  'type': 'FeatureCollection',
  'features': features,
  'attribution': '© MapTiler © OpenStreetMap contributors',
};

void main() {
  test('production wiring chooses MapTiler only with valid config', () async {
    final valid = ProviderContainer(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          AppEnvironment(mapStyleUrl: '', mapTilerApiKey: 'placeholder-key'),
        ),
      ],
    );
    addTearDown(valid.dispose);
    expect(
      valid.read(placeSearchRepositoryProvider),
      isA<MapTilerPlaceSearchRepository>(),
    );

    final missing = ProviderContainer(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          AppEnvironment(mapStyleUrl: ''),
        ),
      ],
    );
    addTearDown(missing.dispose);
    await expectLater(
      missing.read(placeSearchRepositoryProvider).search('place'),
      throwsA(
        isA<PlaceSearchException>().having(
          (e) => e.kind,
          'kind',
          PlaceSearchErrorKind.unconfigured,
        ),
      ),
    );

    final invalid = ProviderContainer(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          AppEnvironment(
            mapStyleUrl: '',
            placeSearchBaseUrl: 'invalid',
            mapTilerApiKey: 'placeholder-key',
          ),
        ),
      ],
    );
    addTearDown(invalid.dispose);
    expect(
      invalid.read(placeSearchRepositoryProvider),
      isA<UnconfiguredPlaceSearchRepository>(),
    );
  });

  test('GET contract encodes path queries and never logs the key', () async {
    final adapter = _Adapter(_collection([_point]));
    final repository = _repository(adapter);
    addTearDown(repository.dispose);
    for (final query in [
      'MS Ramaiah',
      'Cubbon Park, Bangalore',
      "King's Road",
      'A/B',
      'München 市',
    ]) {
      await repository.search(query);
      final request = adapter.requests.last;
      expect(request.method, 'GET');
      expect(request.uri.host, 'api.maptiler.com');
      expect(request.uri.pathSegments, ['geocoding', '$query.json']);
      expect(request.uri.queryParameters['key'], 'placeholder-key');
      expect(request.uri.queryParameters['autocomplete'], 'true');
      expect(request.uri.queryParameters['limit'], '5');
    }
    expect(adapter.requests[3].uri.toString(), contains('A%2FB.json'));
  });

  test('parses Point, context, ID, and longitude/latitude order', () async {
    final repository = _repository(_Adapter(_collection([_point])));
    addTearDown(repository.dispose);
    final result = (await repository.search('Cubbon Park')).single;
    expect(result.label, 'Cubbon Park');
    expect(result.subtitle, 'Cubbon Park, Bengaluru, Karnataka, India');
    expect(result.providerId, 'poi.42');
    expect(
      result.coordinate,
      const GeoCoordinate(latitude: 12.97, longitude: 77.59),
    );
    expect(result.toDestination().coordinate, result.coordinate);
    expect(result.toDestination().displayLabel, result.label);
  });

  test(
    'uses documented center for non-Point geometry and optional fields',
    () async {
      final repository = _repository(
        _Adapter(
          _collection([
            {
              'type': 'Feature',
              'text': 'Region',
              'geometry': {'type': 'Polygon', 'coordinates': []},
              'center': [-73.5, -33.4],
            },
          ]),
        ),
      );
      addTearDown(repository.dispose);
      final result = (await repository.search('Region')).single;
      expect(
        result.coordinate,
        const GeoCoordinate(latitude: -33.4, longitude: -73.5),
      );
      expect(result.subtitle, isNull);
      expect(result.providerId, isNull);
    },
  );

  test('skips invalid siblings and returns empty for zero features', () async {
    final invalids = <Object?>[
      {
        'type': 'Feature',
        'text': 'bad latitude',
        'geometry': {
          'type': 'Point',
          'coordinates': [77, 91],
        },
      },
      {
        'type': 'Feature',
        'text': 'bad longitude',
        'geometry': {
          'type': 'Point',
          'coordinates': [181, 12],
        },
      },
      {
        'type': 'Feature',
        'text': 'bad coordinate',
        'geometry': {
          'type': 'Point',
          'coordinates': ['x', 12],
        },
      },
      {
        'type': 'Feature',
        'text': ' ',
        'geometry': {
          'type': 'Point',
          'coordinates': [77, 12],
        },
      },
      {'not': 'a feature'},
    ];
    final adapter = _Adapter(_collection([...invalids, _point]));
    final repository = _repository(adapter);
    addTearDown(repository.dispose);
    expect((await repository.search('place')).map((result) => result.label), [
      'Cubbon Park',
    ]);
    adapter.data = _collection([]);
    expect(await repository.search('place'), isEmpty);
  });

  test('rejects malformed response envelope and JSON', () async {
    final adapter = _Adapter({'features': []});
    final repository = _repository(adapter);
    addTearDown(repository.dispose);
    await expectLater(repository.search('place'), _invalidResponse);
    adapter.data = {'type': 'FeatureCollection', 'features': 'wrong'};
    await expectLater(repository.search('place'), _invalidResponse);
    adapter.rawBody = '{bad json';
    await expectLater(repository.search('place'), _invalidResponse);
  });

  test(
    'maps timeout, offline, auth and provider errors without key leakage',
    () async {
      final adapter = _Adapter(_collection([]));
      final repository = _repository(adapter);
      addTearDown(repository.dispose);
      for (final kind in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        adapter.failure = kind;
        await expectLater(
          repository.search('place'),
          throwsA(
            isA<PlaceSearchException>().having(
              (e) => e.kind,
              'kind',
              PlaceSearchErrorKind.unavailable,
            ),
          ),
        );
      }
      adapter.failure = DioExceptionType.connectionError;
      await expectLater(
        repository.search('place'),
        throwsA(
          isA<PlaceSearchException>().having(
            (e) => e.kind,
            'kind',
            PlaceSearchErrorKind.unavailable,
          ),
        ),
      );
      adapter.failure = null;
      for (final status in [401, 403, 400, 500]) {
        adapter.status = status;
        try {
          await repository.search('place');
          fail('Expected provider error');
        } on PlaceSearchException catch (error) {
          expect(error.kind, PlaceSearchErrorKind.providerFailure);
          expect(error.message, isNot(contains('placeholder-key')));
        }
      }
    },
  );
}

final _invalidResponse = throwsA(
  isA<PlaceSearchException>().having(
    (e) => e.kind,
    'kind',
    PlaceSearchErrorKind.invalidResponse,
  ),
);

MapTilerPlaceSearchRepository _repository(_Adapter adapter) =>
    MapTilerPlaceSearchRepository(
      baseUri: Uri.parse('https://api.maptiler.com'),
      apiKey: 'placeholder-key',
      dio: Dio()..httpClientAdapter = adapter,
    );

final class _Adapter implements HttpClientAdapter {
  _Adapter(this.data);

  Object data;
  String? rawBody;
  int status = 200;
  DioExceptionType? failure;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (failure case final type?) {
      throw DioException(requestOptions: options, type: type);
    }
    return ResponseBody.fromString(
      rawBody ?? jsonEncode(data),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
