import 'dart:convert';

import 'package:http/http.dart' as http;
import '../services/auth_service.dart';

class ApiServiceBase {
  final String baseUrl =
      "http://Doppy-GaOoLi-env.eba-i6rkanrz.us-east-1.elasticbeanstalk.com";
  final AuthService _authService = AuthService(); // 토큰을 가져오기 위함

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

  // GET, POST, DELETE 등 공통 HTTP 메소드 구현
  Future<http.Response> get(String endpoint) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();
    print('🚀 [API GET] 요청 시작: $url');
    try {
      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 10)); // 10초 타임아웃 설정

      // 응답 로그 (한글 깨짐 방지: utf8.decode)
      final responseBody = utf8.decode(response.bodyBytes);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ [API GET] 성공: ${response.statusCode}, $url');
        print('📦 Response Body: $responseBody');
      } else {
        print('⚠️ [API GET] 실패: ${response.statusCode}, $url');
        print('📦 Response Body: $responseBody');
      }
      return response;
    } catch (e, s) {
      print('❌ [API GET] 네트워크 오류: $url');
      print('   - 에러: $e');
      print('   - 스택 트레이스: $s');
      // 예외를 다시 던져서 Provider 등 상위 레이어에서 처리할 수 있게 함
      rethrow;
    }
  }

  Future<http.Response> post(String endpoint, {Object? body}) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();
    final encodedBody = body != null ? jsonEncode(body) : null;

    print('🚀 [API POST] 요청 시작: $url');
    if (encodedBody != null) {
      print('📋 Request Body: $encodedBody');
    }

    try {
      final response = await http
          .post(url, headers: headers, body: encodedBody)
          .timeout(const Duration(seconds: 10)); // 10초 타임아웃 설정

      final responseBody = utf8.decode(response.bodyBytes);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ [API POST] 성공: ${response.statusCode}, $url');
        print('📦 Response Body: $responseBody');
      } else {
        print('⚠️ [API POST] 실패: ${response.statusCode}, $url');
        print('📦 Response Body: $responseBody');
      }
      return response;
    } catch (e, s) {
      print('❌ [API POST] 네트워크 오류: $url');
      print('   - 에러: $e');
      print('   - 스택 트레이스: $s');
      rethrow;
    }
  }

  Future<http.Response> delete(String endpoint) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();
    return await http.delete(url, headers: headers);
  }
}