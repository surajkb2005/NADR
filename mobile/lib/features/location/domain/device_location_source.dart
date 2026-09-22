import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';

abstract interface class DeviceLocationSource {
  DeviceLocationState get state;

  Stream<PositionSample> get positions;

  Stream<DeviceLocationState> get statusChanges;

  Future<LocationServiceStatus> checkService();

  Future<LocationPermissionStatus> checkPermission();

  Future<LocationPermissionStatus> requestPermission();

  Future<PositionSample?> getCurrentPosition();

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}
