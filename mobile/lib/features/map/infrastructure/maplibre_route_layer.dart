import 'dart:convert';

import 'package:maplibre/maplibre.dart' as maplibre;
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

/// Owns the selected road route's style source and line layer.
final class MapLibreRouteLayer {
  static const sourceId = 'nadr-selected-route-source';
  static const layerId = 'nadr-selected-route-line';
  static const emptyGeoJson = '{"type":"FeatureCollection","features":[]}';

  maplibre.StyleController? _style;
  maplibre.StyleController? _installingStyle;
  Future<void>? _installation;
  RouteAlternative? _route;
  int _generation = 0;
  bool _sourceDirty = false;
  Future<void>? _sourceUpdateInFlight;

  Future<void> setRoute(RouteAlternative? route) async {
    if (identical(route, _route)) return;
    _route = route;
    _sourceDirty = true;
    await _flushSource();
  }

  Future<void> install(maplibre.StyleController style) async {
    if (identical(style, _style)) return;
    if (identical(style, _installingStyle)) {
      await _installation;
      return;
    }
    final generation = ++_generation;
    _style = null;
    _sourceDirty = true;
    _installingStyle = style;
    final operation = _installStyle(style, generation);
    _installation = operation;
    try {
      await operation;
    } finally {
      if (identical(_installation, operation)) {
        _installation = null;
        _installingStyle = null;
      }
    }
  }

  Future<void> _installStyle(
    maplibre.StyleController style,
    int generation,
  ) async {
    await style.addSource(
      maplibre.GeoJsonSource(id: sourceId, data: emptyGeoJson),
    );
    await style.addLayer(
      const maplibre.LineStyleLayer(
        id: layerId,
        sourceId: sourceId,
        layout: {'line-cap': 'round', 'line-join': 'round'},
        paint: {'line-color': '#1976D2', 'line-width': 5, 'line-opacity': 0.92},
      ),
    );
    if (generation != _generation) return;
    _style = style;
    await _flushSource();
  }

  void detach() {
    _generation++;
    _style = null;
  }

  Future<void> _flushSource() async {
    while (_style != null && _sourceDirty) {
      final existing = _sourceUpdateInFlight;
      if (existing != null) {
        await existing;
        continue;
      }
      final operation = _writeLatestSource();
      _sourceUpdateInFlight = operation;
      try {
        await operation;
      } finally {
        if (identical(_sourceUpdateInFlight, operation)) {
          _sourceUpdateInFlight = null;
        }
      }
    }
  }

  Future<void> _writeLatestSource() async {
    while (_sourceDirty) {
      final style = _style;
      if (style == null) return;
      final route = _route;
      _sourceDirty = false;
      await style.updateGeoJsonSource(id: sourceId, data: geoJsonFor(route));
      if (!identical(style, _style)) {
        _sourceDirty = true;
        return;
      }
    }
  }

  static String geoJsonFor(RouteAlternative? route) {
    if (route == null || !route.isRenderableRoadRoute) return emptyGeoJson;
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final point in route.path) [point.longitude, point.latitude],
            ],
          },
          'properties': const <String, Object>{},
        },
      ],
    });
  }
}
