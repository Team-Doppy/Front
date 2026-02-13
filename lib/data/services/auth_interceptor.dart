import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// 토큰 첨부 + 401 시 리프레시 후 재시도.
/// BaseApiService, UploadInit 등 모든 Dio에 공통으로 추가.
class AuthInterceptor {
  AuthInterceptor._();

  static Future<bool>? _refreshFuture;
  static const _skipPaths = ['/api/auth/login', '/api/auth/refresh'];

  static InterceptorsWrapper create(Dio dio, {String? debugLabel}) {
    final auth = AuthService();
    final label = debugLabel ?? 'Dio';

    return InterceptorsWrapper(
      onRequest: (opt, h) async {
        final path = opt.path;
        final skipAuth = _skipPaths.any((p) => path.contains(p));
        if (!skipAuth) {
          await auth.validateAndRefreshToken();
          final token = await auth.getToken();
          if (token != null && token.isNotEmpty) {
            opt.headers['Authorization'] = 'Bearer $token';
          } else if (kDebugMode) {
            debugPrint('[$label] no token for ${opt.method} $path');
          }
        }
        if (kDebugMode) {
          debugPrint('[$label] ${opt.method} $path');
        }
        h.next(opt);
      },
      onError: (error, h) async {
        final isExpired = error.response?.statusCode == 401 ||
            (error.response?.statusCode == 500 &&
                error.response?.data?.toString().contains('ExpiredJwtException') == true);
        if (!isExpired) {
          h.next(error);
          return;
        }

        final alreadyRetried = (error.requestOptions.extra['__retried'] as bool?) == true;
        if (alreadyRetried) {
          h.next(error);
          return;
        }

        try {
          if (kDebugMode) debugPrint('[$label] 401/Expired, attempting token refresh...');
          _refreshFuture ??= auth.tryRefreshToken();
          final refreshed = await _refreshFuture!;
          _refreshFuture = null;

          if (!refreshed) {
            h.next(error);
            return;
          }

          final newToken = await auth.getToken();
          if (newToken != null && newToken.isNotEmpty) {
            error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          }
          error.requestOptions.extra['__retried'] = true;
          final response = await dio.fetch(error.requestOptions);
          h.resolve(response);
        } catch (e) {
          if (kDebugMode) debugPrint('[$label] Refresh failed: $e');
          _refreshFuture = null;
          h.next(error);
        }
      },
    );
  }
}
