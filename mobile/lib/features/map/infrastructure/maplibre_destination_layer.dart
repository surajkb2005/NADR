import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' as maplibre;
import 'package:nadr_mobile/features/destination/domain/destination.dart';

/// Owns the single native MapLibre feature used for the confirmed destination.
final class MapLibreDestinationLayer {
  static const sourceId = 'nadr-destination-source';
  static const layerId = 'nadr-destination-symbol';
  static const iconId = 'nadr-destination-pin';
  static const emptyGeoJson = '{"type":"FeatureCollection","features":[]}';

  maplibre.StyleController? _style;
  Destination? _destination;
  int _generation = 0;
  bool _sourceDirty = false;
  Future<void>? _sourceUpdateInFlight;

  Future<void> setDestination(Destination? destination) async {
    if (destination == _destination) return;
    _destination = destination;
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
    await style.addImageFromCanvas(
      id: iconId,
      width: 38,
      height: 46,
      painter: _drawIcon,
    );
    await style.addLayer(
      const maplibre.SymbolStyleLayer(
        id: layerId,
        sourceId: sourceId,
        layout: {
          'icon-image': iconId,
          'icon-anchor': 'bottom',
          'icon-size': 1,
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
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
      final destination = _destination;
      _sourceDirty = false;
      await style.updateGeoJsonSource(
        id: sourceId,
        data: geoJsonFor(destination),
      );
      if (!identical(style, _style)) {
        _sourceDirty = true;
        return;
      }
    }
  }

  static String geoJsonFor(Destination? destination) {
    if (destination == null) return emptyGeoJson;
    final coordinate = destination.coordinate;
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'id': 'destination:${coordinate.latitude},${coordinate.longitude}',
          'geometry': {
            'type': 'Point',
            'coordinates': [coordinate.longitude, coordinate.latitude],
          },
          'properties': const <String, Object>{},
        },
      ],
    });
  }

  static void _drawIcon(Canvas canvas) {
    final outline = Paint()..color = Colors.white;
    final fill = Paint()..color = const Color(0xFFE65100);
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.24);
    final pin = Path()
      ..moveTo(19, 45)
      ..cubicTo(16, 38, 5, 29, 5, 19)
      ..cubicTo(5, 10, 11, 4, 19, 4)
      ..cubicTo(27, 4, 33, 10, 33, 19)
      ..cubicTo(33, 29, 22, 38, 19, 45)
      ..close();
    canvas.save();
    canvas.translate(0, 1.5);
    canvas.drawPath(pin, shadow);
    canvas.restore();
    canvas.drawPath(pin, outline);
    canvas.save();
    canvas.translate(19, 20);
    canvas.scale(0.82);
    canvas.translate(-19, -20);
    canvas.drawPath(pin, fill);
    canvas.restore();
    canvas.drawCircle(const Offset(19, 18), 5.5, Paint()..color = Colors.white);
  }
}
