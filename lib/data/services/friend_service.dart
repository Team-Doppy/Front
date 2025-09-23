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
    final code = response.statusCode;
    final body = response.body;
    // 일부 서버는 201/204를 반환할 수 있음 → 2xx 모두 성공 처리
    if (code < 200 || code >= 300) {
      // 특수 케이스: 서버가 바디 파싱 실패(예: No value present) 응답 시
      if (code == 400 && body.contains('No value present')) {
        // 쿼리파라미터 방식으로 재시도 (서버 구현 케이스 대응)
        final fallback = await post(
          '/api/friends/request?targetUsername=${Uri.encodeComponent(targetUsername)}',
        );
        final fcode = fallback.statusCode;
        if (fcode >= 200 && fcode < 300) return;
        // ignore: avoid_print
        print(
          '[FriendService] fallback also failed | code=$fcode body=${fallback.body}',
        );
      }
      // 디버그를 위해 상태/본문 로그 남김
      // ignore: avoid_print
      print('[FriendService] sendFriendRequest failed | code=$code body=$body');
      throw Exception('친구 신청 실패');
    }
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
