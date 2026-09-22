import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:nadr_mobile/core/diagnostics/nadr_diagnostics.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/location/domain/device_location_source.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';
import 'package:nadr_mobile/features/location/infrastructure/gps_fix_quality_gate.dart';
import 'package:nadr_mobile/features/location/infrastructure/gps_accuracy.dart';

abstract interface class GeolocatorClient {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<Position> getCurrentPosition(LocationSettings settings);

  Stream<Position> getPositionStream(LocationSettings settings);
}

final class DefaultGeolocatorClient implements GeolocatorClient {
  const DefaultGeolocatorClient();

  @override
  Future<LocationPermission> checkPermission() {
    return Geolocator.checkPermission();
  }

  @override
  Future<Position> getCurrentPosition(LocationSettings settings) {
    return Geolocator.getCurrentPosition(locationSettings: settings);
  }

  @override
  Stream<Position> getPositionStream(LocationSettings settings) {
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  @override
  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<LocationPermission> requestPermission() {
    return Geolocator.requestPermission();
  }
}

final class GeolocatorDeviceLocationSource implements DeviceLocationSource {
  GeolocatorDeviceLocationSource({
    GeolocatorClient? client,
    DateTime Function()? clock,
  }) : _client = client ?? const DefaultGeolocatorClient(),
       _clock = clock ?? DateTime.now;

  static final _currentPositionSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
    timeLimit: const Duration(seconds: 15),
  );

  static final _streamSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    // A quarantined fix needs fresh confirmation even after the phone stops.
    // The 2 s interval bounds delivery; unchanged accepted fixes are deduped.
    distanceFilter: 0,
    intervalDuration: const Duration(seconds: 2),
  );

  final GeolocatorClient _client;
  final DateTime Function() _clock;
  final GpsFixQualityGate _qualityGate = const GpsFixQualityGate();
  final GpsOutlierQuarantine _outlierQuarantine = GpsOutlierQuarantine();
  final StreamController<PositionSample> _positionsController =
      StreamController<PositionSample>.broadcast(sync: true);
  final StreamController<DeviceLocationState> _statusController =
      StreamController<DeviceLocationState>.broadcast(sync: true);

  DeviceLocationState _state = const DeviceLocationState();
  StreamSubscription<Position>? _positionSubscription;
  bool _permissionRequestAttempted = false;
  bool _starting = false;
  bool _disposed = false;
  int _operationGeneration = 0;
  int _rawSequence = 0;
  Position? _lastAcceptedPlatformPosition;

  @override
  DeviceLocationState get state => _state;

  @override
  Stream<PositionSample> get positions => _positionsController.stream;

  @override
  Stream<DeviceLocationState> get statusChanges => _statusController.stream;

  @override
  Future<LocationServiceStatus> checkService() async {
    final enabled = await _client.isLocationServiceEnabled();
    final serviceStatus = enabled
        ? LocationServiceStatus.enabled
        : LocationServiceStatus.disabled;
    _emitState(_state.copyWith(serviceStatus: serviceStatus));
    return serviceStatus;
  }

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    final permission = _mapPermission(await _client.checkPermission());
    _emitState(_state.copyWith(permissionStatus: permission));
    return permission;
  }

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    _permissionRequestAttempted = true;
    final permission = _mapPermission(await _client.requestPermission());
    _emitState(_state.copyWith(permissionStatus: permission));
    return permission;
  }

  @override
  Future<PositionSample?> getCurrentPosition() async {
    final position = await _client.getCurrentPosition(_currentPositionSettings);
    return toPositionSample(position);
  }

  @override
  Future<void> start() async {
    if (_disposed || _starting || _positionSubscription != null) return;

    _starting = true;
    final generation = ++_operationGeneration;
    _outlierQuarantine.reset();
    _emitState(
      _state.copyWith(
        trackingStatus: LocationTrackingStatus.starting,
        errorMessage: null,
      ),
    );

    try {
      final serviceStatus = await checkService();
      if (!_isCurrent(generation)) return;
      if (serviceStatus == LocationServiceStatus.disabled) {
        _emitState(
          _state.copyWith(trackingStatus: LocationTrackingStatus.stopped),
        );
        return;
      }

      var permissionStatus = await checkPermission();
      if (!_isCurrent(generation)) return;

      if (permissionStatus == LocationPermissionStatus.denied) {
        if (_permissionRequestAttempted) {
          _emitState(
            _state.copyWith(trackingStatus: LocationTrackingStatus.stopped),
          );
          return;
        }

        permissionStatus = await requestPermission();
        if (!_isCurrent(generation)) return;
      }

      if (permissionStatus == LocationPermissionStatus.denied ||
          permissionStatus == LocationPermissionStatus.deniedForever) {
        _emitState(
          _state.copyWith(trackingStatus: LocationTrackingStatus.stopped),
        );
        return;
      }

      _emitState(
        _state.copyWith(
          permissionStatus: LocationPermissionStatus.granted,
          trackingStatus: LocationTrackingStatus.acquiring,
          errorMessage: null,
        ),
      );

      try {
        final initialPosition = await _client.getCurrentPosition(
          _currentPositionSettings,
        );
        if (!_isCurrent(generation)) return;
        _handlePlatformPosition(initialPosition, generation);
      } on TimeoutException {
        // The continuous stream can still deliver the first fix.
      } on Object catch (error) {
        if (!_isCurrent(generation)) return;
        _emitState(
          _state.copyWith(
            trackingStatus: LocationTrackingStatus.error,
            errorMessage: 'Initial location unavailable: $error',
          ),
        );
      }

      if (!_isCurrent(generation)) return;
      _positionSubscription = _client
          .getPositionStream(_streamSettings)
          .listen(
            (position) => _handlePlatformPosition(position, generation),
            onError: (Object error, StackTrace stackTrace) =>
                _handleStreamError(error, stackTrace, generation),
            onDone: () => _handleUnexpectedStreamEnd(generation),
            cancelOnError: false,
          );
    } on Object catch (error) {
      if (_isCurrent(generation)) {
        _emitState(
          _state.copyWith(
            trackingStatus: LocationTrackingStatus.error,
            errorMessage: 'Unable to start location: $error',
          ),
        );
      }
    } finally {
      if (_isCurrent(generation)) _starting = false;
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _operationGeneration += 1;
    _starting = false;
    _outlierQuarantine.reset();
    final subscription = _positionSubscription;
    _positionSubscription = null;
    await subscription?.cancel();
    _emitState(_state.copyWith(trackingStatus: LocationTrackingStatus.stopped));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _operationGeneration += 1;
    _starting = false;
    _outlierQuarantine.reset();
    final subscription = _positionSubscription;
    _positionSubscription = null;
    await subscription?.cancel();
    _disposed = true;
    await _positionsController.close();
    await _statusController.close();
  }

  void _handlePlatformPosition(Position position, int generation) {
    final sequence = ++_rawSequence;
    final receivedAt = _clock();
    NadrDiagnostics.log(
      'NADR_GPS_RAW',
      'seq=$sequence generation=$generation platform=${position.timestamp.toIso8601String()} '
          'received=${receivedAt.toIso8601String()} lat=${position.latitude} '
          'lon=${position.longitude} hasAccuracy=${position.hasAccuracy} '
          'accuracyReported=${GpsAccuracy.isReported(position)} accuracy=${position.accuracy} '
          'speed=${position.speed} heading=${position.hasHeading ? position.heading : 'unknown'}',
    );
    if (!_isCurrent(generation)) {
      NadrDiagnostics.log(
        'NADR_GPS_REJECT',
        'seq=$sequence reason=obsolete_session',
      );
      return;
    }
    final decision = _qualityGate.evaluate(
      position,
      receivedAt: receivedAt,
      previousAccepted: _lastAcceptedPlatformPosition,
    );
    if (!decision.accepted) {
      NadrDiagnostics.log(
        'NADR_GPS_REJECT',
        'seq=$sequence reason=${decision.reason}',
      );
      return;
    }
    final outlierDecision = _outlierQuarantine.consider(
      position,
      previousAccepted: _lastAcceptedPlatformPosition,
    );
    final previousAccepted = _lastAcceptedPlatformPosition;
    final context =
        'seq=$sequence candidate=${position.latitude},${position.longitude} '
        'lastAccepted=${previousAccepted?.latitude},${previousAccepted?.longitude} '
        'distanceM=${outlierDecision.displacementMeters.toStringAsFixed(1)} '
        'elapsedS=${outlierDecision.elapsedSeconds.toStringAsFixed(1)} '
        'hasAccuracy=${position.hasAccuracy} accuracyReported=${GpsAccuracy.isReported(position)} '
        'accuracy=${position.accuracy} '
        'supports=${outlierDecision.supportCount} reason=${outlierDecision.reason}';
    if (outlierDecision.rejectedCandidate case final rejected?) {
      NadrDiagnostics.log(
        'NADR_GPS_REJECT',
        'candidate=${rejected.latitude},${rejected.longitude} reason=candidate_disagreed',
      );
    }
    if (!outlierDecision.accepted) {
      NadrDiagnostics.log(
        outlierDecision.action == GpsOutlierAction.rejected
            ? 'NADR_GPS_REJECT'
            : 'NADR_GPS_QUARANTINE',
        context,
      );
      return;
    }
    if (outlierDecision.action == GpsOutlierAction.confirmed) {
      NadrDiagnostics.log('NADR_GPS_CONFIRM', context);
    }
    _lastAcceptedPlatformPosition = position;
    NadrDiagnostics.log('NADR_GPS_ACCEPT', context);
    _emitPosition(toPositionSample(position));
  }

  void _emitPosition(PositionSample position) {
    if (_disposed) return;
    _positionsController.add(position);
    if (_state.trackingStatus != LocationTrackingStatus.active) {
      _emitState(
        _state.copyWith(
          trackingStatus: LocationTrackingStatus.active,
          errorMessage: null,
        ),
      );
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace, int generation) {
    if (!_isCurrent(generation)) return;
    _emitState(
      _state.copyWith(
        trackingStatus: LocationTrackingStatus.error,
        errorMessage: 'Location update failed: $error',
      ),
    );
    final subscription = _positionSubscription;
    _positionSubscription = null;
    unawaited(subscription?.cancel());
  }

  void _handleUnexpectedStreamEnd(int generation) {
    if (!_isCurrent(generation) || _positionSubscription == null) return;
    _positionSubscription = null;
    _emitState(
      _state.copyWith(
        trackingStatus: LocationTrackingStatus.error,
        errorMessage: 'Location updates stopped unexpectedly.',
      ),
    );
  }

  bool _isCurrent(int generation) {
    return !_disposed && generation == _operationGeneration;
  }

  void _emitState(DeviceLocationState nextState) {
    if (_disposed || nextState == _state) return;
    _state = nextState;
    _statusController.add(nextState);
  }

  static LocationPermissionStatus _mapPermission(
    LocationPermission permission,
  ) {
    return switch (permission) {
      LocationPermission.denied => LocationPermissionStatus.denied,
      LocationPermission.deniedForever =>
        LocationPermissionStatus.deniedForever,
      LocationPermission.whileInUse ||
      LocationPermission.always => LocationPermissionStatus.granted,
      LocationPermission.unableToDetermine => LocationPermissionStatus.denied,
    };
  }

  static PositionSample toPositionSample(Position position) {
    final heading =
        position.hasHeading &&
            position.heading.isFinite &&
            position.heading >= 0 &&
            position.heading <= 360
        ? position.heading
        : null;

    return PositionSample(
      coordinate: GeoCoordinate(
        latitude: position.latitude,
        longitude: position.longitude,
      ),
      heading: heading,
      horizontalAccuracyMeters: GpsAccuracy.measuredMeters(position),
      timestamp: position.timestamp,
      source: PositionSource.gps,
    );
  }
}
