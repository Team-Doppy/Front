import 'dart:convert';

import 'package:doppy/data/services/base_api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/email_verification_models.dart';
import '../models/login_response_model.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static final String baseUrl = BaseApiService.baseUrl;
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _refreshKey = 'refresh_token';
  static const _usernameKey = 'username';

  static String? _cachedUsername;

  String? get currentUsernameSync => _cachedUsername;

  Future<void> saveUsername(String username) async {
    await _storage.write(key: _usernameKey, value: username);
    _cachedUsername = username;
  }

  Future<String?> getToken() => _storage.read(key: _tokenKey);
  Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);
  Future<String?> getUsername() async {
    final u = await _storage.read(key: _usernameKey);
    _cachedUsername = u;
    return u;
  }

  Future<LoginResponse?> login(
    String username,
    String password, {
    String? region,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/auth/login');
      final body = <String, dynamic>{
        'username': username,
        'password': password,
      };
      if (region != null) body['region'] = region;

      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final loginRes = LoginResponse.fromJson(data);

        await _storage.write(key: _tokenKey, value: loginRes.token);
        await _storage.write(key: _refreshKey, value: loginRes.refreshToken);
        await saveUsername(loginRes.username);

        debugPrint('[AuthService] 로그인 성공: ${loginRes.username}, token length: ${loginRes.token.length}');
        return loginRes;
      }
      if (res.statusCode == 502) {
        throw Exception('서버 내부 오류가 발생했어요');
      }
    } catch (e) {
      debugPrint('[AuthService] 로그인 실패: $e');
      if (e.toString().contains('서버 내부 오류')) rethrow;
    }
    return null;
  }

  Future<void> logout() async {
    try {
      final refresh = await getRefreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        await http.post(
          Uri.parse('$baseUrl/api/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refresh}),
        );
      }
    } catch (e) {
      debugPrint('[AuthService] logout 서버 호출 실패 (무시): $e');
    }
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _usernameKey);
    _cachedUsername = null;
    debugPrint('[AuthService] 로그아웃');
  }

  Future<bool> checkUsernameDuplicate(String username) async {
    try {
      final url = Uri.parse('$baseUrl/api/auth/check-username/$username');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        return data['available'] == true;
      }
    } catch (e) {
      debugPrint('[AuthService] checkUsernameDuplicate: $e');
    }
    return false;
  }

  Future<bool> register({
    required String username,
    required String password,
    required String email,
    String? alias,
    String? region,
  }) async {
    try {
      final body = <String, dynamic>{
        'username': username,
        'password': password,
        'email': email,
      };
      if (alias != null) body['alias'] = alias;
      if (region != null) body['region'] = region;

      final res = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final loginRes = await login(username, password, region: region);
        return loginRes != null;
      }
    } catch (e) {
      debugPrint('[AuthService] register: $e');
    }
    return false;
  }

  Future<EmailSendCodeResult> sendEmailVerificationCode({
    required String email,
    String region = 'KR',
    String mode = 'REGISTER',
  }) async {
    try {
      final token = await getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final res = await http.post(
        Uri.parse('$baseUrl/api/auth/email/send-code'),
        headers: headers,
        body: jsonEncode({'email': email, 'region': region, 'mode': mode}),
      );

      Map<String, dynamic>? data;
      try {
        data = res.bodyBytes.isNotEmpty
            ? jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>?
            : null;
      } catch (_) {}

      if (res.statusCode == 200) {
        DateTime? expiresAt;
        int? expiresIn;
        if (data?['expiresAt'] != null) {
          try {
            expiresAt = DateTime.parse(data!['expiresAt'].toString());
          } catch (_) {}
        }
        if (data?['expiresIn'] != null) {
          expiresIn = int.tryParse(data!['expiresIn'].toString());
        }
        return EmailSendCodeResult(
          success: true,
          statusCode: res.statusCode,
          expiresAt: expiresAt,
          expiresIn: expiresIn,
        );
      }
      return EmailSendCodeResult(
        success: false,
        statusCode: res.statusCode,
        message: data?['message']?.toString() ?? _httpMsg(res.statusCode),
      );
    } catch (e) {
      debugPrint('[AuthService] sendEmailVerificationCode: $e');
      return EmailSendCodeResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  Future<EmailVerifyCodeResult> verifyEmailCode({
    required String email,
    required String code,
    String mode = 'REGISTER',
  }) async {
    try {
      final token = await getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final res = await http.post(
        Uri.parse('$baseUrl/api/auth/email/verify-code'),
        headers: headers,
        body: jsonEncode({'email': email, 'code': code, 'mode': mode}),
      );

      Map<String, dynamic>? data;
      try {
        data = res.bodyBytes.isNotEmpty
            ? jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>?
            : null;
      } catch (_) {}

      if (res.statusCode == 200) {
        final v = data?['verified'];
        final verified = v == null ? true : v.toString().toLowerCase() == 'true';
        return EmailVerifyCodeResult(
          success: true,
          verified: verified,
          statusCode: res.statusCode,
        );
      }
      final err = data != null ? ApiError.fromJson(data) : null;
      return EmailVerifyCodeResult(
        success: false,
        statusCode: res.statusCode,
        message: err?.message ?? data?['message']?.toString() ?? _httpMsg(res.statusCode),
        error: err,
      );
    } catch (e) {
      debugPrint('[AuthService] verifyEmailCode: $e');
      return EmailVerifyCodeResult(success: false, message: e.toString());
    }
  }

  Future<LoginResponse?> updateEmail({required String email}) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) return null;

      final res = await http.patch(
        Uri.parse('$baseUrl/api/auth/update-email'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'email': email}),
      );

      Map<String, dynamic>? data;
      try {
        data = res.bodyBytes.isNotEmpty
            ? jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>?
            : null;
      } catch (_) {}

      if (res.statusCode == 200 && data != null) {
        final d = data['data'] ?? data;
        if (d is Map<String, dynamic>) {
          final t = d['accessToken'] ?? d['token'] ?? '';
          final r = d['refreshToken'] ?? '';
          final u = d['username'] ?? '';
          if (t.toString().isNotEmpty && r.toString().isNotEmpty) {
            await _storage.write(key: _tokenKey, value: t.toString());
            await _storage.write(key: _refreshKey, value: r.toString());
            await saveUsername(u.toString());
            return LoginResponse(
              token: t.toString(),
              refreshToken: r.toString(),
              username: u.toString(),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[AuthService] updateEmail: $e');
    }
    return null;
  }

  /// ID 찾기 (Postman: Username Find). POST /api/auth/username/find { email }
  Future<FindUsernameResult> findUsernameByEmail(String email) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/auth/username/find'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim()}),
      );
      Map<String, dynamic>? data;
      try {
        data = res.bodyBytes.isNotEmpty
            ? jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>?
            : null;
      } catch (_) {}
      if (res.statusCode == 200 && data != null) {
        final username = data['username'] ?? data['data']?['username'];
        return FindUsernameResult(success: true, username: username?.toString());
      }
      return FindUsernameResult(
        success: false,
        message: data?['message']?.toString() ?? _httpMsg(res.statusCode),
      );
    } catch (e) {
      debugPrint('[AuthService] findUsernameByEmail: $e');
      return FindUsernameResult(success: false, message: e.toString());
    }
  }

  /// 비밀번호 재설정 코드 발송 (Postman: Send Email Code mode=PASSWORD_RESET, body에 username 추가 가능)
  /// POST /api/auth/email/send-code { email, region, mode: "PASSWORD_RESET" }
  Future<EmailSendCodeResult> sendPasswordResetCode(String email, {String? username}) async {
    try {
      final body = <String, dynamic>{
        'email': email.trim(),
        'region': 'KR',
        'mode': 'PASSWORD_RESET',
      };
      if (username != null && username.isNotEmpty) body['username'] = username;
      final res = await http.post(
        Uri.parse('$baseUrl/api/auth/email/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      Map<String, dynamic>? data;
      try {
        data = res.bodyBytes.isNotEmpty
            ? jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>?
            : null;
      } catch (_) {}
      if (res.statusCode == 200) {
        int? expiresIn;
        if (data?['expiresIn'] != null) {
          expiresIn = int.tryParse(data!['expiresIn'].toString());
        }
        return EmailSendCodeResult(
          success: true,
          statusCode: res.statusCode,
          expiresIn: expiresIn,
        );
      }
      return EmailSendCodeResult(
        success: false,
        statusCode: res.statusCode,
        message: data?['message']?.toString() ?? _httpMsg(res.statusCode),
      );
    } catch (e) {
      debugPrint('[AuthService] sendPasswordResetCode: $e');
      return EmailSendCodeResult(success: false, message: e.toString());
    }
  }

  /// 비밀번호 재설정 실행 (Postman: Password Change)
  /// POST /api/auth/password/change { username, email, code, newPassword }
  Future<ResetPasswordResult> resetPassword({
    required String username,
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/auth/password/change'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username.trim(),
          'email': email.trim(),
          'code': code.trim(),
          'newPassword': newPassword,
        }),
      );
      Map<String, dynamic>? data;
      try {
        data = res.bodyBytes.isNotEmpty
            ? jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>?
            : null;
      } catch (_) {}
      if (res.statusCode == 200 || res.statusCode == 204) {
        return ResetPasswordResult(success: true);
      }
      return ResetPasswordResult(
        success: false,
        message: data?['message']?.toString() ?? _httpMsg(res.statusCode),
      );
    } catch (e) {
      debugPrint('[AuthService] resetPassword: $e');
      return ResetPasswordResult(success: false, message: e.toString());
    }
  }

  static String _httpMsg(int code) {
    switch (code) {
      case 400: return '잘못된 요청입니다.';
      case 401: return '인증이 필요합니다.';
      case 404: return '찾을 수 없습니다.';
      case 500: return '서버 오류가 발생했습니다.';
      default: return '오류가 발생했습니다.';
    }
  }

  Future<bool> validateAndRefreshToken() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;

    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;

      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map;
      final exp = payload['exp'] as int?;
      if (exp == null) return false;

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (now < exp - 300) return true; // 5분 여유

      return await _refreshToken();
    } catch (_) {
      return false;
    }
  }

  /// 401 시 Dio 등에서 호출. 리프레시 성공 여부 반환.
  Future<bool> tryRefreshToken() async => _refreshToken();

  Future<bool> _refreshToken() async {
    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refresh}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final d = data['data'] ?? data;
        final newToken = d['token'] ?? d['accessToken'];
        final newRefresh = d['refreshToken'];
        if (newToken != null && newRefresh != null) {
          await _storage.write(key: _tokenKey, value: newToken.toString());
          await _storage.write(key: _refreshKey, value: newRefresh.toString());
          debugPrint('[AuthService] 토큰 갱신 성공');
          return true;
        }
      }
    } catch (e) {
      debugPrint('[AuthService] 토큰 갱신 실패: $e');
    }
    return false;
  }
}
