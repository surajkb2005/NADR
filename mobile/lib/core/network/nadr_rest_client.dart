import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nadr_mobile/app/bootstrap/environment.dart';
import 'package:nadr_mobile/core/network/api_models.dart';
import 'package:path_provider/path_provider.dart';

enum NadrNetworkErrorKind {
  unconfigured,
  connectionUnavailable,
  timeout,
  invalidResponse,
  unauthorized,
  validation,
  rateLimited,
  serverFailure,
  httpFailure,
  cancelled,
}

final class NadrNetworkException implements Exception {
  const NadrNetworkException(this.kind, this.message, {this.statusCode});
  final NadrNetworkErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

enum BackendConnectivityState {
  healthy,
  degraded,
  unreachable,
  timedOut,
  unconfigured,
  backendError,
}

final class BackendConnectivityResult {
  const BackendConnectivityResult({
    required this.state,
    required this.message,
    required this.checkedAt,
    this.root,
    this.health,
  });
  final BackendConnectivityState state;
  final String message;
  final DateTime checkedAt;
  final ApiRootResponse? root;
  final ApiHealthResponse? health;
}

/// One Dio instance owns all existing REST contracts and one cookie jar.
/// Endpoints are relative to either direct FastAPI `/` or Nginx `/api/`.
final class NadrRestClient {
  NadrRestClient({required Uri baseUri, required CookieJar cookieJar, Dio? dio})
    : baseUri = normalizeApiBaseUri(baseUri),
      _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: this.baseUri.toString(),
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.json,
      contentType: Headers.jsonContentType,
      headers: const {'Accept': Headers.jsonContentType},
    );
    _dio.interceptors.add(CookieManager(cookieJar));
  }

  final Uri baseUri;
  final Dio _dio;
  Dio get dio => _dio;

  String get displayBaseUrl => baseUri.toString();

  void dispose() => _dio.close(force: true);

  static Uri normalizeApiBaseUri(Uri uri) {
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'NADR_API_BASE_URL must be an HTTP(S) base URL without credentials, query, or fragment.',
      );
    }
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length >= 2 &&
        segments[segments.length - 1] == 'api' &&
        segments[segments.length - 2] == 'api') {
      throw const FormatException('NADR_API_BASE_URL must not repeat /api.');
    }
    return uri.replace(
      path: '/${segments.join('/')}${segments.isEmpty ? '' : '/'}',
    );
  }

  Future<ApiRootResponse> getRoot({CancelToken? cancelToken}) => _decode(
    _request('GET', '', cancelToken: cancelToken),
    ApiRootResponse.fromJson,
  );

  Future<ApiHealthResponse> getHealth({CancelToken? cancelToken}) => _decode(
    _request('GET', 'health', cancelToken: cancelToken),
    ApiHealthResponse.fromJson,
  );

  Future<ApiRouteResponse> calculateRoute({
    required List<double> start,
    required List<double> end,
    String mode = 'normal',
    CancelToken? cancelToken,
  }) => _decode(
    _request(
      'POST',
      'route',
      data: {'start': start, 'end': end, 'mode': mode},
      cancelToken: cancelToken,
    ),
    ApiRouteResponse.fromJson,
  );

  Future<ApiSpaceWeatherResponse> getCurrentSpaceWeather({
    required double latitude,
    required double longitude,
    CancelToken? cancelToken,
  }) => _decode(
    _request(
      'GET',
      'space-weather/current',
      queryParameters: {'latitude': latitude, 'longitude': longitude},
      cancelToken: cancelToken,
    ),
    ApiSpaceWeatherResponse.fromJson,
  );

  Future<ApiHeatmapResponse> getHeatmap({
    required List<double> bbox,
    double resolution = 0.05,
    CancelToken? cancelToken,
  }) => _decode(
    _request(
      'POST',
      'heatmap',
      data: {'bbox': bbox, 'resolution': resolution},
      cancelToken: cancelToken,
    ),
    ApiHeatmapResponse.fromJson,
  );

  Future<ApiMessageResponse> requestOtp(
    String email, {
    CancelToken? cancelToken,
  }) => _decode(
    _request(
      'POST',
      'auth/request-otp',
      data: {'email': email},
      cancelToken: cancelToken,
    ),
    ApiMessageResponse.fromJson,
  );

  Future<ApiLoginResponse> verifyOtp({
    required String email,
    required String otp,
    CancelToken? cancelToken,
  }) => _decode(
    _request(
      'POST',
      'auth/verify-otp',
      data: {'email': email, 'otp': otp},
      cancelToken: cancelToken,
    ),
    ApiLoginResponse.fromJson,
  );

  Future<ApiAuthStatusResponse> getAuthStatus({CancelToken? cancelToken}) =>
      _decode(
        _request('GET', 'auth/status', cancelToken: cancelToken),
        ApiAuthStatusResponse.fromJson,
      );

  Future<ApiMessageResponse> logout({CancelToken? cancelToken}) => _decode(
    _request('POST', 'auth/logout', cancelToken: cancelToken),
    ApiMessageResponse.fromJson,
  );

  Future<BackendConnectivityResult> checkConnectivity({
    CancelToken? cancelToken,
  }) async {
    final checkedAt = DateTime.now();
    try {
      final root = await getRoot(cancelToken: cancelToken);
      try {
        final health = await getHealth(cancelToken: cancelToken);
        final healthy =
            root.status == 'operational' &&
            health.status == 'healthy' &&
            health.services.values.every((service) => service);
        return BackendConnectivityResult(
          state: healthy
              ? BackendConnectivityState.healthy
              : BackendConnectivityState.degraded,
          message: healthy
              ? 'Backend reachable and healthy.'
              : 'Backend reachable, but one or more services are degraded.',
          checkedAt: checkedAt,
          root: root,
          health: health,
        );
      } on NadrNetworkException catch (error) {
        if (error.statusCode == 503) {
          return BackendConnectivityResult(
            state: BackendConnectivityState.degraded,
            message: 'Backend reachable; health endpoint reports service unavailable.',
            checkedAt: checkedAt,
            root: root,
          );
        }
        rethrow;
      }
    } on NadrNetworkException catch (error) {
      return BackendConnectivityResult(
        state: switch (error.kind) {
          NadrNetworkErrorKind.unconfigured =>
            BackendConnectivityState.unconfigured,
          NadrNetworkErrorKind.connectionUnavailable =>
            BackendConnectivityState.unreachable,
          NadrNetworkErrorKind.timeout => BackendConnectivityState.timedOut,
          _ => BackendConnectivityState.backendError,
        },
        message: error.message,
        checkedAt: checkedAt,
      );
    }
  }

  Future<Object?> _request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        options: Options(method: method),
      );
      return response.data;
    } on DioException catch (error) {
      throw _mapDioError(error);
    }
  }

  static Future<T> _decode<T>(
    Future<Object?> request,
    T Function(Object?) parser,
  ) async {
    final data = await request;
    try {
      return parser(data);
    } on ApiDecodingException catch (error) {
      throw NadrNetworkException(
        NadrNetworkErrorKind.invalidResponse,
        error.toString(),
      );
    }
  }

  static NadrNetworkException _mapDioError(DioException error) {
    if (error.error is FormatException) {
      return const NadrNetworkException(
        NadrNetworkErrorKind.invalidResponse,
        'Backend returned invalid JSON.',
      );
    }
    final status = error.response?.statusCode;
    if (status != null) {
      final detail = _safeBackendDetail(error.response?.data);
      if (status == 401) {
        return NadrNetworkException(
          NadrNetworkErrorKind.unauthorized,
          detail ?? 'Authentication required or session expired.',
          statusCode: status,
        );
      }
      if (status == 422) {
        return NadrNetworkException(
          NadrNetworkErrorKind.validation,
          detail ?? 'Backend rejected the request fields.',
          statusCode: status,
        );
      }
      if (status == 429) {
        return NadrNetworkException(
          NadrNetworkErrorKind.rateLimited,
          detail ?? 'Too many requests. Try again later.',
          statusCode: status,
        );
      }
      if (status >= 500) {
        return NadrNetworkException(
          NadrNetworkErrorKind.serverFailure,
          'Backend returned HTTP $status.',
          statusCode: status,
        );
      }
      return NadrNetworkException(
        NadrNetworkErrorKind.httpFailure,
        'Backend returned HTTP $status.',
        statusCode: status,
      );
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => const NadrNetworkException(
        NadrNetworkErrorKind.timeout,
        'Backend request timed out.',
      ),
      DioExceptionType.cancel => const NadrNetworkException(
        NadrNetworkErrorKind.cancelled,
        'Backend request cancelled.',
      ),
      DioExceptionType.badResponse => const NadrNetworkException(
        NadrNetworkErrorKind.invalidResponse,
        'Invalid backend response.',
      ),
      _ => const NadrNetworkException(
        NadrNetworkErrorKind.connectionUnavailable,
        'Cannot reach the backend. Check its URL and network connection.',
      ),
    };
  }

  static String? _safeBackendDetail(Object? data) {
    if (data is! Map || data['detail'] is! String) return null;
    final detail = data['detail'] as String;
    // These are the current backend's fixed public messages. Arbitrary
    // exception text and validation payloads can contain email/OTP input.
    return const {
          'Invalid or expired OTP.',
          'Not authenticated',
          'Invalid token',
          'Session expired',
          'Too many OTP requests. Please wait a minute and try again.',
        }.contains(detail)
        ? detail
        : null;
  }
}

final nadrRestClientProvider = FutureProvider<NadrRestClient>((ref) async {
  final baseUri = ref.watch(appEnvironmentProvider).apiBaseUri;
  if (baseUri == null) {
    throw const NadrNetworkException(
      NadrNetworkErrorKind.unconfigured,
      'NADR_API_BASE_URL is not configured.',
    );
  }
  final support = await getApplicationSupportDirectory();
  final client = NadrRestClient(
    baseUri: baseUri,
    cookieJar: PersistCookieJar(
      storage: FileStorage('${support.path}/nadr_session_cookies'),
    ),
  );
  ref.onDispose(client.dispose);
  return client;
});
