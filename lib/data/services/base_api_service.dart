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

  static const String baseUrl = "https://api.doppy.app";
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
  DateTime? _lastRefreshTime; // 🎯 마지막 갱신 시간 (중복 갱신 방지)

  /// JWT 만료 시간 추출 유틸리티
  /// [token] - JWT 토큰 문자열
  /// 반환: 만료 시간 (밀리초), 실패 시 null
  int? _getTokenExpiration(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      // JWT payload 디코딩
      final payload = parts[1];
      // Base64 패딩 추가
      String normalized = base64Url.normalize(payload);
      final decoded = base64Url.decode(normalized);
      final json = jsonDecode(utf8.decode(decoded));
      final exp = json['exp'] as int?;

      // 초를 밀리초로 변환
      return exp != null ? exp * 1000 : null;
    } catch (e) {
      print('[BaseApiService] 토큰 만료 시간 추출 실패: $e');
      return null;
    }
  }

  void _setupInterceptors() {
    // 요청 인터셉터: 모든 요청에 토큰 추가
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 🎯 인증/리프레시 엔드포인트는 토큰 체크 건너뛰기
          final path = options.path;
          final isAuthEndpoint =
              path.contains('/api/auth/login') ||
              path.contains('/api/auth/refresh') ||
              path.contains('/api/auth/register');

          // 🎯 클라이언트 우선 방식: JWT 만료 시간 확인 및 미리 리프레시
          if (!isAuthEndpoint) {
            final token = await _authService.getToken();
            if (token != null && token.isNotEmpty) {
              // JWT 만료 시간 추출
              final expirationTime = _getTokenExpiration(token);
              final now = DateTime.now().millisecondsSinceEpoch;

              // 🎯 만료 시간이 유효하고, 실제로 만료되었거나 곧 만료될 때만 갱신
              if (expirationTime != null && expirationTime > now) {
                // 🎯 프로덕션: 5분 전에 리프레시
                final bufferTime = 5 * 60 * 1000; // 5분 버퍼
                final timeUntilExpiry = expirationTime - now;

                // 🎯 마지막 갱신 후 1분 이내면 다시 갱신하지 않음 (중복 갱신 방지)
                final shouldSkipRefresh =
                    _lastRefreshTime != null &&
                    DateTime.now().difference(_lastRefreshTime!).inSeconds < 60;

                // 만료 임박 시에만 미리 리프레시 (중복 갱신 방지)
                if (timeUntilExpiry < bufferTime && !shouldSkipRefresh) {
                  final remainingSeconds = timeUntilExpiry / 1000;
                  print(
                    '[BaseApiService] 토큰 만료 임박 (${remainingSeconds.toStringAsFixed(1)}초 남음) - 미리 리프레시',
                  );

                  // 리프레시 중이 아니면 리프레시 시도
                  if (!_isRefreshing) {
                    _isRefreshing = true;
                    _refreshCompleter = Completer<bool>();
                    final refreshed = await _refreshTokenWithRetry();
                    _isRefreshing = false;
                    _refreshCompleter?.complete(refreshed);
                    _refreshCompleter = null;

                    if (refreshed) {
                      _lastRefreshTime = DateTime.now(); // 🎯 갱신 시간 저장
                      final newToken = await _authService.getToken();
                      if (newToken != null && newToken.isNotEmpty) {
                        options.headers['Authorization'] = 'Bearer $newToken';
                        print('[BaseApiService] ✅ 토큰 갱신 완료');
                      }
                    } else {
                      print('[BaseApiService] ⚠️ 토큰 갱신 실패 (기존 토큰 사용)');
                      options.headers['Authorization'] = 'Bearer $token';
                    }
                  } else {
                    // 이미 리프레시 중이면 완료까지 대기
                    if (_refreshCompleter != null) {
                      final ok = await _refreshCompleter!.future;
                      if (ok) {
                        _lastRefreshTime = DateTime.now(); // 🎯 갱신 시간 저장
                        final newToken = await _authService.getToken();
                        if (newToken != null && newToken.isNotEmpty) {
                          options.headers['Authorization'] = 'Bearer $newToken';
                        }
                      } else {
                        options.headers['Authorization'] = 'Bearer $token';
                      }
                    } else {
                      options.headers['Authorization'] = 'Bearer $token';
                    }
                  }
                } else {
                  // 아직 유효하면 기존 토큰 사용
                  options.headers['Authorization'] = 'Bearer $token';
                }
              } else {
                // 만료 시간 추출 실패 또는 이미 만료된 경우 기존 토큰 사용 (401 시 갱신)
                options.headers['Authorization'] = 'Bearer $token';
              }
            }
          }

          print('[BaseApiService] ${options.method} ${options.path}');
          handler.next(options);
        },

        onResponse: (response, handler) async {
          // 🎯 백업 방식: 서버가 자동으로 갱신한 경우 헤더에서 새 토큰 확인
          // 모든 헤더 키 확인 (대소문자 무관)
          final headers = response.headers.map;
          String? newAccessToken;
          String? newRefreshToken;

          for (final entry in headers.entries) {
            final key = entry.key.toLowerCase();
            if (key == 'x-new-access-token') {
              newAccessToken = entry.value.first;
            } else if (key == 'x-new-refresh-token') {
              newRefreshToken = entry.value.first;
            }
          }

          if (newAccessToken != null &&
              newRefreshToken != null &&
              newAccessToken.isNotEmpty &&
              newRefreshToken.isNotEmpty) {
            await _authService.saveToken(newAccessToken);
            await _authService.saveRefreshToken(newRefreshToken);
            print('[BaseApiService] ✅ 서버 자동 토큰 갱신 감지');
          }

          handler.next(response);
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
                  // 🎯 http 기반 재시도 (인터셉터 우회)
                  final response = await _retryRequestWithHttp(
                    error.requestOptions,
                  );
                  if (response != null) {
                    handler.resolve(response);
                    return;
                  } else {
                    handler.next(error);
                    return;
                  }
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
                // 🎯 http 기반 재시도 (인터셉터 우회)
                final response = await _retryRequestWithHttp(
                  error.requestOptions,
                );
                if (response != null) {
                  handler.resolve(response);
                  return;
                } else {
                  handler.next(error);
                  return;
                }
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

          // 🎯 API 응답 구조 확인 (data 안에 있을 수도 있고, 직접 있을 수도 있음)
          final data = responseData['data'] ?? responseData;
          final newToken = data['token'] ?? data['accessToken'];
          final newRefreshToken = data['refreshToken'];

          if (newToken != null && newRefreshToken != null) {
            await _authService.saveToken(newToken);
            await _authService.saveRefreshToken(newRefreshToken);
            print('✅ [BaseApiService] 토큰 갱신 성공 (attempt=${attempt + 1})');
            return true;
          } else {
            print(
              '❌ [BaseApiService] 토큰 갱신 실패: 응답에 토큰이 없습니다 (attempt=${attempt + 1})',
            );
          }
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

  /// http 기반 재시도 (인터셉터 우회)
  Future<Response?> _retryRequestWithHttp(RequestOptions requestOptions) async {
    try {
      final newToken = await _authService.getToken();
      if (newToken == null || newToken.isEmpty) {
        print('[BaseApiService] 재시도 실패: 토큰 없음');
        return null;
      }

      // URL 구성
      final uri = Uri.parse('$baseUrl${requestOptions.path}');
      final uriWithQuery =
          requestOptions.queryParameters.isNotEmpty
              ? uri.replace(queryParameters: requestOptions.queryParameters)
              : uri;

      // 헤더 구성
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Bearer $newToken',
      };

      // 기존 헤더 추가 (Dio Headers는 Map<String, List<String>> 형태)
      requestOptions.headers.forEach((key, values) {
        if (values != null) {
          if (values is List && values.isNotEmpty) {
            headers[key] = values.first.toString();
          } else if (values is String) {
            headers[key] = values;
          } else {
            headers[key] = values.toString();
          }
        }
      });

      // http 요청
      http.Response httpResponse;
      if (requestOptions.method == 'GET') {
        httpResponse = await http.get(uriWithQuery, headers: headers);
      } else if (requestOptions.method == 'POST') {
        final body =
            requestOptions.data != null
                ? jsonEncode(requestOptions.data)
                : null;
        httpResponse = await http.post(
          uriWithQuery,
          headers: headers,
          body: body,
        );
      } else if (requestOptions.method == 'PUT') {
        final body =
            requestOptions.data != null
                ? jsonEncode(requestOptions.data)
                : null;
        httpResponse = await http.put(
          uriWithQuery,
          headers: headers,
          body: body,
        );
      } else if (requestOptions.method == 'DELETE') {
        httpResponse = await http.delete(uriWithQuery, headers: headers);
      } else if (requestOptions.method == 'PATCH') {
        final body =
            requestOptions.data != null
                ? jsonEncode(requestOptions.data)
                : null;
        httpResponse = await http.patch(
          uriWithQuery,
          headers: headers,
          body: body,
        );
      } else {
        print('[BaseApiService] 지원하지 않는 HTTP 메서드: ${requestOptions.method}');
        return null;
      }

      // Dio Response로 변환
      final responseData =
          httpResponse.bodyBytes.isNotEmpty
              ? jsonDecode(utf8.decode(httpResponse.bodyBytes))
              : null;

      final dioResponse = Response(
        data: responseData,
        statusCode: httpResponse.statusCode,
        statusMessage: httpResponse.reasonPhrase,
        requestOptions: requestOptions,
        headers: Headers.fromMap(
          httpResponse.headers.map((k, v) => MapEntry(k, [v])),
        ),
      );

      return dioResponse;
    } catch (e) {
      print('[BaseApiService] http 재시도 실패: $e');
      return null;
    }
  }

  /// 토큰 갱신 실패 시 다이얼로그로 재로그인 유도 (인스타그램식)
  void _handleTokenRefreshFailure() {
    print('❌ [DioClient] 토큰 갱신 실패 - 세션 만료 다이얼로그');
    final context = navigatorKey.currentContext;
    if (context != null) {
      if (_sessionDialogVisible) return;
      _sessionDialogVisible = true;
      final localization = AppLocalizations.of(context);
      DialogUtils.showConfirmDialog(
        context,
        title: localization.translate('session_expired'),
        message: localization.translate('session_expired_message'),
        confirmText: localization.translate('login'),
        cancelText: localization.translate('later'),
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
