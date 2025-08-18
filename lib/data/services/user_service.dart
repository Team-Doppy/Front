import 'dart:convert';
import 'api_service_base.dart';

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
}
