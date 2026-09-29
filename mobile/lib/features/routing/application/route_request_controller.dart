import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/network/nadr_rest_client.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/features/routing/infrastructure/rest_route_repository.dart';

enum RouteRequestPhase { idle, waitingForPosition, loading, success, failure }

enum RouteRequestOutcome {
  success,
  duplicateIgnored,
  missingStart,
  missingDestination,
  cancelled,
  failed,
}

final class RouteRequestState {
  const RouteRequestState({
    this.phase = RouteRequestPhase.idle,
    this.message,
    this.alternativeCount = 0,
  });

  final RouteRequestPhase phase;
  final String? message;
  final int alternativeCount;
}

final routeRequestControllerProvider =
    NotifierProvider<RouteRequestController, RouteRequestState>(
      RouteRequestController.new,
    );

final class RouteRequestController extends Notifier<RouteRequestState> {
  int _requestGeneration = 0;
  bool _disposed = false;

  @override
  RouteRequestState build() {
    final initial = ref.read(navigationSessionProvider);
    ref.listen(
      navigationSessionProvider.select(
        (session) => (session.destination, session.currentRouteStart),
      ),
      (previous, next) {
        if (previous?.$1 != next.$1) {
          _requestGeneration++;
          if (next.$1 == null) {
            state = const RouteRequestState();
            ref.read(navigationSessionProvider.notifier).setLoading(false);
          } else if (next.$2 == null) {
            state = const RouteRequestState(
              phase: RouteRequestPhase.waitingForPosition,
              message: 'Waiting for your current position.',
            );
            ref.read(navigationSessionProvider.notifier).setLoading(false);
          } else {
            unawaited(_startRequest(next.$1!, next.$2!));
          }
        } else if (next.$1 != null &&
            next.$2 != null &&
            state.phase == RouteRequestPhase.waitingForPosition) {
          unawaited(_startRequest(next.$1!, next.$2!));
        }
      },
    );
    ref.onDispose(() {
      _disposed = true;
      _requestGeneration++;
    });
    if (initial.destination != null && initial.currentRouteStart != null) {
      Future<void>.microtask(() {
        if (!_disposed &&
            _requestGeneration == 0 &&
            state.phase == RouteRequestPhase.idle) {
          final current = ref.read(navigationSessionProvider);
          if (current.destination != null &&
              current.currentRouteStart != null) {
            unawaited(
              _startRequest(current.destination!, current.currentRouteStart!),
            );
          }
        }
      });
    }
    return initial.destination == null
        ? const RouteRequestState()
        : initial.currentRouteStart == null
        ? const RouteRequestState(
            phase: RouteRequestPhase.waitingForPosition,
            message: 'Waiting for your current position.',
          )
        : const RouteRequestState();
  }

  Future<RouteRequestOutcome> requestRoute() async {
    final sessionSnapshot = ref.read(navigationSessionProvider);
    final destination = sessionSnapshot.destination;
    if (destination == null) return RouteRequestOutcome.missingDestination;
    final start = sessionSnapshot.currentRouteStart;
    if (start == null) {
      _requestGeneration++;
      state = const RouteRequestState(
        phase: RouteRequestPhase.waitingForPosition,
        message: 'Waiting for your current position.',
      );
      ref.read(navigationSessionProvider.notifier).setLoading(false);
      return RouteRequestOutcome.missingStart;
    }
    if (state.phase == RouteRequestPhase.loading) {
      return RouteRequestOutcome.duplicateIgnored;
    }
    return _startRequest(destination, start);
  }

  Future<RouteRequestOutcome> _startRequest(
    Destination destination,
    GeoCoordinate start,
  ) async {
    final generation = ++_requestGeneration;
    state = const RouteRequestState(phase: RouteRequestPhase.loading);
    final session = ref.read(navigationSessionProvider.notifier);
    session.clearError();
    session.setLoading(true);

    try {
      final repository = await ref.read(routeRepositoryProvider.future);
      if (!_isCurrent(generation)) return RouteRequestOutcome.cancelled;
      final alternatives = await repository.calculateRoute(
        start: start,
        end: destination.coordinate,
        mode: RouteMode.normal,
      );
      if (!_isCurrent(generation)) return RouteRequestOutcome.cancelled;
      final accepted = RouteAlternatives(
        byMode: {
          for (final entry in alternatives.byMode.entries)
            if (entry.value.isRenderableRoadRoute) entry.key: entry.value,
        },
        metadata: alternatives.metadata,
      );
      if (accepted.isEmpty) {
        throw NadrNetworkException(
          alternatives.byMode.values.any((route) => route.isBackendFallback)
              ? NadrNetworkErrorKind.fallbackRoute
              : NadrNetworkErrorKind.noRoute,
          'No usable road route was returned.',
        );
      }
      session.setRouteAlternatives(accepted);
      final preferred = accepted[RouteMode.normal] != null
          ? RouteMode.normal
          : accepted.byMode.keys.first;
      session.selectRoute(preferred);
      final count = accepted.byMode.length;
      state = RouteRequestState(
        phase: RouteRequestPhase.success,
        message: 'Route data received ($count alternatives).',
        alternativeCount: count,
      );
      return RouteRequestOutcome.success;
    } on NadrNetworkException catch (error) {
      if (!_isCurrent(generation)) return RouteRequestOutcome.cancelled;
      if (error.kind == NadrNetworkErrorKind.cancelled) {
        state = const RouteRequestState();
        return RouteRequestOutcome.cancelled;
      }
      _setRecoverableError(_messageFor(error.kind));
      return RouteRequestOutcome.failed;
    } on Object {
      if (!_isCurrent(generation)) return RouteRequestOutcome.cancelled;
      _setRecoverableError('Unable to request a route. Try again.');
      return RouteRequestOutcome.failed;
    } finally {
      if (_isCurrent(generation)) session.setLoading(false);
    }
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _requestGeneration;

  void _setRecoverableError(String message) {
    state = RouteRequestState(
      phase: RouteRequestPhase.failure,
      message: message,
    );
    ref.read(navigationSessionProvider.notifier).setError(message);
  }

  static String _messageFor(NadrNetworkErrorKind kind) => switch (kind) {
    NadrNetworkErrorKind.unconfigured =>
      'Backend URL is not configured for route requests.',
    NadrNetworkErrorKind.connectionUnavailable =>
      'Cannot reach the backend. Check the local network and try again.',
    NadrNetworkErrorKind.timeout => 'The route request timed out. Try again.',
    NadrNetworkErrorKind.validation =>
      'The backend rejected the route coordinates.',
    NadrNetworkErrorKind.rateLimited =>
      'Too many route requests. Wait briefly and try again.',
    NadrNetworkErrorKind.serverFailure =>
      'The backend could not calculate the route. Try again.',
    NadrNetworkErrorKind.invalidResponse =>
      'The backend returned invalid route data.',
    NadrNetworkErrorKind.noRoute =>
      'No route is available for this destination. Try again.',
    NadrNetworkErrorKind.fallbackRoute =>
      'Only a straight-line fallback is available. Try again for a road route.',
    NadrNetworkErrorKind.unauthorized =>
      'Authentication is required before requesting a route.',
    NadrNetworkErrorKind.httpFailure =>
      'The route request was rejected. Try again.',
    NadrNetworkErrorKind.cancelled => 'Route request cancelled.',
  };
}
