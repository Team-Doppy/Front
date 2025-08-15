import 'dart:convert';
import 'api_service_base.dart';
import '../models/group_model.dart';
import '../models/group_member_model.dart';

class GroupService extends ApiServiceBase {
  /// 17. 그룹 생성
  Future<void> createGroup(String name) async {
    final response = await post('/api/groups', body: {'name': name});
    if (response.statusCode != 200) throw Exception('그룹 생성 실패');
  }

  /// 18. 내 그룹 목록 조회
  Future<List<Group>> getMyGroups() async {
    final response = await get('/api/groups');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => Group.fromJson(item)).toList();
    }
    throw Exception('그룹 목록 조회 실패');
  }

  /// 19. 그룹에 멤버 추가
  Future<void> addGroupMember(int groupId, String memberUsername) async {
    final response = await post('/api/groups/$groupId/members', body: {'memberUsername': memberUsername});
    if (response.statusCode != 200) throw Exception('그룹 멤버 추가 실패');
  }

  /// 20. 그룹에서 멤버 삭제
  Future<void> deleteGroupMember(int groupId, int memberId) async {
    final response = await delete('/api/groups/$groupId/members/$memberId');
    if (response.statusCode != 200) throw Exception('그룹 멤버 삭제 실패');
  }

  /// 21. 그룹 멤버 목록 조회
  Future<List<GroupMember>> getGroupMembers(int groupId) async {
    final response = await get('/api/groups/$groupId/members');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((item) => GroupMember.fromJson(item)).toList();
    }
    throw Exception('그룹 멤버 목록 조회 실패');
  }

  /// 22. 그룹 삭제
  Future<void> deleteGroup(int groupId) async {
    final response = await delete('/api/groups/$groupId');
    if (response.statusCode != 200) throw Exception('그룹 삭제 실패');
  }
}