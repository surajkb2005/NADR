import 'dart:async';
import 'dart:math' as math;

import 'package:nadr_mobile/core/diagnostics/nadr_diagnostics.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/map/domain/current_location_marker.dart';
import 'package:nadr_mobile/features/map/domain/map_camera.dart';
import 'package:nadr_mobile/features/map/domain/nadr_map_controller.dart';
import 'package:nadr_mobile/features/map/presentation/current_location_marker_mapper.dart';
import 'package:nadr_mobile/features/map/presentation/route_camera_fit.dart';
import 'package:nadr_mobile/features/navigation/domain/navigation_session_state.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

enum MapCameraFollowMode { following, userExplore }

enum RecenterOutcome {
  success,
  alreadyCentered,
  coalesced,
  noMap,
  noPosition,
  cancelled,
}

final class MapCameraFollowController {
  MapCameraFollowController({this.onChanged});

  static const navigationZoom = 16.5;
  static const minimumUsefulNavigationZoom = 15.5;

  /// Keep individual IMU steps visible instead of immediately moving the map
  /// by the same sub-meter amount underneath a screen-centered marker. GPS
  /// follow is unchanged, and IMU follow catches up after several steps.
  static const minimumImuCameraFollowDisplacementMeters = 5.0;

  final void Function()? onChanged;

  NadrMapController? _mapController;
  CurrentLocationMarkerData? _marker;
  PositionSample? _displayedPosition;
  GeoCoordinate? _lastCameraTarget;
  MapCameraFollowMode _followMode = MapCameraFollowMode.following;
  bool _hasPositionedFirstGpsFix = false;
  Timer? _cameraCooldown;
  MapCameraUpdate? _pendingCameraUpdate;
  Future<RecenterOutcome>? _recenterInFlight;
  RouteAlternative? _previewRoute;
  RouteCameraFit? _pendingRouteFit;
  Future<void>? _routeFitInFlight;
  int _routeFitGeneration = 0;
  bool _disposed = false;

  CurrentLocationMarkerData? get marker => _marker;
  MapCameraFollowMode get followMode => _followMode;
  bool get canRecenter => _mapController != null && _marker != null;

  Future<void> attachMapController(NadrMapController controller) async {
    if (_disposed) return;
    if (!identical(controller, _mapController)) {
      _cameraCooldown?.cancel();
      _cameraCooldown = null;
      _pendingCameraUpdate = null;
      _lastCameraTarget = null;
      _hasPositionedFirstGpsFix = false;
    }
    _mapController = controller;
    NadrDiagnostics.log('NADR_MAP_SOURCE', 'map_controller_attached');
    onChanged?.call();
    await controller.updateCurrentLocationMarker(_marker);
    await _moveForLatestPositionIfNeeded();
    await retryPendingRouteFit();
  }

  /// A selected-route change opens one preview; location ticks never call it.
  Future<void> previewSelectedRoute(
    RouteAlternative? route,
    RouteCameraFit? fit,
  ) async {
    if (identical(route, _previewRoute)) return;
    _previewRoute = route;
    _routeFitGeneration++;
    _pendingRouteFit = route == null ? null : fit;
    if (_pendingRouteFit == null) return;
    _suspendFollowForRoutePreview();
    await retryPendingRouteFit();
  }

  Future<void> retryPendingRouteFit() async {
    while (!_disposed && _mapController != null && _pendingRouteFit != null) {
      final existing = _routeFitInFlight;
      if (existing != null) {
        await existing;
        continue;
      }
      final operation = _fitLatestRoute();
      _routeFitInFlight = operation;
      try {
        await operation;
      } finally {
        if (identical(_routeFitInFlight, operation)) _routeFitInFlight = null;
      }
      // A failed fit remains pending for a later style-ready callback.
      if (_pendingRouteFit != null) return;
    }
  }

  Future<void> _fitLatestRoute() async {
    final controller = _mapController;
    final fit = _pendingRouteFit;
    if (controller == null || fit == null) return;
    final generation = _routeFitGeneration;
    try {
      await controller.fitBounds(fit.bounds, padding: fit.padding);
      if (generation == _routeFitGeneration) _pendingRouteFit = null;
    } on Object catch (error) {
      NadrDiagnostics.log('NADR_MAP_ROUTE_FIT', 'camera_error=$error');
    }
  }

  void _suspendFollowForRoutePreview() {
    _cameraCooldown?.cancel();
    _cameraCooldown = null;
    _pendingCameraUpdate = null;
    if (_followMode != MapCameraFollowMode.userExplore) {
      _followMode = MapCameraFollowMode.userExplore;
      onChanged?.call();
    }
  }

  void detachMapController(NadrMapController? controller) {
    if (controller != null && !identical(controller, _mapController)) return;
    _mapController = null;
    _cameraCooldown?.cancel();
    _cameraCooldown = null;
    _pendingCameraUpdate = null;
    onChanged?.call();
  }

  Future<void> updateFromSession(NavigationSessionState session) async {
    if (_disposed) return;
    final nextMarker = currentLocationMarkerFromSession(session);
    final nextPosition = session.displayedPosition;
    if (nextMarker == _marker && nextPosition == _displayedPosition) return;

    final availabilityChanged = (nextMarker == null) != (_marker == null);
    final positionChanged = nextMarker != _marker;
    _marker = nextMarker;
    _displayedPosition = nextPosition;
    if (availabilityChanged) onChanged?.call();

    final controller = _mapController;
    if (controller == null) return;
    if (positionChanged) {
      await controller.updateCurrentLocationMarker(nextMarker);
    }
    await _moveForPosition(nextPosition);
  }

  void handleUserGesture() {
    _pendingRouteFit = null;
    _routeFitGeneration++;
    if (_followMode == MapCameraFollowMode.userExplore) return;
    _followMode = MapCameraFollowMode.userExplore;
    _cameraCooldown?.cancel();
    _cameraCooldown = null;
    _pendingCameraUpdate = null;
    NadrDiagnostics.log('NADR_MAP_GESTURE', 'user_explore follow=disabled');
    onChanged?.call();
  }

  Future<RecenterOutcome> recenter() {
    NadrDiagnostics.log(
      'NADR_MAP_RECENTER_REQUEST',
      'follow=${_followMode.name} position=${_displayedPosition?.coordinate}',
    );
    if (_recenterInFlight != null) {
      NadrDiagnostics.log('NADR_MAP_RECENTER_COALESCED', 'in_flight');
      return Future.value(RecenterOutcome.coalesced);
    }
    final controller = _mapController;
    final position = _displayedPosition;
    if (controller == null) {
      NadrDiagnostics.log(
        'NADR_MAP_RECENTER_FAILURE',
        'reason=no_map_controller',
      );
      return Future.value(RecenterOutcome.noMap);
    }
    if (position == null) {
      NadrDiagnostics.log(
        'NADR_MAP_RECENTER_FAILURE',
        'reason=no_displayed_position',
      );
      return Future.value(RecenterOutcome.noPosition);
    }

    _pendingRouteFit = null;
    _routeFitGeneration++;
    final operation = _recenterAfterRouteFit(controller, position);
    _recenterInFlight = operation;
    return _finishRecenter(operation);
  }

  Future<RecenterOutcome> _recenterAfterRouteFit(
    NadrMapController controller,
    PositionSample position,
  ) async {
    final fit = _routeFitInFlight;
    if (fit != null) await fit;
    return _performRecenter(controller, position);
  }

  Future<RecenterOutcome> _finishRecenter(
    Future<RecenterOutcome> operation,
  ) async {
    try {
      return await operation;
    } finally {
      if (identical(_recenterInFlight, operation)) _recenterInFlight = null;
      final pending = _pendingCameraUpdate;
      if (_cameraCooldown == null &&
          pending != null &&
          _followMode == MapCameraFollowMode.following) {
        _pendingCameraUpdate = null;
        _scheduleCamera(pending, const Duration(milliseconds: 300));
      }
    }
  }

  Future<RecenterOutcome> _performRecenter(
    NadrMapController controller,
    PositionSample position,
  ) async {
    final currentZoom = controller.currentCamera?.zoom;
    final zoom =
        currentZoom != null &&
            currentZoom.isFinite &&
            currentZoom >= minimumUsefulNavigationZoom
        ? currentZoom
        : navigationZoom;

    if (_followMode != MapCameraFollowMode.following) {
      _followMode = MapCameraFollowMode.following;
      NadrDiagnostics.log('NADR_MAP_FOLLOW', 'enabled_by_recenter');
      onChanged?.call();
    }
    final camera = controller.currentCamera;
    if (camera != null &&
        camera.zoom.isFinite &&
        (camera.zoom - zoom).abs() <= 0.05 &&
        _distanceMeters(camera.center, position.coordinate) <= 3) {
      NadrDiagnostics.log(
        'NADR_MAP_RECENTER_ALREADY_CENTERED',
        'center=${position.coordinate} zoom=$zoom',
      );
      return RecenterOutcome.alreadyCentered;
    }
    _cameraCooldown?.cancel();
    _cameraCooldown = null;
    _pendingCameraUpdate = null;
    _hasPositionedFirstGpsFix = true;
    NadrDiagnostics.log(
      'NADR_MAP_RECENTER_START',
      'center=${position.coordinate} currentZoom=$currentZoom targetZoom=$zoom',
    );
    try {
      await controller.recenter(position.coordinate, zoom: zoom);
      _lastCameraTarget = position.coordinate;
      _startCooldown(const Duration(milliseconds: 700));
      NadrDiagnostics.log(
        'NADR_MAP_RECENTER_SUCCESS',
        'center=${position.coordinate} zoom=$zoom',
      );
      return RecenterOutcome.success;
    } on MapCameraAnimationCancelled {
      NadrDiagnostics.log(
        'NADR_MAP_RECENTER_CANCELLED',
        'reason=superseded_or_user_gesture',
      );
      return RecenterOutcome.cancelled;
    } on Object catch (error) {
      NadrDiagnostics.log(
        'NADR_MAP_RECENTER_FAILURE',
        'reason=camera_error error=$error',
      );
      rethrow;
    }
  }

  static double _distanceMeters(GeoCoordinate a, GeoCoordinate b) {
    const earthRadius = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = lat2 - lat1;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0, 1)));
  }

  Future<void> restoreMarkerAfterStyleReload() async {
    NadrDiagnostics.log('NADR_MAP_SOURCE', 'style_reload_restore_marker');
    await _mapController?.updateCurrentLocationMarker(_marker);
  }

  void dispose() {
    _disposed = true;
    _pendingRouteFit = null;
    _cameraCooldown?.cancel();
    _pendingCameraUpdate = null;
    _mapController = null;
  }

  Future<void> _moveForLatestPositionIfNeeded() async {
    await _moveForPosition(_displayedPosition);
  }

  Future<void> _moveForPosition(PositionSample? position) async {
    final controller = _mapController;
    if (controller == null || position == null) return;
    if (position.coordinate == _lastCameraTarget) return;

    final isFirstDisplayedGps =
        !_hasPositionedFirstGpsFix && position.source == PositionSource.gps;
    if (isFirstDisplayedGps && _followMode == MapCameraFollowMode.following) {
      _hasPositionedFirstGpsFix = true;
      _scheduleCamera(
        MapCameraUpdate(center: position.coordinate, zoom: navigationZoom),
        const Duration(milliseconds: 500),
      );
      return;
    }

    final lastCameraTarget = _lastCameraTarget;
    if (position.source == PositionSource.imu &&
        lastCameraTarget != null &&
        _distanceMeters(lastCameraTarget, position.coordinate) <
            minimumImuCameraFollowDisplacementMeters) {
      NadrDiagnostics.throttled(
        'NADR_MAP_FOLLOW',
        'imu_marker_dead_zone',
        'marker_visible camera_deferred distanceMeters='
            '${_distanceMeters(lastCameraTarget, position.coordinate)}',
      );
      return;
    }

    if (_followMode == MapCameraFollowMode.following) {
      _scheduleCamera(
        MapCameraUpdate(center: position.coordinate),
        const Duration(milliseconds: 300),
      );
    }
  }

  void _scheduleCamera(MapCameraUpdate update, Duration duration) {
    final controller = _mapController;
    if (_disposed ||
        controller == null ||
        _followMode != MapCameraFollowMode.following) {
      return;
    }
    if (_recenterInFlight != null) {
      _pendingCameraUpdate = update;
      return;
    }
    if (_cameraCooldown != null) {
      _pendingCameraUpdate = update;
      return;
    }
    _lastCameraTarget = update.center;
    NadrDiagnostics.log(
      'NADR_MAP_FOLLOW',
      'programmatic_camera center=${update.center} zoom=${update.zoom} durationMs=${duration.inMilliseconds}',
    );
    unawaited(
      controller
          .animateCamera(update, duration: duration)
          .catchError(
            (Object error) => NadrDiagnostics.log(
              'NADR_MAP_FOLLOW',
              error is MapCameraAnimationCancelled
                  ? 'camera_cancelled'
                  : 'camera_error=$error',
            ),
          ),
    );
    _startCooldown(duration + const Duration(milliseconds: 50));
  }

  void _startCooldown(Duration duration) {
    _cameraCooldown?.cancel();
    _cameraCooldown = Timer(duration, () {
      _cameraCooldown = null;
      final pending = _pendingCameraUpdate;
      _pendingCameraUpdate = null;
      if (pending != null && pending.center != _lastCameraTarget) {
        _scheduleCamera(pending, const Duration(milliseconds: 300));
      }
    });
  }
}
