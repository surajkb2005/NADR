import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/destination/application/place_search_controller.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_repository.dart';
import 'package:nadr_mobile/features/destination/domain/place_search_result.dart';
import 'package:nadr_mobile/features/destination/infrastructure/unconfigured_place_search_repository.dart';
import 'package:nadr_mobile/features/destination/presentation/destination_search_surface.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';

final _first = PlaceSearchResult(
  label: 'A very long station name that should fit in a narrow search bar',
  subtitle: 'Central district',
  coordinate: const GeoCoordinate(latitude: 12.98, longitude: 77.60),
);
final _second = PlaceSearchResult(
  label: 'Second place',
  coordinate: const GeoCoordinate(latitude: 13.01, longitude: 77.61),
);

void main() {
  testWidgets('rounded field, idle state, clear text, and fallback action', (
    tester,
  ) async {
    var fallbackOpened = false;
    final container = _container(_FakeRepository((_) async => []));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _app(container, onFallback: () => fallbackOpened = true),
    );
    expect(
      find.byKey(const ValueKey('destination-search-surface')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('destination-suggestions')), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('destination-search-field')),
          )
          .decoration
          ?.hintText,
      'Search destination',
    );
    final material = tester.widget<Material>(
      find.byKey(const ValueKey('destination-search-surface')),
    );
    expect(material.borderRadius, BorderRadius.circular(28));
    await tester.enterText(
      find.byKey(const ValueKey('destination-search-field')),
      'ab',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('clear-search-text')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('clear-search-text')));
    await tester.pump();
    expect(container.read(placeSearchControllerProvider).query, isEmpty);
    await tester.tap(find.byKey(const ValueKey('destination-surface')));
    expect(fallbackOpened, isTrue);
  });

  testWidgets(
    'loading, multiple results, subtitle, selection and replacement',
    (tester) async {
      final repository = _FakeRepository((_) async => [_first, _second]);
      final container = _container(repository);
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(container));
      await tester.enterText(
        find.byKey(const ValueKey('destination-search-field')),
        'first',
      );
      await tester.pump();
      expect(find.text('Searching…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(find.text(_first.label), findsOneWidget);
      expect(find.text('Central district'), findsOneWidget);
      expect(find.text('Second place'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('place-result-0')));
      await tester.pump();
      expect(
        container.read(navigationSessionProvider).destination?.coordinate,
        _first.coordinate,
      );
      expect(
        container.read(navigationSessionProvider).destination?.displayLabel,
        _first.label,
      );
      expect(
        find.byKey(const ValueKey('destination-suggestions')),
        findsNothing,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('destination-search-field')),
            )
            .controller
            ?.text,
        _first.label,
      );
      await tester.enterText(
        find.byKey(const ValueKey('destination-search-field')),
        'second',
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('place-result-1')));
      await tester.pump();
      expect(
        container.read(navigationSessionProvider).destination?.coordinate,
        _second.coordinate,
      );
      expect(
        container.read(navigationSessionProvider).destination?.displayLabel,
        'Second place',
      );
    },
  );

  testWidgets('empty and provider failure remain compact and recoverable', (
    tester,
  ) async {
    final empty = _container(_FakeRepository((_) async => []));
    addTearDown(empty.dispose);
    await tester.pumpWidget(_app(empty));
    await tester.enterText(
      find.byKey(const ValueKey('destination-search-field')),
      'unknown',
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);

    final unavailable = _container(const UnconfiguredPlaceSearchRepository());
    addTearDown(unavailable.dispose);
    await tester.pumpWidget(_app(unavailable));
    await tester.enterText(
      find.byKey(const ValueKey('destination-search-field')),
      'station',
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(find.text('Search unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'editing clear preserves destination and outside tap dismisses results',
    (tester) async {
      final container = _container(_FakeRepository((_) async => [_first]));
      addTearDown(container.dispose);
      container
          .read(navigationSessionProvider.notifier)
          .setDestination(
            const Destination(
              coordinate: GeoCoordinate(latitude: 1, longitude: 2),
              displayLabel: 'Original',
            ),
          );
      await tester.pumpWidget(_app(container));
      await tester.enterText(
        find.byKey(const ValueKey('destination-search-field')),
        'place',
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('destination-suggestions')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('outside')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('destination-suggestions')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('clear-search-text')));
      await tester.pump();
      expect(
        container.read(navigationSessionProvider).destination?.displayLabel,
        'Original',
      );
    },
  );

  testWidgets('dark narrow layout handles long selected label', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = _container(_FakeRepository((_) async => [_first]));
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container, dark: true));
    await tester.enterText(
      find.byKey(const ValueKey('destination-search-field')),
      'station',
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('place-result-0')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.byType(DestinationSearchSurface)))
          .brightness,
      Brightness.dark,
    );
  });
}

ProviderContainer _container(PlaceSearchRepository repository) =>
    ProviderContainer(
      overrides: [
        placeSearchRepositoryProvider.overrideWithValue(repository),
        placeSearchDebounceProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );

Widget _app(
  ProviderContainer container, {
  VoidCallback? onFallback,
  bool dark = false,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: ThemeData(useMaterial3: true),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.green)),
          Align(
            alignment: Alignment.bottomCenter,
            child: TextButton(
              key: const ValueKey('outside'),
              onPressed: () {},
              child: const Text('Outside'),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: DestinationSearchSurface(
                destination: container
                    .read(navigationSessionProvider)
                    .destination,
                onSelect: container
                    .read(navigationSessionProvider.notifier)
                    .setDestination,
                onOpenFallback: onFallback ?? () {},
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

final class _FakeRepository implements PlaceSearchRepository {
  _FakeRepository(this.result);
  final Future<List<PlaceSearchResult>> Function(String) result;
  @override
  Future<List<PlaceSearchResult>> search(String query) => result(query);
}
