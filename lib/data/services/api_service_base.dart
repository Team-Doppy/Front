// lib/data/services/api_service_base.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// 인증이 필요한 모든 API 서비스의 기반이 되는 클래스
class ApiServiceBase {
  static final String baseUrl = "http://13.125.227.178:5000";

  // AuthService는 static으로 만들어 어디서든 접근 가능하게 하거나,
  // get_it 같은 서비스 로케이터를 사용하는 것이 좋지만, 지금은 간단하게 인스턴스를 생성합니다.
  final AuthService _authService = AuthService();

  /// 모든 요청에 자동으로 인증 토큰을 포함하는 헤더를 생성합니다.
  Future<Map<String, String>> _getHeaders() async {
    final token = await _authService.getToken();
    if (token == null) {
      throw Exception('인증 토큰이 없습니다. 다시 로그인해주세요.');
    }
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  /// 응답을 처리하고 토큰 만료 시 자동 갱신을 시도합니다.
  Future<http.Response> _handleResponse(
    http.Response response,
    String endpoint, {
    Object? body,
    String method = 'GET',
  }) async {
    // 토큰 만료 (401) 또는 인증 실패 (403)인 경우
    if (response.statusCode == 401 || response.statusCode == 403) {
      print('[ApiServiceBase] 토큰 만료 감지, 자동 갱신 시도...');

      try {
        // 토큰 갱신 시도
        final refreshSuccess = await _authService.refreshToken();

        if (refreshSuccess) {
          print('[ApiServiceBase] 토큰 갱신 성공, 원본 요청 재시도...');

          // 새로운 토큰으로 원본 요청 재시도
          final newHeaders = await _getHeaders();
          final url = Uri.parse('$baseUrl$endpoint');

          // 원본 요청 타입에 따라 재시도
          switch (method.toUpperCase()) {
            case 'GET':
              return await http
                  .get(url, headers: newHeaders)
                  .timeout(const Duration(seconds: 10));
            case 'POST':
              return await http
                  .post(url, headers: newHeaders, body: jsonEncode(body))
                  .timeout(const Duration(seconds: 10));
            case 'PUT':
              return await http
                  .put(url, headers: newHeaders, body: jsonEncode(body))
                  .timeout(const Duration(seconds: 10));
            case 'DELETE':
              return await http
                  .delete(url, headers: newHeaders)
                  .timeout(const Duration(seconds: 10));
            default:
              throw Exception('지원하지 않는 HTTP 메서드: $method');
          }
        } else {
          print('[ApiServiceBase] 토큰 갱신 실패');
          throw Exception('인증 토큰 갱신에 실패했습니다. 다시 로그인해주세요.');
        }
      } catch (e) {
        print('[ApiServiceBase] 토큰 갱신 중 오류: $e');
        throw Exception('인증 토큰 갱신 중 오류가 발생했습니다. 다시 로그인해주세요.');
      }
    }

    // 일부 서버가 만료 토큰에 대해 500을 반환하는 경우에 대한 방어 로직
    if (response.statusCode == 500) {
      final bodyText = response.body;
      final maybeExpired =
          bodyText.contains('ExpiredJwtException') ||
          bodyText.contains('JWT expired');
      if (maybeExpired) {
        print('[ApiServiceBase] 500 내 ExpiredJwtException 감지 → 토큰 갱신 시도 후 재요청');
        try {
          final refreshed = await _authService.refreshToken();
          if (refreshed) {
            final newHeaders = await _getHeaders();
            final url = Uri.parse('$baseUrl$endpoint');
            switch (method.toUpperCase()) {
              case 'GET':
                return await http
                    .get(url, headers: newHeaders)
                    .timeout(const Duration(seconds: 10));
              case 'POST':
                return await http
                    .post(url, headers: newHeaders, body: jsonEncode(body))
                    .timeout(const Duration(seconds: 10));
              case 'PUT':
                return await http
                    .put(url, headers: newHeaders, body: jsonEncode(body))
                    .timeout(const Duration(seconds: 10));
              case 'DELETE':
                return await http
                    .delete(url, headers: newHeaders)
                    .timeout(const Duration(seconds: 10));
              default:
                throw Exception('지원하지 않는 HTTP 메서드: $method');
            }
          } else {
            throw Exception('토큰 갱신 실패');
          }
        } catch (e) {
          print('[ApiServiceBase] 500 처리 중 토큰 갱신 오류: $e');
          rethrow;
        }
      }
    }

    // 정상 응답이거나 토큰 만료가 아닌 경우
    return response;
  }

  /// GET 요청을 처리합니다.
  Future<http.Response> get(String endpoint) async {
    // 요청 전 선제 토큰 검증/갱신
    await _authService.validateAndRefreshToken();
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();
    final response = await http
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 10));

    return await _handleResponse(response, endpoint, method: 'GET');
  }

  /// POST 요청을 처리합니다.
  Future<http.Response> post(String endpoint, {Object? body}) async {
    // 요청 전 선제 토큰 검증/갱신
    await _authService.validateAndRefreshToken();
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();
    final response = await http
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));

    return await _handleResponse(
      response,
      endpoint,
      body: body,
      method: 'POST',
    );
  }

  /// PUT 요청을 처리합니다.
  Future<http.Response> put(String endpoint, {Object? body}) async {
    // 요청 전 선제 토큰 검증/갱신
    await _authService.validateAndRefreshToken();
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();
    final response = await http
        .put(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));

    return await _handleResponse(response, endpoint, body: body, method: 'PUT');
  }

  /// DELETE 요청을 처리합니다.
  Future<http.Response> delete(String endpoint) async {
    // 요청 전 선제 토큰 검증/갱신
    await _authService.validateAndRefreshToken();
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();
    final response = await http
        .delete(url, headers: headers)
        .timeout(const Duration(seconds: 10));

    return await _handleResponse(response, endpoint, method: 'DELETE');
  }
}
