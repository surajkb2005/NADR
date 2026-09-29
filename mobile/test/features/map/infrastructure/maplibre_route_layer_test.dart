import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart' as maplibre;
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/map/infrastructure/maplibre_route_layer.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

void main() {
  final normal = _route(RouteMode.normal, const [
    GeoCoordinate(latitude: 12.97, longitude: 77.59),
    GeoCoordinate(latitude: 12.98, longitude: 77.60),
    GeoCoordinate(latitude: -1.2, longitude: -70.3),
  ]);
  final safe = _route(RouteMode.safe, const [
    GeoCoordinate(latitude: 13, longitude: 78),
    GeoCoordinate(latitude: 14, longitude: 79),
  ]);

  test('GeoJSON uses every point in order as longitude, latitude', () {
    final json = jsonDecode(MapLibreRouteLayer.geoJsonFor(normal)) as Map;
    final geometry = (json['features'] as List).single['geometry'] as Map;
    expect(geometry['type'], 'LineString');
    expect(geometry['coordinates'], [
      [77.59, 12.97],
      [77.60, 12.98],
      [-70.3, -1.2],
    ]);
    expect(
      MapLibreRouteLayer.geoJsonFor(null),
      MapLibreRouteLayer.emptyGeoJson,
    );
    expect(
      MapLibreRouteLayer.geoJsonFor(
        _route(RouteMode.normal, const [
          GeoCoordinate(latitude: 1, longitude: 2),
        ]),
      ),
      MapLibreRouteLayer.emptyGeoJson,
    );
    expect(
      MapLibreRouteLayer.geoJsonFor(
        _route(RouteMode.normal, const [
          GeoCoordinate(latitude: 1, longitude: 2),
          GeoCoordinate(latitude: 3, longitude: 4),
        ], optimization: 'fallback'),
      ),
      MapLibreRouteLayer.emptyGeoJson,
    );
  });

  test('installs once, replaces selected route, and clears source', () async {
    final layer = MapLibreRouteLayer();
    final style = _RecordingStyle();
    await layer.setRoute(normal);
    await layer.install(style);
    await layer.install(style);
    expect(style.sources, [MapLibreRouteLayer.sourceId]);
    expect(style.layers, [MapLibreRouteLayer.layerId]);
    expect(style.writes.last, MapLibreRouteLayer.geoJsonFor(normal));
    await layer.setRoute(safe);
    expect(style.writes.last, MapLibreRouteLayer.geoJsonFor(safe));
    await layer.setRoute(null);
    expect(style.writes.last, MapLibreRouteLayer.emptyGeoJson);
  });

  test('style reload restores latest selected route', () async {
    final layer = MapLibreRouteLayer();
    final first = _RecordingStyle();
    await layer.install(first);
    await layer.setRoute(normal);
    layer.detach();
    await layer.setRoute(safe);
    final second = _RecordingStyle();
    await layer.install(second);
    expect(second.sources, [MapLibreRouteLayer.sourceId]);
    expect(second.layers, [MapLibreRouteLayer.layerId]);
    expect(second.writes.last, MapLibreRouteLayer.geoJsonFor(safe));
  });

  test('rapid A to B writes leave B as final geometry', () async {
    final layer = MapLibreRouteLayer();
    final style = _RecordingStyle();
    await layer.install(style);
    final gate = Completer<void>();
    style.nextWriteGate = gate;
    final first = layer.setRoute(normal);
    final second = layer.setRoute(safe);
    gate.complete();
    await Future.wait([first, second]);
    expect(style.writes.last, MapLibreRouteLayer.geoJsonFor(safe));
  });
}

RouteAlternative _route(
  RouteMode mode,
  List<GeoCoordinate> path, {
  String? optimization,
}) => RouteAlternative(
  mode: mode,
  path: path,
  metrics: const RouteMetrics(),
  optimization: optimization,
);

final class _RecordingStyle implements maplibre.StyleController {
  final sources = <String>[];
  final layers = <String>[];
  final writes = <String>[];
  Completer<void>? nextWriteGate;

  @override
  Future<void> addSource(maplibre.Source source) async =>
      sources.add(source.id);

  @override
  Future<void> addLayer(
    maplibre.StyleLayer layer, {
    String? belowLayerId,
    String? aboveLayerId,
    int? atIndex,
  }) async => layers.add(layer.id);

  @override
  Future<void> updateGeoJsonSource({
    required String id,
    required String data,
  }) async {
    final gate = nextWriteGate;
    nextWriteGate = null;
    if (gate != null) await gate.future;
    writes.add(data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
