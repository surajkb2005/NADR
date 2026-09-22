import 'package:nadr_mobile/features/imu/domain/imu_sensor_sample.dart';
import 'package:nadr_mobile/features/navigation/domain/connection_status.dart';

abstract interface class ImuSensorSource {
  Stream<ImuSensorSample> get samples;

  Stream<SensorStatus> get statusChanges;

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}
