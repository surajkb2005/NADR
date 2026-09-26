import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/destination/presentation/destination_info_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('shows empty state when no destination', (tester) async {
    await tester.pumpWidget(_wrap(const DestinationInfoCard()));

    expect(find.text('No destination selected'), findsOneWidget);
  });

  testWidgets('shows coordinates when destination has no label', (
    tester,
  ) async {
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 12.97, longitude: 77.59),
    );

    await tester.pumpWidget(
      _wrap(const DestinationInfoCard(destination: destination)),
    );

    expect(find.text('12.97, 77.59'), findsOneWidget);
  });

  testWidgets('shows label as title and coordinates as subtitle when present', (
    tester,
  ) async {
    const destination = Destination(
      coordinate: GeoCoordinate(latitude: 12.97, longitude: 77.59),
      displayLabel: 'MG Road',
    );

    await tester.pumpWidget(
      _wrap(const DestinationInfoCard(destination: destination)),
    );

    expect(find.text('MG Road'), findsOneWidget);
    expect(find.text('12.97, 77.59'), findsOneWidget);
  });
}
