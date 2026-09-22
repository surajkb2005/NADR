import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/features/map/domain/current_location_marker.dart';
import 'package:nadr_mobile/features/navigation/domain/navigation_session_state.dart';

CurrentLocationMarkerData? currentLocationMarkerFromSession(
  NavigationSessionState session,
) {
  final position = session.displayedPosition;
  if (position == null) return null;

  return CurrentLocationMarkerData(
    coordinate: position.coordinate,
    visualMode: switch (session.navigationMode) {
      NavigationMode.gps => CurrentLocationVisualMode.gps,
      NavigationMode.imu => CurrentLocationVisualMode.imu,
    },
    heading: _validHeading(position.heading),
  );
}

double? _validHeading(double? heading) {
  if (heading == null || !heading.isFinite || heading < 0 || heading > 360) {
    return null;
  }
  return heading == 360 ? 0 : heading;
}
