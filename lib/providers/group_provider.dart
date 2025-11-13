// lib/providers/group_provider.dart
import 'package:flutter/material.dart';
import '../data/models/group_model.dart';
import '../data/models/group_member_model.dart';
import '../data/services/group_service.dart';

class GroupProvider with ChangeNotifier {
  // 🎯 싱글톤 패턴
  static final GroupProvider _instance = GroupProvider._internal();
  factory GroupProvider() => _instance;
  GroupProvider._internal();

  final GroupService _groupService = GroupService();

  // 🎯 그룹 스키마 캐시 (기본 정보 + memberCount + memberThumbnails)
  List<Group> _cachedGroups = [];
  bool _isGroupsCached = false;
  bool _isLoadingGroups = false;

  // 🎯 그룹별 멤버 상세 캐시 (별도 API로 조회)
  final Map<int, List<GroupMember>> _cachedGroupMembers = {};
  final Map<int, bool> _isMembersCached = {};
  final Map<int, bool> _isLoadingMembers = {};

  // Getters
  List<Group> get myGroups => _cachedGroups;
  bool get isLoading => _isLoadingGroups;
  bool get isGroupsCached => _isGroupsCached;

  List<GroupMember> membersOf(int groupId) =>
      _cachedGroupMembers[groupId] ?? const [];

  bool isMembersCached(int groupId) => _isMembersCached[groupId] ?? false;

  bool isLoadingMembers(int groupId) => _isLoadingMembers[groupId] ?? false;

  /// 📋 그룹 목록 조회 (스키마만 - memberCount + memberThumbnails 포함)
  /// forceRefresh: true면 캐시 무시하고 서버에서 다시 받아옴
  Future<void> fetchMyGroups({bool forceRefresh = false}) async {
    // 이미 캐시되어 있고 forceRefresh가 아니면 스킵
    if (_isGroupsCached && !forceRefresh) {
      print('✅ [GroupProvider] 그룹 목록 캐시 사용');
      return;
    }

    // 이미 로딩 중이면 중복 요청 방지
    if (_isLoadingGroups) {
      print('⚠️ [GroupProvider] 그룹 목록 로딩 중 - 중복 요청 무시');
      return;
    }

    _isLoadingGroups = true;
    notifyListeners();

    try {
      print('🔄 [GroupProvider] 그룹 목록 서버에서 조회 시작');
      final groups = await _groupService.getMyGroups();

      _cachedGroups = groups;
      _isGroupsCached = true;

      print('✅ [GroupProvider] 그룹 목록 캐시 완료 - ${_cachedGroups.length}개');
    } catch (e) {
      print('❌ [GroupProvider] 그룹 목록 조회 에러: $e');
      _isGroupsCached = false;
    } finally {
      _isLoadingGroups = false;
      notifyListeners();
    }
  }

  /// 🆕 그룹 생성 → 캐시 무효화 및 재조회
  Future<bool> createGroup(
    String name, {
    String? description, // 🎯 그룹 설명 추가
    String? profileImageUrl, // 🎯 프로필 이미지 URL
  }) async {
    try {
      print('🔄 [GroupProvider] 그룹 생성 시작: $name');
      await _groupService.createGroup(
        name,
        description: description,
        profileImageUrl: profileImageUrl,
      );

      // 🎯 캐시 무효화 및 재조회
      await _invalidateAndRefreshGroups();

      print('✅ [GroupProvider] 그룹 생성 완료');
      return true;
    } catch (e) {
      print('❌ [GroupProvider] 그룹 생성 에러: $e');
      return false;
    }
  }

  /// ✏️ 그룹 수정 → 캐시 무효화 및 재조회
  Future<bool> updateGroup(int groupId, String name, String description) async {
    try {
      print('🔄 [GroupProvider] 그룹 수정 시작: $groupId');
      await _groupService.updateGroup(groupId, name, description);

      // 🎯 캐시 무효화 및 재조회
      await _invalidateAndRefreshGroups();

      print('✅ [GroupProvider] 그룹 수정 완료');
      return true;
    } catch (e) {
      print('❌ [GroupProvider] 그룹 수정 에러: $e');
      return false;
    }
  }

  /// 🗑️ 그룹 삭제 → 캐시 무효화 및 재조회
  Future<bool> deleteGroup(int groupId) async {
    try {
      print('🔄 [GroupProvider] 그룹 삭제 시작: $groupId');
      await _groupService.deleteGroup(groupId);

      // 🎯 캐시 무효화 및 재조회
      await _invalidateAndRefreshGroups();

      // 해당 그룹의 멤버 캐시도 삭제
      _cachedGroupMembers.remove(groupId);
      _isMembersCached.remove(groupId);
      _isLoadingMembers.remove(groupId);

      print('✅ [GroupProvider] 그룹 삭제 완료');
      return true;
    } catch (e) {
      print('❌ [GroupProvider] 그룹 삭제 에러: $e');
      return false;
    }
  }

  // ===== 그룹 멤버 상세 조회 (별도 엔드포인트) =====

  /// 📋 그룹 멤버 상세 조회 (캐시 사용)
  Future<void> fetchGroupMembers(
    int groupId, {
    bool forceRefresh = false,
  }) async {
    // 이미 캐시되어 있고 forceRefresh가 아니면 스킵
    if ((_isMembersCached[groupId] ?? false) && !forceRefresh) {
      print('✅ [GroupProvider] 그룹 $groupId 멤버 캐시 사용');
      return;
    }

    // 이미 로딩 중이면 중복 요청 방지
    if (_isLoadingMembers[groupId] ?? false) {
      print('⚠️ [GroupProvider] 그룹 $groupId 멤버 로딩 중 - 중복 요청 무시');
      return;
    }

    _isLoadingMembers[groupId] = true;
    notifyListeners();

    try {
      print('🔄 [GroupProvider] 그룹 $groupId 멤버 서버에서 조회 시작');
      final members = await _groupService.getGroupMembers(groupId);

      _cachedGroupMembers[groupId] = members;
      _isMembersCached[groupId] = true;

      print('✅ [GroupProvider] 그룹 $groupId 멤버 캐시 완료 - ${members.length}개');
    } catch (e) {
      print('❌ [GroupProvider] 그룹 $groupId 멤버 조회 에러: $e');
      _cachedGroupMembers[groupId] = <GroupMember>[];
      _isMembersCached[groupId] = false;
    } finally {
      _isLoadingMembers[groupId] = false;
      notifyListeners();
    }
  }

  /// ➕ 멤버 추가 → 그룹 스키마 & 멤버 캐시 무효화
  Future<bool> addMember(int groupId, String userId) async {
    try {
      print('🔄 [GroupProvider] 그룹 $groupId에 멤버 추가: $userId');
      await _groupService.addMemberToGroup(groupId, userId);

      // 🎯 그룹 스키마 무효화 (memberCount 변경)
      await _invalidateAndRefreshGroups();

      // 🎯 해당 그룹의 멤버 캐시 무효화
      _isMembersCached[groupId] = false;
      await fetchGroupMembers(groupId, forceRefresh: true);

      print('✅ [GroupProvider] 멤버 추가 완료');
      return true;
    } catch (e) {
      print('❌ [GroupProvider] 멤버 추가 에러: $e');
      return false;
    }
  }

  /// ➖ 멤버 제거 → 그룹 스키마 & 멤버 캐시 무효화
  Future<bool> removeMember(int groupId, String userId) async {
    try {
      print('🔄 [GroupProvider] 그룹 $groupId에서 멤버 제거: $userId');
      await _groupService.removeMemberFromGroup(groupId, userId);

      // 🎯 그룹 스키마 무효화 (memberCount 변경)
      await _invalidateAndRefreshGroups();

      // 🎯 해당 그룹의 멤버 캐시 무효화
      _isMembersCached[groupId] = false;
      await fetchGroupMembers(groupId, forceRefresh: true);

      print('✅ [GroupProvider] 멤버 제거 완료');
      return true;
    } catch (e) {
      print('❌ [GroupProvider] 멤버 제거 에러: $e');
      return false;
    }
  }

  /// ➖ 여러 멤버 일괄 제거 (배치) → 그룹 스키마 & 멤버 캐시 무효화
  Future<bool> removeMembersBatch(int groupId, List<String> usernames) async {
    try {
      print('🔄 [GroupProvider] 그룹 $groupId에서 멤버 일괄 제거: ${usernames.length}명');
      await _groupService.removeMembersFromGroupBatch(groupId, usernames);

      // 🎯 그룹 스키마 무효화 (memberCount 변경)
      await _invalidateAndRefreshGroups();

      // 🎯 해당 그룹의 멤버 캐시 무효화
      _isMembersCached[groupId] = false;
      await fetchGroupMembers(groupId, forceRefresh: true);

      print('✅ [GroupProvider] 멤버 일괄 제거 완료');
      return true;
    } catch (e) {
      print('❌ [GroupProvider] 멤버 일괄 제거 에러: $e');
      return false;
    }
  }

  // ===== 헬퍼 메서드 =====

  /// 🎯 그룹 스키마 캐시 무효화 및 재조회
  Future<void> _invalidateAndRefreshGroups() async {
    print('🔄 [GroupProvider] 그룹 스키마 캐시 무효화 및 재조회');
    _isGroupsCached = false;
    await fetchMyGroups(forceRefresh: true);
  }

  /// 🗑️ 모든 캐시 초기화
  void clearAllCache() {
    print('🗑️ [GroupProvider] 모든 캐시 초기화');

    _cachedGroups.clear();
    _isGroupsCached = false;
    _isLoadingGroups = false;

    _cachedGroupMembers.clear();
    _isMembersCached.clear();
    _isLoadingMembers.clear();

    notifyListeners();
  }

  /// 🚪 로그아웃 시 모든 데이터 초기화
  void logout() {
    print('🚪 [GroupProvider] 로그아웃 - 모든 데이터 초기화');
    clearAllCache();
  }
}
