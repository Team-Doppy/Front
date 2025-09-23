import 'dart:convert';
import 'api_service_base.dart';
import '../models/user_model.dart';

class UserService extends ApiServiceBase {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  /// 4. 내 친구 수 조회
  Future<int> getFriendCount() async {
    final response = await get('/api/users/friend-count');
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes))['friendCount'];
    }
    throw Exception('친구 수 조회 실패');
  }

  /// 5. 자기소개 저장
  Future<void> saveSelfIntroduction(String introduction) async {
    final response = await put(
      '/api/users/self-introduction',
      body: {'selfIntroduction': introduction},
    );
    if (response.statusCode != 200) {
      throw Exception('자기소개 저장 실패');
    }
  }

  /// 6. 내 자기소개 조회
  Future<String> getSelfIntroduction() async {
    final response = await get('/api/users/self-introduction');
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes))['selfIntroduction'];
    }
    throw Exception('자기소개 조회 실패');
  }

  /// 7. 타인 자기소개 조회
  Future<String> getOtherUserSelfIntroduction(String username) async {
    final response = await get('/api/users/$username/self-introduction');
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes))['selfIntroduction'];
    }
    throw Exception('타인 자기소개 조회 실패');
  }

  /// 프로필 정보 조회 (/api/profile/info)
  Future<User> getMyProfile() async {
    final response = await get('/api/profile/info');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
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
  }
}
