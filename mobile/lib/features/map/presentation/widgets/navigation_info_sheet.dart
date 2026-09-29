import 'package:flutter/material.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/destination/presentation/destination_info_card.dart';
import 'package:nadr_mobile/features/navigation/presentation/navigation_status_panel.dart';
import 'package:nadr_mobile/features/routing/application/route_request_controller.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/features/routing/presentation/route_info_card.dart';
import 'package:nadr_mobile/shared/widgets/bottom_sheet_surface.dart';
import 'package:nadr_mobile/shared/widgets/dedup_issue_banner.dart';

/// Compact, scrollable route context. Destination and route state are passed
/// from the canonical navigation session; this widget owns no duplicate state.
class NavigationInfoSheet extends StatelessWidget {
  const NavigationInfoSheet({
    required this.status,
    required this.routeRequestState,
    required this.onRetryRoute,
    this.destination,
    this.selectedRoute,
    this.routeAlternatives,
    this.issue,
    this.onSelectRoute,
    this.controller,
    super.key,
  });

  final NavigationStatusData status;
  final Destination? destination;
  final RouteRequestState routeRequestState;
  final RouteAlternative? selectedRoute;
  final RouteAlternatives? routeAlternatives;
  final NavigationIssue? issue;
  final ValueChanged<RouteMode>? onSelectRoute;
  final VoidCallback onRetryRoute;
  final DraggableScrollableController? controller;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      key: const ValueKey('navigation-info-sheet'),
      controller: controller,
      initialChildSize: 0.20,
      minChildSize: 0.16,
      maxChildSize: 0.48,
      snap: true,
      builder: (context, scrollController) {
        return BottomSheetSurface(
          scrollController: scrollController,
          child: _NavigationInfoContent(
            status: status,
            destination: destination,
            routeRequestState: routeRequestState,
            selectedRoute: selectedRoute,
            routeAlternatives: routeAlternatives,
            issue: issue,
            onSelectRoute: onSelectRoute,
            onRetryRoute: onRetryRoute,
          ),
        );
      },
    );
  }
}

class _NavigationInfoContent extends StatelessWidget {
  const _NavigationInfoContent({
    required this.status,
    required this.destination,
    required this.routeRequestState,
    required this.selectedRoute,
    required this.routeAlternatives,
    required this.issue,
    required this.onSelectRoute,
    required this.onRetryRoute,
  });

  final NavigationStatusData status;
  final Destination? destination;
  final RouteRequestState routeRequestState;
  final RouteAlternative? selectedRoute;
  final RouteAlternatives? routeAlternatives;
  final NavigationIssue? issue;
  final ValueChanged<RouteMode>? onSelectRoute;
  final VoidCallback onRetryRoute;

  @override
  Widget build(BuildContext context) {
    final routeIsWaiting =
        routeRequestState.phase == RouteRequestPhase.waitingForPosition;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (issue == null && !routeIsWaiting)
          NavigationStatusPanel(
            data: status,
            showModeChip: false,
            showTrackingChip: false,
          ),
        if (issue case final currentIssue?) ...[
          const SizedBox(height: 12),
          DedupIssueBanner(issue: currentIssue),
        ],
        if (destination case final currentDestination?) ...[
          const SizedBox(height: 12),
          DestinationInfoCard(destination: currentDestination),
          const SizedBox(height: 12),
          RouteInfoCard(
            requestState: routeRequestState,
            selectedRoute: selectedRoute,
            alternatives: routeAlternatives,
            onSelectRoute: onSelectRoute,
            onRetry: onRetryRoute,
          ),
        ],
      ],
    );
  }
}
