// lib/data/services/dio_client.dart

import 'package:dio/dio.dart';
import 'package:doppy/utils/error_handler.dart';
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

  static const String baseUrl = "http://13.125.227.178:5000";
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
              final refreshed = await _refreshToken();
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

  /// 토큰 갱신 (DioClient에서만 처리)
  Future<bool> _refreshToken() async {
    final refreshToken = await _authService.getRefreshToken();
    if (refreshToken == null) {
      print('❌ [DioClient] 리프레시 토큰이 없습니다');
      return false;
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

        // AuthService를 통해 새로운 토큰들 저장
        await _authService.saveToken(newToken);
        await _authService.saveRefreshToken(newRefreshToken);

        print('✅ [DioClient] 토큰 갱신 성공');
        return true;
      } else {
        print('❌ [DioClient] 토큰 갱신 실패: ${response.statusCode}');
        print('❌ [DioClient] 응답 내용: ${response.body}');
        // 네트워크/서버 이슈 등으로 실패 시에는 여기서 로그아웃하지 않고 false만 반환
        return false;
      }
    } catch (e) {
      print('❌ [DioClient] 토큰 갱신 오류: $e');
      // 네트워크 오류 등 일시적 실패도 false만 반환
      return false;
    }
  }

  /// 토큰 갱신 실패 시 로그인 화면으로 이동
  void _handleTokenRefreshFailure() {
    print('❌ [DioClient] 토큰 갱신 실패 - 로그인 화면으로 이동');
    final context = navigatorKey.currentContext;
    if (context != null) {
      // 모든 화면을 pop하고 로그인 화면으로 이동
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      ErrorHandler.showError(context, '마지막 접속 후 30일이 지나 재로그인이 필요해요');
    }
  }
}
