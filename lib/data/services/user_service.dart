import 'package:dio/dio.dart';
import 'base_api_service.dart';
import '../models/user_model.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final Dio _dio = BaseApiService().dio;

  /// GET /api/auth/me (Postman: Get Me) – 내 정보
  Future<Map<String, dynamic>> getUserBundle() async {
    final res = await _dio.get('/api/auth/me');
    if (res.statusCode == 200) {
      final d = res.data;
      if (d is Map<String, dynamic>) {
        return (d['data'] ?? d) as Map<String, dynamic>;
      }
    }
    throw Exception('내 정보 조회 실패');
  }

  Future<User> getMyProfile() async {
    final bundle = await getUserBundle();
    return User.fromJson(bundle);
  }

  /// 회원 탈퇴 (Postman: DELETE /api/auth/account). Bearer 필수.
  Future<void> deleteAccount({String? reasonKey, String? detail}) async {
    final res = await _dio.delete('/api/auth/account');
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('회원 탈퇴 실패: ${res.statusCode}');
    }
  }
}
