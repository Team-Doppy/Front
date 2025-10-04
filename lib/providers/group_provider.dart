// lib/providers/group_provider.dart
import 'package:flutter/material.dart';
import '../data/models/group_model.dart';
import '../data/models/group_member_model.dart';
import '../data/services/group_service.dart';

class GroupProvider with ChangeNotifier {
  final GroupService _groupService = GroupService();

  List<Group> _myGroups = [];
  bool _isLoading = false;
  DateTime? _lastFetchedAt;
  Duration _ttl = const Duration(days: 3650); // 사실상 무기한 캐시

  // 그룹별 멤버 캐시
  final Map<int, List<GroupMember>> _groupMembers = {};
  final Map<int, DateTime> _groupMembersFetchedAt = {};
  final Duration _membersTtl = const Duration(minutes: 3);

  List<Group> get myGroups => _myGroups;
  bool get isLoading => _isLoading;
  bool get _isCacheValid =>
      _lastFetchedAt != null &&
      DateTime.now().difference(_lastFetchedAt!) < _ttl &&
      _myGroups.isNotEmpty;

  List<GroupMember> membersOf(int groupId) =>
      _groupMembers[groupId] ?? const [];

  /// 외부에서 캐시 TTL 조정 가능
  void setCacheTtl(Duration ttl) {
    _ttl = ttl;
  }

  /// 캐시 무효화(그룹 생성/수정/삭제 후 호출)
  void invalidateGroupsCache() {
    _lastFetchedAt = null;
  }

  /// 특정 그룹의 멤버 캐시 무효화
  void invalidateMembersCache(int groupId) {
    _groupMembersFetchedAt.remove(groupId);
  }

  Future<void> fetchMyGroups({bool forceRefresh = false}) async {
    // 캐시가 유효하고 강제 새로고침이 아니면 네트워크 생략
    if (!forceRefresh && _isCacheValid) {
      // 필요 시 가벼운 notify (UI 반영)
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();
    try {
      final groups = await _groupService.getMyGroups();
      _myGroups = groups;
      _lastFetchedAt = DateTime.now();
      // 초기 그룹 응답에 멤버가 포함되어 있다면 멤버 캐시에 선반영
      for (final g in groups) {
        if (g.members.isNotEmpty) {
          _groupMembers[g.id] = g.members;
          _groupMembersFetchedAt[g.id] = DateTime.now();
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
      // 생성 성공 시 캐시 무효화 후 즉시 새로고침
      invalidateGroupsCache();
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
      invalidateGroupsCache();
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
      invalidateGroupsCache();
      await fetchMyGroups(forceRefresh: true);
      return true;
    } catch (e) {
      print("그룹 삭제 에러: $e");
      return false;
    }
  }

  // ===== 멤버 관리 =====
  bool _isMembersCacheValid(int groupId) {
    final fetchedAt = _groupMembersFetchedAt[groupId];
    if (fetchedAt == null) return false;
    // 빈 배열도 TTL 동안은 유효로 간주(불필요한 재호출 방지)
    return DateTime.now().difference(fetchedAt) < _membersTtl;
  }

  Future<void> fetchGroupMembers(
    int groupId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _isMembersCacheValid(groupId)) {
      notifyListeners();
      return;
    }
    try {
      final members = await _groupService.getGroupMembers(groupId);
      _groupMembers[groupId] = members;
      _groupMembersFetchedAt[groupId] = DateTime.now();
      notifyListeners();
    } catch (e) {
      print('그룹 멤버 조회 에러: $e');
      // 에러 시에도 최소 TTL 동안은 재호출 방지를 위해 빈 배열 캐시
      _groupMembers[groupId] = _groupMembers[groupId] ?? <GroupMember>[];
      _groupMembersFetchedAt[groupId] = DateTime.now();
      notifyListeners();
    }
  }

  Future<bool> addMember(int groupId, String userId) async {
    try {
      await _groupService.addMemberToGroup(groupId, userId);
      invalidateMembersCache(groupId);
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
      invalidateMembersCache(groupId);
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
    _lastFetchedAt = null;
    _groupMembers.clear();
    _groupMembersFetchedAt.clear();
    notifyListeners();
    print('[GroupProvider] 로그아웃 - 그룹 데이터 초기화 완료');
  }
}
