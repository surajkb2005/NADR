import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/features/map/domain/map_defaults.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/interactive_map_layer.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/maplibre_map_surface.dart';

void main() {
  testWidgets('missing style shows a controlled configuration error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InteractiveMapLayer(
          styleUri: null,
          initialCamera: MapDefaults.initialCamera,
          surfaceBuilder: _unusedBuilder,
          onControllerChanged: (_) {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('map-configuration-error')), findsOne);
    expect(find.textContaining('NADR_MAP_STYLE_URL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading and style failure remain inside the map layer', (
    tester,
  ) async {
    MapSurfaceCallbacks? capturedCallbacks;
    Widget builder(
      MapSurfaceConfiguration configuration,
      MapSurfaceCallbacks callbacks,
    ) {
      capturedCallbacks = callbacks;
      return const ColoredBox(
        key: ValueKey('test-map-surface'),
        color: Colors.blue,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: InteractiveMapLayer(
          styleUri: Uri.parse('https://maps.example.test/style.json'),
          initialCamera: MapDefaults.initialCamera,
          surfaceBuilder: builder,
          onControllerChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Loading map'), findsOneWidget);
    expect(find.byKey(const ValueKey('test-map-surface')), findsOneWidget);

    capturedCallbacks!.onError('The style document is invalid.');
    await tester.pump();

    expect(find.text('The style document is invalid.'), findsOneWidget);
    expect(find.text('Retry map'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful style load removes the loading presentation', (
    tester,
  ) async {
    MapSurfaceCallbacks? capturedCallbacks;
    Widget builder(
      MapSurfaceConfiguration configuration,
      MapSurfaceCallbacks callbacks,
    ) {
      capturedCallbacks = callbacks;
      return const ColoredBox(color: Colors.blue);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: InteractiveMapLayer(
          styleUri: Uri.parse('https://maps.example.test/style.json'),
          initialCamera: MapDefaults.initialCamera,
          surfaceBuilder: builder,
          onControllerChanged: (_) {},
        ),
      ),
    );

    capturedCallbacks!.onStyleLoaded();
    await tester.pump();

    expect(find.text('Loading map'), findsNothing);
    expect(find.byKey(const ValueKey('map-configuration-error')), findsNothing);
  });
}

Widget _unusedBuilder(
  MapSurfaceConfiguration configuration,
  MapSurfaceCallbacks callbacks,
) {
  throw StateError('A map surface must not be built without a style URL.');
}
