import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/features/routing/application/route_request_controller.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/features/routing/presentation/route_info_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

RouteAlternative _route({
  double? distance,
  double? etaSeconds,
  RiskZone? riskZone,
}) {
  return RouteAlternative(
    mode: RouteMode.normal,
    path: const [],
    metrics: RouteMetrics(
      distanceMeters: distance,
      estimatedTimeSeconds: etaSeconds,
      maximumRiskZone: riskZone,
    ),
  );
}

void main() {
  testWidgets('idle phase shows idle prompt', (tester) async {
    await tester.pumpWidget(
      _wrap(const RouteInfoCard(requestState: RouteRequestState())),
    );

    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('Route details will appear here.'), findsOneWidget);
  });

  testWidgets('loading phase shows loading message', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RouteInfoCard(
          requestState: RouteRequestState(phase: RouteRequestPhase.loading),
        ),
      ),
    );

    expect(find.text('Loading'), findsOneWidget);
    expect(find.text('Calculating route…'), findsOneWidget);
  });

  testWidgets('failure phase shows message and retry when provided', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      _wrap(
        RouteInfoCard(
          requestState: const RouteRequestState(
            phase: RouteRequestPhase.failure,
            message: 'Cannot reach the backend.',
          ),
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Cannot reach the backend.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('route-info-retry')));
    expect(retried, isTrue);
  });

  testWidgets('failure phase without onRetry shows no retry button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const RouteInfoCard(
          requestState: RouteRequestState(
            phase: RouteRequestPhase.failure,
            message: 'Failed.',
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('route-info-retry')), findsNothing);
  });

  testWidgets('success with zero alternatives shows empty message', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const RouteInfoCard(
          requestState: RouteRequestState(
            phase: RouteRequestPhase.success,
            alternativeCount: 0,
          ),
        ),
      ),
    );

    expect(find.text('Ready'), findsOneWidget);
    expect(
      find.text('No routes were returned for this destination.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'success without a selected route does not claim an empty result',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RouteInfoCard(
            requestState: RouteRequestState(
              phase: RouteRequestPhase.success,
              alternativeCount: 2,
            ),
          ),
        ),
      );
      expect(find.text('No route selected.'), findsOneWidget);
    },
  );

  testWidgets('success with full metrics shows distance, eta, and risk', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        RouteInfoCard(
          requestState: const RouteRequestState(
            phase: RouteRequestPhase.success,
            alternativeCount: 1,
          ),
          selectedRoute: _route(
            distance: 4200,
            etaSeconds: 900,
            riskZone: RiskZone.medium,
          ),
        ),
      ),
    );

    expect(find.text('4.2 km'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('Medium risk'), findsOneWidget);
  });

  testWidgets(
    'success with missing optional metrics shows no fabricated values',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          RouteInfoCard(
            requestState: const RouteRequestState(
              phase: RouteRequestPhase.success,
              alternativeCount: 1,
            ),
            selectedRoute: _route(),
          ),
        ),
      );

      expect(
        find.text('Route found. No additional metrics were provided.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('multiple alternatives show real modes and select callback', (
    tester,
  ) async {
    final normal = _route(distance: 1000);
    final safe = RouteAlternative(
      mode: RouteMode.safe,
      path: const [],
      metrics: const RouteMetrics(distanceMeters: 1200),
    );
    RouteMode? selected;
    await tester.pumpWidget(
      _wrap(
        RouteInfoCard(
          requestState: const RouteRequestState(
            phase: RouteRequestPhase.success,
            alternativeCount: 2,
          ),
          selectedRoute: normal,
          alternatives: RouteAlternatives(
            byMode: {RouteMode.normal: normal, RouteMode.safe: safe},
          ),
          onSelectRoute: (mode) => selected = mode,
        ),
      ),
    );
    expect(find.text('Route profile'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    await tester.tap(find.text('Safe'));
    expect(selected, RouteMode.safe);
  });

  testWidgets('route metrics fit a narrow layout with absent ETA and risk', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _wrap(
        RouteInfoCard(
          requestState: const RouteRequestState(
            phase: RouteRequestPhase.success,
            alternativeCount: 1,
          ),
          selectedRoute: _route(distance: 4200),
        ),
      ),
    );
    expect(find.text('4.2 km'), findsOneWidget);
    expect(find.text('15 min'), findsNothing);
    expect(find.text('Medium risk'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
