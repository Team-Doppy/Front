import 'package:doppy/data/services/api_service_base.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/login_response_model.dart';
import '../models/user_model.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _storage = const FlutterSecureStorage();
  final String _tokenKey = 'auth_token';
  final String _usernameKey = 'username';
  final String _baseUrl = ApiServiceBase.baseUrl;

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

  /// 4. 토큰 검증 (클라이언트 사이드)
  Future<bool> validateAndRefreshToken() async {
    final token = await getToken();
    if (token == null) {
      print('[AuthService] No token found');
      return false;
    }

    print('[AuthService] Validating token: ${token.substring(0, 20)}...');

    try {
      // JWT 토큰을 디코딩하여 만료 시간 확인
      final parts = token.split('.');
      if (parts.length != 3) {
        print('[AuthService] Invalid token format');
        return false;
      }

      // JWT payload 디코딩
      final payload = parts[1];
      // Base64 패딩 추가
      final normalized = base64.normalize(payload);
      final resp = utf8.decode(base64.decode(normalized));
      final payloadMap = json.decode(resp);

      // 만료 시간 확인
      final exp = payloadMap['exp'] as int?;
      if (exp == null) {
        print('[AuthService] No expiration time in token');
        return false;
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final isExpired = now >= exp;

      print(
        '[AuthService] Token expires at: ${DateTime.fromMillisecondsSinceEpoch(exp * 1000)}',
      );
      print(
        '[AuthService] Current time: ${DateTime.fromMillisecondsSinceEpoch(now * 1000)}',
      );
      print('[AuthService] Token is expired: $isExpired');

      if (isExpired) {
        print('[AuthService] Token expired, attempting refresh...');
        return await _refreshToken();
      } else {
        print('[AuthService] Token is valid');
        return true;
      }
    } catch (e) {
      print('[AuthService] Token validation error: $e');
      return false;
    }
  }

  /// 5. 토큰 갱신 (현재는 서버에 refresh 엔드포인트가 없으므로 false 반환)
  Future<bool> _refreshToken() async {
    print(
      '[AuthService] Token refresh not available - server does not support refresh endpoint',
    );
    return false;
  }
}
