import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/group_model.dart';
import '../models/group_member_model.dart';
import 'api_service_base.dart';

class GroupService extends ApiServiceBase {

  // 1. 그룹 생성
  Future<Group> createGroup(String name) async {
    final body = jsonEncode({'name': name});
    final response = await post('/api/groups', body: body);
    if (response.statusCode == 201) {
      return Group.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('그룹 생성 실패');
    }
  }

  // 2. 그룹 목록 조회
  Future<List<Group>> getGroups() async {
    final response = await get('/api/groups');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => Group.fromJson(item)).toList();
    } else {
      throw Exception('그룹 목록 조회 실패');
    }
  }

  // 3. 그룹에 멤버 추가
  Future<void> addGroupMember(int groupId, String memberUsername) async {
    final body = jsonEncode({'memberUsername': memberUsername});
    final response = await post('/api/groups/$groupId/members', body: body);
    if (response.statusCode != 200) {
      // API 명세에 따라 409(친구 관계 아님) 등 특정 에러 처리 가능
      final error = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(error['message'] ?? '멤버 추가 실패');
    }
  }

  // 4. 그룹 멤버 목록 조회
  Future<List<GroupMember>> getGroupMembers(int groupId) async {
    final response = await get('/api/groups/$groupId/members');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => GroupMember.fromJson(item)).toList();
    } else {
      throw Exception('그룹 멤버 목록 조회 실패');
    }
  }

  // 5. 그룹에서 멤버 삭제
  Future<void> deleteGroupMember(int groupId, int memberId) async {
    final response = await delete('/api/groups/$groupId/members/$memberId');
    if (response.statusCode != 200) {
      throw Exception('멤버 삭제 실패');
    }
  }

  // 6. 그룹 삭제
  Future<void> deleteGroup(int groupId) async {
    final response = await delete('/api/groups/$groupId');
    if (response.statusCode != 200) {
      throw Exception('그룹 삭제 실패');
    }
  }
}