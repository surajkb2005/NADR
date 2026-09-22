import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/features/location/domain/device_location_state.dart';
import 'package:nadr_mobile/features/location/presentation/location_status_indicator.dart';

void main() {
  testWidgets('shows compact active and failure states', (tester) async {
    Future<void> pumpState(DeviceLocationState state) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LocationStatusIndicator(state: state)),
        ),
      );
    }

    await pumpState(
      const DeviceLocationState(
        serviceStatus: LocationServiceStatus.enabled,
        permissionStatus: LocationPermissionStatus.granted,
        trackingStatus: LocationTrackingStatus.active,
      ),
    );
    expect(find.text('Location active'), findsOneWidget);

    await pumpState(
      const DeviceLocationState(serviceStatus: LocationServiceStatus.disabled),
    );
    expect(find.text('Location services disabled'), findsOneWidget);

    await pumpState(
      const DeviceLocationState(
        serviceStatus: LocationServiceStatus.enabled,
        permissionStatus: LocationPermissionStatus.deniedForever,
      ),
    );
    expect(find.text('Location permission blocked'), findsOneWidget);
  });
}
