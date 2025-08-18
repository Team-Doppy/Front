import 'dart:convert';
import 'api_service_base.dart';
import '../models/friend_model.dart';
import '../models/user_model.dart';

class FriendService extends ApiServiceBase {
  static final FriendService _instance = FriendService._internal();
  factory FriendService() => _instance;
  FriendService._internal();

  /// 8. 친구 신청
  Future<void> sendFriendRequest(String targetUsername) async {
    final response = await post(
      '/api/friends/request',
      body: {'targetUsername': targetUsername},
    );
    if (response.statusCode != 200) throw Exception('친구 신청 실패');
  }

  /// 9. 친구 수락
  Future<void> acceptFriendRequest(String requesterUsername) async {
    final response = await post('/api/friends/accept/$requesterUsername');
    if (response.statusCode != 200) throw Exception('친구 요청 수락 실패');
  }

  /// 10. 친구 거절
  Future<void> rejectFriendRequest(String requesterUsername) async {
    final response = await post('/api/friends/reject/$requesterUsername');
    if (response.statusCode != 200) throw Exception('친구 요청 거절 실패');
  }

  /// 12. 친구 삭제
  Future<void> deleteFriend(String targetUsername) async {
    final response = await delete('/api/friends/delete/$targetUsername');
    if (response.statusCode != 200) throw Exception('친구 삭제 실패');
  }

  /// 13. 사용자 검색
  Future<List<User>> searchUsers(String query) async {
    final response = await get('/api/friends/search?username=$query');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      // API 응답이 {"username": "..."} 이므로 User 모델로 변환
      return data
          .map((item) => User(id: 0, username: item['username']))
          .toList();
    }
    throw Exception('사용자 검색 실패');
  }

  /// 14. 수락된 친구 목록 조회
  Future<List<Friend>> getAcceptedFriends() async {
    final response = await get('/api/friends/accepted');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => Friend.fromJson(item)).toList();
    }
    throw Exception('친구 목록 조회 실패');
  }

  /// 15. 보낸 친구 신청 목록
  Future<List<Friend>> getSentFriendRequests() async {
    final response = await get('/api/friends/sent-requests');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => Friend.fromJson(item)).toList();
    }
    throw Exception('보낸 친구 신청 목록 조회 실패');
  }

  /// 16. 받은 친구 신청 목록
  Future<List<Friend>> getReceivedFriendRequests() async {
    final response = await get('/api/friends/received-requests');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => Friend.fromJson(item)).toList();
    }
    throw Exception('받은 친구 신청 목록 조회 실패');
  }
}
