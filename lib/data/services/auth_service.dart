import 'package:doppy/data/services/base_api_service.dart';
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
  static const String baseUrl = BaseApiService.baseUrl;

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

  /// 4. 토큰 검증 및 갱신 (클라이언트 사이드)
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
      final expirationTime = exp * 1000; // 밀리초로 변환
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final isExpired = now >= exp;

      // 🎯 테스트 환경: 만료 기간이 1분이므로 10초 전에 리프레시
      // 프로덕션에서는 5 * 60 * 1000 (5분) 사용
      final bufferTime = 10 * 1000; // 10초 버퍼 (테스트용)
      final shouldRefresh = isExpired || (expirationTime - nowMs) < bufferTime;

      print(
        '[AuthService] Token expires at: ${DateTime.fromMillisecondsSinceEpoch(exp * 1000)}',
      );
      print(
        '[AuthService] Current time: ${DateTime.fromMillisecondsSinceEpoch(now * 1000)}',
      );
      print('[AuthService] Token is expired: $isExpired');
      print('[AuthService] Should refresh: $shouldRefresh');

      // 🎯 토큰이 만료되었거나 곧 만료될 경우 리프레시 시도
      if (shouldRefresh) {
        print(
          '[AuthService] Token expired or expiring soon - attempting refresh...',
        );

        final refreshed = await _refreshToken();
        if (refreshed) {
          print('[AuthService] ✅ Token refreshed successfully');
          return true;
        } else {
          print('[AuthService] ❌ Token refresh failed');
          return false;
        }
      } else {
        print('[AuthService] Token is valid');
        return true;
      }
    } catch (e) {
      print('[AuthService] Token validation error: $e');
      return false;
    }
  }

  /// 🎯 리프레시 토큰으로 새 토큰 발급 (재시도 포함)
  Future<bool> _refreshToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      print('[AuthService] ❌ 리프레시 토큰이 없습니다');
      return false;
    }

    const maxRetries = 2;
    const retry1Delay = Duration(milliseconds: 300);
    const retry2Delay = Duration(milliseconds: 800);

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        final delay = attempt == 1 ? retry1Delay : retry2Delay;
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
            await saveToken(newToken);
            await saveRefreshToken(newRefreshToken);
            print('✅ [AuthService] 토큰 갱신 성공 (attempt=${attempt + 1})');
            return true;
          } else {
            print(
              '❌ [AuthService] 토큰 갱신 실패: 응답에 토큰이 없습니다 (attempt=${attempt + 1})',
            );
          }
        } else {
          print(
            '❌ [AuthService] 토큰 갱신 실패: ${response.statusCode} (attempt=${attempt + 1})',
          );
        }
      } catch (e) {
        print('❌ [AuthService] 토큰 갱신 오류 (attempt=${attempt + 1}): $e');
      }
    }

    // 모든 재시도 실패
    print('[AuthService] ❌ 토큰 갱신 실패: 모든 재시도 소진');
    return false;
  }

  /// 사용자 region 업데이트 (언어 변경 시)
  Future<bool> updateUserRegion(String region) async {
    try {
      final token = await getToken();
      if (token == null) {
        print('[AuthService] 토큰이 없습니다');
        return false;
      }

      print('[AuthService] Region 업데이트 시작: $region');
      print('[AuthService] Base URL: $baseUrl');

      final url = Uri.parse('$baseUrl/api/auth/update-region');
      print('[AuthService] 요청 URL: $url');

      final requestBody = jsonEncode({'region': region});
      print('[AuthService] 요청 본문: $requestBody');

      final response = await http.patch(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: requestBody,
      );

      print('[AuthService] Region 업데이트 응답 상태: ${response.statusCode}');
      print('[AuthService] Region 업데이트 응답 본문: ${response.body}');

      if (response.statusCode == 200) {
        // 🎯 새 토큰 저장
        final responseData = jsonDecode(response.body);

        if (responseData['success'] == true && responseData['data'] != null) {
          final data = responseData['data'];

          // token (accessToken)
          if (data['token'] != null) {
            await saveToken(data['token']);
            print('[AuthService] 새 access token 저장 완료');
            print('[AuthService] 새 토큰: ${data['token']}');
          }

          // refreshToken
          if (data['refreshToken'] != null) {
            await saveRefreshToken(data['refreshToken']);
            print('[AuthService] 새 refresh token 저장 완료');
          }

          // 사용자 정보도 업데이트
          if (data['username'] != null) {
            print(
              '[AuthService] 사용자: ${data['username']}, Region: ${data['region']}',
            );
          }

          print('[AuthService] Region 업데이트 성공: $region');
          return true;
        } else {
          print('[AuthService] Region 업데이트 실패: 응답 구조 오류');
          print('[AuthService] 응답 데이터: $responseData');
          return false;
        }
      } else {
        print('[AuthService] Region 업데이트 실패: ${response.statusCode}');
        print('[AuthService] 에러 메시지: ${response.body}');
        return false;
      }
    } catch (e, stackTrace) {
      print('[AuthService] Region 업데이트 오류: $e');
      print('[AuthService] Stack trace: $stackTrace');
      return false;
    }
  }
}
