// lib/providers/group_provider.dart
import 'package:flutter/material.dart';
import '../data/models/group_model.dart';
import '../data/models/group_member_model.dart';
import '../data/models/user_model.dart';
import '../data/services/group_service.dart';
import '../data/services/auth_service.dart';
import 'friend_provider.dart';

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

  // 🎯 allFriends 그룹 메타데이터 캐시 (이미지 수정/순서 변경 시 사용)
  int? _allFriendsGroupId;
  @pragma('vm:entry-point')
  @pragma('vm:entry-point')
  // Getters
  List<Group> get myGroups => _cachedGroups;
  bool get isLoading => _isLoadingGroups;
  bool get isGroupsCached => _isGroupsCached;
  int? get allFriendsGroupId => _allFriendsGroupId;

  List<GroupMember> membersOf(int groupId) =>
      _cachedGroupMembers[groupId] ?? const [];

  bool isMembersCached(int groupId) => _isMembersCached[groupId] ?? false;

  bool isLoadingMembers(int groupId) => _isLoadingMembers[groupId] ?? false;

  /// 📋 그룹 목록 조회 (스키마만 - memberCount + memberThumbnails 포함)
  /// forceRefresh: true면 캐시 무시하고 서버에서 다시 받아옴
  /// friendProvider: 친구 수 조회용 (allFriends 그룹 생성 시 사용)
  Future<void> fetchMyGroups({
    bool forceRefresh = false,
    FriendProvider? friendProvider,
  }) async {
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

      // 🎯 서버에서 그룹 목록 조회
      final result = await _groupService.getMyGroups();

      final groups = result.$1;
      final allFriendsDisplayOrder = result.$2;
      final allFriendsImage = result.$3;
      final allFriendsGroupId = result.$4;
      final totalFriendCount = result.$5;
      final allFriendsDescription = result.$6;

      _allFriendsGroupId = allFriendsGroupId;

      // 🎯 가상 allFriends 그룹 생성 (서버 데이터 사용)
      final allFriendsGroup = await _createVirtualAllFriendsGroup(
        allFriendsDisplayOrder,
        allFriendsImage,
        allFriendsGroupId,
        totalFriendCount,
        allFriendsDescription,
        friendProvider,
      );

      // 🎯 모든 그룹을 displayOrder로 정렬 (allFriends 포함)
      // 서버에서 받은 groups는 이미 displayOrder 순서로 정렬되어 있음
      final allGroups = <Group>[];

      // 🎯 allFriends 그룹을 올바른 위치에 삽입 (displayOrder 기반)
      if (allFriendsGroup != null) {
        bool inserted = false;
        // displayOrder 순서대로 삽입
        for (int i = 0; i < groups.length; i++) {
          // allFriends의 displayOrder 위치에 삽입
          // displayOrder가 i와 같거나 작으면 allFriends를 앞에 삽입
          if (!inserted && allFriendsDisplayOrder <= i) {
            allGroups.add(allFriendsGroup);
            inserted = true;
          }
          allGroups.add(groups[i]);
        }
        // 아직 삽입되지 않았으면 마지막에 추가
        if (!inserted) {
          allGroups.add(allFriendsGroup);
        }
      } else {
        // allFriends 그룹이 없으면 기존 그룹만 사용
        allGroups.addAll(groups);
      }

      _cachedGroups = allGroups;
      _isGroupsCached = true;

      print(
        '✅ [GroupProvider] 그룹 목록 캐시 완료 - ${_cachedGroups.length}개 (allFriends 포함)',
      );
    } catch (e) {
      print('❌ [GroupProvider] 그룹 목록 조회 에러: $e');
      _isGroupsCached = false;
    } finally {
      _isLoadingGroups = false;
      notifyListeners();
    }
  }

  /// 🎯 가상 allFriends 그룹 생성
  Future<Group?> _createVirtualAllFriendsGroup(
    int displayOrder,
    String? imageUrl,
    int? groupId,
    int? totalFriendCountFromServer,
    String? descriptionFromServer,
    FriendProvider? friendProvider,
  ) async {
    // 🎯 서버에서 받은 totalFriendCount 우선 사용, 없으면 friendProvider 사용, 둘 다 없으면 0
    final totalFriendCount =
        totalFriendCountFromServer ??
        friendProvider?.acceptedFriends.length ??
        0;

    // 🎯 allFriendsGroupId가 null이면 임시 ID(-1) 사용
    final virtualGroupId = groupId ?? -1;

    // 🎯 현재 사용자 정보 조회 (ownerId 설정용)
    final authService = AuthService();
    final currentUsername = authService.currentUsernameSync ?? '';

    // 🎯 서버에서 받은 데이터 사용 (description도 서버에서 받은 값 사용)
    return Group(
      id: virtualGroupId,
      name: 'allFriends',
      description: descriptionFromServer ?? '모든 친구', // 🎯 서버에서 받은 값 사용
      ownerId: currentUsername,
      owner: User(username: currentUsername, alias: currentUsername),
      createdAt: DateTime.now(), // 가상 그룹이므로 현재 시간 사용
      members: const [],
      profileImageUrl: imageUrl, // 🎯 서버에서 받은 이미지 URL 사용 (로컬 파일 경로 포함)
      memberCount: totalFriendCount, // 🎯 서버에서 받은 값 사용
      postCount: null, // 🎯 allFriends는 서버 응답에 postCount가 없으므로 null (필요시 별도 처리)
      memberThumbnails: null,
      isSystem: true, // 시스템 그룹으로 표시
    );
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

  Future<bool> updateGroup(
    int groupId,
    String name,
    String description, {
    String? profileImageUrl, // 🎯 프로필 이미지 URL
  }) async {
    try {
      print('🔄 [GroupProvider] 그룹 수정 시작: $groupId');

      // 🎯 시스템 그룹(전체 친구)은 항상 -1을 ID로 받음 (서버가 알아서 처리)
      final bool isAllFriendsGroup = groupId == -1;

      if (isAllFriendsGroup) {
        await _groupService.updateAllFriendsGroup(
          description: description,
          groupImage: profileImageUrl,
        );
      } else {
        await _groupService.updateGroup(
          groupId,
          name,
          description,
          profileImageUrl: profileImageUrl, // 🎯 이미지 URL 전달
        );
      }

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
      // 🎯 실패 시에도 빈 배열로 캐시하여 재시도 방지 (무한 재시도 방지)
      _cachedGroupMembers[groupId] = <GroupMember>[];
      _isMembersCached[groupId] = true; // 캐시된 것으로 표시하여 재시도 방지
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
      // 🎯 멤버 목록 조회 (실패해도 멤버 추가는 성공한 것으로 간주, 재시도 방지)
      try {
        await fetchGroupMembers(groupId, forceRefresh: true);
      } catch (e) {
        // 멤버 목록 조회 실패해도 멤버 추가 자체는 성공한 것으로 간주
        print('⚠️ [GroupProvider] 멤버 추가 성공했으나 목록 조회 실패 (무시): $e');
      }

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
      // 🎯 멤버 목록 조회 (실패해도 멤버 제거는 성공한 것으로 간주, 재시도 방지)
      try {
        await fetchGroupMembers(groupId, forceRefresh: true);
      } catch (e) {
        // 멤버 목록 조회 실패해도 멤버 제거 자체는 성공한 것으로 간주
        print('⚠️ [GroupProvider] 멤버 제거 성공했으나 목록 조회 실패 (무시): $e');
      }

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

      // 🎯 멤버 삭제 API 호출 (실패 시 즉시 false 반환)
      await _groupService.removeMembersFromGroupBatch(groupId, usernames);

      // 🎯 멤버 삭제 성공 후에만 그룹 스키마 업데이트 시도 (실패해도 무시)
      try {
        await _invalidateAndRefreshGroups();
      } catch (e) {
        print('⚠️ [GroupProvider] 멤버 일괄 제거 성공했으나 그룹 스키마 업데이트 실패 (무시): $e');
      }

      // 🎯 해당 그룹의 멤버 캐시 무효화
      _isMembersCached[groupId] = false;
      // 🎯 멤버 목록 조회 (실패해도 멤버 일괄 제거는 성공한 것으로 간주, 재시도 방지)
      try {
        await fetchGroupMembers(groupId, forceRefresh: true);
      } catch (e) {
        // 멤버 목록 조회 실패해도 멤버 일괄 제거 자체는 성공한 것으로 간주
        print('⚠️ [GroupProvider] 멤버 일괄 제거 성공했으나 목록 조회 실패 (무시): $e');
      }

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

  /// 🔄 그룹 순서 변경 (드래그 앤 드롭)
  Future<bool> reorderGroups(List<Map<String, dynamic>> groups) async {
    try {
      print('🔄 [GroupProvider] 그룹 순서 변경 시작: ${groups.length}개');
      final reorderedGroups = await _groupService.reorderGroups(groups);

      // 🎯 캐시 업데이트
      _cachedGroups = reorderedGroups;
      _isGroupsCached = true;

      notifyListeners();
      print('✅ [GroupProvider] 그룹 순서 변경 완료');
      return true;
    } catch (e) {
      print('❌ [GroupProvider] 그룹 순서 변경 에러: $e');
      return false;
    }
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
