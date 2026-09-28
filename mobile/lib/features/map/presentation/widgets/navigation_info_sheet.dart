import 'package:flutter/material.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart' as domain;
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/routing/application/route_request_controller.dart';
import 'package:nadr_mobile/shared/widgets/bottom_sheet_surface.dart';
import 'package:nadr_mobile/shared/widgets/compact_status_chip.dart';

class NavigationInfoSheet extends StatelessWidget {
  const NavigationInfoSheet({
    required this.mode,
    required this.canRequestRoute,
    required this.routeRequestState,
    required this.onRequestRoute,
    this.destination,
    super.key,
  });

  final domain.NavigationMode mode;
  final Destination? destination;
  final bool canRequestRoute;
  final RouteRequestState routeRequestState;
  final VoidCallback onRequestRoute;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      key: const ValueKey('navigation-info-sheet'),
      initialChildSize: 0.20,
      minChildSize: 0.16,
      maxChildSize: 0.48,
      snap: true,
      builder: (context, scrollController) {
        return BottomSheetSurface(
          scrollController: scrollController,
          child: _NavigationInfoContent(
            mode: mode,
            destination: destination,
            canRequestRoute: canRequestRoute,
            routeRequestState: routeRequestState,
            onRequestRoute: onRequestRoute,
          ),
        );
      },
    );
  }
}

class _NavigationInfoContent extends StatelessWidget {
  const _NavigationInfoContent({
    required this.mode,
    required this.destination,
    required this.canRequestRoute,
    required this.routeRequestState,
    required this.onRequestRoute,
  });

  final domain.NavigationMode mode;
  final Destination? destination;
  final bool canRequestRoute;
  final RouteRequestState routeRequestState;
  final VoidCallback onRequestRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGps = mode == domain.NavigationMode.gps;
    final statusColor = isGps
        ? theme.colorScheme.primary
        : theme.brightness == Brightness.dark
        ? const Color(0xFFD0BCFF)
        : const Color(0xFF6F42C1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'NADR Navigation',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            CompactStatusChip(
              label: isGps ? 'GPS' : 'IMU',
              icon: isGps ? Icons.location_on_outlined : Icons.explore_outlined,
              color: statusColor,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          destination == null ? 'No destination selected' : 'Destination set',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          destination == null
              ? 'Select a destination to view route information.'
              : '${destination!.coordinate.latitude}, '
                    '${destination!.coordinate.longitude}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('get-route-button'),
            onPressed:
                canRequestRoute &&
                    routeRequestState.phase != RouteRequestPhase.loading
                ? onRequestRoute
                : null,
            icon: routeRequestState.phase == RouteRequestPhase.loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.route_outlined),
            label: Text(
              routeRequestState.phase == RouteRequestPhase.loading
                  ? 'Getting route…'
                  : 'Get route',
            ),
          ),
        ),
        if (routeRequestState.message case final message?) ...[
          const SizedBox(height: 8),
          Text(
            message,
            key: const ValueKey('route-request-status'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: routeRequestState.phase == RouteRequestPhase.failure
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
