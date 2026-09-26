import 'package:flutter/material.dart';
import 'package:nadr_mobile/shared/widgets/app_error_message.dart';

/// Severity used only for banner color, not to invent new error meaning.
enum IssueSeverity { info, warning, error }

/// One truthful navigation issue to surface to the user.
///
/// Two issues are "the same" for de-duplication purposes when [message]
/// matches — this prevents identical repeated errors from stacking in the
/// presentation layer as required by Task 3.
@immutable
final class NavigationIssue {
  const NavigationIssue({
    required this.message,
    this.severity = IssueSeverity.warning,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IssueSeverity severity;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavigationIssue &&
          message == other.message &&
          severity == other.severity &&
          actionLabel == other.actionLabel;

  @override
  int get hashCode => Object.hash(message, severity, actionLabel);
}

/// Shows at most one banner at a time for the current issue (or none).
///
/// If the same [issue] (by message/severity/actionLabel) is passed again on
/// a rebuild, the banner is not re-announced/re-inserted — it just remains,
/// preventing repeated identical errors from stacking as separate banners.
class DedupIssueBanner extends StatefulWidget {
  const DedupIssueBanner({this.issue, super.key});

  final NavigationIssue? issue;

  @override
  State<DedupIssueBanner> createState() => _DedupIssueBannerState();
}

class _DedupIssueBannerState extends State<DedupIssueBanner> {
  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    if (issue == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final color = switch (issue.severity) {
      IssueSeverity.info => theme.colorScheme.primary,
      IssueSeverity.warning => const Color(0xFFF29900),
      IssueSeverity.error => theme.colorScheme.error,
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('nav-issue-banner'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: color),
                child: IconTheme.merge(
                  data: IconThemeData(color: color),
                  child: AppErrorMessage(message: issue.message),
                ),
              ),
            ),
            if (issue.actionLabel != null && issue.onAction != null) ...[
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('nav-issue-banner-action'),
                onPressed: issue.onAction,
                child: Text(issue.actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
