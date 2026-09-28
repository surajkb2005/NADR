import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';
import 'package:nadr_mobile/app/theme/nadr_theme.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart' as domain;
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/core/network/nadr_rest_client.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_repository.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_result.dart';
import 'package:nadr_mobile/features/destination/infrastructure/unconfigured_place_search_repository.dart';
import 'package:nadr_mobile/features/destination/application/place_search_controller.dart';
import 'package:nadr_mobile/features/map/domain/current_location_marker.dart';
import 'package:nadr_mobile/features/map/domain/map_camera.dart';
import 'package:nadr_mobile/features/map/domain/nadr_map_controller.dart';
import 'package:nadr_mobile/features/map/presentation/map_screen.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/maplibre_map_surface.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/navigation_mode_control.dart';
import 'package:nadr_mobile/features/location/application/location_coordinator.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/features/routing/domain/route_repository.dart';
import 'package:nadr_mobile/features/routing/infrastructure/rest_route_repository.dart';
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
    expect(
      find.byKey(const ValueKey('destination-search-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('backend-diagnostics-button')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
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
    expect(
      find.byKey(const ValueKey('destination-search-field')),
      findsOneWidget,
    );
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

    expect(
      find.byKey(const ValueKey('destination-search-field')),
      findsOneWidget,
    );
    expect(find.byType(NavigationModeControl), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('destination surface opens the two-method selection panel', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());

    await tester.tap(find.byKey(const ValueKey('destination-surface')));
    await tester.pumpAndSettle();

    expect(find.text('Choose destination'), findsOneWidget);
    expect(find.text('Select a point on the map'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('destination-latitude-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('destination-longitude-field')),
      findsOneWidget,
    );
  });

  testWidgets('manual coordinates confirm, replace, and clear destination', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());

    await _openDestinationPanel(tester);
    await tester.enterText(
      find.byKey(const ValueKey('destination-latitude-field')),
      '12.3456789',
    );
    await tester.enterText(
      find.byKey(const ValueKey('destination-longitude-field')),
      '-45.9876543',
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm-coordinate-destination')),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(navigationSessionProvider).destination,
      const Destination(
        coordinate: GeoCoordinate(latitude: 12.3456789, longitude: -45.9876543),
      ),
    );
    expect(find.text('12.3456789, -45.9876543'), findsWidgets);

    await _openDestinationPanel(tester);
    await tester.enterText(
      find.byKey(const ValueKey('destination-latitude-field')),
      '-33.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('destination-longitude-field')),
      '151.2',
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm-coordinate-destination')),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(navigationSessionProvider).destination?.coordinate,
      const GeoCoordinate(latitude: -33.5, longitude: 151.2),
    );

    await _openDestinationPanel(tester);
    await tester.tap(find.byKey(const ValueKey('clear-destination')));
    await tester.pumpAndSettle();
    expect(container.read(navigationSessionProvider).destination, isNull);
  });

  testWidgets('canceling selection preserves an existing destination', (
    tester,
  ) async {
    const original = Destination(
      coordinate: GeoCoordinate(latitude: 10.25, longitude: 20.75),
    );
    container.read(navigationSessionProvider.notifier).setDestination(original);
    await tester.pumpWidget(testApp());

    await _openDestinationPanel(tester);
    await tester.tap(find.byKey(const ValueKey('close-destination-panel')));
    await tester.pumpAndSettle();

    expect(container.read(navigationSessionProvider).destination, original);
  });

  testWidgets(
    'map long-press requires selection mode and review confirmation',
    (tester) async {
      late MapSurfaceCallbacks callbacks;
      final configured = _configuredContainer(
        onCallbacks: (value) => callbacks = value,
      );
      addTearDown(configured.dispose);
      await tester.pumpWidget(_configuredApp(configured));
      await tester.pump();

      callbacks.onUserGesture();
      callbacks.onLongPress?.call(
        const GeoCoordinate(latitude: 1.5, longitude: 2.5),
      );
      await tester.pump();
      expect(configured.read(navigationSessionProvider).destination, isNull);
      expect(
        find.byKey(const ValueKey('confirm-map-destination')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('destination-surface')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-destination-on-map')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('map-destination-instructions')),
        findsOneWidget,
      );

      callbacks.onLongPress?.call(
        const GeoCoordinate(latitude: 1.5, longitude: 2.5),
      );
      await tester.pumpAndSettle();
      expect(find.text('Latitude: 1.5'), findsOneWidget);
      expect(configured.read(navigationSessionProvider).destination, isNull);
      await tester.tap(find.byKey(const ValueKey('confirm-map-destination')));
      await tester.pumpAndSettle();
      expect(
        configured.read(navigationSessionProvider).destination?.coordinate,
        const GeoCoordinate(latitude: 1.5, longitude: 2.5),
      );
    },
  );

  testWidgets(
    'map proposal cancellation leaves existing destination unchanged',
    (tester) async {
      late MapSurfaceCallbacks callbacks;
      final configured = _configuredContainer(
        onCallbacks: (value) => callbacks = value,
      );
      addTearDown(configured.dispose);
      const original = Destination(
        coordinate: GeoCoordinate(latitude: 5, longitude: 6),
      );
      configured
          .read(navigationSessionProvider.notifier)
          .setDestination(original);
      await tester.pumpWidget(_configuredApp(configured));

      await _openDestinationPanel(tester);
      await tester.tap(find.byKey(const ValueKey('select-destination-on-map')));
      await tester.pumpAndSettle();
      callbacks.onLongPress?.call(
        const GeoCoordinate(latitude: 7, longitude: 8),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cancel-map-destination')));
      await tester.pumpAndSettle();

      expect(configured.read(navigationSessionProvider).destination, original);
    },
  );

  testWidgets('destination selection requests a route; recenter does not', (
    tester,
  ) async {
    final adapter = _CountingAdapter();
    final client = NadrRestClient(
      baseUri: Uri.parse('https://api.example.test'),
      cookieJar: CookieJar(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(client.dispose);
    final mapController = _RecordingMapController();
    final configured = _configuredContainer(
      mapController: mapController,
      restClient: client,
    );
    addTearDown(configured.dispose);
    final session = configured.read(navigationSessionProvider.notifier);
    session.updateGpsPosition(
      PositionSample(
        coordinate: const GeoCoordinate(latitude: 12, longitude: 77),
        timestamp: DateTime.utc(2026, 9, 23),
        source: domain.PositionSource.gps,
      ),
    );
    await tester.pumpWidget(_configuredApp(configured));
    await tester.pumpAndSettle();
    await _openDestinationPanel(tester);
    await tester.enterText(
      find.byKey(const ValueKey('destination-latitude-field')),
      '13',
    );
    await tester.enterText(
      find.byKey(const ValueKey('destination-longitude-field')),
      '78',
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm-coordinate-destination')),
    );
    await tester.pumpAndSettle();
    expect(adapter.requests, 1);
    await tester.tap(find.byKey(const ValueKey('recenter-button')));
    await tester.pumpAndSettle();

    expect(
      configured.read(navigationSessionProvider).destination?.coordinate,
      const GeoCoordinate(latitude: 13, longitude: 78),
    );
    expect(adapter.requests, 1);
  });

  testWidgets('automatic route request stores data without a map layer', (
    tester,
  ) async {
    final repository = _WidgetRouteRepository();
    final configured = _configuredContainer(routeRepository: repository);
    addTearDown(configured.dispose);
    final session = configured.read(navigationSessionProvider.notifier);
    session.updateGpsPosition(
      PositionSample(
        coordinate: const GeoCoordinate(latitude: 12.1, longitude: 77.2),
        timestamp: DateTime.utc(2026, 9, 23),
        source: domain.PositionSource.gps,
      ),
    );
    session.setDestination(
      const Destination(
        coordinate: GeoCoordinate(latitude: 12.3, longitude: 77.4),
      ),
    );
    await tester.pumpWidget(_configuredApp(configured));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    await tester.drag(find.byType(BottomSheetSurface), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(
      configured.read(navigationSessionProvider).routeAlternatives.isNotEmpty,
      isTrue,
    );
    expect(find.text('Route data received (1 alternatives).'), findsOneWidget);
    expect(
      find.text('Route map rendering is coming in the next stage.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'search selection updates session and existing destination marker',
    (tester) async {
      final marker = _RecordingMapController();
      final configured = _configuredContainer(
        mapController: marker,
        placeSearchRepository: _WidgetSearchRepository(),
      );
      addTearDown(configured.dispose);
      await tester.pumpWidget(_configuredApp(configured));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('destination-search-field')),
        'MG Road',
      );
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump();
      await tester.tap(find.text('MG Road Station'));
      await tester.pump();
      final destination = configured
          .read(navigationSessionProvider)
          .destination;
      expect(
        destination?.coordinate,
        const GeoCoordinate(latitude: 12.98, longitude: 77.60),
      );
      expect(destination?.displayLabel, 'MG Road Station');
      expect(marker.destinationUpdates.last, destination);
      expect(find.text('MG Road Station'), findsOneWidget);
    },
  );
}

Future<void> _openDestinationPanel(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('destination-surface')));
  await tester.pumpAndSettle();
}

ProviderContainer _configuredContainer({
  ValueChanged<MapSurfaceCallbacks>? onCallbacks,
  _RecordingMapController? mapController,
  NadrRestClient? restClient,
  RouteRepository? routeRepository,
  PlaceSearchRepository? placeSearchRepository,
}) {
  final controller = mapController ?? _RecordingMapController();
  Widget surfaceBuilder(
    MapSurfaceConfiguration configuration,
    MapSurfaceCallbacks callbacks,
  ) {
    onCallbacks?.call(callbacks);
    return _FakeMapSurface(callbacks: callbacks, controller: controller);
  }

  return ProviderContainer(
    overrides: [
      appEnvironmentProvider.overrideWithValue(
        AppEnvironment(
          apiBaseUrl: 'https://api.example.test',
          wsBaseUrl: 'wss://api.example.test/ws',
          mapStyleUrl: 'https://maps.example.test/style.json',
        ),
      ),
      mapSurfaceBuilderProvider.overrideWithValue(surfaceBuilder),
      deviceLocationSourceProvider.overrideWithValue(
        FakeDeviceLocationSource(),
      ),
      if (restClient != null)
        nadrRestClientProvider.overrideWith((ref) async => restClient),
      if (routeRepository != null)
        routeRepositoryProvider.overrideWith((ref) async => routeRepository),
      if (placeSearchRepository != null) ...[
        placeSearchRepositoryProvider.overrideWithValue(placeSearchRepository),
        placeSearchDebounceProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    ],
  );
}

final class _WidgetSearchRepository implements PlaceSearchRepository {
  @override
  Future<List<PlaceSearchResult>> search(String query) async => [
    PlaceSearchResult(
      label: 'MG Road Station',
      coordinate: const GeoCoordinate(latitude: 12.98, longitude: 77.60),
    ),
  ];
}

Widget _configuredApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: NadrTheme.light, home: const MapScreen()),
  );
}

class _FakeMapSurface extends StatefulWidget {
  const _FakeMapSurface({required this.callbacks, required this.controller});

  final MapSurfaceCallbacks callbacks;
  final NadrMapController controller;

  @override
  State<_FakeMapSurface> createState() => _FakeMapSurfaceState();
}

class _FakeMapSurfaceState extends State<_FakeMapSurface> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.callbacks.onControllerReady(widget.controller);
      widget.callbacks.onStyleLoaded();
    });
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.green);
}

final class _RecordingMapController implements NadrMapController {
  final destinationUpdates = <Destination?>[];
  MapCameraState? camera;

  @override
  MapCameraState? get currentCamera => camera;

  @override
  MapBounds? get visibleBounds => null;

  @override
  Future<void> animateCamera(
    MapCameraUpdate update, {
    Duration duration = const Duration(milliseconds: 700),
  }) async {
    if (update.center != null) {
      camera = MapCameraState(
        center: update.center!,
        zoom: update.zoom ?? 16.5,
      );
    }
  }

  @override
  Future<void> fitBounds(
    MapBounds bounds, {
    MapViewportPadding padding = const MapViewportPadding(),
    Duration duration = const Duration(milliseconds: 700),
  }) async {}

  @override
  Future<void> moveCamera(MapCameraUpdate update) => animateCamera(update);

  @override
  Future<void> recenter(
    GeoCoordinate center, {
    double zoom = 16.5,
    bool animate = true,
  }) => animateCamera(MapCameraUpdate(center: center, zoom: zoom));

  @override
  Future<void> setCenter(GeoCoordinate center, {bool animate = true}) =>
      animateCamera(MapCameraUpdate(center: center));

  @override
  Future<void> setZoom(double zoom, {bool animate = true}) =>
      animateCamera(MapCameraUpdate(zoom: zoom));

  @override
  Future<void> updateCurrentLocationMarker(
    CurrentLocationMarkerData? marker,
  ) async {}

  @override
  Future<void> updateDestinationMarker(Destination? destination) async {
    destinationUpdates.add(destination);
  }
}

final class _CountingAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

final class _WidgetRouteRepository implements RouteRepository {
  int calls = 0;

  @override
  Future<RouteAlternatives> calculateRoute({
    required GeoCoordinate start,
    required GeoCoordinate end,
    RouteMode mode = RouteMode.normal,
  }) async {
    calls++;
    return RouteAlternatives(
      byMode: {
        RouteMode.normal: RouteAlternative(
          mode: RouteMode.normal,
          path: [start, end],
          metrics: const RouteMetrics(distanceMeters: 1000),
          optimization: 'fixture',
        ),
      },
    );
  }
}
