import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/features/imu/infrastructure/android_imu_sensor_source.dart';

void main() {
  test('Android compass heading is normalized clockwise from north', () {
    expect(AndroidImuSensorSource.normalizeCompassHeading(0), 0);
    expect(AndroidImuSensorSource.normalizeCompassHeading(90), 90);
    expect(AndroidImuSensorSource.normalizeCompassHeading(180), 180);
    expect(AndroidImuSensorSource.normalizeCompassHeading(270), 270);
    expect(AndroidImuSensorSource.normalizeCompassHeading(360), 0);
    expect(AndroidImuSensorSource.normalizeCompassHeading(-90), 270);
    expect(AndroidImuSensorSource.normalizeCompassHeading(450), 90);
    expect(AndroidImuSensorSource.normalizeCompassHeading(null), isNull);
    expect(AndroidImuSensorSource.normalizeCompassHeading(double.nan), isNull);
  });
}
