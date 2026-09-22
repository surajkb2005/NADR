import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/location/domain/device_location_source.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';
import 'package:nadr_mobile/features/location/infrastructure/geolocator_device_location_source.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';

final deviceLocationSourceProvider = Provider<DeviceLocationSource>((ref) {
  final source = GeolocatorDeviceLocationSource();
  ref.onDispose(() => unawaited(source.dispose()));
  return source;
});

final locationCoordinatorProvider =
    NotifierProvider<LocationCoordinator, DeviceLocationState>(
      LocationCoordinator.new,
    );

final class LocationCoordinator extends Notifier<DeviceLocationState>
    with WidgetsBindingObserver {
  late DeviceLocationSource _source;
  StreamSubscription<PositionSample>? _positionSubscription;
  StreamSubscription<DeviceLocationState>? _statusSubscription;
  bool _trackingRequested = false;
  bool _disposed = false;

  @override
  DeviceLocationState build() {
    _source = ref.watch(deviceLocationSourceProvider);
    WidgetsBinding.instance.addObserver(this);

    _positionSubscription = _source.positions.listen(
      _handlePosition,
      onError: _handlePositionError,
    );
    _statusSubscription = _source.statusChanges.listen(
      _handleSourceState,
      onError: _handleStatusError,
    );

    ref.onDispose(_dispose);
    Future<void>.microtask(start);
    return _source.state;
  }

  Future<void> start() async {
    if (_disposed || _trackingRequested) return;
    _trackingRequested = true;
    try {
      await _source.start();
    } on Object catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        trackingStatus: LocationTrackingStatus.error,
        errorMessage: 'Unable to start location: $error',
      );
    }
  }

  Future<void> stop() async {
    if (_disposed || !_trackingRequested) return;
    _trackingRequested = false;
    await _source.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(start());
      case AppLifecycleState.paused || AppLifecycleState.detached:
        unawaited(stop());
      case AppLifecycleState.inactive || AppLifecycleState.hidden:
        break;
    }
  }

  void _handlePosition(PositionSample position) {
    if (_disposed) return;
    ref.read(navigationSessionProvider.notifier).updateGpsPosition(position);
  }

  void _handlePositionError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    state = state.copyWith(
      trackingStatus: LocationTrackingStatus.error,
      errorMessage: 'Location update failed: $error',
    );
  }

  void _handleSourceState(DeviceLocationState nextState) {
    if (_disposed) return;
    state = nextState;
  }

  void _handleStatusError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    state = state.copyWith(
      trackingStatus: LocationTrackingStatus.error,
      errorMessage: 'Location status failed: $error',
    );
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    _trackingRequested = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_positionSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    unawaited(_source.stop());
  }
}
