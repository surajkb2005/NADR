import 'package:flutter/material.dart' hide NavigationMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/imu/application/imu_navigation_state.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';
import 'package:nadr_mobile/features/navigation/domain/navigation_session_state.dart';
import 'package:nadr_mobile/features/navigation/presentation/navigation_status_panel.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

PositionSample _sample({double? heading, double? accuracy}) => PositionSample(
  coordinate: const GeoCoordinate(latitude: 12.97, longitude: 77.59),
  timestamp: DateTime(2026),
  source: PositionSource.gps,
  heading: heading,
  horizontalAccuracyMeters: accuracy,
);

void main() {
  testWidgets('GPS mode with reported accuracy shows accuracy and heading', (
    tester,
  ) async {
    final session = NavigationSessionState(
      navigationMode: NavigationMode.gps,
      latestGpsPosition: _sample(heading: 45, accuracy: 8),
    );
    final data = NavigationStatusData.fromSessionState(session: session);

    await tester.pumpWidget(_wrap(NavigationStatusPanel(data: data)));

    expect(find.text('GPS mode'), findsOneWidget);
    expect(find.text('±8 m'), findsOneWidget);
    expect(find.text('45°'), findsOneWidget);
  });

  testWidgets('GPS mode with no fix shows "No GPS fix", no heading', (
    tester,
  ) async {
    final session = NavigationSessionState(navigationMode: NavigationMode.gps);
    final data = NavigationStatusData.fromSessionState(session: session);

    await tester.pumpWidget(_wrap(NavigationStatusPanel(data: data)));

    expect(find.text('No GPS fix'), findsOneWidget);
    expect(find.text('Heading unavailable'), findsOneWidget);
  });

  testWidgets(
    'GPS mode with fix but unreported accuracy shows "Accuracy unknown"',
    (tester) async {
      final session = NavigationSessionState(
        navigationMode: NavigationMode.gps,
        latestGpsPosition: _sample(),
      );
      final data = NavigationStatusData.fromSessionState(session: session);

      await tester.pumpWidget(_wrap(NavigationStatusPanel(data: data)));

      expect(find.text('Accuracy unknown'), findsOneWidget);
    },
  );

  testWidgets('IMU active with heading shows heading value', (tester) async {
    final session = NavigationSessionState(
      navigationMode: NavigationMode.imu,
      latestImuPosition: _sample(heading: 0),
    );
    final imuState = const ImuNavigationState(ImuNavigationPhase.active);
    final data = NavigationStatusData.fromSessionState(
      session: session,
      imuState: imuState,
    );

    await tester.pumpWidget(_wrap(NavigationStatusPanel(data: data)));

    expect(find.text('IMU mode'), findsOneWidget);
    expect(find.text('IMU active'), findsOneWidget);
    expect(find.text('0°'), findsOneWidget);
  });

  testWidgets(
    'IMU headingUnavailable phase hides heading even if a stale value exists',
    (tester) async {
      final session = NavigationSessionState(
        navigationMode: NavigationMode.imu,
        latestImuPosition: _sample(heading: 120),
      );
      final imuState = const ImuNavigationState(
        ImuNavigationPhase.headingUnavailable,
      );
      final data = NavigationStatusData.fromSessionState(
        session: session,
        imuState: imuState,
      );

      await tester.pumpWidget(_wrap(NavigationStatusPanel(data: data)));

      expect(find.text('No heading'), findsOneWidget);
      expect(find.text('Heading unavailable'), findsOneWidget);
      expect(find.text('120°'), findsNothing);
    },
  );

  testWidgets('Long IMU label and narrow layout wraps without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final session = NavigationSessionState(
      navigationMode: NavigationMode.imu,
      latestImuPosition: _sample(),
    );
    final imuState = const ImuNavigationState(ImuNavigationPhase.calibrating);
    final data = NavigationStatusData.fromSessionState(
      session: session,
      imuState: imuState,
    );

    await tester.pumpWidget(_wrap(NavigationStatusPanel(data: data)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'GPS tracking state distinguishes waiting, active, and unavailable',
    (tester) async {
      for (final (status, label) in [
        (LocationTrackingStatus.acquiring, 'GPS waiting'),
        (LocationTrackingStatus.active, 'GPS tracking'),
        (LocationTrackingStatus.error, 'GPS unavailable'),
      ]) {
        final data = NavigationStatusData.fromSessionState(
          session: NavigationSessionState(),
          locationState: DeviceLocationState(trackingStatus: status),
        );
        await tester.pumpWidget(_wrap(NavigationStatusPanel(data: data)));
        expect(find.text(label), findsOneWidget);
      }
    },
  );

  testWidgets('disabled service overrides active tracking', (tester) async {
    final data = NavigationStatusData.fromSessionState(
      session: NavigationSessionState(),
      locationState: const DeviceLocationState(
        serviceStatus: LocationServiceStatus.disabled,
        trackingStatus: LocationTrackingStatus.active,
      ),
    );
    await tester.pumpWidget(_wrap(NavigationStatusPanel(data: data)));
    expect(find.text('GPS unavailable'), findsOneWidget);
  });

  testWidgets('invalid GPS accuracy remains unknown', (tester) async {
    final data = NavigationStatusData.fromSessionState(
      session: NavigationSessionState(
        latestGpsPosition: _sample(accuracy: double.nan),
      ),
    );
    await tester.pumpWidget(_wrap(NavigationStatusPanel(data: data)));
    expect(find.text('Accuracy unknown'), findsOneWidget);
  });

  testWidgets('unknown location state remains unlabelled', (tester) async {
    await tester.pumpWidget(
      _wrap(
        NavigationStatusPanel(
          data: NavigationStatusData.fromSessionState(
            session: NavigationSessionState(),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('nav-status-tracking')), findsNothing);
  });

  testWidgets('narrow GPS layout with tracking label does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = NavigationStatusData.fromSessionState(
      session: NavigationSessionState(latestGpsPosition: _sample(accuracy: 12)),
      locationState: const DeviceLocationState(
        trackingStatus: LocationTrackingStatus.acquiring,
      ),
    );
    await tester.pumpWidget(_wrap(NavigationStatusPanel(data: data)));
    expect(tester.takeException(), isNull);
  });
}
