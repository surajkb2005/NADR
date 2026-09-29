import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/destination/application/place_search_controller.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_repository.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_result.dart';
import 'package:nadr_mobile/features/destination/infrastructure/unconfigured_place_search_repository.dart';

final _place = PlaceSearchResult(
  label: 'Place B',
  coordinate: const GeoCoordinate(latitude: 12, longitude: 77),
);

void main() {
  test('idle, short query, debounce, results, and clear', () async {
    final repository = _FakeSearchRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    final controller = container.read(placeSearchControllerProvider.notifier);
    expect(
      container.read(placeSearchControllerProvider).phase,
      PlaceSearchPhase.idle,
    );
    controller.updateQuery('ab');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(repository.queries, isEmpty);
    controller.updateQuery('first');
    controller.updateQuery('second');
    expect(
      container.read(placeSearchControllerProvider).phase,
      PlaceSearchPhase.loading,
    );
    await _until(() => repository.queries.length == 1);
    expect(repository.queries.single, 'second');
    repository.pending.single.complete([_place]);
    await _until(
      () =>
          container.read(placeSearchControllerProvider).phase ==
          PlaceSearchPhase.results,
    );
    expect(
      container.read(placeSearchControllerProvider).results.single.label,
      'Place B',
    );
    controller.clear();
    expect(
      container.read(placeSearchControllerProvider).phase,
      PlaceSearchPhase.idle,
    );
    expect(container.read(placeSearchControllerProvider).results, isEmpty);
  });

  test('empty results and provider failure are recoverable', () async {
    final repository = _FakeSearchRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    final controller = container.read(placeSearchControllerProvider.notifier);
    controller.updateQuery('empty');
    await _until(() => repository.pending.length == 1);
    repository.pending[0].complete([]);
    await _until(
      () =>
          container.read(placeSearchControllerProvider).phase ==
          PlaceSearchPhase.empty,
    );
    controller.updateQuery('fails');
    await _until(() => repository.pending.length == 2);
    repository.pending[1].completeError(
      const PlaceSearchException(
        PlaceSearchErrorKind.providerFailure,
        'Provider failed.',
      ),
    );
    await _until(
      () =>
          container.read(placeSearchControllerProvider).phase ==
          PlaceSearchPhase.failure,
    );
    expect(
      container.read(placeSearchControllerProvider).errorKind,
      PlaceSearchErrorKind.providerFailure,
    );
    controller.updateQuery('again');
    await _until(() => repository.pending.length == 3);
    repository.pending[2].complete([_place]);
    await _until(
      () =>
          container.read(placeSearchControllerProvider).phase ==
          PlaceSearchPhase.results,
    );
  });

  test('late Query A cannot replace newer Query B', () async {
    final repository = _FakeSearchRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    final controller = container.read(placeSearchControllerProvider.notifier);
    controller.updateQuery('Query A');
    await _until(() => repository.pending.length == 1);
    controller.updateQuery('Query B');
    await _until(() => repository.pending.length == 2);
    repository.pending[1].complete([_place]);
    await _until(
      () =>
          container.read(placeSearchControllerProvider).phase ==
          PlaceSearchPhase.results,
    );
    repository.pending[0].complete([]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(container.read(placeSearchControllerProvider).query, 'Query B');
    expect(
      container.read(placeSearchControllerProvider).results.single,
      _place,
    );
  });

  test('clearing during an in-flight query ignores its late result', () async {
    final repository = _FakeSearchRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    final controller = container.read(placeSearchControllerProvider.notifier);
    controller.updateQuery('place');
    await _until(() => repository.pending.length == 1);
    controller.clear();
    repository.pending.single.complete([_place]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      container.read(placeSearchControllerProvider).phase,
      PlaceSearchPhase.idle,
    );
    expect(container.read(placeSearchControllerProvider).results, isEmpty);
  });

  test(
    'unconfigured repository reports a controlled configuration error',
    () async {
      final container = _container(const UnconfiguredPlaceSearchRepository());
      addTearDown(container.dispose);
      container
          .read(placeSearchControllerProvider.notifier)
          .updateQuery('place');
      await _until(
        () =>
            container.read(placeSearchControllerProvider).phase ==
            PlaceSearchPhase.failure,
      );
      expect(
        container.read(placeSearchControllerProvider).errorKind,
        PlaceSearchErrorKind.unconfigured,
      );
    },
  );
}

ProviderContainer _container(PlaceSearchRepository repository) =>
    ProviderContainer(
      overrides: [
        placeSearchRepositoryProvider.overrideWithValue(repository),
        placeSearchDebounceProvider.overrideWithValue(
          const Duration(milliseconds: 5),
        ),
      ],
    );

final class _FakeSearchRepository implements PlaceSearchRepository {
  final queries = <String>[];
  final pending = <Completer<List<PlaceSearchResult>>>[];

  @override
  Future<List<PlaceSearchResult>> search(String query) {
    queries.add(query);
    final request = Completer<List<PlaceSearchResult>>();
    pending.add(request);
    return request.future;
  }
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}
