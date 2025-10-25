// lib/providers/group_provider.dart
import 'package:flutter/material.dart';
import '../data/models/group_model.dart';
import '../data/models/group_member_model.dart';
import '../data/services/group_service.dart';

class GroupProvider with ChangeNotifier {
  final GroupService _groupService = GroupService();

  List<Group> _myGroups = [];
  bool _isLoading = false;

  // 그룹별 멤버
  final Map<int, List<GroupMember>> _groupMembers = {};

  List<Group> get myGroups => _myGroups;
  bool get isLoading => _isLoading;

  List<GroupMember> membersOf(int groupId) =>
      _groupMembers[groupId] ?? const [];

  Future<void> fetchMyGroups({bool forceRefresh = false}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final groups = await _groupService.getMyGroups();
      _myGroups = groups;
      // 초기 그룹 응답에 멤버가 포함되어 있다면 멤버에 선반영
      for (final g in groups) {
        if (g.members.isNotEmpty) {
          _groupMembers[g.id] = g.members;
        }
      }
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print("그룹 목록 조회 에러: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createGroup(String name) async {
    try {
      await _groupService.createGroup(name);
      // 생성 성공 시 즉시 새로고침
      await fetchMyGroups(forceRefresh: true);
      return true;
    } catch (e) {
      print("그룹 생성 에러: $e");
      return false;
    }
  }

  Future<bool> updateGroup(int groupId, String name, String description) async {
    try {
      await _groupService.updateGroup(groupId, name, description);
      await fetchMyGroups(forceRefresh: true);
      return true;
    } catch (e) {
      print("그룹 수정 에러: $e");
      return false;
    }
  }

  Future<bool> deleteGroup(int groupId) async {
    try {
      await _groupService.deleteGroup(groupId);
      await fetchMyGroups(forceRefresh: true);
      return true;
    } catch (e) {
      print("그룹 삭제 에러: $e");
      return false;
    }
  }

  // ===== 멤버 관리 =====
  Future<void> fetchGroupMembers(
    int groupId, {
    bool forceRefresh = false,
  }) async {
    try {
      final members = await _groupService.getGroupMembers(groupId);
      _groupMembers[groupId] = members;
      notifyListeners();
    } catch (e) {
      print('그룹 멤버 조회 에러: $e');
      // 에러 시에도 빈 배열로 설정
      _groupMembers[groupId] = _groupMembers[groupId] ?? <GroupMember>[];
      notifyListeners();
    }
  }

  Future<bool> addMember(int groupId, String userId) async {
    try {
      await _groupService.addMemberToGroup(groupId, userId);
      await fetchGroupMembers(groupId, forceRefresh: true);
      return true;
    } catch (e) {
      print('멤버 추가 에러: $e');
      return false;
    }
  }

  Future<bool> removeMember(int groupId, String userId) async {
    try {
      await _groupService.removeMemberFromGroup(groupId, userId);
      await fetchGroupMembers(groupId, forceRefresh: true);
      return true;
    } catch (e) {
      print('멤버 제거 에러: $e');
      return false;
    }
  }

  /// 로그아웃 시 모든 그룹 데이터 초기화
  void logout() {
    _myGroups.clear();
    _isLoading = false;
    _groupMembers.clear();
    notifyListeners();
    print('[GroupProvider] 로그아웃 - 그룹 데이터 초기화 완료');
  }
}
