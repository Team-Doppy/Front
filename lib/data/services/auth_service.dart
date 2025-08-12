import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AuthService {
  final _storage = const FlutterSecureStorage();
  final String _tokenKey = 'auth_token';

  // 🎯 [수정] API 명세서에 맞게 전체 URL을 정확히 입력했습니다. (포트와 엔드포인트 추가)
  final String _baseUrl = "http://doppy-gaooli-env.eba-i6rkanrz.us-east-1.elasticbeanstalk.com";
  
  //API 2번: 사용자 로그인
  Future<bool> login(String username, String password) async {
    // 🎯 [수정] 이메일(email)이 아닌 사용자 이름(username)을 받도록 변경했습니다.
    final loginUrl = Uri.parse('$_baseUrl/api/auth/login');

    // 🎯 [수정] API 명세서에 따라 'email' 키를 'username'으로 변경했습니다.
    final body = {'username': username, 'password': password};

    // ✨ [로그 추가] 1. 요청 시작과 내용을 콘솔에 출력
    print('🚀 [AuthService] 로그인 요청 시작: $loginUrl');
    print('📋 Request Body: ${jsonEncode(body)}');

    try {
      final response = await http
          .post(
            loginUrl,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10)); // 10초 타임아웃 추가

      // ✨ [로그 추가] 2. 서버의 응답 코드와 내용을 그대로 출력
      final responseBody = utf8.decode(response.bodyBytes); // 한글 깨짐 방지

      if (response.statusCode == 200) {
        print('✅ [AuthService] 로그인 성공! Status: ${response.statusCode}');
        print('📦 Response Body: $responseBody');

        final responseData = jsonDecode(responseBody);
        // 🎯 [수정] API 명세서에 따라 'accessToken'을 'token'으로 변경했습니다.
        final String token = responseData['token'];

        await _saveToken(token);
        return true;
      } else {
        print('⚠️ [AuthService] 로그인 실패. Status: ${response.statusCode}');
        print('📦 Response Body: $responseBody');
        return false;
      }
    } catch (e, s) {
      // ✨ [로그 추가] 3. 네트워크 오류나 타임아웃 발생 시 에러와 위치를 출력
      print('❌ [AuthService] 네트워크 또는 파싱 오류 발생: $e');
      print('📄 Stack Trace: $s');
      return false;
    }
  }

  Future<void> _saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
  }
}
