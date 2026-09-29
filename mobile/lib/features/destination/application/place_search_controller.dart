import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_repository.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_result.dart';
import 'package:nadr_mobile/features/destination/infrastructure/unconfigured_place_search_repository.dart';

enum PlaceSearchPhase { idle, loading, results, empty, failure }

final class PlaceSearchState {
  const PlaceSearchState({
    this.query = '',
    this.phase = PlaceSearchPhase.idle,
    this.results = const [],
    this.errorMessage,
    this.errorKind,
  });

  final String query;
  final PlaceSearchPhase phase;
  final List<PlaceSearchResult> results;
  final String? errorMessage;
  final PlaceSearchErrorKind? errorKind;
}

final placeSearchDebounceProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 300),
);

final placeSearchControllerProvider =
    NotifierProvider<PlaceSearchController, PlaceSearchState>(
      PlaceSearchController.new,
    );

final class PlaceSearchController extends Notifier<PlaceSearchState> {
  static const minimumQueryLength = 3;

  Timer? _debounceTimer;
  int _generation = 0;
  bool _disposed = false;

  @override
  PlaceSearchState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _debounceTimer?.cancel();
    });
    return const PlaceSearchState();
  }

  void updateQuery(String input) {
    final query = input.trim();
    final generation = ++_generation;
    _debounceTimer?.cancel();
    if (query.length < minimumQueryLength) {
      state = PlaceSearchState(query: query);
      return;
    }

    state = PlaceSearchState(query: query, phase: PlaceSearchPhase.loading);
    _debounceTimer = Timer(ref.read(placeSearchDebounceProvider), () {
      unawaited(_search(query, generation));
    });
  }

  void clear() => updateQuery('');

  Future<void> _search(String query, int generation) async {
    try {
      final results = await ref
          .read(placeSearchRepositoryProvider)
          .search(query);
      if (!_isCurrent(generation)) return;
      state = PlaceSearchState(
        query: query,
        phase: results.isEmpty
            ? PlaceSearchPhase.empty
            : PlaceSearchPhase.results,
        results: List.unmodifiable(results),
      );
    } on PlaceSearchException catch (error) {
      if (!_isCurrent(generation)) return;
      state = PlaceSearchState(
        query: query,
        phase: PlaceSearchPhase.failure,
        errorMessage: error.message,
        errorKind: error.kind,
      );
    } on Object {
      if (!_isCurrent(generation)) return;
      state = PlaceSearchState(
        query: query,
        phase: PlaceSearchPhase.failure,
        errorMessage: 'Place search is unavailable. Try again.',
        errorKind: PlaceSearchErrorKind.unavailable,
      );
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;
}
