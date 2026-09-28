import 'package:flutter/material.dart';
import 'package:nadr_mobile/features/routing/application/route_request_controller.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/shared/widgets/compact_status_chip.dart';

/// Read-only presentation of the current route request state and, when
/// available, the selected route's real metrics.
///
/// Shows idle/loading/success/empty/failure states from the existing
/// [RouteRequestState]. Metrics fields (distance, ETA, risk) are displayed
/// only when the backend actually provided them — never estimated or
/// fabricated here.
class RouteInfoCard extends StatelessWidget {
  const RouteInfoCard({
    required this.requestState,
    this.selectedRoute,
    this.alternatives,
    this.onSelectRoute,
    this.onRetry,
    super.key,
  });

  final RouteRequestState requestState;
  final RouteAlternative? selectedRoute;
  final RouteAlternatives? alternatives;
  final ValueChanged<RouteMode>? onSelectRoute;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card.filled(
      key: const ValueKey('route-info-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Route',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _phaseChip(theme),
              ],
            ),
            const SizedBox(height: 10),
            _body(theme),
          ],
        ),
      ),
    );
  }

  Widget _phaseChip(ThemeData theme) {
    final colors = theme.colorScheme;
    return switch (requestState.phase) {
      RouteRequestPhase.idle => CompactStatusChip(
        key: const ValueKey('route-info-phase'),
        label: 'Idle',
        icon: Icons.route_outlined,
        color: colors.outline,
      ),
      RouteRequestPhase.loading => CompactStatusChip(
        key: const ValueKey('route-info-phase'),
        label: 'Loading',
        icon: Icons.hourglass_top_rounded,
        color: colors.primary,
      ),
      RouteRequestPhase.success => CompactStatusChip(
        key: const ValueKey('route-info-phase'),
        label: 'Ready',
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF188038),
      ),
      RouteRequestPhase.failure => CompactStatusChip(
        key: const ValueKey('route-info-phase'),
        label: 'Failed',
        icon: Icons.error_outline_rounded,
        color: colors.error,
      ),
    };
  }

  Widget _body(ThemeData theme) {
    switch (requestState.phase) {
      case RouteRequestPhase.idle:
        return Text(
          'Request a route to see details here.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );

      case RouteRequestPhase.loading:
        return Text(
          'Requesting route from the backend…',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );

      case RouteRequestPhase.failure:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              requestState.message ?? 'Unable to get a route.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('route-info-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        );

      case RouteRequestPhase.success:
        if (requestState.alternativeCount == 0) {
          return Text(
            'No routes were returned for this destination.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        if (selectedRoute == null) {
          return Text(
            'No route selected.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${selectedRoute!.mode.name} route',
              style: theme.textTheme.labelLarge,
            ),
            if (alternatives != null && alternatives!.byMode.length > 1) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in alternatives!.byMode.keys)
                    ChoiceChip(
                      label: Text(mode.name),
                      selected: selectedRoute!.mode == mode,
                      onSelected: onSelectRoute == null
                          ? null
                          : (_) => onSelectRoute!(mode),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            _metricsRow(theme, selectedRoute!),
          ],
        );
    }
  }

  Widget _metricsRow(ThemeData theme, RouteAlternative route) {
    final metrics = route.metrics;
    final chips = <Widget>[];

    final distance = _formatDistance(metrics.distanceMeters);
    if (distance != null) {
      chips.add(
        CompactStatusChip(
          key: const ValueKey('route-info-distance'),
          label: distance,
          icon: Icons.straighten_rounded,
        ),
      );
    }

    final eta = _formatDuration(metrics.estimatedTimeSeconds);
    if (eta != null) {
      chips.add(
        CompactStatusChip(
          key: const ValueKey('route-info-eta'),
          label: eta,
          icon: Icons.schedule_rounded,
        ),
      );
    }

    if (metrics.maximumRiskZone != null) {
      chips.add(
        CompactStatusChip(
          key: const ValueKey('route-info-risk'),
          label: _riskLabel(metrics.maximumRiskZone!),
          icon: Icons.warning_amber_rounded,
          color: _riskColor(theme, metrics.maximumRiskZone!),
        ),
      );
    }

    if (chips.isEmpty) {
      return Text(
        'Route found. No additional metrics were provided.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  static String? _formatDistance(double? meters) {
    if (meters == null || !meters.isFinite || meters < 0) return null;
    return meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)} km'
        : '${meters.toStringAsFixed(0)} m';
  }

  static String? _formatDuration(double? seconds) {
    if (seconds == null || !seconds.isFinite || seconds < 0) return null;
    final totalMinutes = (seconds / 60).round();
    if (totalMinutes < 60) return '$totalMinutes min';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  static String _riskLabel(RiskZone zone) => switch (zone) {
    RiskZone.low => 'Low risk',
    RiskZone.medium => 'Medium risk',
    RiskZone.high => 'High risk',
  };

  static Color _riskColor(ThemeData theme, RiskZone zone) => switch (zone) {
    RiskZone.low => const Color(0xFF188038),
    RiskZone.medium => const Color(0xFFF29900),
    RiskZone.high => theme.colorScheme.error,
  };
}
