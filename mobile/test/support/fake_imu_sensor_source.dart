import 'dart:async';

import 'package:nadr_mobile/features/imu/domain/imu_sensor_sample.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_source.dart';
import 'package:nadr_mobile/features/navigation/domain/connection_status.dart';

final class FakeImuSensorSource implements ImuSensorSource {
  final _samples = StreamController<ImuSensorSample>.broadcast(sync: true);
  final _statuses = StreamController<SensorStatus>.broadcast(sync: true);
  int startCalls = 0;
  int stopCalls = 0;
  bool disposed = false;

  @override
  Stream<ImuSensorSample> get samples => _samples.stream;
  @override
  Stream<SensorStatus> get statusChanges => _statuses.stream;

  void emitSample(ImuSensorSample sample) => _samples.add(sample);
  void emitStatus(SensorStatus status) => _statuses.add(status);

  @override
  Future<void> start() async {
    startCalls++;
    emitStatus(SensorStatus.starting);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _samples.close();
    await _statuses.close();
  }
}
