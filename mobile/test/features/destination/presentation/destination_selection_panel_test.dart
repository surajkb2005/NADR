import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/destination/presentation/destination_selection_panel.dart';

void main() {
  group('coordinate validation', () {
    test('accepts finite boundary and precise values', () {
      for (final value in ['-90', '90', '12.345678901234']) {
        expect(validateLatitude(value), isNull, reason: value);
      }
      for (final value in ['-180', '180', '-77.594612345']) {
        expect(validateLongitude(value), isNull, reason: value);
      }
    });

    test('rejects empty and malformed values', () {
      for (final value in [null, '', '   ', 'twelve', '1.2.3', '--2']) {
        expect(validateLatitude(value), isNotNull, reason: '$value');
        expect(validateLongitude(value), isNotNull, reason: '$value');
      }
    });

    test('rejects NaN and either spelling of infinity', () {
      for (final value in ['NaN', 'Infinity', '-Infinity']) {
        expect(validateLatitude(value), 'Enter a finite number.');
        expect(validateLongitude(value), 'Enter a finite number.');
      }
    });

    test('rejects coordinates outside their geographic ranges', () {
      expect(validateLatitude('90.00001'), contains('-90 and 90'));
      expect(validateLatitude('-90.00001'), contains('-90 and 90'));
      expect(validateLongitude('180.00001'), contains('-180 and 180'));
      expect(validateLongitude('-180.00001'), contains('-180 and 180'));
    });
  });

  testWidgets('field-level errors are shown without confirming', (
    tester,
  ) async {
    Destination? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DestinationSelectionPanel(
            destination: null,
            onSelectOnMap: () {},
            onConfirm: (value) => confirmed = value,
            onClear: () {},
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('destination-latitude-field')),
      '91',
    );
    await tester.enterText(
      find.byKey(const ValueKey('destination-longitude-field')),
      'bad',
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm-coordinate-destination')),
    );
    await tester.pump();

    expect(find.text('Latitude must be between -90 and 90.'), findsOneWidget);
    expect(find.text('Enter a valid number.'), findsOneWidget);
    expect(confirmed, isNull);
  });
}
