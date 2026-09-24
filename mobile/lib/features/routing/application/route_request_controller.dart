import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/core/network/nadr_rest_client.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/features/routing/infrastructure/rest_route_repository.dart';

enum RouteRequestPhase { idle, loading, success, failure }

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
  bool _requestInFlight = false;

  @override
  RouteRequestState build() => const RouteRequestState();

  Future<RouteRequestOutcome> requestRoute() async {
    if (_requestInFlight) return RouteRequestOutcome.duplicateIgnored;

    final sessionSnapshot = ref.read(navigationSessionProvider);
    final start = sessionSnapshot.currentRouteStart;
    if (start == null) {
      _setRecoverableError('Waiting for a valid current position.');
      return RouteRequestOutcome.missingStart;
    }
    final destination = sessionSnapshot.destination;
    if (destination == null) {
      _setRecoverableError('Choose a destination before requesting a route.');
      return RouteRequestOutcome.missingDestination;
    }

    // These local values are the immutable request snapshot. Sensor and mode
    // updates after this point cannot alter the in-flight request.
    final startSnapshot = start;
    final destinationSnapshot = destination.coordinate;
    _requestInFlight = true;
    state = const RouteRequestState(phase: RouteRequestPhase.loading);
    final session = ref.read(navigationSessionProvider.notifier);
    session.clearError();
    session.setLoading(true);

    try {
      final repository = await ref.read(routeRepositoryProvider.future);
      final alternatives = await repository.calculateRoute(
        start: startSnapshot,
        end: destinationSnapshot,
        mode: RouteMode.normal,
      );
      session.setRouteAlternatives(alternatives);
      final preferred = alternatives[RouteMode.normal] != null
          ? RouteMode.normal
          : alternatives.byMode.keys.first;
      session.selectRoute(preferred);
      final count = alternatives.byMode.length;
      state = RouteRequestState(
        phase: RouteRequestPhase.success,
        message: 'Route data received ($count alternatives).',
        alternativeCount: count,
      );
      return RouteRequestOutcome.success;
    } on NadrNetworkException catch (error) {
      if (error.kind == NadrNetworkErrorKind.cancelled) {
        state = const RouteRequestState();
        return RouteRequestOutcome.cancelled;
      }
      _setRecoverableError(_messageFor(error.kind));
      return RouteRequestOutcome.failed;
    } on Object {
      _setRecoverableError('Unable to request a route. Try again.');
      return RouteRequestOutcome.failed;
    } finally {
      _requestInFlight = false;
      session.setLoading(false);
    }
  }

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
    NadrNetworkErrorKind.unauthorized =>
      'Authentication is required before requesting a route.',
    NadrNetworkErrorKind.httpFailure =>
      'The route request was rejected. Try again.',
    NadrNetworkErrorKind.cancelled => 'Route request cancelled.',
  };
}
