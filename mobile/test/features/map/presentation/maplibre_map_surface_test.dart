import 'dart:convert';
import 'dart:ui' show Canvas, Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart' as maplibre;
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/map/domain/current_location_marker.dart';
import 'package:nadr_mobile/features/map/infrastructure/maplibre_current_location_layer.dart';
import 'package:nadr_mobile/features/map/infrastructure/maplibre_destination_layer.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/maplibre_map_surface.dart';

void main() {
  test('only genuine MapLibre camera gestures disable follow', () {
    expect(
      isUserCameraGestureEvent(
        const maplibre.MapEventStartMoveCamera(
          reason: maplibre.CameraChangeReason.apiGesture,
        ),
      ),
      isTrue,
    );
    for (final reason in [
      maplibre.CameraChangeReason.apiAnimation,
      maplibre.CameraChangeReason.developerAnimation,
    ]) {
      expect(
        isUserCameraGestureEvent(
          maplibre.MapEventStartMoveCamera(reason: reason),
        ),
        isFalse,
      );
    }
  });

  test('only a valid MapLibre long click yields a destination coordinate', () {
    expect(
      coordinateFromLongPressEvent(
        const maplibre.MapEventLongClick(
          point: maplibre.Geographic(lon: 77.5946, lat: 12.9716),
          screenPoint: Offset(100, 200),
        ),
      ),
      const GeoCoordinate(latitude: 12.9716, longitude: 77.5946),
    );
    expect(
      coordinateFromLongPressEvent(
        const maplibre.MapEventStartMoveCamera(
          reason: maplibre.CameraChangeReason.apiGesture,
        ),
      ),
      isNull,
    );
  });

  test('native marker is geographic rather than a projected screen point', () {
    const marker = CurrentLocationMarkerData(
      coordinate: GeoCoordinate(latitude: 12.97, longitude: 77.59),
      visualMode: CurrentLocationVisualMode.gps,
      heading: 45,
    );
    final json = jsonDecode(
      MapLibreCurrentLocationLayer.geoJsonFor(marker),
    ) as Map<String, dynamic>;
    final feature = (json['features'] as List).single as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>;
    expect(geometry['type'], 'Point');
    expect(geometry['coordinates'], [77.59, 12.97]);
    expect(feature['properties']['heading'], 0);
    expect(feature['properties']['icon'], contains('gps-neutral'));
    expect(json.toString(), isNot(contains('screen')));
  });

  test('native pointer uses compact zoom-independent symbol dimensions', () {
    expect(MapLibreCurrentLocationLayer.symbolPixels, inInclusiveRange(20, 28));
  });

  test('GPS and IMU use distinct native symbol identifiers', () {
    const point = GeoCoordinate(latitude: 12.97, longitude: 77.59);
    final gps = jsonDecode(
      MapLibreCurrentLocationLayer.geoJsonFor(
        const CurrentLocationMarkerData(
          coordinate: point,
          visualMode: CurrentLocationVisualMode.gps,
        ),
      ),
    ) as Map<String, dynamic>;
    final imu = jsonDecode(
      MapLibreCurrentLocationLayer.geoJsonFor(
        const CurrentLocationMarkerData(
          coordinate: point,
          visualMode: CurrentLocationVisualMode.imu,
        ),
      ),
    ) as Map<String, dynamic>;
    final gpsIcon = (gps['features'] as List).single['properties']['icon'];
    final imuIcon = (imu['features'] as List).single['properties']['icon'];
    expect(gpsIcon, isNot(imuIcon));
    expect(gpsIcon, contains('gps'));
    expect(imuIcon, contains('imu'));
  });

  test('IMU heading selects compact arrow, absent heading stays neutral', () {
    const point = GeoCoordinate(latitude: 12.97, longitude: 77.59);
    String icon(double? heading) {
      final data = jsonDecode(
        MapLibreCurrentLocationLayer.geoJsonFor(
          CurrentLocationMarkerData(
            coordinate: point,
            visualMode: CurrentLocationVisualMode.imu,
            heading: heading,
          ),
        ),
      ) as Map<String, dynamic>;
      return (data['features'] as List).single['properties']['icon'] as String;
    }

    expect(icon(null), contains('neutral'));
    expect(icon(90), contains('direction'));
    expect(MapLibreCurrentLocationLayer.symbolPixels, inInclusiveRange(20, 26));
  });

  test('no displayed position means an empty native source', () {
    expect(
      MapLibreCurrentLocationLayer.geoJsonFor(null),
      MapLibreCurrentLocationLayer.emptyGeoJson,
    );
  });

  test('style reload recreates source and restores latest marker', () async {
    const marker = CurrentLocationMarkerData(
      coordinate: GeoCoordinate(latitude: 13.01, longitude: 77.61),
      visualMode: CurrentLocationVisualMode.imu,
      heading: 120,
    );
    final locationLayer = MapLibreCurrentLocationLayer();
    await locationLayer.setMarker(marker);
    final firstStyle = _RecordingStyleController();
    await locationLayer.install(firstStyle);
    expect(firstStyle.sources, [
      MapLibreCurrentLocationLayer.sourceId,
      MapLibreCurrentLocationLayer.imuSourceId,
    ]);
    expect(firstStyle.layers, [
      MapLibreCurrentLocationLayer.layerId,
      MapLibreCurrentLocationLayer.imuLayerId,
    ]);
    expect(
      firstStyle.data.last,
      MapLibreCurrentLocationLayer.geoJsonFor(marker),
    );

    final reloadedStyle = _RecordingStyleController();
    await locationLayer.install(reloadedStyle);
    expect(reloadedStyle.sources, [
      MapLibreCurrentLocationLayer.sourceId,
      MapLibreCurrentLocationLayer.imuSourceId,
    ]);
    expect(reloadedStyle.layers, [
      MapLibreCurrentLocationLayer.layerId,
      MapLibreCurrentLocationLayer.imuLayerId,
    ]);
    expect(
      reloadedStyle.data.last,
      MapLibreCurrentLocationLayer.geoJsonFor(marker),
    );
  });

  test(
    'position changes update GeoJSON without recreating style objects',
    () async {
      final locationLayer = MapLibreCurrentLocationLayer();
      final style = _RecordingStyleController();
      await locationLayer.install(style);
      const first = CurrentLocationMarkerData(
        coordinate: GeoCoordinate(latitude: 12.97, longitude: 77.59),
        visualMode: CurrentLocationVisualMode.gps,
      );
      const second = CurrentLocationMarkerData(
        coordinate: GeoCoordinate(latitude: 12.98, longitude: 77.60),
        visualMode: CurrentLocationVisualMode.gps,
      );
      await locationLayer.setMarker(first);
      await locationLayer.setMarker(first);
      await locationLayer.setMarker(second);
      expect(style.sources, [
        MapLibreCurrentLocationLayer.sourceId,
        MapLibreCurrentLocationLayer.imuSourceId,
      ]);
      expect(style.layers, [
        MapLibreCurrentLocationLayer.layerId,
        MapLibreCurrentLocationLayer.imuLayerId,
      ]);
      expect(style.data, hasLength(6)); // two source writes per marker state
      expect(
        style.sourceData[MapLibreCurrentLocationLayer.sourceId],
        MapLibreCurrentLocationLayer.geoJsonFor(second),
      );
    },
  );

  test('same-coordinate mode changes switch native source and layer', () async {
    final layer = MapLibreCurrentLocationLayer();
    final style = _RecordingStyleController();
    await layer.install(style);
    const point = GeoCoordinate(latitude: 12.97, longitude: 77.59);
    const gps = CurrentLocationMarkerData(
      coordinate: point,
      visualMode: CurrentLocationVisualMode.gps,
    );
    const imu = CurrentLocationMarkerData(
      coordinate: point,
      visualMode: CurrentLocationVisualMode.imu,
    );

    await layer.setMarker(gps);
    expect(
      style.sourceData[MapLibreCurrentLocationLayer.sourceId],
      MapLibreCurrentLocationLayer.geoJsonFor(gps),
    );
    await layer.setMarker(imu);
    expect(
      style.sourceData[MapLibreCurrentLocationLayer.sourceId],
      MapLibreCurrentLocationLayer.emptyGeoJson,
    );
    expect(
      style.sourceData[MapLibreCurrentLocationLayer.imuSourceId],
      MapLibreCurrentLocationLayer.geoJsonFor(imu),
    );
    await layer.setMarker(gps);
    expect(
      style.sourceData[MapLibreCurrentLocationLayer.imuSourceId],
      MapLibreCurrentLocationLayer.emptyGeoJson,
    );
    expect(
      style.sourceData[MapLibreCurrentLocationLayer.sourceId],
      MapLibreCurrentLocationLayer.geoJsonFor(gps),
    );
  });

  test('same-coordinate heading change creates a new native feature', () async {
    final layer = MapLibreCurrentLocationLayer();
    final style = _RecordingStyleController();
    await layer.install(style);
    const point = GeoCoordinate(latitude: 12.97, longitude: 77.59);
    const north = CurrentLocationMarkerData(
      coordinate: point,
      visualMode: CurrentLocationVisualMode.imu,
      heading: 0,
    );
    const east = CurrentLocationMarkerData(
      coordinate: point,
      visualMode: CurrentLocationVisualMode.imu,
      heading: 90,
    );
    await layer.setMarker(north);
    final northFeature =
        (jsonDecode(
                  style.sourceData[MapLibreCurrentLocationLayer.imuSourceId]!,
                )['features']
                as List)
            .single;
    await layer.setMarker(east);
    final eastFeature =
        (jsonDecode(
                  style.sourceData[MapLibreCurrentLocationLayer.imuSourceId]!,
                )['features']
                as List)
            .single;
    expect(eastFeature['id'], isNot(northFeature['id']));
    expect(eastFeature['properties']['heading'], 90);
  });

  test(
    'destination layer creates, replaces, and removes one feature',
    () async {
      final layer = MapLibreDestinationLayer();
      final style = _RecordingStyleController();
      await layer.install(style);
      const first = Destination(
        coordinate: GeoCoordinate(latitude: 12.97, longitude: 77.59),
      );
      const replacement = Destination(
        coordinate: GeoCoordinate(latitude: -33.5, longitude: 151.2),
      );

      await layer.setDestination(first);
      expect(style.sources, [MapLibreDestinationLayer.sourceId]);
      expect(style.layers, [MapLibreDestinationLayer.layerId]);
      expect(
        style.sourceData[MapLibreDestinationLayer.sourceId],
        MapLibreDestinationLayer.geoJsonFor(first),
      );
      await layer.setDestination(replacement);
      final replacementJson = jsonDecode(
        style.sourceData[MapLibreDestinationLayer.sourceId]!,
      ) as Map<String, dynamic>;
      expect(replacementJson['features'], hasLength(1));
      expect(replacementJson['features'].single['geometry']['coordinates'], [
        151.2,
        -33.5,
      ]);
      expect(style.sources, hasLength(1));
      expect(style.layers, hasLength(1));

      await layer.setDestination(null);
      expect(
        style.sourceData[MapLibreDestinationLayer.sourceId],
        MapLibreDestinationLayer.emptyGeoJson,
      );
    },
  );

  test('style reload recreates and restores confirmed destination', () async {
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 40.7128, longitude: -74.006),
    );
    final layer = MapLibreDestinationLayer();
    await layer.setDestination(destination);
    final first = _RecordingStyleController();
    await layer.install(first);
    final reloaded = _RecordingStyleController();
    await layer.install(reloaded);

    expect(reloaded.sources, [MapLibreDestinationLayer.sourceId]);
    expect(reloaded.layers, [MapLibreDestinationLayer.layerId]);
    expect(
      reloaded.sourceData[MapLibreDestinationLayer.sourceId],
      MapLibreDestinationLayer.geoJsonFor(destination),
    );
  });
}

final class _RecordingStyleController implements maplibre.StyleController {
  final sources = <String>[];
  final layers = <String>[];
  final data = <String>[];
  final sourceData = <String, String>{};

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
  Future<void> addImageFromCanvas({
    required String id,
    required void Function(Canvas canvas) painter,
    int width = 200,
    int height = 200,
  }) async {}

  @override
  Future<void> updateGeoJsonSource({
    required String id,
    required String data,
  }) async {
    this.data.add(data);
    sourceData[id] = data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
