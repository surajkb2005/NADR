import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:nadr_mobile/features/imu/domain/imu_sensor_sample.dart';
import 'package:nadr_mobile/features/imu/infrastructure/android_heading_capability.dart';
import 'package:nadr_mobile/features/imu/infrastructure/android_imu_sensor_source.dart';
import 'package:nadr_mobile/features/navigation/domain/connection_status.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('capability channel reports native support and absence', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AndroidHeadingCapabilitySource.channel,
        null,
      ),
    );
    for (final supported in [true, false]) {
      messenger.setMockMethodCallHandler(
        AndroidHeadingCapabilitySource.channel,
        (call) async {
          expect(call.method, 'hasNorthReferencedHeading');
          return supported;
        },
      );
      expect(
        await const AndroidHeadingCapabilitySource()
            .hasNorthReferencedHeading(),
        supported,
      );
    }
  });

  test(
    'unsupported device ignores constant zero and keeps neutral sample',
    () async {
      final motion = StreamController<UserAccelerometerEvent>.broadcast(
        sync: true,
      );
      final compass = StreamController<CompassEvent>.broadcast(sync: true);
      final gyroscope = StreamController<GyroscopeEvent>.broadcast(sync: true);
      final steps = StreamController<Object?>.broadcast(sync: true);
      final source = AndroidImuSensorSource(
        headingCapability: const _FakeCapability(false),
        motionEvents: () => motion.stream,
        compassEvents: () => compass.stream,
        gyroscopeEvents: () => gyroscope.stream,
        stepEvents: () => steps.stream,
      );
      addTearDown(() async {
        await source.dispose();
        await motion.close();
        await compass.close();
        await gyroscope.close();
        await steps.close();
      });
      final statuses = <SensorStatus>[];
      final samples = <ImuSensorSample>[];
      source.statusChanges.listen(statuses.add);
      source.samples.listen(samples.add);

      await source.start();
      compass.add(CompassEvent.fromList([0, 0, 15]));
      steps.add({'type': 'ready'});
      motion.add(UserAccelerometerEvent(4, 0, 0, DateTime.now()));
      await pumpEventQueue();

      expect(statuses, contains(SensorStatus.headingUnavailable));
      expect(statuses, isNot(contains(SensorStatus.active)));
      expect(samples.single.heading, isNull);
    },
  );

  test(
    'north zero works; low quality calibrates; invalid heading pauses',
    () async {
      final motion = StreamController<UserAccelerometerEvent>.broadcast(
        sync: true,
      );
      final compass = StreamController<CompassEvent>.broadcast(sync: true);
      final gyroscope = StreamController<GyroscopeEvent>.broadcast(sync: true);
      final steps = StreamController<Object?>.broadcast(sync: true);
      final source = AndroidImuSensorSource(
        headingCapability: const _FakeCapability(true),
        motionEvents: () => motion.stream,
        compassEvents: () => compass.stream,
        gyroscopeEvents: () => gyroscope.stream,
        stepEvents: () => steps.stream,
      );
      addTearDown(() async {
        await source.dispose();
        await motion.close();
        await compass.close();
        await gyroscope.close();
        await steps.close();
      });
      final statuses = <SensorStatus>[];
      final samples = <ImuSensorSample>[];
      source.statusChanges.listen(statuses.add);
      source.samples.listen(samples.add);
      await source.start();
      compass.add(CompassEvent.fromList([0, 0, 15]));
      gyroscope.add(GyroscopeEvent(0, 0, 0, DateTime.now()));
      steps.add({'type': 'ready'});
      motion.add(UserAccelerometerEvent(4, 0, 0, DateTime.now()));
      await pumpEventQueue();
      expect(statuses, contains(SensorStatus.active));
      expect(samples.last.heading, 0);

      compass.add(CompassEvent.fromList([45, 0, 45]));
      motion.add(UserAccelerometerEvent(4, 0, 0, DateTime.now()));
      await pumpEventQueue();
      expect(statuses.last, SensorStatus.calibrating);
      expect(samples.last.heading, 45);
      expect(samples.last.headingAccuracyDegrees, 45);

      compass.add(CompassEvent.fromList([0, 0, 15]));
      motion.add(UserAccelerometerEvent(4, 0, 0, DateTime.now()));
      await pumpEventQueue();
      expect(statuses.last, SensorStatus.active);

      compass.add(CompassEvent.fromList([double.nan, 0, -1]));
      motion.add(UserAccelerometerEvent(4, 0, 0, DateTime.now()));
      await pumpEventQueue();
      expect(statuses.last, SensorStatus.headingUnavailable);
      expect(samples.last.heading, isNull);

      compass.add(CompassEvent.fromList([90, 0, 15]));
      motion.add(UserAccelerometerEvent(4, 0, 0, DateTime.now()));
      await pumpEventQueue();
      expect(statuses.last, SensorStatus.active);
      expect(samples.last.heading, 90);

      steps.add({'type': 'step'});
      await pumpEventQueue();
      expect(samples.last.stepDetected, isTrue);
      expect(samples.last.heading, 90);
      expect(samples.last.headingAccuracyDegrees, 15);
    },
  );
}

final class _FakeCapability implements HeadingCapabilitySource {
  const _FakeCapability(this.supported);
  final bool supported;

  @override
  Future<bool> hasNorthReferencedHeading() async => supported;
}
