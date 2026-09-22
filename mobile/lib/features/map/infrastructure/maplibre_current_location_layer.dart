import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' as maplibre;
import 'package:nadr_mobile/core/diagnostics/nadr_diagnostics.dart';
import 'package:nadr_mobile/features/map/domain/current_location_marker.dart';

/// A native style symbol stays in the same render frame as MapLibre's camera.
final class MapLibreCurrentLocationLayer {
  static const sourceId = 'nadr-current-location-source';
  static const layerId = 'nadr-current-location-symbol';
  static const imuSourceId = 'nadr-current-location-imu-source';
  static const imuLayerId = 'nadr-current-location-imu-symbol';
  static const symbolPixels = 26;

  maplibre.StyleController? _style;
  CurrentLocationMarkerData? _marker;
  int _generation = 0;
  bool _sourceDirty = false;
  Future<void>? _sourceUpdateInFlight;

  Future<void> setMarker(CurrentLocationMarkerData? marker) async {
    if (marker == _marker) return;
    _marker = marker;
    _sourceDirty = true;
    await _flushSource();
  }

  Future<void> install(maplibre.StyleController style) async {
    if (identical(style, _style)) {
      _sourceDirty = true;
      await _flushSource();
      return;
    }
    _style = null;
    _sourceDirty = true;
    final generation = ++_generation;
    await style.addSource(
      maplibre.GeoJsonSource(id: sourceId, data: emptyGeoJson),
    );
    await style.addSource(
      maplibre.GeoJsonSource(id: imuSourceId, data: emptyGeoJson),
    );
    for (final mode in CurrentLocationVisualMode.values) {
      for (final directional in [false, true]) {
        await style.addImageFromCanvas(
          id: _iconId(mode, directional),
          width: symbolPixels,
          height: symbolPixels,
          painter: (canvas) => _drawIcon(canvas, mode, directional),
        );
      }
    }
    await style.addLayer(
      const maplibre.SymbolStyleLayer(
        id: layerId,
        sourceId: sourceId,
        layout: {
          'icon-image': 'nadr-location-gps-neutral',
          'icon-rotate': 0,
          'icon-rotation-alignment': 'map',
          'icon-size': 1,
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      ),
    );
    await style.addLayer(
      const maplibre.SymbolStyleLayer(
        id: imuLayerId,
        sourceId: imuSourceId,
        layout: {
          'icon-image': ['get', 'icon'],
          'icon-rotate': ['get', 'heading'],
          'icon-rotation-alignment': 'map',
          'icon-size': 1,
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      ),
    );
    if (generation != _generation) return;
    _style = style;
    NadrDiagnostics.log(
      'NADR_MAP_SOURCE',
      'created generation=$generation gpsSource=$sourceId imuSource=$imuSourceId',
    );
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
      final marker = _marker;
      _sourceDirty = false;
      NadrDiagnostics.log(
        'NADR_MAP_MARKER',
        'lat=${marker?.coordinate.latitude} lon=${marker?.coordinate.longitude} '
            'mode=${marker?.visualMode.name} heading=${marker?.heading}',
      );
      // Changing mode empties one native source and populates another. It does
      // not depend on MapLibre repainting a changed icon property at the same
      // point in a single source, as the old layer did.
      await style.updateGeoJsonSource(
        id: sourceId,
        data: geoJsonFor(
          marker?.visualMode == CurrentLocationVisualMode.gps ? marker : null,
        ),
      );
      if (!identical(style, _style)) {
        _sourceDirty = true;
        return;
      }
      await style.updateGeoJsonSource(
        id: imuSourceId,
        data: geoJsonFor(
          marker?.visualMode == CurrentLocationVisualMode.imu ? marker : null,
        ),
      );
      if (!identical(style, _style)) {
        _sourceDirty = true;
        return;
      }
    }
  }

  static const emptyGeoJson = '{"type":"FeatureCollection","features":[]}';

  static String geoJsonFor(CurrentLocationMarkerData? marker) {
    if (marker == null) return emptyGeoJson;
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          // A heading/style-only change also changes feature identity. This
          // prevents a same-coordinate native symbol from retaining old paint.
          'id':
              '${marker.visualMode.name}:${marker.heading}:${marker.coordinate.latitude},${marker.coordinate.longitude}',
          'geometry': {
            'type': 'Point',
            'coordinates': [
              marker.coordinate.longitude,
              marker.coordinate.latitude,
            ],
          },
          'properties': {
            'icon': _iconId(
              marker.visualMode,
              marker.visualMode == CurrentLocationVisualMode.imu &&
                  marker.heading != null,
            ),
            'heading': marker.visualMode == CurrentLocationVisualMode.imu
                ? (marker.heading ?? 0)
                : 0,
          },
        },
      ],
    });
  }

  static String _iconId(CurrentLocationVisualMode mode, bool directional) =>
      'nadr-location-${mode.name}-${directional ? 'direction' : 'neutral'}';

  static void _drawIcon(
    Canvas canvas,
    CurrentLocationVisualMode mode,
    bool directional,
  ) {
    final color = mode == CurrentLocationVisualMode.gps
        ? const Color(0xFF1565C0)
        : const Color(0xFF7E57C2);
    final outline = Paint()..color = Colors.white;
    final fill = Paint()..color = color;
    if (!directional) {
      canvas.drawCircle(const Offset(13, 13), 11, outline);
      canvas.drawCircle(const Offset(13, 13), 7.5, fill);
      return;
    }
    final path = Path()
      ..moveTo(13, 2)
      ..lineTo(22.5, 22.5)
      ..lineTo(13, 18)
      ..lineTo(3.5, 22.5)
      ..close();
    canvas.drawPath(path, outline);
    final inner = Path()
      ..moveTo(13, 5)
      ..lineTo(19.5, 19)
      ..lineTo(13, 16)
      ..lineTo(6.5, 19)
      ..close();
    canvas.drawPath(inner, fill);
  }
}
