import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart' as domain;
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/imu/application/imu_navigation_state.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';
import 'package:nadr_mobile/features/navigation/presentation/navigation_issue_resolver.dart';
import 'package:nadr_mobile/features/routing/application/route_request_controller.dart';
import 'package:nadr_mobile/shared/widgets/dedup_issue_banner.dart';

const _destination = Destination(
  coordinate: GeoCoordinate(latitude: 12.97, longitude: 77.59),
);

void main() {
  test('disabled location service takes priority over everything else', () {
    final issue = NavigationIssueResolver.resolve(
      mode: domain.NavigationMode.gps,
      location: const DeviceLocationState(
        serviceStatus: LocationServiceStatus.disabled,
      ),
      destination: _destination,
      routeRequest: const RouteRequestState(),
    );

    expect(issue?.message, 'Location services are turned off.');
  });

  test('denied permission surfaces a grant-permission action', () {
    final issue = NavigationIssueResolver.resolve(
      mode: domain.NavigationMode.gps,
      location: const DeviceLocationState(
        permissionStatus: LocationPermissionStatus.denied,
      ),
      destination: _destination,
      routeRequest: const RouteRequestState(),
      onRequestLocationPermission: () {},
    );

    expect(issue?.actionLabel, 'Grant permission');
  });

  test('GPS acquiring shows a waiting message, not an error', () {
    final issue = NavigationIssueResolver.resolve(
      mode: domain.NavigationMode.gps,
      location: const DeviceLocationState(
        permissionStatus: LocationPermissionStatus.granted,
        trackingStatus: LocationTrackingStatus.acquiring,
      ),
      destination: _destination,
      routeRequest: const RouteRequestState(),
    );

    expect(issue?.message, 'Waiting for a GPS fix…');
    expect(issue?.severity, IssueSeverity.info);
  });

  test('IMU headingUnavailable is a warning, not a fatal error', () {
    final issue = NavigationIssueResolver.resolve(
      mode: domain.NavigationMode.imu,
      location: const DeviceLocationState(
        permissionStatus: LocationPermissionStatus.granted,
        trackingStatus: LocationTrackingStatus.active,
      ),
      imu: const ImuNavigationState(ImuNavigationPhase.headingUnavailable),
      destination: _destination,
      routeRequest: const RouteRequestState(),
    );

    expect(issue?.severity, IssueSeverity.warning);
    expect(issue?.message, contains('heading is unavailable'));
  });

  test('no destination is surfaced once GPS/IMU are healthy', () {
    final issue = NavigationIssueResolver.resolve(
      mode: domain.NavigationMode.gps,
      location: const DeviceLocationState(
        permissionStatus: LocationPermissionStatus.granted,
        trackingStatus: LocationTrackingStatus.active,
      ),
      routeRequest: const RouteRequestState(),
    );

    expect(issue?.message, 'No destination selected yet.');
  });

  test('route failure surfaces the real backend message with retry', () {
    var retried = false;
    final issue = NavigationIssueResolver.resolve(
      mode: domain.NavigationMode.gps,
      location: const DeviceLocationState(
        permissionStatus: LocationPermissionStatus.granted,
        trackingStatus: LocationTrackingStatus.active,
      ),
      destination: _destination,
      routeRequest: const RouteRequestState(
        phase: RouteRequestPhase.failure,
        message: 'Cannot reach the backend.',
      ),
      onRetryRoute: () => retried = true,
    );

    expect(issue?.message, 'Cannot reach the backend.');
    issue?.onAction?.call();
    expect(retried, isTrue);
  });

  test('everything healthy returns no issue', () {
    final issue = NavigationIssueResolver.resolve(
      mode: domain.NavigationMode.gps,
      location: const DeviceLocationState(
        permissionStatus: LocationPermissionStatus.granted,
        trackingStatus: LocationTrackingStatus.active,
      ),
      destination: _destination,
      routeRequest: const RouteRequestState(
        phase: RouteRequestPhase.success,
        alternativeCount: 1,
      ),
    );

    expect(issue, isNull);
  });

  test('blocked permission offers no action without a real callback', () {
    final issue = NavigationIssueResolver.resolve(
      mode: domain.NavigationMode.gps,
      location: const DeviceLocationState(
        permissionStatus: LocationPermissionStatus.deniedForever,
      ),
      destination: _destination,
      routeRequest: const RouteRequestState(),
    );
    expect(issue?.message, 'Location permission is blocked for this app.');
    expect(issue?.onAction, isNull);
    expect(issue?.actionLabel, isNull);
  });

  test('IMU initialization phases are informational', () {
    for (final phase in [
      ImuNavigationPhase.waitingForGps,
      ImuNavigationPhase.starting,
      ImuNavigationPhase.calibrating,
    ]) {
      final issue = NavigationIssueResolver.resolve(
        mode: domain.NavigationMode.imu,
        location: const DeviceLocationState(
          permissionStatus: LocationPermissionStatus.granted,
        ),
        imu: ImuNavigationState(phase),
        destination: _destination,
        routeRequest: const RouteRequestState(),
      );
      expect(issue?.severity, IssueSeverity.info);
    }
  });

  test('IMU unavailable and sensor error are surfaced', () {
    for (final phase in [
      ImuNavigationPhase.unavailable,
      ImuNavigationPhase.error,
    ]) {
      final issue = NavigationIssueResolver.resolve(
        mode: domain.NavigationMode.imu,
        location: const DeviceLocationState(
          permissionStatus: LocationPermissionStatus.granted,
        ),
        imu: ImuNavigationState(phase),
        destination: _destination,
        routeRequest: const RouteRequestState(),
      );
      expect(issue?.severity, IssueSeverity.error);
    }
  });

  test('route idle, loading, empty and success do not invent issues', () {
    for (final request in [
      const RouteRequestState(),
      const RouteRequestState(phase: RouteRequestPhase.loading),
      const RouteRequestState(phase: RouteRequestPhase.success),
      const RouteRequestState(
        phase: RouteRequestPhase.success,
        alternativeCount: 1,
      ),
    ]) {
      final issue = NavigationIssueResolver.resolve(
        mode: domain.NavigationMode.gps,
        location: const DeviceLocationState(
          permissionStatus: LocationPermissionStatus.granted,
          trackingStatus: LocationTrackingStatus.active,
        ),
        destination: _destination,
        routeRequest: request,
      );
      expect(issue, isNull);
    }
  });

  test('route failure without callback has no retry action', () {
    final issue = NavigationIssueResolver.resolve(
      mode: domain.NavigationMode.gps,
      location: const DeviceLocationState(
        permissionStatus: LocationPermissionStatus.granted,
        trackingStatus: LocationTrackingStatus.active,
      ),
      destination: _destination,
      routeRequest: const RouteRequestState(phase: RouteRequestPhase.failure),
    );
    expect(issue?.message, 'Unable to get a route.');
    expect(issue?.onAction, isNull);
    expect(issue?.actionLabel, isNull);
  });
}
