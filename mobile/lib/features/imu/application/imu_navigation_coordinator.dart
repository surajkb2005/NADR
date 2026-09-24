import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/core/diagnostics/nadr_diagnostics.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart' as domain;
import 'package:nadr_mobile/features/imu/application/imu_navigation_state.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_sample.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_source.dart';
import 'package:nadr_mobile/features/imu/infrastructure/android_imu_sensor_source.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/features/navigation/domain/connection_status.dart';
import 'package:nadr_mobile/features/navigation/domain/position_estimator.dart';
import 'package:nadr_mobile/features/navigation/infrastructure/step_based_imu_position_estimator.dart';

final imuSensorSourceProvider = Provider<ImuSensorSource>((ref) {
  final source = AndroidImuSensorSource();
  ref.onDispose(() => unawaited(source.dispose()));
  return source;
});

final imuPositionEstimatorProvider = Provider<PositionEstimator>((ref) {
  const configuredStepLengthText = String.fromEnvironment(
    'NADR_IMU_STEP_LENGTH_METERS',
    defaultValue: '0.65',
  );
  final configuredStepLength = double.tryParse(configuredStepLengthText);
  final stepLength =
      configuredStepLength != null &&
          configuredStepLength.isFinite &&
          configuredStepLength >=
              StepBasedImuPositionEstimator.minimumConfiguredStepLengthMeters &&
          configuredStepLength <=
              StepBasedImuPositionEstimator.maximumConfiguredStepLengthMeters
      ? configuredStepLength
      : StepBasedImuPositionEstimator.defaultStepLengthMeters;
  return StepBasedImuPositionEstimator(
    stepLengthMeters: stepLength,
    onDiagnostic: (message) {
      if (message.startsWith('stage=step')) {
        NadrDiagnostics.log('NADR_IMU_ESTIMATOR', message);
      } else {
        NadrDiagnostics.throttled(
          'NADR_IMU_ESTIMATOR',
          'estimator_tick',
          message,
        );
      }
    },
  );
});

final imuNavigationCoordinatorProvider =
    NotifierProvider<ImuNavigationCoordinator, ImuNavigationState>(
      ImuNavigationCoordinator.new,
    );

final class ImuNavigationCoordinator extends Notifier<ImuNavigationState>
    with WidgetsBindingObserver {
  late ImuSensorSource _source;
  late PositionEstimator _estimator;
  StreamSubscription<ImuSensorSample>? _samples;
  StreamSubscription<SensorStatus>? _statuses;
  Timer? _tickTimer;
  int _eventsSinceTick = 0;
  DateTime? _lastVisualPublishedAt;
  bool _sensorReady = false;
  bool _running = false;
  bool _paused = false;
  bool _disposed = false;
  bool _failureLatched = false;
  int _generation = 0;

  @override
  ImuNavigationState build() {
    _source = ref.watch(imuSensorSourceProvider);
    _estimator = ref.watch(imuPositionEstimatorProvider);
    WidgetsBinding.instance.addObserver(this);
    _samples = _source.samples.listen(_onSample, onError: _onStreamError);
    _statuses = _source.statusChanges.listen(
      _onStatus,
      onError: _onStreamError,
    );
    ref.listen(
      navigationSessionProvider.select(
        (session) => (session.navigationMode, session.latestGpsPosition),
      ),
      (previous, next) => unawaited(_synchronize()),
    );
    ref.onDispose(_dispose);
    Future<void>.microtask(_synchronize);
    return const ImuNavigationState(ImuNavigationPhase.stopped);
  }

  void setNavigationMode(domain.NavigationMode mode) {
    _failureLatched = false;
    ref.read(navigationSessionProvider.notifier).setNavigationMode(mode);
    unawaited(_synchronize());
  }

  Future<void> _synchronize() async {
    if (_disposed) return;
    final session = ref.read(navigationSessionProvider);
    if (session.navigationMode == domain.NavigationMode.gps) {
      await _stop();
      state = const ImuNavigationState(ImuNavigationPhase.stopped);
      return;
    }
    if (_paused) {
      state = const ImuNavigationState(ImuNavigationPhase.paused);
      return;
    }
    if (session.latestGpsPosition == null) {
      await _stop();
      state = const ImuNavigationState(ImuNavigationPhase.waitingForGps);
      return;
    }
    if (_running) return;
    if (_failureLatched) return;
    await _start();
  }

  Future<void> _start() async {
    if (_disposed || _running) return;
    final gps = ref.read(navigationSessionProvider).latestGpsPosition;
    if (gps == null) return;
    _running = true;
    _sensorReady = false;
    _eventsSinceTick = 0;
    _lastVisualPublishedAt = null;
    final generation = ++_generation;
    _estimator.reset(origin: gps.coordinate, timestamp: DateTime.now());
    ref
        .read(navigationSessionProvider.notifier)
        .updateImuPosition(_estimator.latestEstimate!);
    ref
        .read(navigationSessionProvider.notifier)
        .setSensorStatus(SensorStatus.starting);
    state = const ImuNavigationState(ImuNavigationPhase.starting);
    try {
      await _source.start();
      if (_disposed || !_running || generation != _generation) return;
      _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        _tick();
      });
    } on Object {
      _fail(ImuNavigationPhase.error);
    }
  }

  void _onSample(ImuSensorSample sample) {
    if (!_running || _disposed || _paused || !_sensorReady) return;
    try {
      // Raw acceleration updates heading/diagnostics and drives the conservative
      // software cadence fallback when the hardware detector stays silent.
      _estimator.estimate(sample);
      _eventsSinceTick++;
    } on Object {
      _fail(ImuNavigationPhase.error);
    }
  }

  void _tick() {
    if (!_running || _disposed || _paused) return;
    try {
      final now = DateTime.now();
      final eventsSinceTick = _eventsSinceTick;
      _eventsSinceTick = 0;
      final estimate = _estimator.estimate(
        ImuSensorSample(
          linearAccelerationX: 0,
          linearAccelerationY: 0,
          linearAccelerationZ: 0,
          timestamp: now,
          isDecayTick: true,
        ),
      );
      if (_sensorReady &&
          estimate.heading != null &&
          state.phase != ImuNavigationPhase.active &&
          state.phase != ImuNavigationPhase.calibrating) {
        ref
            .read(navigationSessionProvider.notifier)
            .setSensorStatus(SensorStatus.active);
        state = const ImuNavigationState(ImuNavigationPhase.active);
      }
      final previousPublished = ref
          .read(navigationSessionProvider)
          .latestImuPosition;
      final shouldPublish =
          previousPublished == null ||
          previousPublished.coordinate != estimate.coordinate ||
          previousPublished.heading != estimate.heading;
      final publishNow =
          shouldPublish &&
          (_lastVisualPublishedAt == null ||
              now.difference(_lastVisualPublishedAt!) >=
                  const Duration(milliseconds: 400));
      NadrDiagnostics.throttled(
        'NADR_IMU_TICK',
        'tick',
        'eventsSinceTick=$eventsSinceTick sensorReady=$_sensorReady '
            'estimate=${estimate.coordinate} estimateHeading=${estimate.heading} '
            'previousPublished=${previousPublished?.coordinate} changed=$shouldPublish publish=$publishNow',
      );
      if (publishNow) {
        _lastVisualPublishedAt = now;
        ref
            .read(navigationSessionProvider.notifier)
            .updateImuPosition(estimate);
      }
    } on Object {
      _fail(ImuNavigationPhase.error);
    }
  }

  void _onStatus(SensorStatus status) {
    if (_disposed || !_running) return;
    if (status == SensorStatus.active) {
      _sensorReady = true;
      if (state.phase == ImuNavigationPhase.headingUnavailable ||
          state.phase == ImuNavigationPhase.calibrating) {
        ref
            .read(navigationSessionProvider.notifier)
            .setSensorStatus(SensorStatus.starting);
        state = const ImuNavigationState(ImuNavigationPhase.starting);
      }
    } else if (status == SensorStatus.calibrating) {
      _sensorReady = true;
      ref
          .read(navigationSessionProvider.notifier)
          .setSensorStatus(SensorStatus.calibrating);
      state = const ImuNavigationState(ImuNavigationPhase.calibrating);
    } else if (status == SensorStatus.headingUnavailable) {
      _sensorReady = false;
      _eventsSinceTick = 0;
      final neutral = _estimator.clearHeading(timestamp: DateTime.now());
      ref.read(navigationSessionProvider.notifier).updateImuPosition(neutral);
      ref
          .read(navigationSessionProvider.notifier)
          .setSensorStatus(SensorStatus.headingUnavailable);
      state = const ImuNavigationState(ImuNavigationPhase.headingUnavailable);
    } else if (status == SensorStatus.error ||
        status == SensorStatus.unavailable) {
      _fail(switch (status) {
        SensorStatus.headingUnavailable =>
          ImuNavigationPhase.headingUnavailable,
        SensorStatus.calibrating => ImuNavigationPhase.calibrating,
        SensorStatus.unavailable => ImuNavigationPhase.unavailable,
        _ => ImuNavigationPhase.error,
      });
    }
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    _fail(ImuNavigationPhase.error);
  }

  void _fail(ImuNavigationPhase phase) {
    if (_disposed) return;
    _running = false;
    _sensorReady = false;
    _eventsSinceTick = 0;
    _failureLatched = true;
    _generation++;
    _tickTimer?.cancel();
    _tickTimer = null;
    ref.read(navigationSessionProvider.notifier).setSensorStatus(
      switch (phase) {
        ImuNavigationPhase.unavailable => SensorStatus.unavailable,
        ImuNavigationPhase.headingUnavailable =>
          SensorStatus.headingUnavailable,
        ImuNavigationPhase.calibrating => SensorStatus.calibrating,
        _ => SensorStatus.error,
      },
    );
    state = ImuNavigationState(phase);
    unawaited(_source.stop());
  }

  Future<void> _stop() async {
    if (!_running) return;
    _running = false;
    _sensorReady = false;
    _eventsSinceTick = 0;
    _generation++;
    _tickTimer?.cancel();
    _tickTimer = null;
    ref
        .read(navigationSessionProvider.notifier)
        .setSensorStatus(SensorStatus.stopped);
    await _source.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _paused = true;
      unawaited(
        _stop().then((_) {
          if (!_disposed) {
            this.state = const ImuNavigationState(ImuNavigationPhase.paused);
          }
        }),
      );
    } else if (state == AppLifecycleState.resumed) {
      _paused = false;
      _failureLatched = false;
      unawaited(_synchronize());
    }
  }

  void _dispose() {
    _disposed = true;
    _running = false;
    _generation++;
    _tickTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_samples?.cancel());
    unawaited(_statuses?.cancel());
    unawaited(_source.stop());
  }
}
