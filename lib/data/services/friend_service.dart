import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/friend_model.dart';
import '../models/user_model.dart';
import 'api_service_base.dart';

class FriendService extends ApiServiceBase {

  // 8. 사용자 검색
  Future<List<User>> searchUsers(String searchTerm) async {
    final response = await get('/api/friends/search?username=$searchTerm');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => User.fromJson(item)).toList();
    } else {
      throw Exception('사용자 검색 실패');
    }
  }

  // 1. 친구 신청
  Future<void> sendFriendRequest(String targetUsername) async {
    final body = jsonEncode({'targetUsername': targetUsername});
    final response = await post('/api/friends/request', body: body);
    if (response.statusCode != 200) {
      throw Exception('친구 신청 실패');
    }
  }

  // 2. 받은 친구 요청 목록 조회
  Future<List<Friend>> getReceivedFriendRequests() async {
    final response = await get('/api/friends/received-requests');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => Friend.fromJson(item)).toList();
    } else {
      throw Exception('받은 친구 요청 목록 조회 실패');
    }
  }

  // 3. 친구 요청 수락
  Future<void> acceptFriendRequest(String requesterUsername) async {
    final response = await post('/api/friends/accept/$requesterUsername');
    if (response.statusCode != 200) {
      throw Exception('친구 요청 수락 실패');
    }
  }

  // 6. 수락된 친구 목록 조회
  Future<List<Friend>> getAcceptedFriends() async {
    final response = await get('/api/friends/accepted');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => Friend.fromJson(item)).toList();
    } else {
      throw Exception('친구 목록 조회 실패');
    }
  }
}