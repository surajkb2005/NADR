import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadr_mobile/shared/widgets/dedup_issue_banner.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('null issue renders nothing', (tester) async {
    await tester.pumpWidget(_wrap(const DedupIssueBanner()));

    expect(find.byKey(const ValueKey('nav-issue-banner')), findsNothing);
  });

  testWidgets('shows message and optional action button', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        DedupIssueBanner(
          issue: NavigationIssue(
            message: 'GPS is unavailable right now.',
            actionLabel: 'Retry',
            onAction: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('GPS is unavailable right now.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-issue-banner-action')));
    expect(tapped, isTrue);
  });

  testWidgets('rebuilding with an identical issue shows only one banner', (
    tester,
  ) async {
    const issue = NavigationIssue(message: 'No destination selected yet.');

    await tester.pumpWidget(_wrap(const DedupIssueBanner(issue: issue)));
    await tester.pumpWidget(_wrap(const DedupIssueBanner(issue: issue)));

    expect(find.byKey(const ValueKey('nav-issue-banner')), findsOneWidget);
    expect(find.text('No destination selected yet.'), findsOneWidget);
  });

  testWidgets('clearing the issue removes the banner', (tester) async {
    const issue = NavigationIssue(message: 'Waiting for a GPS fix…');

    await tester.pumpWidget(_wrap(const DedupIssueBanner(issue: issue)));
    expect(find.byKey(const ValueKey('nav-issue-banner')), findsOneWidget);

    await tester.pumpWidget(_wrap(const DedupIssueBanner()));
    expect(find.byKey(const ValueKey('nav-issue-banner')), findsNothing);
  });
}
