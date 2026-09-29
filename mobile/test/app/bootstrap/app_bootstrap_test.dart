import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/app/app.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';
import 'package:nadr_mobile/features/location/application/location_coordinator.dart';

import '../../support/fake_device_location_source.dart';

void main() {
  testWidgets('application foundation renders through Riverpod bootstrap', (
    tester,
  ) async {
    final environment = AppEnvironment(
      apiBaseUrl: 'https://api.example.test',
      wsBaseUrl: 'wss://api.example.test',
      mapStyleUrl: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(environment),
          deviceLocationSourceProvider.overrideWithValue(
            FakeDeviceLocationSource(),
          ),
        ],
        child: const NadrApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('destination-search-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('navigation-info-sheet')), findsOneWidget);
    expect(find.text('GPS mode'), findsNothing);
    expect(find.text('No GPS fix'), findsOneWidget);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.useMaterial3, isTrue);
    expect(app.darkTheme?.useMaterial3, isTrue);
  });
}
