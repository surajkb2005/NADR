import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/shared/widgets/app_error_message.dart';
import 'package:nadr_mobile/shared/widgets/app_loading_overlay.dart';
import 'package:nadr_mobile/shared/widgets/compact_status_chip.dart';

void main() {
  testWidgets('loading overlay is conditional and reusable', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppLoadingOverlay(
          isLoading: true,
          message: 'Preparing route',
          child: ColoredBox(color: Colors.white),
        ),
      ),
    );

    expect(find.text('Preparing route'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ModalBarrier), findsAtLeastNWidgets(1));
  });

  testWidgets('error message and compact status chip render labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppErrorMessage(message: 'Unable to load'),
              CompactStatusChip(label: 'GPS', icon: Icons.location_on_outlined),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Unable to load'), findsOneWidget);
    expect(find.text('GPS'), findsOneWidget);
  });
}
