// lib/data/services/dio_client.dart

import 'package:dio/dio.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import '../../main.dart';

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

          print('[DioClient] ${options.method} ${options.path}');
          handler.next(options);
        },

        onError: (error, handler) async {
          // 401 에러 시 토큰 갱신 후 재시도
          if (error.response?.statusCode == 401 ||
              (error.response?.statusCode == 500 &&
                  error.response?.data?.toString().contains(
                        'ExpiredJwtException',
                      ) ==
                      true)) {
            print('[DioClient] Token expired, attempting refresh...');

            try {
              final refreshed = await _refreshToken();
              if (refreshed) {
                print('[DioClient] Token refreshed, retrying request...');

                // 새로운 토큰으로 원본 요청 재시도
                final newToken = await _authService.getToken();
                if (newToken != null && newToken.isNotEmpty) {
                  error.requestOptions.headers['Authorization'] =
                      'Bearer $newToken';
                }

                final response = await _dio.fetch(error.requestOptions);
                handler.resolve(response);
                return;
              } else {
                // 토큰 갱신 실패 시 로그인 화면으로 이동
                _handleTokenRefreshFailure();
              }
            } catch (e) {
              print('[DioClient] Token refresh failed: $e');
              _handleTokenRefreshFailure();
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
        await _authService.logout();
        return false;
      }
    } catch (e) {
      print('❌ [DioClient] 토큰 갱신 오류: $e');
      await _authService.logout();
      return false;
    }
  }

  /// 토큰 갱신 실패 시 로그인 화면으로 이동
  void _handleTokenRefreshFailure() {
    final context = navigatorKey.currentContext;
    if (context != null) {
      // 모든 화면을 pop하고 로그인 화면으로 이동
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      ErrorHandler.showError(context, '마지막 접속 후 30일이 지나 재로그인이 필요해요');
    }
  }
}
