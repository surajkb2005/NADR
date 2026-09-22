import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/navigation/domain/connection_status.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';

const _notProvided = Object();

final class NavigationSessionState {
  NavigationSessionState({
    this.navigationMode = NavigationMode.gps,
    this.latestGpsPosition,
    this.latestImuPosition,
    this.destination,
    RouteAlternatives? routeAlternatives,
    this.selectedRoute,
    this.selectedRouteMode = RouteMode.normal,
    this.sensorStatus = SensorStatus.stopped,
    this.webSocketStatus = WebSocketStatus.disconnected,
    this.isLoading = false,
    this.errorMessage,
  }) : routeAlternatives = routeAlternatives ?? RouteAlternatives.empty();

  factory NavigationSessionState.initial() => NavigationSessionState();

  final NavigationMode navigationMode;
  final PositionSample? latestGpsPosition;
  final PositionSample? latestImuPosition;
  final Destination? destination;
  final RouteAlternatives routeAlternatives;
  final RouteAlternative? selectedRoute;
  final RouteMode selectedRouteMode;
  final SensorStatus sensorStatus;
  final WebSocketStatus webSocketStatus;
  final bool isLoading;
  final String? errorMessage;

  PositionSample? get displayedPosition => switch (navigationMode) {
    NavigationMode.gps => latestGpsPosition,
    NavigationMode.imu => latestImuPosition,
  };

  bool get hasGpsFix => latestGpsPosition != null;

  double? get currentHeading => displayedPosition?.heading;

  NavigationSessionState copyWith({
    NavigationMode? navigationMode,
    Object? latestGpsPosition = _notProvided,
    Object? latestImuPosition = _notProvided,
    Object? destination = _notProvided,
    RouteAlternatives? routeAlternatives,
    Object? selectedRoute = _notProvided,
    RouteMode? selectedRouteMode,
    SensorStatus? sensorStatus,
    WebSocketStatus? webSocketStatus,
    bool? isLoading,
    Object? errorMessage = _notProvided,
  }) {
    return NavigationSessionState(
      navigationMode: navigationMode ?? this.navigationMode,
      latestGpsPosition: identical(latestGpsPosition, _notProvided)
          ? this.latestGpsPosition
          : latestGpsPosition as PositionSample?,
      latestImuPosition: identical(latestImuPosition, _notProvided)
          ? this.latestImuPosition
          : latestImuPosition as PositionSample?,
      destination: identical(destination, _notProvided)
          ? this.destination
          : destination as Destination?,
      routeAlternatives: routeAlternatives ?? this.routeAlternatives,
      selectedRoute: identical(selectedRoute, _notProvided)
          ? this.selectedRoute
          : selectedRoute as RouteAlternative?,
      selectedRouteMode: selectedRouteMode ?? this.selectedRouteMode,
      sensorStatus: sensorStatus ?? this.sensorStatus,
      webSocketStatus: webSocketStatus ?? this.webSocketStatus,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: identical(errorMessage, _notProvided)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}
