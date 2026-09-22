import 'dart:async';

import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/location/domain/device_location_source.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';

final class FakeDeviceLocationSource implements DeviceLocationSource {
  FakeDeviceLocationSource({
    DeviceLocationState initialState = const DeviceLocationState(),
    DeviceLocationState? stateOnStart,
  }) : _state = initialState,
       stateOnStart =
           stateOnStart ??
           const DeviceLocationState(
             serviceStatus: LocationServiceStatus.enabled,
             permissionStatus: LocationPermissionStatus.granted,
             trackingStatus: LocationTrackingStatus.active,
           ),
       _positionsController = StreamController<PositionSample>.broadcast(
         sync: true,
       ),
       _statusController = StreamController<DeviceLocationState>.broadcast(
         sync: true,
       );

  final DeviceLocationState stateOnStart;
  final StreamController<PositionSample> _positionsController;
  final StreamController<DeviceLocationState> _statusController;
  DeviceLocationState _state;

  int startCalls = 0;
  int stopCalls = 0;
  bool disposed = false;

  @override
  DeviceLocationState get state => _state;

  @override
  Stream<PositionSample> get positions => _positionsController.stream;

  @override
  Stream<DeviceLocationState> get statusChanges => _statusController.stream;

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    return _state.permissionStatus;
  }

  @override
  Future<LocationServiceStatus> checkService() async {
    return _state.serviceStatus;
  }

  @override
  Future<PositionSample?> getCurrentPosition() async => null;

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    return _state.permissionStatus;
  }

  @override
  Future<void> start() async {
    startCalls += 1;
    emitState(stateOnStart);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    emitState(_state.copyWith(trackingStatus: LocationTrackingStatus.stopped));
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await _positionsController.close();
    await _statusController.close();
  }

  void emitPosition(PositionSample position) {
    _positionsController.add(position);
  }

  void emitPositionError(Object error) {
    _positionsController.addError(error);
  }

  void emitState(DeviceLocationState nextState) {
    _state = nextState;
    _statusController.add(nextState);
  }
}
