// lib/data/services/dio_client.dart

import 'package:dio/dio.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import '../../main.dart';
import 'dart:async'; // Added for Completer

/// 토큰 갱신을 자동으로 처리하는 Dio 클라이언트
class BaseApiService {
  static final BaseApiService _instance = BaseApiService._internal();
  factory BaseApiService() => _instance;
  BaseApiService._internal() {
    _setupInterceptors();
  }

  static const String baseUrl = "https://www.nbillion.co.kr";
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
  bool _isRefreshing = false;
  Completer<bool>? _refreshCompleter;
  static const int _maxRefreshRetries = 2;
  static const Duration _retry1Delay = Duration(milliseconds: 300);
  static const Duration _retry2Delay = Duration(milliseconds: 800);
  static bool _sessionDialogVisible = false;

  void _setupInterceptors() {
    // 요청 인터셉터: 모든 요청에 토큰 추가
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 요청 시에는 토큰만 주입 (검증/갱신은 onError에서 단일 비행 처리)
          final token = await _authService.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          print('[DioClient] ${options.method} ${options.path}');
          handler.next(options);
        },

        onError: (error, handler) async {
          // 인증/리프레시 엔드포인트에는 개입하지 않음
          final path = error.requestOptions.path;
          final isAuthEndpoint =
              path.contains('/api/auth/login') ||
              path.contains('/api/auth/refresh');

          // 401 또는 만료 표시가 있는 500만 리프레시 시도
          final status = error.response?.statusCode;
          final bodyStr = error.response?.data?.toString() ?? '';
          final shouldRefresh =
              (status == 401) ||
              (status == 500 && bodyStr.contains('ExpiredJwtException'));

          if (!isAuthEndpoint && shouldRefresh) {
            print('[DioClient] Token expired, attempting refresh...');

            try {
              // 이미 리프레시 중이면 완료까지 대기
              if (_isRefreshing && _refreshCompleter != null) {
                final ok = await _refreshCompleter!.future;
                if (ok) {
                  final newToken = await _authService.getToken();
                  if (newToken != null && newToken.isNotEmpty) {
                    error.requestOptions.headers['Authorization'] =
                        'Bearer $newToken';
                  }
                  final response = await _dio.fetch(error.requestOptions);
                  handler.resolve(response);
                  return;
                } else {
                  _handleTokenRefreshFailure();
                  return;
                }
              }

              // 최초 1회만 리프레시 시도 (단일 비행)
              _isRefreshing = true;
              _refreshCompleter = Completer<bool>();
              final refreshed = await _refreshTokenWithRetry();
              _isRefreshing = false;
              _refreshCompleter?.complete(refreshed);
              _refreshCompleter = null;

              if (refreshed) {
                print('[DioClient] Token refreshed, retrying request...');
                final newToken = await _authService.getToken();
                if (newToken != null && newToken.isNotEmpty) {
                  error.requestOptions.headers['Authorization'] =
                      'Bearer $newToken';
                }
                final response = await _dio.fetch(error.requestOptions);
                handler.resolve(response);
                return;
              } else {
                _handleTokenRefreshFailure();
                return;
              }
            } catch (e) {
              print('[DioClient] Token refresh failed: $e');
              _isRefreshing = false;
              _refreshCompleter?.complete(false);
              _refreshCompleter = null;
              _handleTokenRefreshFailure();
              return;
            }
          }

          handler.next(error);
        },
      ),
    );
  }

  /// 토큰 갱신 (재시도 포함)
  Future<bool> _refreshTokenWithRetry() async {
    final refreshToken = await _authService.getRefreshToken();
    if (refreshToken == null) {
      print('❌ [DioClient] 리프레시 토큰이 없습니다');
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

          print('✅ [DioClient] 토큰 갱신 성공 (attempt=${attempt + 1})');
          return true;
        } else {
          print(
            '❌ [DioClient] 토큰 갱신 실패: ${response.statusCode} (attempt=${attempt + 1})',
          );
        }
      } catch (e) {
        print('❌ [DioClient] 토큰 갱신 오류 (attempt=${attempt + 1}): $e');
      }
    }

    return false;
  }

  /// 토큰 갱신 실패 시 다이얼로그로 재로그인 유도 (인스타그램식)
  void _handleTokenRefreshFailure() {
    print('❌ [DioClient] 토큰 갱신 실패 - 세션 만료 다이얼로그');
    final context = navigatorKey.currentContext;
    if (context != null) {
      if (_sessionDialogVisible) return;
      _sessionDialogVisible = true;
      DialogUtils.showConfirmDialog(
        context,
        title: '세션 만료',
        message: '로그인 세션이 만료되었습니다. 다시 로그인하시겠어요?',
        confirmText: '로그인',
        cancelText: '나중에',
        isDestructive: false,
      ).then((goLogin) {
        _sessionDialogVisible = false;
        if (goLogin == true) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (route) => false);
        } else {
          // 머무름: 필요시 스낵바 안내
          ErrorHandler.showInfo(context, context.tr('some_features_limited'));
        }
      });
    }
  }
}
