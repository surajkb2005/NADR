import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/core/network/nadr_rest_client.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/features/routing/application/route_request_controller.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/features/routing/domain/route_repository.dart';
import 'package:nadr_mobile/features/routing/infrastructure/rest_route_repository.dart';

void main() {
  test('requires a current position and confirmed destination', () async {
    final repository = _RecordingRouteRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    final requester = container.read(routeRequestControllerProvider.notifier);

    expect(await requester.requestRoute(), RouteRequestOutcome.missingStart);
    _setGps(container, const GeoCoordinate(latitude: 1, longitude: 2));
    expect(
      await requester.requestRoute(),
      RouteRequestOutcome.missingDestination,
    );
    expect(repository.calls, isEmpty);
  });

  test('GPS mode snapshots accepted GPS start and destination', () async {
    final repository = _RecordingRouteRepository();
    final container = _readyContainer(repository);
    addTearDown(container.dispose);

    expect(
      await container
          .read(routeRequestControllerProvider.notifier)
          .requestRoute(),
      RouteRequestOutcome.success,
    );

    expect(repository.calls, hasLength(1));
    expect(
      repository.calls.single.start,
      const GeoCoordinate(latitude: 12.1, longitude: 77.2),
    );
    expect(
      repository.calls.single.end,
      const GeoCoordinate(latitude: 12.3, longitude: 77.4),
    );
    expect(repository.calls.single.mode, RouteMode.normal);
  });

  test(
    'IMU mode uses current displayed IMU position at request time',
    () async {
      final repository = _RecordingRouteRepository();
      final container = _readyContainer(repository);
      addTearDown(container.dispose);
      final session = container.read(navigationSessionProvider.notifier);
      session.updateImuPosition(
        _position(
          PositionSource.imu,
          const GeoCoordinate(latitude: 12.2, longitude: 77.3),
        ),
      );
      session.setNavigationMode(NavigationMode.imu);

      await container
          .read(routeRequestControllerProvider.notifier)
          .requestRoute();

      expect(
        repository.calls.single.start,
        const GeoCoordinate(latitude: 12.2, longitude: 77.3),
      );
    },
  );

  test(
    'in-flight request keeps its endpoint snapshot during updates',
    () async {
      final completer = Completer<RouteAlternatives>();
      final repository = _RecordingRouteRepository(result: completer.future);
      final container = _readyContainer(repository);
      addTearDown(container.dispose);
      final requester = container.read(routeRequestControllerProvider.notifier);

      final request = requester.requestRoute();
      await Future<void>.delayed(Duration.zero);
      final session = container.read(navigationSessionProvider.notifier);
      _setGps(container, const GeoCoordinate(latitude: 55, longitude: 66));
      session.setDestination(
        const Destination(
          coordinate: GeoCoordinate(latitude: 33, longitude: 44),
        ),
      );
      completer.complete(_alternatives());

      expect(await request, RouteRequestOutcome.success);
      expect(
        repository.calls.single.start,
        const GeoCoordinate(latitude: 12.1, longitude: 77.2),
      );
      expect(
        repository.calls.single.end,
        const GeoCoordinate(latitude: 12.3, longitude: 77.4),
      );
    },
  );

  test('rapid taps are coalesced into one backend request', () async {
    final completer = Completer<RouteAlternatives>();
    final repository = _RecordingRouteRepository(result: completer.future);
    final container = _readyContainer(repository);
    addTearDown(container.dispose);
    final requester = container.read(routeRequestControllerProvider.notifier);

    final first = requester.requestRoute();
    final duplicate = await requester.requestRoute();

    expect(duplicate, RouteRequestOutcome.duplicateIgnored);
    completer.complete(_alternatives());
    expect(await first, RouteRequestOutcome.success);
    expect(repository.calls, hasLength(1));
  });

  test(
    'success stores all alternatives and compact status in session',
    () async {
      final repository = _RecordingRouteRepository();
      final container = _readyContainer(repository);
      addTearDown(container.dispose);

      await container
          .read(routeRequestControllerProvider.notifier)
          .requestRoute();

      final session = container.read(navigationSessionProvider);
      final request = container.read(routeRequestControllerProvider);
      expect(session.routeAlternatives.byMode, hasLength(4));
      expect(session.selectedRouteMode, RouteMode.normal);
      expect(
        session.selectedRoute,
        same(session.routeAlternatives[RouteMode.normal]),
      );
      expect(session.destination, isNotNull);
      expect(session.isLoading, isFalse);
      expect(request.phase, RouteRequestPhase.success);
      expect(request.alternativeCount, 4);
    },
  );

  test(
    'failure preserves destination, mode, position, and previous route',
    () async {
      final repository = _RecordingRouteRepository(
        failure: const NadrNetworkException(
          NadrNetworkErrorKind.timeout,
          'raw timeout detail',
        ),
      );
      final container = _readyContainer(repository);
      addTearDown(container.dispose);
      final session = container.read(navigationSessionProvider.notifier);
      session.setRouteAlternatives(_alternatives());
      session.selectRoute(RouteMode.safe);
      session.updateImuPosition(
        _position(
          PositionSource.imu,
          const GeoCoordinate(latitude: 12.2, longitude: 77.3),
        ),
      );
      session.setNavigationMode(NavigationMode.imu);
      final before = container.read(navigationSessionProvider);

      expect(
        await container
            .read(routeRequestControllerProvider.notifier)
            .requestRoute(),
        RouteRequestOutcome.failed,
      );

      final after = container.read(navigationSessionProvider);
      expect(after.destination, before.destination);
      expect(after.navigationMode, NavigationMode.imu);
      expect(after.displayedPosition, before.displayedPosition);
      expect(after.routeAlternatives, same(before.routeAlternatives));
      expect(after.selectedRoute, same(before.selectedRoute));
      expect(after.errorMessage, 'The route request timed out. Try again.');
      expect(after.errorMessage, isNot(contains('raw')));
    },
  );

  test('cancellation is quiet and preserves existing state', () async {
    final repository = _RecordingRouteRepository(
      failure: const NadrNetworkException(
        NadrNetworkErrorKind.cancelled,
        'cancelled',
      ),
    );
    final container = _readyContainer(repository);
    addTearDown(container.dispose);

    expect(
      await container
          .read(routeRequestControllerProvider.notifier)
          .requestRoute(),
      RouteRequestOutcome.cancelled,
    );
    expect(container.read(navigationSessionProvider).errorMessage, isNull);
    expect(
      container.read(routeRequestControllerProvider).phase,
      RouteRequestPhase.idle,
    );
  });

  test('GPS and IMU updates never auto-request or clear route data', () async {
    final repository = _RecordingRouteRepository();
    final container = _readyContainer(repository);
    addTearDown(container.dispose);
    final session = container.read(navigationSessionProvider.notifier);
    session.setRouteAlternatives(_alternatives());
    final routeState = container
        .read(navigationSessionProvider)
        .routeAlternatives;

    _setGps(container, const GeoCoordinate(latitude: 13, longitude: 78));
    session.updateImuPosition(
      _position(
        PositionSource.imu,
        const GeoCoordinate(latitude: 13.1, longitude: 78.1),
      ),
    );
    session.setNavigationMode(NavigationMode.imu);
    session.setNavigationMode(NavigationMode.gps);

    expect(repository.calls, isEmpty);
    expect(
      container.read(navigationSessionProvider).routeAlternatives,
      same(routeState),
    );
    expect(container.read(navigationSessionProvider).destination, isNotNull);
  });
}

ProviderContainer _container(RouteRepository repository) => ProviderContainer(
  overrides: [routeRepositoryProvider.overrideWith((ref) async => repository)],
);

ProviderContainer _readyContainer(RouteRepository repository) {
  final container = _container(repository);
  _setGps(container, const GeoCoordinate(latitude: 12.1, longitude: 77.2));
  container
      .read(navigationSessionProvider.notifier)
      .setDestination(
        const Destination(
          coordinate: GeoCoordinate(latitude: 12.3, longitude: 77.4),
        ),
      );
  return container;
}

void _setGps(ProviderContainer container, GeoCoordinate coordinate) {
  container
      .read(navigationSessionProvider.notifier)
      .updateGpsPosition(_position(PositionSource.gps, coordinate));
}

PositionSample _position(PositionSource source, GeoCoordinate coordinate) =>
    PositionSample(
      coordinate: coordinate,
      timestamp: DateTime.now().toUtc(),
      source: source,
    );

RouteAlternatives _alternatives() {
  const path = [
    GeoCoordinate(latitude: 12.1, longitude: 77.2),
    GeoCoordinate(latitude: 12.3, longitude: 77.4),
  ];
  return RouteAlternatives(
    byMode: {
      for (final mode in RouteMode.values)
        mode: RouteAlternative(
          mode: mode,
          path: path,
          metrics: const RouteMetrics(distanceMeters: 1000),
        ),
    },
  );
}

final class _RouteCall {
  const _RouteCall(this.start, this.end, this.mode);
  final GeoCoordinate start;
  final GeoCoordinate end;
  final RouteMode mode;
}

final class _RecordingRouteRepository implements RouteRepository {
  _RecordingRouteRepository({this.result, this.failure});

  final Future<RouteAlternatives>? result;
  final Object? failure;
  final calls = <_RouteCall>[];

  @override
  Future<RouteAlternatives> calculateRoute({
    required GeoCoordinate start,
    required GeoCoordinate end,
    RouteMode mode = RouteMode.normal,
  }) {
    calls.add(_RouteCall(start, end, mode));
    if (failure case final error?) return Future.error(error);
    return result ?? Future.value(_alternatives());
  }
}
