import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart' as maplibre;
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/map/domain/map_camera.dart';
import 'package:nadr_mobile/features/map/domain/nadr_map_controller.dart';
import 'package:nadr_mobile/features/map/infrastructure/maplibre_nadr_map_controller.dart';

final class MapSurfaceConfiguration {
  const MapSurfaceConfiguration({
    required this.styleUri,
    required this.initialCamera,
  });

  final Uri styleUri;
  final MapCameraState initialCamera;
}

final class MapSurfaceCallbacks {
  const MapSurfaceCallbacks({
    required this.onControllerReady,
    required this.onStyleLoaded,
    required this.onUserGesture,
    required this.onError,
    this.onLongPress,
  });

  final ValueChanged<NadrMapController> onControllerReady;
  final VoidCallback onStyleLoaded;
  final VoidCallback onUserGesture;
  final ValueChanged<String> onError;
  final ValueChanged<GeoCoordinate>? onLongPress;
}

typedef MapSurfaceBuilder = Widget Function(
  MapSurfaceConfiguration configuration,
  MapSurfaceCallbacks callbacks,
);

final mapSurfaceBuilderProvider = Provider<MapSurfaceBuilder>((ref) {
  return buildMapLibreSurface;
});

Widget buildMapLibreSurface(
  MapSurfaceConfiguration configuration,
  MapSurfaceCallbacks callbacks,
) {
  return MapLibreMapSurface(configuration: configuration, callbacks: callbacks);
}

bool isUserCameraGestureEvent(maplibre.MapEvent event) {
  return event is maplibre.MapEventStartMoveCamera &&
      event.reason == maplibre.CameraChangeReason.apiGesture;
}

GeoCoordinate? coordinateFromLongPressEvent(maplibre.MapEvent event) {
  if (event is! maplibre.MapEventLongClick) return null;
  final latitude = event.point.lat;
  final longitude = event.point.lon;
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180) {
    return null;
  }
  return GeoCoordinate(latitude: latitude, longitude: longitude);
}

class MapLibreMapSurface extends StatefulWidget {
  const MapLibreMapSurface({
    required this.configuration,
    required this.callbacks,
    super.key,
  });

  final MapSurfaceConfiguration configuration;
  final MapSurfaceCallbacks callbacks;

  @override
  State<MapLibreMapSurface> createState() => _MapLibreMapSurfaceState();
}

class _MapLibreMapSurfaceState extends State<MapLibreMapSurface> {
  MapLibreNadrMapController? _controller;

  @override
  void dispose() {
    _controller?.detachStyle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = widget.configuration.initialCamera;
    final topAttributionPadding = MediaQuery.paddingOf(context).top + 80;

    return maplibre.MapLibreMap(
      key: const ValueKey('maplibre-map'),
      options: maplibre.MapOptions(
        initStyle: widget.configuration.styleUri.toString(),
        initCenter: maplibre.Geographic(
          lon: camera.center.longitude,
          lat: camera.center.latitude,
        ),
        initZoom: camera.zoom,
        initBearing: camera.bearing,
        initPitch: camera.tilt,
        gestures: const maplibre.MapGestures.all(
          pan: true,
          zoom: true,
          rotate: true,
          pitch: true,
        ),
      ),
      onMapCreated: (controller) {
        _controller = MapLibreNadrMapController(controller);
        widget.callbacks.onControllerReady(_controller!);
      },
      onStyleLoaded: (style) {
        final controller = _controller;
        if (controller == null) return;
        controller
            .onStyleLoaded(style)
            .then((_) {
              if (mounted) widget.callbacks.onStyleLoaded();
            })
            .catchError((Object error) {
              if (mounted) {
                widget.callbacks.onError('Map marker layers failed: $error');
              }
            });
      },
      onEvent: (event) {
        final coordinate = coordinateFromLongPressEvent(event);
        if (coordinate != null) {
          widget.callbacks.onLongPress?.call(coordinate);
        }
        if (isUserCameraGestureEvent(event)) {
          widget.callbacks.onUserGesture();
        }
      },
      children: [
        maplibre.SourceAttribution(
          alignment: Alignment.topRight,
          padding: EdgeInsets.fromLTRB(8, topAttributionPadding, 8, 8),
        ),
      ],
    );
  }
}
