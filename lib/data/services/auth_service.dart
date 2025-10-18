import 'package:doppy/data/services/api_service_base.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/login_response_model.dart';
import 'account_manager_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _storage = const FlutterSecureStorage();
  final String _tokenKey = 'auth_token';
  final String _refreshTokenKey = 'refresh_token';
  final String _usernameKey = 'username';
  final String _baseUrl = ApiServiceBase.baseUrl;

  // 앱 시작 시 1회 로드되어 메모리에 보관되는 동기 접근용 사용자명
  static String? _cachedUsername;

  /// 로그인 성공 시 호출하여 username을 메모리에 캐시한다.
  Future<void> initAfterLogin() async {
    try {
      _cachedUsername = await _storage.read(key: _usernameKey);
    } catch (_) {}
  }

  /// 동기 접근 가능한 현재 사용자명(없으면 null)
  String? get currentUsernameSync => _cachedUsername;

  /// 1. 사용자 등록
  Future<bool> register({
    required String username,
    required String password,
    String? alias,
  }) async {
    final url = Uri.parse('$_baseUrl/api/auth/register');
    final body = {'username': username, 'password': password, 'alias': alias};
    // null 값은 보내지 않도록 처리
    body.removeWhere((key, value) => value == null);

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 회원가입 성공 후 자동 로그인
        final loginResult = await login(username, password);
        return loginResult != null;
      }
      return false;
    } catch (e) {
      print('❌ [AuthService] 회원가입 오류: $e');
      return false;
    }
  }

  /// 2. 사용자 로그인
  Future<LoginResponse?> login(
    String username,
    String password, {
    bool setAsCurrent = true,
  }) async {
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

        // 기존 토큰 저장
        await _saveToken(loginResponse.token);
        await _saveRefreshToken(loginResponse.refreshToken);
        await _saveUsername(loginResponse.username);
        await initAfterLogin();

        // 로컬 계정 기록도 업데이트 (로그인 시)
        if (setAsCurrent) {
          await AccountManagerService.updateCurrentAccountTokens(
            token: loginResponse.token,
            refreshToken: loginResponse.refreshToken,
          );
        }

        print('[-] [AuthService] login success: ${loginResponse.username}');
        return loginResponse;
      }
    } catch (e) {
      print('❌ [AuthService] 로그인 오류: $e');
    }
    return null;
  }

  /// 3. 사용자명 중복 확인 (인증 불필요)
  Future<bool> checkUsernameDuplicate(String username) async {
    final url = Uri.parse('$_baseUrl/api/auth/check-username/$username');
    try {
      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        if (jsonDecode(utf8.decode(response.bodyBytes))['available'] == true) {
          return true;
        }
        return false;
      }

      return false;
    } catch (e) {
      print('❌ [AuthService] 사용자명 중복확인 오류: $e');
      return false;
    }
  }

  // --- 토큰 및 사용자명 관리 ---
  Future<void> _saveToken(String token) async =>
      await _storage.write(key: _tokenKey, value: token);
  Future<void> _saveRefreshToken(String refreshToken) async =>
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
  Future<void> _saveUsername(String username) async {
    await _storage.write(key: _usernameKey, value: username);
    _cachedUsername = username; // 메모리 캐시 동기화
  }

  // Public methods for external access
  Future<void> saveToken(String token) async => await _saveToken(token);
  Future<void> saveRefreshToken(String refreshToken) async =>
      await _saveRefreshToken(refreshToken);
  Future<void> saveUsername(String username) async =>
      await _saveUsername(username);
  Future<String?> getToken() async => await _storage.read(key: _tokenKey);
  Future<String?> getRefreshToken() async =>
      await _storage.read(key: _refreshTokenKey);
  Future<String?> getUsername() async => await _storage.read(key: _usernameKey);
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _usernameKey);
    await AccountManagerService.clearCurrentAccount();
    _cachedUsername = null; // 메모리 캐시 초기화
    print('[-] [AuthService] logout success');
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
      final payloadMap = jsonDecode(resp);

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

  /// 5. 토큰 갱신 (public)
  Future<bool> refreshToken() async {
    return await _refreshToken();
  }

  /// 5. 토큰 갱신 (리프레시 토큰 사용) - private
  Future<bool> _refreshToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) {
      print('❌ [AuthService] 리프레시 토큰이 없습니다');
      return false;
    }

    try {
      final url = Uri.parse('$_baseUrl/api/auth/refresh');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        final newToken = responseData['token'];
        final newRefreshToken = responseData['refreshToken'];

        // 새로운 토큰들 저장
        await _saveToken(newToken);
        await _saveRefreshToken(newRefreshToken);

        // AccountManagerService의 현재 계정 토큰도 업데이트 (로컬 저장된 계정 기록 포함)
        await AccountManagerService.updateCurrentAccountTokens(
          token: newToken,
          refreshToken: newRefreshToken,
        );

        print('✅ [AuthService] 토큰 갱신 성공 - 로컬 계정 기록도 업데이트됨');
        return true;
      } else {
        print('❌ [AuthService] 토큰 갱신 실패: ${response.statusCode}');
        print('❌ [AuthService] 응답 내용: ${response.body}');
        await logout();
        return false;
      }
    } catch (e) {
      print('❌ [AuthService] 토큰 갱신 오류: $e');
      await logout();
      return false;
    }
  }
}
