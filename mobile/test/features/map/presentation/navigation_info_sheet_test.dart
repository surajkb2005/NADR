import 'package:flutter/material.dart' hide NavigationMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/imu/application/imu_navigation_state.dart';
import 'package:nadr_mobile/features/destination/presentation/destination_info_card.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';
import 'package:nadr_mobile/features/navigation/domain/navigation_session_state.dart';
import 'package:nadr_mobile/features/navigation/presentation/navigation_issue_resolver.dart';
import 'package:nadr_mobile/features/navigation/presentation/navigation_status_panel.dart';
import 'package:nadr_mobile/features/routing/application/route_request_controller.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/features/routing/presentation/route_info_card.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/navigation_info_sheet.dart';
import 'package:nadr_mobile/shared/widgets/bottom_sheet_surface.dart';
import 'package:nadr_mobile/shared/widgets/dedup_issue_banner.dart';

const _destination = Destination(
  coordinate: GeoCoordinate(latitude: 12.97, longitude: 77.59),
);

NavigationStatusData _gpsStatus({double? accuracy, double? heading}) {
  return NavigationStatusData.fromSessionState(
    session: NavigationSessionState(
      latestGpsPosition: PositionSample(
        coordinate: const GeoCoordinate(latitude: 12.96, longitude: 77.58),
        timestamp: DateTime.utc(2026),
        source: PositionSource.gps,
        heading: heading,
        horizontalAccuracyMeters: accuracy,
      ),
    ),
  );
}

NavigationStatusData _imuStatus({
  double? heading,
  ImuNavigationPhase phase = ImuNavigationPhase.active,
}) {
  final imu = ImuNavigationState(phase);
  return NavigationStatusData.fromSessionState(
    session: NavigationSessionState(
      navigationMode: NavigationMode.imu,
      latestImuPosition: PositionSample(
        coordinate: const GeoCoordinate(latitude: 12.96, longitude: 77.58),
        timestamp: DateTime.utc(2026),
        source: PositionSource.imu,
        heading: heading,
      ),
    ),
    imuState: imu,
  );
}

Widget _sheet({
  NavigationStatusData? status,
  Destination? destination,
  RouteRequestState routeRequestState = const RouteRequestState(),
  RouteAlternative? selectedRoute,
  RouteAlternatives? routeAlternatives,
  NavigationIssue? issue,
  ValueChanged<RouteMode>? onSelectRoute,
  VoidCallback? onRetryRoute,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          const ColoredBox(
            key: ValueKey('map-under-sheet'),
            color: Colors.blueGrey,
            child: SizedBox.expand(),
          ),
          NavigationInfoSheet(
            status: status ?? _gpsStatus(),
            destination: destination,
            routeRequestState: routeRequestState,
            selectedRoute: selectedRoute,
            routeAlternatives: routeAlternatives,
            issue: issue,
            onSelectRoute: onSelectRoute,
            onRetryRoute: onRetryRoute ?? () {},
          ),
        ],
      ),
    ),
  );
}

RouteAlternative _route({
  required RouteMode mode,
  double? distance,
  double? eta,
  RiskZone? maximumRisk,
}) =>
    RouteAlternative(
      mode: mode,
      path: const [
        GeoCoordinate(latitude: 12.96, longitude: 77.58),
        GeoCoordinate(latitude: 12.97, longitude: 77.59),
      ],
      metrics: RouteMetrics(
        distanceMeters: distance,
        estimatedTimeSeconds: eta,
        maximumRiskZone: maximumRisk,
      ),
    );

void main() {
  testWidgets('no-destination sheet stays compact without duplicate prompts', (
    tester,
  ) async {
    await tester.pumpWidget(_sheet(status: _gpsStatus(accuracy: 8)));

    expect(find.byType(BottomSheetSurface), findsOneWidget);
    expect(find.text('±8 m'), findsOneWidget);
    expect(find.text('GPS mode'), findsNothing);
    expect(find.text('Heading unavailable'), findsNothing);
    expect(find.text('No destination selected'), findsNothing);
    expect(find.byType(DestinationInfoCard), findsNothing);
    expect(find.byType(RouteInfoCard), findsNothing);
    expect(find.byKey(const ValueKey('get-route-button')), findsNothing);
    expect(find.byKey(const ValueKey('map-under-sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected destination and missing-position wait are truthful', (
    tester,
  ) async {
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 12.97, longitude: 77.59),
      displayLabel: 'A long but readable destination label',
    );
    await tester.pumpWidget(
      _sheet(
        status: _gpsStatus(),
        destination: destination,
        routeRequestState: const RouteRequestState(
          phase: RouteRequestPhase.waitingForPosition,
          message: 'Waiting for your current position.',
        ),
      ),
    );

    expect(find.text('A long but readable destination label'), findsOneWidget);
    expect(find.text('12.97, 77.59'), findsOneWidget);
    expect(find.text('Waiting for your current position.'), findsOneWidget);
    expect(find.byKey(const ValueKey('get-route-button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading sheet keeps map visible and shows compact progress text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sheet(
        destination: _destination,
        routeRequestState: const RouteRequestState(
          phase: RouteRequestPhase.loading,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('map-under-sheet')), findsOneWidget);
    expect(find.text('Calculating route…'), findsOneWidget);
    expect(find.byKey(const ValueKey('get-route-button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route success shows real metrics and selectable profiles', (
    tester,
  ) async {
    final normal = _route(
      mode: RouteMode.normal,
      distance: 4200,
      eta: 900,
      maximumRisk: RiskZone.medium,
    );
    final safe = _route(mode: RouteMode.safe, distance: 4700);
    RouteMode? selected;
    await tester.pumpWidget(
      _sheet(
        destination: _destination,
        routeRequestState: const RouteRequestState(
          phase: RouteRequestPhase.success,
          alternativeCount: 2,
        ),
        selectedRoute: normal,
        routeAlternatives: RouteAlternatives(
          byMode: {RouteMode.normal: normal, RouteMode.safe: safe},
        ),
        onSelectRoute: (mode) => selected = mode,
      ),
    );

    expect(find.text('Route profile'), findsOneWidget);
    expect(find.text('4.2 km'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('Medium risk'), findsOneWidget);
    expect(find.text('normal route'), findsNothing);
    await tester.drag(find.byType(BottomSheetSurface), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Safe'));
    await tester.tap(find.text('Safe'));
    expect(selected, RouteMode.safe);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route failure uses one recoverable sheet action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _sheet(
        destination: _destination,
        routeRequestState: const RouteRequestState(
          phase: RouteRequestPhase.failure,
          message: 'The route request timed out. Try again.',
        ),
        onRetryRoute: () => retried = true,
      ),
    );

    expect(find.text('The route request timed out. Try again.'), findsOneWidget);
    expect(find.byType(DedupIssueBanner), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tester.drag(find.byType(BottomSheetSurface), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('route-info-retry')));
    await tester.tap(find.byKey(const ValueKey('route-info-retry')));
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IMU status stays truthful without a duplicate mode chip', (
    tester,
  ) async {
    final status = _imuStatus(phase: ImuNavigationPhase.calibrating);
    final issue = NavigationIssueResolver.resolveStatusIssue(
      mode: NavigationMode.imu,
      location: const DeviceLocationState(),
      imu: const ImuNavigationState(ImuNavigationPhase.calibrating),
    );
    await tester.pumpWidget(_sheet(status: status, issue: issue));

    expect(find.text('IMU mode'), findsNothing);
    expect(find.text('Calibrating IMU heading…'), findsOneWidget);
    expect(find.text('Heading unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active IMU keeps its real heading visible', (tester) async {
    await tester.pumpWidget(
      _sheet(status: _imuStatus(heading: 145)),
    );

    expect(find.text('IMU mode'), findsNothing);
    expect(find.text('IMU active'), findsOneWidget);
    expect(find.text('145°'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long destination label stays safe on narrow sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _sheet(
        destination: const Destination(
          coordinate: GeoCoordinate(latitude: 12.97, longitude: 77.59),
          displayLabel:
              'A very long destination label that must not widen the sheet or overflow',
        ),
        routeRequestState: const RouteRequestState(
          phase: RouteRequestPhase.loading,
        ),
      ),
    );

    expect(find.byType(DestinationInfoCard), findsOneWidget);
    expect(find.text('Calculating route…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
