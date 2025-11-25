// lib/data/services/dio_client.dart

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:doppy/data/services/base_api_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_service.dart';
import 'package:flutter/material.dart';

/// 토큰 갱신을 자동으로 처리하는 Dio 클라이언트
class DioClient {
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;
  DioClient._internal() {
    _setupInterceptors();
  }

  static const String baseUrl = BaseApiService.baseUrl;
  final AuthService _authService = AuthService();

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
    ),
  );

  Dio get dio => _dio;

  // ===== Refresh coordination =====
  Future<bool>? _refreshFuture; // 동시 401 발생 시 리프레시 1회만 수행
  static const int _maxRefreshRetries = 2;
  static const Duration _retry1Delay = Duration(milliseconds: 300);
  static const Duration _retry2Delay = Duration(milliseconds: 800);

  void _setupInterceptors() {
    // 요청 인터셉터: 모든 요청에 토큰 추가
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 요청 전 토큰 검증/갱신
          await _authService.validateAndRefreshToken();

          final token = await _authService.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          debugPrint('[DioClient] ${options.method} ${options.path}');
          handler.next(options);
        },

        onError: (error, handler) async {
          // 401(또는 만료 시그널) → 토큰 리프레시 시도 후 재시도
          final bool isExpired =
              error.response?.statusCode == 401 ||
              (error.response?.statusCode == 500 &&
                  error.response?.data?.toString().contains(
                        'ExpiredJwtException',
                      ) ==
                      true);

          if (!isExpired) {
            handler.next(error);
            return;
          }

          // 이미 한번 재시도한 요청은 무한 루프 방지를 위해 그대로 실패 처리
          final alreadyRetried =
              (error.requestOptions.extra['__retried'] as bool?) == true;
          if (alreadyRetried) {
            handler.next(error);
            return;
          }

          try {
            debugPrint(
              '[DioClient] Token expired, attempting refresh (coordinated) ...',
            );

            _refreshFuture ??= _refreshTokenWithRetry();
            final refreshed = await _refreshFuture!;
            _refreshFuture = null;

            if (!refreshed) {
              // 리프레시 실패: 자동 로그아웃하지 않고 401 그대로 전달
              // (상위에서 UX적으로 로그인 유도 처리)
              handler.next(error);
              return;
            }

            debugPrint(
              '[DioClient] Token refreshed, retrying original request',
            );
            final newToken = await _authService.getToken();
            if (newToken != null && newToken.isNotEmpty) {
              error.requestOptions.headers['Authorization'] =
                  'Bearer $newToken';
            }

            final RequestOptions requestOptions = error.requestOptions;
            requestOptions.extra['__retried'] = true;
            final response = await _dio.fetch(requestOptions);
            handler.resolve(response);
            return;
          } catch (e) {
            debugPrint('[DioClient] Refresh coordination failed: $e');
            handler.next(error);
            return;
          }
        },
      ),
    );
  }

  /// 토큰 갱신 (DioClient에서만 처리)
  Future<bool> _refreshTokenWithRetry() async {
    final refreshToken = await _authService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      debugPrint('❌ [DioClient] 리프레시 토큰 없음');
      return false;
    }

    for (int attempt = 0; attempt <= _maxRefreshRetries; attempt++) {
      if (attempt > 0) {
        final delay = attempt == 1 ? _retry1Delay : _retry2Delay;
        await Future.delayed(delay);
      }

      try {
        final url = Uri.parse('$baseUrl/api/auth/refresh');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        );

        if (response.statusCode == 200) {
          final responseData = jsonDecode(utf8.decode(response.bodyBytes));
          final newToken = responseData['token'];
          final newRefreshToken = responseData['refreshToken'];

          await _authService.saveToken(newToken);
          await _authService.saveRefreshToken(newRefreshToken);

          debugPrint('✅ [DioClient] 토큰 갱신 성공 (attempt=${attempt + 1})');
          return true;
        } else {
          debugPrint(
            '❌ [DioClient] 토큰 갱신 실패(status=${response.statusCode}) (attempt=${attempt + 1})',
          );
        }
      } catch (e) {
        debugPrint('❌ [DioClient] 토큰 갱신 오류 (attempt=${attempt + 1}): $e');
      }
    }

    // 재시도 실패 → 자동 로그아웃하지 않음 (상위에서 UX 처리)
    return false;
  }
}
