import 'package:nadr_mobile/core/geo/navigation_mode.dart' as domain;
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/imu/application/imu_navigation_state.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';
import 'package:nadr_mobile/features/routing/application/route_request_controller.dart';
import 'package:nadr_mobile/shared/widgets/dedup_issue_banner.dart';

/// Resolves the single highest-priority truthful issue from real existing
/// state, or null when nothing needs surfacing.
///
/// This is presentation-only mapping logic — it does not poll sensors or
/// the backend, and it does not treat every missing optional field (e.g. an
/// absent IMU heading) as a fatal application error. Priority: permission/
/// service problems first (block everything), then destination, then route.
abstract final class NavigationIssueResolver {
  static NavigationIssue? resolve({
    required domain.NavigationMode mode,
    required DeviceLocationState location,
    ImuNavigationState? imu,
    Destination? destination,
    required RouteRequestState routeRequest,
    void Function()? onRequestLocationPermission,
    void Function()? onOpenLocationSettings,
    void Function()? onRetryRoute,
  }) {
    if (location.serviceStatus == LocationServiceStatus.disabled) {
      return NavigationIssue(
        message: 'Location services are turned off.',
        severity: IssueSeverity.error,
        actionLabel: onOpenLocationSettings != null ? 'Open settings' : null,
        onAction: onOpenLocationSettings,
      );
    }

    switch (location.permissionStatus) {
      case LocationPermissionStatus.deniedForever:
        return NavigationIssue(
          message: 'Location permission is blocked for this app.',
          severity: IssueSeverity.error,
          actionLabel: onOpenLocationSettings != null ? 'Open settings' : null,
          onAction: onOpenLocationSettings,
        );
      case LocationPermissionStatus.denied:
        return NavigationIssue(
          message: 'Location permission was denied.',
          severity: IssueSeverity.error,
          actionLabel: onRequestLocationPermission != null
              ? 'Grant permission'
              : null,
          onAction: onRequestLocationPermission,
        );
      case LocationPermissionStatus.notRequested ||
          LocationPermissionStatus.granted:
        break;
    }

    if (mode == domain.NavigationMode.gps &&
        location.trackingStatus == LocationTrackingStatus.error) {
      return const NavigationIssue(
        message: 'GPS is unavailable right now.',
        severity: IssueSeverity.error,
      );
    }

    if (mode == domain.NavigationMode.gps &&
        (location.trackingStatus == LocationTrackingStatus.starting ||
            location.trackingStatus == LocationTrackingStatus.acquiring)) {
      return const NavigationIssue(
        message: 'Waiting for a GPS fix…',
        severity: IssueSeverity.info,
      );
    }

    if (mode == domain.NavigationMode.imu && imu != null) {
      final imuIssue = switch (imu.phase) {
        ImuNavigationPhase.waitingForGps => const NavigationIssue(
          message: 'Waiting for a GPS fix before IMU navigation.',
          severity: IssueSeverity.info,
        ),
        ImuNavigationPhase.starting => const NavigationIssue(
          message: 'Starting IMU sensors…',
          severity: IssueSeverity.info,
        ),
        ImuNavigationPhase.calibrating => const NavigationIssue(
          message: 'Calibrating IMU heading…',
          severity: IssueSeverity.info,
        ),
        ImuNavigationPhase.unavailable => const NavigationIssue(
          message: 'IMU sensors are unavailable on this device.',
          severity: IssueSeverity.error,
        ),
        ImuNavigationPhase.headingUnavailable => const NavigationIssue(
          message: 'IMU heading is unavailable. Positions may not update.',
          severity: IssueSeverity.warning,
        ),
        ImuNavigationPhase.error => const NavigationIssue(
          message: 'IMU sensors reported an error.',
          severity: IssueSeverity.error,
        ),
        _ => null,
      };
      if (imuIssue != null) return imuIssue;
    }

    if (destination == null) {
      return const NavigationIssue(
        message: 'No destination selected yet.',
        severity: IssueSeverity.info,
      );
    }

    if (routeRequest.phase == RouteRequestPhase.failure) {
      return NavigationIssue(
        message: routeRequest.message ?? 'Unable to get a route.',
        severity: IssueSeverity.error,
        actionLabel: onRetryRoute != null ? 'Retry' : null,
        onAction: onRetryRoute,
      );
    }

    return null;
  }
}
