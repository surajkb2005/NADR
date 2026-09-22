import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';
import 'package:nadr_mobile/core/geo/navigation_mode.dart' as domain;
import 'package:nadr_mobile/core/network/backend_connectivity_panel.dart';
import 'package:nadr_mobile/features/imu/application/imu_navigation_coordinator.dart';
import 'package:nadr_mobile/features/imu/application/imu_navigation_state.dart';
import 'package:nadr_mobile/features/map/domain/map_defaults.dart';
import 'package:nadr_mobile/features/map/domain/nadr_map_controller.dart';
import 'package:nadr_mobile/features/map/presentation/map_camera_follow_controller.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/destination_surface.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/interactive_map_layer.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/maplibre_map_surface.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/navigation_info_sheet.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/navigation_mode_control.dart';
import 'package:nadr_mobile/features/location/application/location_coordinator.dart';
import 'package:nadr_mobile/features/location/presentation/location_status_indicator.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/shared/widgets/app_error_message.dart';
import 'package:nadr_mobile/shared/widgets/app_loading_overlay.dart';
import 'package:nadr_mobile/shared/widgets/compact_status_chip.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  NadrMapController? _mapController;
  late final MapCameraFollowController _cameraFollowController;
  bool _recenterErrorVisible = false;

  @override
  void initState() {
    super.initState();
    _cameraFollowController = MapCameraFollowController(
      onChanged: _handleFollowPresentationChanged,
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _cameraFollowController.updateFromSession(
          ref.read(navigationSessionProvider),
        ),
      );
    });
  }

  void _handleFollowPresentationChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _cameraFollowController.dispose();
    super.dispose();
  }

  void _handleMapControllerChanged(NadrMapController? controller) {
    if (!mounted || identical(controller, _mapController)) return;
    final previousController = _mapController;
    setState(() => _mapController = controller);
    if (controller == null) {
      _cameraFollowController.detachMapController(previousController);
    } else {
      unawaited(_cameraFollowController.attachMapController(controller));
    }
  }

  Future<void> _recenterOnCurrentLocation() async {
    try {
      final outcome = await _cameraFollowController.recenter();
      if (!mounted) return;
      switch (outcome) {
        case RecenterOutcome.success:
        case RecenterOutcome.alreadyCentered:
        case RecenterOutcome.coalesced:
        case RecenterOutcome.cancelled:
          return;
        case RecenterOutcome.noMap:
          _showRecenterError('Map is not ready yet.');
          return;
        case RecenterOutcome.noPosition:
          _showRecenterError('Waiting for your location.');
          return;
      }
    } on Object {
      if (!mounted) return;
      _showRecenterError('Unable to recenter on location.');
    }
  }

  void _showRecenterError(String message) {
    if (_recenterErrorVisible) return;
    _recenterErrorVisible = true;
    final messenger = ScaffoldMessenger.of(context);
    final feature = messenger.showSnackBar(AppErrorSnackBar.create(message));
    unawaited(feature.closed.then((_) => _recenterErrorVisible = false));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      navigationSessionProvider.select((state) => state.errorMessage),
      (previous, next) {
        if (next != null && next != previous) {
          ScaffoldMessenger.of(context)
              .showSnackBar(AppErrorSnackBar.create(next));
        }
      },
    );
    ref.listen(
      navigationSessionProvider.select(
        (state) => (state.displayedPosition, state.navigationMode),
      ),
      (previous, next) {
        unawaited(
          _cameraFollowController.updateFromSession(
            ref.read(navigationSessionProvider),
          ),
        );
      },
    );

    final environment = ref.watch(appEnvironmentProvider);
    final mapSurfaceBuilder = ref.watch(mapSurfaceBuilderProvider);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveMapLayer(
            styleUri: environment.mapStyleUri,
            configurationError: environment.mapStyleConfigurationError,
            initialCamera: MapDefaults.initialCamera,
            surfaceBuilder: mapSurfaceBuilder,
            onControllerChanged: _handleMapControllerChanged,
            onStyleLoaded: () => unawaited(
              _cameraFollowController.restoreMarkerAfterStyleReload(),
            ),
            onUserGesture: _cameraFollowController.handleUserGesture,
          ),
          const Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: DestinationSurface(),
              ),
            ),
          ),
          if (kDebugMode)
            Align(
              alignment: Alignment.topRight,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 200, right: 16),
                  child: IconButton.filledTonal(
                    key: const ValueKey('backend-diagnostics-button'),
                    tooltip: 'Backend diagnostics',
                    icon: const Icon(Icons.dns_outlined),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const BackendConnectivityPanel(),
                    ),
                  ),
                ),
              ),
            ),
          _NavigationOverlays(
            canRecenter: _cameraFollowController.canRecenter,
            isFollowing:
                _cameraFollowController.followMode ==
                MapCameraFollowMode.following,
            onRecenter: _recenterOnCurrentLocation,
          ),
          const _SessionLoadingPresentation(),
        ],
      ),
    );
  }
}

class _NavigationOverlays extends ConsumerWidget {
  const _NavigationOverlays({
    required this.canRecenter,
    required this.isFollowing,
    required this.onRecenter,
  });

  final bool canRecenter;
  final bool isFollowing;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      navigationSessionProvider.select((state) => state.navigationMode),
    );
    final locationState = ref.watch(locationCoordinatorProvider);
    final imuState = ref.watch(imuNavigationCoordinatorProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final controlsBottom = constraints.maxHeight * 0.20 + bottomInset + 14;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 16,
              bottom: controlsBottom + 68,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mode == domain.NavigationMode.imu) ...[
                    CompactStatusChip(
                      label: imuState.label,
                      icon: Icons.sensors_rounded,
                      color: imuState.phase == ImuNavigationPhase.active
                          ? const Color(0xFF7E57C2)
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 6),
                  ],
                  LocationStatusIndicator(state: locationState),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: controlsBottom + 68,
              child: Tooltip(
                message: canRecenter
                    ? isFollowing
                          ? 'Following current location'
                          : 'Recenter on current location'
                    : 'Waiting for current location',
                child: FloatingActionButton(
                  key: const ValueKey('recenter-button'),
                  heroTag: 'recenter-button',
                  onPressed: canRecenter ? onRecenter : null,
                  tooltip: 'Recenter on current location',
                  child: Icon(
                    isFollowing
                        ? Icons.gps_fixed_rounded
                        : Icons.my_location_rounded,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: controlsBottom,
              child: Center(
                child: NavigationModeControl(
                  mode: mode,
                  onModeChanged: ref
                      .read(imuNavigationCoordinatorProvider.notifier)
                      .setNavigationMode,
                ),
              ),
            ),
            NavigationInfoSheet(mode: mode),
          ],
        );
      },
    );
  }
}

class _SessionLoadingPresentation extends ConsumerWidget {
  const _SessionLoadingPresentation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(
      navigationSessionProvider.select((state) => state.isLoading),
    );
    return IgnorePointer(
      ignoring: !isLoading,
      child: AppLoadingOverlay(
        isLoading: isLoading,
        message: 'Loading navigation',
        child: const SizedBox.expand(),
      ),
    );
  }
}
