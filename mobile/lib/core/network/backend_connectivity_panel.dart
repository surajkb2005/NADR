import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';
import 'package:nadr_mobile/core/network/nadr_rest_client.dart';

/// Debug-build-only diagnostic surface; it never blocks or replaces the map.
class BackendConnectivityPanel extends ConsumerStatefulWidget {
  const BackendConnectivityPanel({super.key});

  @override
  ConsumerState<BackendConnectivityPanel> createState() =>
      _BackendConnectivityPanelState();
}

class _BackendConnectivityPanelState
    extends ConsumerState<BackendConnectivityPanel> {
  Future<BackendConnectivityResult>? _result;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _retry();
  }

  void _retry() {
    _cancelToken?.cancel();
    final token = CancelToken();
    _cancelToken = token;
    setState(() {
      _result = _check(token);
    });
  }

  Future<BackendConnectivityResult> _check(CancelToken token) async {
    if (ref.read(appEnvironmentProvider).apiBaseUri == null) {
      return BackendConnectivityResult(
        state: BackendConnectivityState.unconfigured,
        message: 'NADR_API_BASE_URL is not configured.',
        checkedAt: DateTime.now(),
      );
    }
    try {
      final client = await ref.read(nadrRestClientProvider.future);
      return await client.checkConnectivity(cancelToken: token);
    } on NadrNetworkException catch (error) {
      return BackendConnectivityResult(
        state: error.kind == NadrNetworkErrorKind.unconfigured
            ? BackendConnectivityState.unconfigured
            : BackendConnectivityState.backendError,
        message: error.message,
        checkedAt: DateTime.now(),
      );
    } on FormatException {
      return BackendConnectivityResult(
        state: BackendConnectivityState.backendError,
        message: 'Backend base URL is invalid.',
        checkedAt: DateTime.now(),
      );
    } on Object {
      return BackendConnectivityResult(
        state: BackendConnectivityState.backendError,
        message: 'Cannot initialize backend connectivity check.',
        checkedAt: DateTime.now(),
      );
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(appEnvironmentProvider).apiBaseUri;
    final visibleUrl = configured == null
        ? 'Not configured'
        : configured
              .replace(userInfo: '', query: null, fragment: null)
              .toString();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backend diagnostics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Base URL: $visibleUrl',
              key: const ValueKey('backend-base-url'),
            ),
            const SizedBox(height: 12),
            FutureBuilder<BackendConnectivityResult>(
              future: _result,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Text(
                    'Checking backend…',
                    key: ValueKey('backend-status'),
                  );
                }
                final result = snapshot.data!;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status: ${result.state.name}',
                      key: const ValueKey('backend-status'),
                    ),
                    Text(
                      result.message,
                      key: const ValueKey('backend-message'),
                    ),
                    Text('Last check: ${result.checkedAt.toLocal()}'),
                    if (result.health != null)
                      Text(
                        'Services: ${result.health!.services.entries.map((entry) => '${entry.key}=${entry.value}').join(', ')}',
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('backend-retry'),
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Check again'),
            ),
          ],
        ),
      ),
    );
  }
}
