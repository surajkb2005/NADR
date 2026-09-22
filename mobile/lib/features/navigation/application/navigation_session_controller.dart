import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/core/diagnostics/nadr_diagnostics.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/navigation/domain/connection_status.dart';
import 'package:nadr_mobile/features/navigation/domain/navigation_session_state.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

final navigationSessionProvider =
    NotifierProvider<NavigationSessionController, NavigationSessionState>(
      NavigationSessionController.new,
    );

final class NavigationSessionController
    extends Notifier<NavigationSessionState> {
  @override
  NavigationSessionState build() => NavigationSessionState.initial();

  bool updateGpsPosition(PositionSample position) {
    _requireSource(position, PositionSource.gps);
    final coordinate = position.coordinate;
    if (!coordinate.latitude.isFinite ||
        !coordinate.longitude.isFinite ||
        coordinate.latitude < -90 ||
        coordinate.latitude > 90 ||
        coordinate.longitude < -180 ||
        coordinate.longitude > 180) {
      NadrDiagnostics.log(
        'NADR_GPS_REJECT',
        'reason=invalid_navigation_coordinate',
      );
      return false;
    }
    final previous = state.latestGpsPosition;
    if (previous != null && !position.timestamp.isAfter(previous.timestamp)) {
      NadrDiagnostics.log(
        'NADR_GPS_REJECT',
        'reason=out_of_order_navigation_sample',
      );
      return false;
    }
    state = state.copyWith(latestGpsPosition: position);
    NadrDiagnostics.log(
      'NADR_NAV_DISPLAY',
      'latestGps=${position.coordinate} mode=${state.navigationMode.name} '
          'displayed=${state.displayedPosition?.coordinate}',
    );
    return true;
  }

  void updateImuPosition(PositionSample position) {
    _requireSource(position, PositionSource.imu);
    state = state.copyWith(latestImuPosition: position);
    NadrDiagnostics.throttled(
      'NADR_NAV_IMU',
      'imu_position',
      'latestImu=${state.latestImuPosition?.coordinate} heading=${position.heading} '
          'mode=${state.navigationMode.name} displayed=${state.displayedPosition?.coordinate}',
    );
  }

  void setNavigationMode(NavigationMode mode) {
    state = state.copyWith(navigationMode: mode);
  }

  void setDestination(Destination destination) {
    state = state.copyWith(destination: destination);
  }

  void clearDestination() {
    state = state.copyWith(destination: null);
  }

  void setRouteAlternatives(RouteAlternatives alternatives) {
    final refreshedSelection = state.selectedRoute == null
        ? null
        : alternatives[state.selectedRouteMode];

    state = state.copyWith(
      routeAlternatives: alternatives,
      selectedRoute: refreshedSelection,
    );
  }

  void selectRoute(RouteMode mode) {
    final route = state.routeAlternatives[mode];
    if (route == null) {
      throw ArgumentError.value(
        mode,
        'mode',
        'No route alternative is available for this mode.',
      );
    }

    state = state.copyWith(selectedRoute: route, selectedRouteMode: mode);
  }

  void clearRoute() {
    state = state.copyWith(
      routeAlternatives: RouteAlternatives.empty(),
      selectedRoute: null,
    );
  }

  void setSensorStatus(SensorStatus status) {
    state = state.copyWith(sensorStatus: status);
  }

  void setWebSocketStatus(WebSocketStatus status) {
    state = state.copyWith(webSocketStatus: status);
  }

  void setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  void setError(String message) {
    state = state.copyWith(errorMessage: message);
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  static void _requireSource(
    PositionSample position,
    PositionSource expectedSource,
  ) {
    if (position.source != expectedSource) {
      throw ArgumentError.value(
        position.source,
        'position.source',
        'Expected a ${expectedSource.name} position sample.',
      );
    }
  }
}
