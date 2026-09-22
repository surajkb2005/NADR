import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nadr_mobile/features/map/domain/map_camera.dart';
import 'package:nadr_mobile/features/map/domain/nadr_map_controller.dart';
import 'package:nadr_mobile/features/map/presentation/widgets/maplibre_map_surface.dart';
import 'package:nadr_mobile/shared/widgets/app_error_message.dart';
import 'package:nadr_mobile/shared/widgets/app_loading_overlay.dart';

enum _MapLoadStatus { loading, ready, error }

class InteractiveMapLayer extends StatefulWidget {
  const InteractiveMapLayer({
    required this.styleUri,
    required this.initialCamera,
    required this.surfaceBuilder,
    required this.onControllerChanged,
    this.onStyleLoaded,
    this.onUserGesture,
    this.configurationError,
    this.styleLoadTimeout = const Duration(seconds: 20),
    super.key,
  });

  final Uri? styleUri;
  final String? configurationError;
  final MapCameraState initialCamera;
  final MapSurfaceBuilder surfaceBuilder;
  final ValueChanged<NadrMapController?> onControllerChanged;
  final VoidCallback? onStyleLoaded;
  final VoidCallback? onUserGesture;
  final Duration styleLoadTimeout;

  @override
  State<InteractiveMapLayer> createState() => _InteractiveMapLayerState();
}

class _InteractiveMapLayerState extends State<InteractiveMapLayer> {
  Timer? _loadTimer;
  late _MapLoadStatus _status;
  String? _errorMessage;
  int _loadAttempt = 0;

  bool get _hasUsableConfiguration =>
      widget.styleUri != null && widget.configurationError == null;

  @override
  void initState() {
    super.initState();
    _startLoadingIfConfigured();
  }

  @override
  void didUpdateWidget(covariant InteractiveMapLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.styleUri != oldWidget.styleUri ||
        widget.configurationError != oldWidget.configurationError) {
      _loadTimer?.cancel();
      _startLoadingIfConfigured();
    }
  }

  void _startLoadingIfConfigured() {
    if (!_hasUsableConfiguration) {
      _status = _MapLoadStatus.error;
      _errorMessage =
          widget.configurationError ??
          'Map unavailable: configure NADR_MAP_STYLE_URL to load the map.';
      return;
    }

    _status = _MapLoadStatus.loading;
    _errorMessage = null;
    _loadTimer = Timer(widget.styleLoadTimeout, () {
      _showError(
        'The map style could not be loaded. Check NADR_MAP_STYLE_URL and your network connection.',
      );
    });
  }

  void _handleControllerReady(NadrMapController controller) {
    if (!mounted) return;
    widget.onControllerChanged(controller);
  }

  void _handleStyleLoaded() {
    if (!mounted) return;
    _loadTimer?.cancel();
    setState(() {
      _status = _MapLoadStatus.ready;
      _errorMessage = null;
    });
    widget.onStyleLoaded?.call();
  }

  void _showError(String message) {
    if (!mounted) return;
    _loadTimer?.cancel();
    widget.onControllerChanged(null);
    setState(() {
      _status = _MapLoadStatus.error;
      _errorMessage = message;
    });
  }

  void _retry() {
    widget.onControllerChanged(null);
    setState(() {
      _loadAttempt += 1;
      _startLoadingIfConfigured();
    });
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasUsableConfiguration || _status == _MapLoadStatus.error) {
      return _MapErrorBackground(
        message: _errorMessage ?? 'The map is unavailable.',
        canRetry: _hasUsableConfiguration,
        onRetry: _retry,
      );
    }

    final callbacks = MapSurfaceCallbacks(
      onControllerReady: _handleControllerReady,
      onStyleLoaded: _handleStyleLoaded,
      onUserGesture: widget.onUserGesture ?? () {},
      onError: _showError,
    );

    Widget map;
    try {
      map = KeyedSubtree(
        key: ValueKey('map-load-attempt-$_loadAttempt'),
        child: widget.surfaceBuilder(
          MapSurfaceConfiguration(
            styleUri: widget.styleUri!,
            initialCamera: widget.initialCamera,
          ),
          callbacks,
        ),
      );
    } on Object catch (error) {
      return _MapErrorBackground(
        message: 'Map rendering could not be initialized: $error',
        canRetry: true,
        onRetry: _retry,
      );
    }

    return AppLoadingOverlay(
      isLoading: _status == _MapLoadStatus.loading,
      message: 'Loading map',
      child: map,
    );
  }
}

class _MapErrorBackground extends StatelessWidget {
  const _MapErrorBackground({
    required this.message,
    required this.canRetry,
    required this.onRetry,
  });

  final String message;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 104, 24, 160),
          child: Material(
            key: const ValueKey('map-configuration-error'),
            color: colors.surfaceContainerHigh,
            elevation: 2,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppErrorMessage(message: message),
                  if (canRetry) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry map'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
