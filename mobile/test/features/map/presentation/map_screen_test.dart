import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';
import 'package:nadr_mobile/app/theme/nadr_theme.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart' as domain;
import 'package:nadr_mobile/features/map/presentation/map_screen.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/maplibre_map_surface.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/navigation_mode_control.dart';
import 'package:nadr_mobile/features/location/application/location_coordinator.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/shared/widgets/bottom_sheet_surface.dart';

import '../../../support/fake_device_location_source.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          AppEnvironment(
            apiBaseUrl: 'https://api.example.test',
            wsBaseUrl: 'wss://api.example.test/ws',
            mapStyleUrl: '',
          ),
        ),
        deviceLocationSourceProvider.overrideWithValue(
          FakeDeviceLocationSource(),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  Widget testApp({ThemeMode themeMode = ThemeMode.light}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NadrTheme.light,
        darkTheme: NadrTheme.dark,
        themeMode: themeMode,
        home: const MapScreen(),
      ),
    );
  }

  testWidgets('main map-first screen and destination surface render', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('map-placeholder')), findsNothing);
    expect(find.byKey(const ValueKey('map-configuration-error')), findsOne);
    expect(find.textContaining('NADR_MAP_STYLE_URL'), findsOneWidget);
    expect(find.text('Choose destination'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('backend-diagnostics-button')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('NADR'), findsOneWidget);
  });

  testWidgets('configured map style is read through AppEnvironment', (
    tester,
  ) async {
    MapSurfaceConfiguration? capturedConfiguration;
    Widget fakeSurfaceBuilder(
      MapSurfaceConfiguration configuration,
      MapSurfaceCallbacks callbacks,
    ) {
      capturedConfiguration = configuration;
      return const ColoredBox(
        key: ValueKey('fake-map-surface'),
        color: Colors.green,
      );
    }

    final configuredContainer = ProviderContainer(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          AppEnvironment(
            apiBaseUrl: 'https://api.example.test',
            wsBaseUrl: 'wss://api.example.test/ws',
            mapStyleUrl: 'https://maps.example.test/style.json',
          ),
        ),
        mapSurfaceBuilderProvider.overrideWithValue(fakeSurfaceBuilder),
        deviceLocationSourceProvider.overrideWithValue(
          FakeDeviceLocationSource(),
        ),
      ],
    );
    addTearDown(configuredContainer.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: configuredContainer,
        child: MaterialApp(theme: NadrTheme.light, home: const MapScreen()),
      ),
    );

    expect(find.byKey(const ValueKey('fake-map-surface')), findsOneWidget);
    expect(
      capturedConfiguration?.styleUri,
      Uri.parse('https://maps.example.test/style.json'),
    );
    expect(capturedConfiguration?.initialCamera.center.latitude, 12.9716);
    expect(capturedConfiguration?.initialCamera.center.longitude, 77.5946);
  });

  testWidgets('GPS and IMU control uses navigation session state', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.pump();

    expect(find.byType(NavigationModeControl), findsOneWidget);
    expect(find.text('Location active'), findsOneWidget);
    expect(
      container.read(navigationSessionProvider).navigationMode,
      domain.NavigationMode.gps,
    );

    var control = tester.widget<SegmentedButton<domain.NavigationMode>>(
      find.byType(SegmentedButton<domain.NavigationMode>),
    );
    expect(control.selected, {domain.NavigationMode.gps});

    await tester.tap(find.text('IMU').first);
    await tester.pump();
    expect(
      container.read(navigationSessionProvider).navigationMode,
      domain.NavigationMode.imu,
    );

    control = tester.widget<SegmentedButton<domain.NavigationMode>>(
      find.byType(SegmentedButton<domain.NavigationMode>),
    );
    expect(control.selected, {domain.NavigationMode.imu});

    await tester.tap(find.text('GPS').first);
    await tester.pump();
    expect(
      container.read(navigationSessionProvider).navigationMode,
      domain.NavigationMode.gps,
    );
  });

  testWidgets('bottom sheet and unavailable reset control render', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());

    expect(find.text('NADR Navigation'), findsOneWidget);
    expect(find.text('No destination selected'), findsOneWidget);
    expect(
      find.text('Select a destination to view route information.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('navigation-info-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('recenter-button')), findsOneWidget);

    final recenter = tester.widget<FloatingActionButton>(
      find.byKey(const ValueKey('recenter-button')),
    );
    expect(recenter.onPressed, isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('recenter-button'))).width,
      56,
    );

    final initialSheetHeight = tester
        .getSize(find.byType(BottomSheetSurface))
        .height;
    await tester.drag(find.byType(BottomSheetSurface), const Offset(0, -180));
    await tester.pumpAndSettle();
    final expandedSheetHeight = tester
        .getSize(find.byType(BottomSheetSurface))
        .height;
    expect(expandedSheetHeight, greaterThan(initialSheetHeight));
  });

  testWidgets('no current-location marker is introduced', (tester) async {
    await tester.pumpWidget(testApp());

    expect(find.byKey(const ValueKey('current-location-marker')), findsNothing);
    expect(container.read(navigationSessionProvider).latestGpsPosition, isNull);
  });

  testWidgets('screen renders in dark mode without external dependencies', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(themeMode: ThemeMode.dark));

    expect(
      Theme.of(tester.element(find.byType(MapScreen))).brightness,
      Brightness.dark,
    );
    expect(find.text('Choose destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen remains usable on a compact Android display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(testApp());

    expect(find.text('Choose destination'), findsOneWidget);
    expect(find.byType(NavigationModeControl), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
