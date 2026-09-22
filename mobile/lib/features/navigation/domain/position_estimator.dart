import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/geo/position_sample.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_sample.dart';

abstract interface class PositionEstimator {
  PositionSample? get latestEstimate;

  void reset({required GeoCoordinate origin, required DateTime timestamp});

  PositionSample clearHeading({required DateTime timestamp});

  PositionSample estimate(ImuSensorSample sample);
}
