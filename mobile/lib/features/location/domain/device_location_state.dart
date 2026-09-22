const _notProvided = Object();

enum LocationServiceStatus { unknown, enabled, disabled }

enum LocationPermissionStatus { notRequested, denied, deniedForever, granted }

enum LocationTrackingStatus { stopped, starting, acquiring, active, error }

final class DeviceLocationState {
  const DeviceLocationState({
    this.serviceStatus = LocationServiceStatus.unknown,
    this.permissionStatus = LocationPermissionStatus.notRequested,
    this.trackingStatus = LocationTrackingStatus.stopped,
    this.errorMessage,
  });

  final LocationServiceStatus serviceStatus;
  final LocationPermissionStatus permissionStatus;
  final LocationTrackingStatus trackingStatus;
  final String? errorMessage;

  DeviceLocationState copyWith({
    LocationServiceStatus? serviceStatus,
    LocationPermissionStatus? permissionStatus,
    LocationTrackingStatus? trackingStatus,
    Object? errorMessage = _notProvided,
  }) {
    return DeviceLocationState(
      serviceStatus: serviceStatus ?? this.serviceStatus,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      trackingStatus: trackingStatus ?? this.trackingStatus,
      errorMessage: identical(errorMessage, _notProvided)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DeviceLocationState &&
            serviceStatus == other.serviceStatus &&
            permissionStatus == other.permissionStatus &&
            trackingStatus == other.trackingStatus &&
            errorMessage == other.errorMessage;
  }

  @override
  int get hashCode => Object.hash(
    serviceStatus,
    permissionStatus,
    trackingStatus,
    errorMessage,
  );
}
