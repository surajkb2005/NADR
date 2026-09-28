import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/features/routing/application/route_request_controller.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/features/routing/domain/route_repository.dart';
import 'package:nadr_mobile/features/routing/infrastructure/rest_route_repository.dart';

const _a = Destination(coordinate: GeoCoordinate(latitude: 12, longitude: 77));
const _b = Destination(coordinate: GeoCoordinate(latitude: 13, longitude: 78));
const _start = GeoCoordinate(latitude: 11, longitude: 76);

void main() {
  test(
    'destination waits for a valid start, then requests exactly once',
    () async {
      final repository = _PendingRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      container.read(routeRequestControllerProvider);
      final session = container.read(navigationSessionProvider.notifier);
      session.setDestination(_a);
      expect(
        container.read(routeRequestControllerProvider).phase,
        RouteRequestPhase.waitingForPosition,
      );
      expect(container.read(navigationSessionProvider).destination, _a);
      expect(repository.calls, isEmpty);
      _gps(session, _start, 1);
      await _until(() => repository.calls.length == 1);
      expect(repository.calls.single.start, _start);
      expect(repository.calls.single.end, _a.coordinate);
      expect(repository.calls.single.mode, RouteMode.normal);
      repository.pending.single.complete(_routes(_start, _a.coordinate));
      await _until(
        () =>
            container.read(routeRequestControllerProvider).phase ==
            RouteRequestPhase.success,
      );
      _gps(session, const GeoCoordinate(latitude: 11.1, longitude: 76.1), 2);
      _gps(session, const GeoCoordinate(latitude: 11.2, longitude: 76.2), 3);
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, hasLength(1));
    },
  );

  test('only the newest destination waiting for start is requested', () async {
    final repository = _PendingRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    container.read(routeRequestControllerProvider);
    final session = container.read(navigationSessionProvider.notifier);
    session.setDestination(_a);
    session.setDestination(_b);
    _gps(session, _start, 1);
    await _until(() => repository.calls.length == 1);
    expect(repository.calls.single.end, _b.coordinate);
  });

  test('setting the same destination does not clear or request again', () async {
    final repository = _PendingRepository();
    final container = _ready(repository);
    addTearDown(container.dispose);
    final session = container.read(navigationSessionProvider.notifier);
    session.setDestination(_a);
    await _until(() => repository.calls.length == 1);
    repository.pending.single.complete(_routes(_start, _a.coordinate));
    await _until(
      () =>
          container.read(routeRequestControllerProvider).phase ==
          RouteRequestPhase.success,
    );
    final route = container.read(navigationSessionProvider).selectedRoute;
    session.setDestination(_a);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(navigationSessionProvider).selectedRoute, same(route));
    expect(repository.calls, hasLength(1));
  });

  test('replacement clears old route and ignores late A success', () async {
    final repository = _PendingRepository();
    final container = _ready(repository);
    addTearDown(container.dispose);
    final session = container.read(navigationSessionProvider.notifier);
    session.setDestination(_a);
    await _until(() => repository.calls.length == 1);
    repository.pending[0].complete(_routes(_start, _a.coordinate));
    await _until(
      () =>
          container.read(routeRequestControllerProvider).phase ==
          RouteRequestPhase.success,
    );
    final oldRoute = container.read(navigationSessionProvider).selectedRoute;
    expect(oldRoute, isNotNull);
    session.setDestination(_b);
    expect(container.read(navigationSessionProvider).selectedRoute, isNull);
    expect(
      container.read(navigationSessionProvider).routeAlternatives.isEmpty,
      isTrue,
    );
    await _until(() => repository.calls.length == 2);
    repository.pending[1].complete(_routes(_start, _b.coordinate));
    await _until(
      () =>
          container.read(routeRequestControllerProvider).phase ==
          RouteRequestPhase.success,
    );
    expect(
      container.read(navigationSessionProvider).selectedRoute?.path.last,
      _b.coordinate,
    );
    session.setDestination(_a);
    await _until(() => repository.calls.length == 3);
    session.setDestination(_b);
    await _until(() => repository.calls.length == 4);
    repository.pending[3].complete(_routes(_start, _b.coordinate));
    await _until(
      () =>
          container.read(routeRequestControllerProvider).phase ==
          RouteRequestPhase.success,
    );
    repository.pending[2].complete(_routes(_start, _a.coordinate));
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(navigationSessionProvider).selectedRoute?.path.last,
      _b.coordinate,
    );
  });

  test('late A failure cannot replace B success', () async {
    final repository = _PendingRepository();
    final container = _ready(repository);
    addTearDown(container.dispose);
    final session = container.read(navigationSessionProvider.notifier);
    session.setDestination(_a);
    await _until(() => repository.calls.length == 1);
    session.setDestination(_b);
    await _until(() => repository.calls.length == 2);
    repository.pending[1].complete(_routes(_start, _b.coordinate));
    await _until(
      () =>
          container.read(routeRequestControllerProvider).phase ==
          RouteRequestPhase.success,
    );
    repository.pending[0].completeError(StateError('stale failure'));
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(routeRequestControllerProvider).phase,
      RouteRequestPhase.success,
    );
    expect(container.read(navigationSessionProvider).errorMessage, isNull);
  });

  test(
    'clearing destination invalidates active result and sends no new request',
    () async {
      final repository = _PendingRepository();
      final container = _ready(repository);
      addTearDown(container.dispose);
      final session = container.read(navigationSessionProvider.notifier);
      session.setDestination(_a);
      await _until(() => repository.calls.length == 1);
      session.clearDestination();
      expect(
        container.read(routeRequestControllerProvider).phase,
        RouteRequestPhase.idle,
      );
      expect(
        container.read(navigationSessionProvider).routeAlternatives.isEmpty,
        isTrue,
      );
      repository.pending.single.complete(_routes(_start, _a.coordinate));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(navigationSessionProvider).destination, isNull);
      expect(container.read(navigationSessionProvider).selectedRoute, isNull);
      expect(repository.calls, hasLength(1));
    },
  );

  test('late failure after destination clear remains ignored', () async {
    final repository = _PendingRepository();
    final container = _ready(repository);
    addTearDown(container.dispose);
    final session = container.read(navigationSessionProvider.notifier);
    session.setDestination(_a);
    await _until(() => repository.calls.length == 1);
    session.clearDestination();
    repository.pending.single.completeError(StateError('stale failure'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(routeRequestControllerProvider).phase, RouteRequestPhase.idle);
    expect(container.read(navigationSessionProvider).errorMessage, isNull);
  });

  test(
    'retry uses current destination and current start after failure',
    () async {
      final repository = _PendingRepository();
      final container = _ready(repository);
      addTearDown(container.dispose);
      final session = container.read(navigationSessionProvider.notifier);
      session.setDestination(_a);
      await _until(() => repository.calls.length == 1);
      repository.pending[0].completeError(StateError('failure'));
      await _until(
        () =>
            container.read(routeRequestControllerProvider).phase ==
            RouteRequestPhase.failure,
      );
      _gps(session, const GeoCoordinate(latitude: 11.5, longitude: 76.5), 2);
      final retry = container
          .read(routeRequestControllerProvider.notifier)
          .requestRoute();
      await _until(() => repository.calls.length == 2);
      expect(
        repository.calls[1].start,
        const GeoCoordinate(latitude: 11.5, longitude: 76.5),
      );
      expect(repository.calls[1].end, _a.coordinate);
      repository.pending[1].complete(
        _routes(repository.calls[1].start, _a.coordinate),
      );
      expect(await retry, RouteRequestOutcome.success);
    },
  );

  test(
    'mode switches preserve route and do not trigger a new request',
    () async {
      final repository = _PendingRepository();
      final container = _ready(repository);
      addTearDown(container.dispose);
      final session = container.read(navigationSessionProvider.notifier);
      session.setDestination(_a);
      await _until(() => repository.calls.length == 1);
      repository.pending.single.complete(_routes(_start, _a.coordinate));
      await _until(
        () =>
            container.read(routeRequestControllerProvider).phase ==
            RouteRequestPhase.success,
      );
      final route = container.read(navigationSessionProvider).selectedRoute;
      session.setNavigationMode(NavigationMode.imu);
      session.setNavigationMode(NavigationMode.gps);
      expect(container.read(navigationSessionProvider).destination, _a);
      expect(
        container.read(navigationSessionProvider).selectedRoute,
        same(route),
      );
      expect(repository.calls, hasLength(1));
    },
  );
}

ProviderContainer _container(RouteRepository repository) => ProviderContainer(
  overrides: [routeRepositoryProvider.overrideWith((ref) async => repository)],
);

ProviderContainer _ready(RouteRepository repository) {
  final container = _container(repository);
  container.read(routeRequestControllerProvider);
  _gps(container.read(navigationSessionProvider.notifier), _start, 1);
  return container;
}

void _gps(
  NavigationSessionController session,
  GeoCoordinate coordinate,
  int second,
) {
  session.updateGpsPosition(
    PositionSample(
      coordinate: coordinate,
      timestamp: DateTime.utc(2026, 1, 1, 0, 0, second),
      source: PositionSource.gps,
    ),
  );
}

RouteAlternatives _routes(GeoCoordinate start, GeoCoordinate end) =>
    RouteAlternatives(
      byMode: {
        RouteMode.normal: RouteAlternative(
          mode: RouteMode.normal,
          path: [start, end],
          metrics: const RouteMetrics(distanceMeters: 1000),
        ),
      },
    );

final class _Call {
  const _Call(this.start, this.end, this.mode);
  final GeoCoordinate start;
  final GeoCoordinate end;
  final RouteMode mode;
}

final class _PendingRepository implements RouteRepository {
  final calls = <_Call>[];
  final pending = <Completer<RouteAlternatives>>[];

  @override
  Future<RouteAlternatives> calculateRoute({
    required GeoCoordinate start,
    required GeoCoordinate end,
    RouteMode mode = RouteMode.normal,
  }) {
    calls.add(_Call(start, end, mode));
    final completer = Completer<RouteAlternatives>();
    pending.add(completer);
    return completer.future;
  }
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}
