import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';
import 'package:nadr_mobile/core/geo/geo_coordinate.dart';
import 'package:nadr_mobile/core/network/backend_connectivity_panel.dart';
import 'package:nadr_mobile/features/destination/domain/destination.dart';
import 'package:nadr_mobile/features/destination/presentation/destination_selection_panel.dart';
import 'package:nadr_mobile/features/destination/presentation/destination_search_surface.dart';
import 'package:nadr_mobile/features/imu/application/imu_navigation_coordinator.dart';
import 'package:nadr_mobile/features/map/domain/map_defaults.dart';
import 'package:nadr_mobile/features/map/domain/nadr_map_controller.dart';
import 'package:nadr_mobile/features/map/presentation/map_camera_follow_controller.dart';
import 'package:nadr_mobile/features/map/presentation/route_camera_fit.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/interactive_map_layer.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/maplibre_map_surface.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/navigation_info_sheet.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/navigation_mode_control.dart';
import 'package:nadr_mobile/features/location/application/location_coordinator.dart';
import 'package:nadr_mobile/features/navigation/application/navigation_session_controller.dart';
import 'package:nadr_mobile/features/navigation/presentation/navigation_issue_resolver.dart';
import 'package:nadr_mobile/features/navigation/presentation/navigation_status_panel.dart';
import 'package:nadr_mobile/features/routing/application/route_request_controller.dart';
import 'package:nadr_mobile/features/routing/domain/route_models.dart';
import 'package:nadr_mobile/shared/widgets/app_error_message.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  NadrMapController? _mapController;
  late final MapCameraFollowController _cameraFollowController;
  bool _recenterErrorVisible = false;
  bool _isSelectingDestinationOnMap = false;

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
      final route = ref.read(navigationSessionProvider).selectedRoute;
      unawaited(
        _cameraFollowController.previewSelectedRoute(
          route,
          _cameraFitFor(route),
        ),
      );
      unawaited(_cameraFollowController.attachMapController(controller));
      unawaited(
        controller.updateDestinationMarker(
          ref.read(navigationSessionProvider).destination,
        ),
      );
      unawaited(
        controller.updateSelectedRoute(
          ref.read(navigationSessionProvider).selectedRoute,
        ),
      );
    }
  }

  void _openDestinationPanel() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => DestinationSelectionPanel(
        destination: ref.read(navigationSessionProvider).destination,
        onSelectOnMap: () {
          if (mounted) setState(() => _isSelectingDestinationOnMap = true);
        },
        onConfirm: ref.read(navigationSessionProvider.notifier).setDestination,
        onClear: ref.read(navigationSessionProvider.notifier).clearDestination,
      ),
    );
  }

  void _handleMapLongPress(GeoCoordinate coordinate) {
    if (!_isSelectingDestinationOnMap) return;
    setState(() => _isSelectingDestinationOnMap = false);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => DestinationReviewPanel(
        coordinate: coordinate,
        onConfirm: () => ref
            .read(navigationSessionProvider.notifier)
            .setDestination(Destination(coordinate: coordinate)),
      ),
    );
  }

  Future<void> _restoreMapLayersAfterStyleReload() async {
    await _cameraFollowController.restoreMarkerAfterStyleReload();
    await _mapController?.updateDestinationMarker(
      ref.read(navigationSessionProvider).destination,
    );
    await _mapController?.updateSelectedRoute(
      ref.read(navigationSessionProvider).selectedRoute,
    );
    await _cameraFollowController.retryPendingRouteFit();
  }

  RouteCameraFit? _cameraFitFor(RouteAlternative? route) {
    final session = ref.read(navigationSessionProvider);
    final media = MediaQuery.of(context);
    return RouteCameraFit.forRoute(
      route: route,
      start: session.currentRouteStart,
      destination: session.destination?.coordinate,
      viewportWidth: media.size.width,
      viewportHeight: media.size.height,
      topInset: media.padding.top,
      bottomInset: media.padding.bottom,
    );
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
    ref.listen(navigationSessionProvider.select((state) => state.destination), (
      previous,
      next,
    ) {
      unawaited(_mapController?.updateDestinationMarker(next));
    });
    ref.listen(
      navigationSessionProvider.select((state) => state.selectedRoute),
      (previous, next) {
        unawaited(_mapController?.updateSelectedRoute(next));
        unawaited(
          _cameraFollowController.previewSelectedRoute(
            next,
            _cameraFitFor(next),
          ),
        );
      },
    );

    final environment = ref.watch(appEnvironmentProvider);
    final mapSurfaceBuilder = ref.watch(mapSurfaceBuilderProvider);
    final destination = ref.watch(
      navigationSessionProvider.select((state) => state.destination),
    );

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
            onStyleLoaded: () => unawaited(_restoreMapLayersAfterStyleReload()),
            onUserGesture: _cameraFollowController.handleUserGesture,
            onLongPress: _handleMapLongPress,
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: DestinationSearchSurface(
                  destination: destination,
                  onSelect: ref
                      .read(navigationSessionProvider.notifier)
                      .setDestination,
                  onOpenFallback: _openDestinationPanel,
                ),
              ),
            ),
          ),
          if (_isSelectingDestinationOnMap)
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 82, 16, 0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Material(
                      key: const ValueKey('map-destination-instructions'),
                      elevation: 2,
                      color: Theme.of(context).colorScheme.inverseSurface,
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Long-press the map to propose a destination.',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const ValueKey(
                                'cancel-map-destination-mode',
                              ),
                              onPressed: () => setState(
                                () => _isSelectingDestinationOnMap = false,
                              ),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
        ],
      ),
    );
  }
}

class _NavigationOverlays extends ConsumerStatefulWidget {
  const _NavigationOverlays({
    required this.canRecenter,
    required this.isFollowing,
    required this.onRecenter,
  });

  final bool canRecenter;
  final bool isFollowing;
  final VoidCallback onRecenter;

  @override
  ConsumerState<_NavigationOverlays> createState() =>
      _NavigationOverlaysState();
}

class _NavigationOverlaysState extends ConsumerState<_NavigationOverlays> {
  late final DraggableScrollableController _sheetController;

  @override
  void initState() {
    super.initState();
    _sheetController = DraggableScrollableController()
      ..addListener(_handleSheetExtentChanged);
  }

  @override
  void dispose() {
    _sheetController
      ..removeListener(_handleSheetExtentChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSheetExtentChanged() {
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
  Widget build(BuildContext context) {
    final session = ref.watch(navigationSessionProvider);
    final mode = session.navigationMode;
    final routeRequestState = ref.watch(routeRequestControllerProvider);
    final locationState = ref.watch(locationCoordinatorProvider);
    final imuState = ref.watch(imuNavigationCoordinatorProvider);
    final destination = session.destination;
    final status = NavigationStatusData.fromSessionState(
      session: session,
      imuState: imuState,
      locationState: locationState,
    );
    final issue = NavigationIssueResolver.resolveStatusIssue(
      mode: mode,
      location: locationState,
      imu: imuState,
      includeGpsWaiting:
          routeRequestState.phase != RouteRequestPhase.waitingForPosition,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final sheetExtent = _sheetController.isAttached
            ? _sheetController.size
            : 0.20;
        final controlsBottom =
            constraints.maxHeight * sheetExtent + bottomInset + 14;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: 16,
              bottom: controlsBottom + 68,
              child: Tooltip(
                message: widget.canRecenter
                    ? widget.isFollowing
                          ? 'Following current location'
                          : 'Recenter on current location'
                    : 'Waiting for current location',
                child: FloatingActionButton(
                  key: const ValueKey('recenter-button'),
                  heroTag: 'recenter-button',
                  onPressed: widget.canRecenter ? widget.onRecenter : null,
                  tooltip: 'Recenter on current location',
                  child: Icon(
                    widget.isFollowing
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
            NavigationInfoSheet(
              controller: _sheetController,
              status: status,
              destination: destination,
              routeRequestState: routeRequestState,
              selectedRoute: session.selectedRoute,
              routeAlternatives: session.routeAlternatives,
              issue: issue,
              onSelectRoute: ref
                  .read(navigationSessionProvider.notifier)
                  .selectRoute,
              onRetryRoute: () => unawaited(
                ref
                    .read(routeRequestControllerProvider.notifier)
                    .requestRoute(),
              ),
            ),
          ],
        );
      },
    );
  }
}
