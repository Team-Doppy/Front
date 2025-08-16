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

  /// GET 요청을 처리합니다.
  Future<http.Response> get(String endpoint) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();
    return await http
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 10));
  }

  /// POST 요청을 처리합니다.
  Future<http.Response> post(String endpoint, {Object? body}) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();
    return await http
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
  }

  /// PUT 요청을 처리합니다.
  Future<http.Response> put(String endpoint, {Object? body}) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();
    return await http
        .put(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
  }

  /// DELETE 요청을 처리합니다.
  Future<http.Response> delete(String endpoint) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();
    return await http
        .delete(url, headers: headers)
        .timeout(const Duration(seconds: 10));
  }
}
