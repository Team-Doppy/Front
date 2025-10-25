import 'package:dio/dio.dart';
import 'base_api_service.dart';
import '../models/user_model.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final Dio _dio = BaseApiService().dio;

  /// 4. 내 친구 수 조회
  Future<int> getFriendCount() async {
    try {
      final response = await _dio.get('/api/users/friend-count');
      if (response.statusCode == 200) {
        return response.data['friendCount'];
      }
      throw Exception('친구 수 조회 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('친구 수 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 5. 자기소개 저장
  Future<void> saveSelfIntroduction(String introduction) async {
    try {
      final response = await _dio.put(
        '/api/users/self-introduction',
        data: {'selfIntroduction': introduction},
      );
      if (response.statusCode != 200) {
        throw Exception('자기소개 저장 실패');
      }
    } catch (e) {
      if (e is DioException) {
        throw Exception('자기소개 저장 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 6. 내 자기소개 조회
  Future<String> getSelfIntroduction() async {
    try {
      final response = await _dio.get('/api/users/self-introduction');
      if (response.statusCode == 200) {
        return response.data['selfIntroduction'];
      }
      throw Exception('자기소개 조회 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('자기소개 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 7. 타인 자기소개 조회
  Future<String> getOtherUserSelfIntroduction(String username) async {
    try {
      final response = await _dio.get('/api/users/$username/self-introduction');
      if (response.statusCode == 200) {
        return response.data['selfIntroduction'];
      }
      throw Exception('타인 자기소개 조회 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('타인 자기소개 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 프로필 정보 업데이트 (/api/profile/info)
  Future<void> updateProfileInfo({
    required String alias,
    required String selfIntroduction,
  }) async {
    try {
      final response = await _dio.put(
        '/api/profile/info',
        data: {'alias': alias, 'selfIntroduction': selfIntroduction},
      );
      if (response.statusCode != 200) {
        throw Exception('프로필 정보 업데이트 실패');
      }
    } catch (e) {
      if (e is DioException) {
        throw Exception('프로필 정보 업데이트 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 프로필 정보 조회 (/api/profile/info)
  Future<User> getMyProfile() async {
    try {
      final response = await _dio.get('/api/profile/info');
      if (response.statusCode == 200) {
        final decoded = response.data;
        // 일반 Map 또는 { data: {...} } 형태 모두 대응
        if (decoded is Map<String, dynamic>) {
          final map =
              decoded['data'] is Map<String, dynamic>
                  ? decoded['data'] as Map<String, dynamic>
                  : decoded;
          return User.fromJson(map);
        }
        throw Exception('프로필 응답 형식 오류: ${decoded.runtimeType}');
      }
      throw Exception('프로필 정보 조회 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        throw Exception('프로필 정보 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 프로필 이미지 삭제 (기본 이미지로 되돌리기)
  Future<void> deleteProfileImage() async {
    try {
      final response = await _dio.delete('/api/profile/image');
      if (response.statusCode != 200) {
        throw Exception('프로필 이미지 삭제 실패: ${response.statusCode}');
      }
    } catch (e) {
      if (e is DioException) {
        throw Exception('프로필 이미지 삭제 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }
}
