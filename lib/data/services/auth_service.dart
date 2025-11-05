import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/login_response_model.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _storage = const FlutterSecureStorage();
  final String _tokenKey = 'auth_token';
  final String _refreshTokenKey = 'refresh_token';
  final String _usernameKey = 'username';
  static const String baseUrl = "http://13.125.227.178:5000";

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
    String? region, // 'KR' 또는 'US'
  }) async {
    final body = {'username': username, 'password': password};
    if (alias != null) body['alias'] = alias;
    if (region != null) body['region'] = region;

    try {
      final url = Uri.parse('$baseUrl/api/auth/register');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 회원가입 성공 후 자동 로그인
        final loginResult = await login(username, password, region: region);
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
    String? region, // 'KR' 또는 'US'
  }) async {
    final body = {'username': username, 'password': password};
    if (region != null) body['region'] = region;

    try {
      final url = Uri.parse('$baseUrl/api/auth/login');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        final loginResponse = LoginResponse.fromJson(responseData);

        // 기존 토큰 저장
        await _saveToken(loginResponse.token);
        await _saveRefreshToken(loginResponse.refreshToken);
        await _saveUsername(loginResponse.username);
        await initAfterLogin();

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
    try {
      final url = Uri.parse('$baseUrl/api/auth/check-username/$username');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        if (responseData['available'] == true) {
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
        print('[AuthService] Token expired - will be handled by DioClient');
        return false; // DioClient에서 갱신 처리
      } else {
        print('[AuthService] Token is valid');
        return true;
      }
    } catch (e) {
      print('[AuthService] Token validation error: $e');
      return false;
    }
  }

  /// 사용자 region 업데이트 (언어 변경 시)
  Future<bool> updateUserRegion(String region) async {
    try {
      final token = await getToken();
      if (token == null) {
        print('[AuthService] 토큰이 없습니다');
        return false;
      }

      final url = Uri.parse('$baseUrl/api/auth/update-region');
      final response = await http.patch(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'region': region}),
      );

      if (response.statusCode == 200) {
        print('[AuthService] Region 업데이트 성공: $region');
        return true;
      } else {
        print('[AuthService] Region 업데이트 실패: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('[AuthService] Region 업데이트 오류: $e');
      return false;
    }
  }
}
