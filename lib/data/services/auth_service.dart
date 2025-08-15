import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/login_response_model.dart';
import '../models/user_model.dart';

class AuthService {
  final _storage = const FlutterSecureStorage();
  final String _tokenKey = 'auth_token';
  final String _usernameKey = 'username';
  final String _baseUrl =
      "http://doppy-gaooli-env.eba-i6rkanrz.us-east-1.elasticbeanstalk.com";

  /// 1. 사용자 등록
  Future<User?> register({
    required String username,
    required String password,
    String? alias,
  }) async {
    final url = Uri.parse('$_baseUrl/api/auth/register');
    final body = {'username': username, 'password': password, 'alias': alias};
    // null 값은 보내지 않도록 처리
    body.removeWhere((key, value) => value == null);

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    }
    return null;
  }

  /// 2. 사용자 로그인
  Future<LoginResponse?> login(String username, String password) async {
    final url = Uri.parse('$_baseUrl/api/auth/login');
    final body = {'username': username, 'password': password};
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final loginResponse = LoginResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
        await _saveToken(loginResponse.token);
        await _saveUsername(loginResponse.username);
        return loginResponse;
      }
    } catch (e) {
      print('❌ [AuthService] 로그인 오류: $e');
    }
    return null;
  }

  /// 3. 사용자 정보 조회 (인증 불필요)
  Future<User?> getUserInfo(String username) async {
    final url = Uri.parse('$_baseUrl/api/auth/users/$username');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    }
    return null;
  }

  // --- 토큰 및 사용자명 관리 ---
  Future<void> _saveToken(String token) async =>
      await _storage.write(key: _tokenKey, value: token);
  Future<void> _saveUsername(String username) async =>
      await _storage.write(key: _usernameKey, value: username);
  Future<String?> getToken() async => await _storage.read(key: _tokenKey);
  Future<String?> getUsername() async => await _storage.read(key: _usernameKey);
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _usernameKey);
  }
}
