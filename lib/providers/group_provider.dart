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

  // 🎯 스마트 감지기: 최근 포스트가 추가/삭제된 그룹 ID 추적
  final Set<int> _recentlyUpdatedGroupIds = {};

  @pragma('vm:entry-point')
  @pragma('vm:entry-point')
  // Getters
  List<Group> get myGroups => _cachedGroups;
  bool get isLoading => _isLoadingGroups;
  bool get isGroupsCached => _isGroupsCached;
  int? get allFriendsGroupId => _allFriendsGroupId;

  /// 🎯 최근 업데이트된 그룹 ID 목록 (스마트 감지기용)
  Set<int> get recentlyUpdatedGroupIds =>
      Set<int>.from(_recentlyUpdatedGroupIds);

  /// 🎯 특정 그룹의 업데이트 상태를 확인하고 제거 (한 번만 감지)
  bool checkAndClearGroupUpdate(int groupId) {
    if (_recentlyUpdatedGroupIds.contains(groupId)) {
      _recentlyUpdatedGroupIds.remove(groupId);
      return true;
    }
    return false;
  }

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
      debugPrint('✅ [GroupProvider] 그룹 목록 캐시 사용');
      return;
    }

    // 이미 로딩 중이면 중복 요청 방지
    if (_isLoadingGroups) {
      debugPrint('⚠️ [GroupProvider] 그룹 목록 로딩 중 - 중복 요청 무시');
      return;
    }

    _isLoadingGroups = true;
    notifyListeners();

    try {
      debugPrint('🔄 [GroupProvider] 그룹 목록 서버에서 조회 시작');

      // 🎯 서버에서 그룹 목록 조회
      final result = await _groupService.getMyGroups();

      final groups = result.$1;
      final allFriendsDisplayOrder = result.$2;
      final allFriendsImage = result.$3;
      final allFriendsGroupId = result.$4;
      final totalFriendCount = result.$5;
      final allFriendsDescription = result.$6;
      final allFriendsPostCount = result.$7;

      _allFriendsGroupId = allFriendsGroupId;

      // 🎯 가상 allFriends 그룹 생성 (서버 데이터 사용)
      final allFriendsGroup = await _createVirtualAllFriendsGroup(
        allFriendsDisplayOrder,
        allFriendsImage,
        allFriendsGroupId,
        totalFriendCount,
        allFriendsDescription,
        allFriendsPostCount,
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

      debugPrint(
        '✅ [GroupProvider] 그룹 목록 캐시 완료 - ${_cachedGroups.length}개 (allFriends 포함)',
      );
    } catch (e) {
      debugPrint('❌ [GroupProvider] 그룹 목록 조회 에러: $e');
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
    int? allFriendsPostCountFromServer,
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
      postCount: allFriendsPostCountFromServer, // 🎯 전체 친구 그룹에 공유된 포스트 수
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
      debugPrint('🔄 [GroupProvider] 그룹 생성 시작: $name');
      await _groupService.createGroup(
        name,
        description: description,
        profileImageUrl: profileImageUrl,
      );

      // 🎯 캐시 무효화 및 재조회
      await _invalidateAndRefreshGroups();

      debugPrint('✅ [GroupProvider] 그룹 생성 완료');
      return true;
    } catch (e) {
      debugPrint('❌ [GroupProvider] 그룹 생성 에러: $e');
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
      debugPrint('🔄 [GroupProvider] 그룹 수정 시작: $groupId');

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

      debugPrint('✅ [GroupProvider] 그룹 수정 완료');
      return true;
    } catch (e) {
      debugPrint('❌ [GroupProvider] 그룹 수정 에러: $e');
      return false;
    }
  }

  /// 🗑️ 그룹 삭제 → 캐시 무효화 및 재조회
  Future<bool> deleteGroup(int groupId) async {
    try {
      debugPrint('🔄 [GroupProvider] 그룹 삭제 시작: $groupId');
      await _groupService.deleteGroup(groupId);

      // 🎯 캐시 무효화 및 재조회
      await _invalidateAndRefreshGroups();

      // 해당 그룹의 멤버 캐시도 삭제
      _cachedGroupMembers.remove(groupId);
      _isMembersCached.remove(groupId);
      _isLoadingMembers.remove(groupId);

      debugPrint('✅ [GroupProvider] 그룹 삭제 완료');
      return true;
    } catch (e) {
      debugPrint('❌ [GroupProvider] 그룹 삭제 에러: $e');
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
      debugPrint('✅ [GroupProvider] 그룹 $groupId 멤버 캐시 사용');
      return;
    }

    // 이미 로딩 중이면 중복 요청 방지
    if (_isLoadingMembers[groupId] ?? false) {
      debugPrint('⚠️ [GroupProvider] 그룹 $groupId 멤버 로딩 중 - 중복 요청 무시');
      return;
    }

    _isLoadingMembers[groupId] = true;
    notifyListeners();

    try {
      debugPrint('🔄 [GroupProvider] 그룹 $groupId 멤버 서버에서 조회 시작');
      final members = await _groupService.getGroupMembers(groupId);

      _cachedGroupMembers[groupId] = members;
      _isMembersCached[groupId] = true;

      debugPrint('✅ [GroupProvider] 그룹 $groupId 멤버 캐시 완료 - ${members.length}개');
    } catch (e) {
      debugPrint('❌ [GroupProvider] 그룹 $groupId 멤버 조회 에러: $e');
      // 🎯 실패 시에도 빈 배열로 캐시하여 재시도 방지 (무한 재시도 방지)
      _cachedGroupMembers[groupId] = <GroupMember>[];
      _isMembersCached[groupId] = true; // 캐시된 것으로 표시하여 재시도 방지
    } finally {
      _isLoadingMembers[groupId] = false;
      notifyListeners();
    }
  }

  /// ➕ 멤버 추가 → 선택적 업데이트 (전체 재조회 생략)
  Future<bool> addMember(int groupId, String userId) async {
    try {
      debugPrint('🔄 [GroupProvider] 그룹 $groupId에 멤버 추가: $userId');
      await _groupService.addMemberToGroup(groupId, userId);

      // 🎯 선택적 업데이트: memberCount만 로컬 업데이트 (전체 재조회 생략)
      updateGroupMemberCount(groupId, 1);

      // 🎯 해당 그룹의 멤버 캐시 무효화
      _isMembersCached[groupId] = false;
      // 🎯 멤버 목록 조회 (실패해도 멤버 추가는 성공한 것으로 간주, 재시도 방지)
      try {
        await fetchGroupMembers(groupId, forceRefresh: true);
      } catch (e) {
        // 멤버 목록 조회 실패해도 멤버 추가 자체는 성공한 것으로 간주
        debugPrint('⚠️ [GroupProvider] 멤버 추가 성공했으나 목록 조회 실패 (무시): $e');
      }

      debugPrint('✅ [GroupProvider] 멤버 추가 완료');
      return true;
    } catch (e) {
      debugPrint('❌ [GroupProvider] 멤버 추가 에러: $e');
      return false;
    }
  }

  /// ➕ 여러 멤버 일괄 추가 (배치) → 선택적 업데이트 (전체 재조회 생략)
  Future<bool> addMembersBatch(int groupId, List<String> usernames) async {
    try {
      debugPrint(
        '🔄 [GroupProvider] 그룹 $groupId에 멤버 일괄 추가: ${usernames.length}명',
      );

      // 🎯 멤버 일괄 추가 API 호출 (실패 시 즉시 false 반환)
      await _groupService.addMultipleMembersToGroup(groupId, usernames);

      // 🎯 선택적 업데이트: memberCount만 로컬 업데이트 (전체 재조회 생략)
      updateGroupMemberCount(groupId, usernames.length);

      // 🎯 해당 그룹의 멤버 캐시 무효화
      _isMembersCached[groupId] = false;
      // 🎯 멤버 목록 조회 (실패해도 멤버 일괄 추가는 성공한 것으로 간주, 재시도 방지)
      try {
        await fetchGroupMembers(groupId, forceRefresh: true);
      } catch (e) {
        // 멤버 목록 조회 실패해도 멤버 일괄 추가 자체는 성공한 것으로 간주
        debugPrint('⚠️ [GroupProvider] 멤버 일괄 추가 성공했으나 목록 조회 실패 (무시): $e');
      }

      debugPrint('✅ [GroupProvider] 멤버 일괄 추가 완료');
      return true;
    } catch (e) {
      debugPrint('❌ [GroupProvider] 멤버 일괄 추가 에러: $e');
      return false;
    }
  }

  /// ➖ 멤버 제거 → 선택적 업데이트 (전체 재조회 생략)
  Future<bool> removeMember(int groupId, String userId) async {
    try {
      debugPrint('🔄 [GroupProvider] 그룹 $groupId에서 멤버 제거: $userId');
      await _groupService.removeMemberFromGroup(groupId, userId);

      // 🎯 선택적 업데이트: memberCount만 로컬 업데이트 (전체 재조회 생략)
      updateGroupMemberCount(groupId, -1);

      // 🎯 해당 그룹의 멤버 캐시 무효화
      _isMembersCached[groupId] = false;
      // 🎯 멤버 목록 조회 (실패해도 멤버 제거는 성공한 것으로 간주, 재시도 방지)
      try {
        await fetchGroupMembers(groupId, forceRefresh: true);
      } catch (e) {
        // 멤버 목록 조회 실패해도 멤버 제거 자체는 성공한 것으로 간주
        debugPrint('⚠️ [GroupProvider] 멤버 제거 성공했으나 목록 조회 실패 (무시): $e');
      }

      debugPrint('✅ [GroupProvider] 멤버 제거 완료');
      return true;
    } catch (e) {
      debugPrint('❌ [GroupProvider] 멤버 제거 에러: $e');
      return false;
    }
  }

  /// ➖ 여러 멤버 일괄 제거 (배치) → 선택적 업데이트 (전체 재조회 생략)
  Future<bool> removeMembersBatch(int groupId, List<String> usernames) async {
    try {
      debugPrint(
        '🔄 [GroupProvider] 그룹 $groupId에서 멤버 일괄 제거: ${usernames.length}명',
      );

      // 🎯 멤버 삭제 API 호출 (실패 시 즉시 false 반환)
      await _groupService.removeMembersFromGroupBatch(groupId, usernames);

      // 🎯 로컬 캐시에서 제거된 멤버들을 즉시 제거 (낙관적 업데이트)
      if (_cachedGroupMembers.containsKey(groupId)) {
        final currentMembers = _cachedGroupMembers[groupId] ?? [];
        _cachedGroupMembers[groupId] =
            currentMembers
                .where((member) => !usernames.contains(member.userId))
                .toList();
        debugPrint(
          '🔄 [GroupProvider] 로컬 캐시에서 ${usernames.length}명 제거: ${currentMembers.length} → ${_cachedGroupMembers[groupId]!.length}',
        );
        notifyListeners(); // 🎯 UI 즉시 업데이트
      }

      // 🎯 선택적 업데이트: memberCount만 로컬 업데이트 (전체 재조회 생략)
      updateGroupMemberCount(groupId, -usernames.length);

      // 🎯 해당 그룹의 멤버 캐시 무효화
      _isMembersCached[groupId] = false;
      // 🎯 서버 동기화를 위해 짧은 지연 후 멤버 목록 조회
      try {
        await Future.delayed(const Duration(milliseconds: 300)); // 🎯 서버 반영 대기
        await fetchGroupMembers(groupId, forceRefresh: true);
      } catch (e) {
        // 멤버 목록 조회 실패해도 멤버 일괄 제거 자체는 성공한 것으로 간주
        // (이미 로컬 캐시에서 제거했으므로 UI는 업데이트됨)
        debugPrint('⚠️ [GroupProvider] 멤버 일괄 제거 성공했으나 목록 조회 실패 (무시): $e');
      }

      debugPrint('✅ [GroupProvider] 멤버 일괄 제거 완료');
      return true;
    } catch (e) {
      debugPrint('❌ [GroupProvider] 멤버 일괄 제거 에러: $e');
      return false;
    }
  }

  // ===== 헬퍼 메서드 =====

  /// 🎯 그룹 스키마 캐시 무효화 및 재조회
  Future<void> _invalidateAndRefreshGroups() async {
    debugPrint('🔄 [GroupProvider] 그룹 스키마 캐시 무효화 및 재조회');
    _isGroupsCached = false;
    await fetchMyGroups(forceRefresh: true);
  }

  /// 🎯 선택적 업데이트: 특정 그룹의 memberCount만 업데이트 (서버 재조회 없음)
  /// 멤버 추가/제거 시 전체 재조회 대신 사용
  void updateGroupMemberCount(int groupId, int delta) {
    if (!_isGroupsCached) {
      debugPrint(
        '⚠️ [GroupProvider] 그룹 캐시가 없어 memberCount 업데이트 불가 - 전체 재조회 권장',
      );
      return;
    }

    final groupIndex = _cachedGroups.indexWhere((g) => g.id == groupId);
    if (groupIndex == -1) {
      debugPrint('⚠️ [GroupProvider] 그룹 $groupId를 찾을 수 없어 memberCount 업데이트 불가');
      return;
    }

    final currentGroup = _cachedGroups[groupIndex];
    final newMemberCount = (currentGroup.memberCount ?? 0) + delta;

    // 새로운 Group 객체 생성 (불변성 유지)
    final updatedGroup = Group(
      id: currentGroup.id,
      name: currentGroup.name,
      description: currentGroup.description,
      ownerId: currentGroup.ownerId,
      owner: currentGroup.owner,
      createdAt: currentGroup.createdAt,
      members: currentGroup.members,
      profileImageUrl: currentGroup.profileImageUrl,
      memberCount: newMemberCount < 0 ? 0 : newMemberCount,
      postCount: currentGroup.postCount,
      memberThumbnails: currentGroup.memberThumbnails,
      isSystem: currentGroup.isSystem,
    );

    _cachedGroups[groupIndex] = updatedGroup;
    notifyListeners();
    debugPrint(
      '✅ [GroupProvider] 그룹 $groupId memberCount 업데이트: ${currentGroup.memberCount} → $newMemberCount (delta: $delta)',
    );
  }

  /// 🎯 선택적 업데이트: 특정 그룹의 postCount만 업데이트 (서버 재조회 없음)
  /// 포스트 생성/삭제 시 전체 재조회 대신 사용
  void updateGroupPostCount(int groupId, int delta) {
    if (!_isGroupsCached) {
      debugPrint('⚠️ [GroupProvider] 그룹 캐시가 없어 postCount 업데이트 불가 - 전체 재조회 권장');
      return;
    }

    final groupIndex = _cachedGroups.indexWhere((g) => g.id == groupId);
    if (groupIndex == -1) {
      debugPrint('⚠️ [GroupProvider] 그룹 $groupId를 찾을 수 없어 postCount 업데이트 불가');
      return;
    }

    final currentGroup = _cachedGroups[groupIndex];
    final currentPostCount = currentGroup.postCount ?? 0;
    final newPostCount = currentPostCount + delta;

    // 새로운 Group 객체 생성 (불변성 유지)
    final updatedGroup = Group(
      id: currentGroup.id,
      name: currentGroup.name,
      description: currentGroup.description,
      ownerId: currentGroup.ownerId,
      owner: currentGroup.owner,
      createdAt: currentGroup.createdAt,
      members: currentGroup.members,
      profileImageUrl: currentGroup.profileImageUrl,
      memberCount: currentGroup.memberCount,
      postCount: newPostCount < 0 ? 0 : newPostCount,
      memberThumbnails: currentGroup.memberThumbnails,
      isSystem: currentGroup.isSystem,
    );

    _cachedGroups[groupIndex] = updatedGroup;
    notifyListeners();
    debugPrint(
      '✅ [GroupProvider] 그룹 $groupId postCount 업데이트: $currentPostCount → $newPostCount (delta: $delta)',
    );
  }

  /// 🎯 선택적 업데이트: 여러 그룹의 postCount를 일괄 업데이트
  /// 공개범위 변경으로 여러 그룹에 영향을 줄 때 사용
  void updateMultipleGroupsPostCount(Map<int, int> groupIdToDelta) {
    if (!_isGroupsCached) {
      debugPrint(
        '⚠️ [GroupProvider] 그룹 캐시가 없어 postCount 일괄 업데이트 불가 - 전체 재조회 권장',
      );
      return;
    }

    bool hasUpdate = false;
    for (final entry in groupIdToDelta.entries) {
      final groupId = entry.key;
      final delta = entry.value;

      // 🎯 포스트가 추가된 경우 (delta > 0)에만 스마트 감지기에 등록
      if (delta > 0) {
        _recentlyUpdatedGroupIds.add(groupId);
        debugPrint('🎯 [GroupProvider] 스마트 감지기: 그룹 $groupId 포스트 추가 감지');
      }

      final groupIndex = _cachedGroups.indexWhere((g) => g.id == groupId);
      if (groupIndex == -1) continue;

      final currentGroup = _cachedGroups[groupIndex];
      final currentPostCount = currentGroup.postCount ?? 0;
      final newPostCount = currentPostCount + delta;

      final updatedGroup = Group(
        id: currentGroup.id,
        name: currentGroup.name,
        description: currentGroup.description,
        ownerId: currentGroup.ownerId,
        owner: currentGroup.owner,
        createdAt: currentGroup.createdAt,
        members: currentGroup.members,
        profileImageUrl: currentGroup.profileImageUrl,
        memberCount: currentGroup.memberCount,
        postCount: newPostCount < 0 ? 0 : newPostCount,
        memberThumbnails: currentGroup.memberThumbnails,
        isSystem: currentGroup.isSystem,
      );

      _cachedGroups[groupIndex] = updatedGroup;
      hasUpdate = true;
      debugPrint(
        '✅ [GroupProvider] 그룹 $groupId postCount 업데이트: $currentPostCount → $newPostCount (delta: $delta)',
      );
    }

    if (hasUpdate) {
      notifyListeners();
    }
  }

  /// 🎯 allFriends 그룹의 memberCount만 업데이트 (서버 재조회 없음)
  /// 친구 수락/취소 시 사용
  void updateAllFriendsMemberCount(int delta) {
    // 🎯 캐시가 없거나 시스템 그룹을 찾을 수 없으면 무시
    // (일반적으로 앱 시작 시 이미 로드되므로, 없으면 나중에 새로고침 시 동기화됨)
    if (!_isGroupsCached) {
      return;
    }

    // 🎯 시스템 그룹(isSystem == true)을 직접 찾아서 업데이트
    final allFriendsGroupIndex = _cachedGroups.indexWhere(
      (g) => g.isSystem == true,
    );

    if (allFriendsGroupIndex == -1) {
      return;
    }

    final allFriendsGroup = _cachedGroups[allFriendsGroupIndex];
    final newMemberCount = (allFriendsGroup.memberCount ?? 0) + delta;

    // 새로운 Group 객체 생성 (불변성 유지)
    final updatedGroup = Group(
      id: allFriendsGroup.id,
      name: allFriendsGroup.name,
      description: allFriendsGroup.description,
      ownerId: allFriendsGroup.ownerId,
      owner: allFriendsGroup.owner,
      createdAt: allFriendsGroup.createdAt,
      members: allFriendsGroup.members,
      profileImageUrl: allFriendsGroup.profileImageUrl,
      memberCount: newMemberCount < 0 ? 0 : newMemberCount,
      postCount: allFriendsGroup.postCount,
      memberThumbnails: allFriendsGroup.memberThumbnails,
      isSystem: allFriendsGroup.isSystem,
    );

    _cachedGroups[allFriendsGroupIndex] = updatedGroup;
    notifyListeners();
  }

  /// FriendProvider의 acceptedFriends.length와 GroupProvider의 memberCount를 동기화
  /// 실제 친구 목록과 비교하여 누락된 친구가 포함된 커스텀 그룹들의 멤버 수도 함께 동기화
  void syncAllFriendsMemberCount(
    int actualCount, {
    FriendProvider? friendProvider,
  }) {
    if (!_isGroupsCached) {
      return;
    }

    // 🎯 시스템 그룹(isSystem == true)을 직접 찾아서 업데이트
    final allFriendsGroupIndex = _cachedGroups.indexWhere(
      (g) => g.isSystem == true,
    );

    if (allFriendsGroupIndex == -1) {
      return;
    }

    final allFriendsGroup = _cachedGroups[allFriendsGroupIndex];
    final currentMemberCount = allFriendsGroup.memberCount ?? 0;

    // 🎯 "모든 친구" 그룹의 memberCount 동기화
    bool hasUpdate = false;
    if (currentMemberCount != actualCount) {
      final updatedGroup = Group(
        id: allFriendsGroup.id,
        name: allFriendsGroup.name,
        description: allFriendsGroup.description,
        ownerId: allFriendsGroup.ownerId,
        owner: allFriendsGroup.owner,
        createdAt: allFriendsGroup.createdAt,
        members: allFriendsGroup.members,
        profileImageUrl: allFriendsGroup.profileImageUrl,
        memberCount: actualCount < 0 ? 0 : actualCount,
        postCount: allFriendsGroup.postCount,
        memberThumbnails: allFriendsGroup.memberThumbnails,
        isSystem: allFriendsGroup.isSystem,
      );

      _cachedGroups[allFriendsGroupIndex] = updatedGroup;
      hasUpdate = true;
      debugPrint(
        '✅ [GroupProvider] 전체 친구 그룹 memberCount 동기화: $currentMemberCount → $actualCount',
      );
    }

    // 🎯 실제 친구 목록과 비교하여 누락된 친구가 포함된 커스텀 그룹들의 멤버 수도 동기화
    if (friendProvider != null) {
      final actualFriendUsernames =
          friendProvider.acceptedFriends.map((f) => f.username).toSet();

      // 🎯 모든 커스텀 그룹(isSystem != true) 확인
      for (int i = 0; i < _cachedGroups.length; i++) {
        final group = _cachedGroups[i];
        // 시스템 그룹은 제외
        if (group.isSystem == true) continue;

        // 🎯 해당 그룹의 멤버 캐시 확인
        if (_cachedGroupMembers.containsKey(group.id)) {
          final groupMembers = _cachedGroupMembers[group.id] ?? [];
          final removedUsernames = <String>[];

          // 🎯 친구 목록에 없는 멤버 찾기
          for (final member in groupMembers) {
            if (!actualFriendUsernames.contains(member.userId)) {
              removedUsernames.add(member.userId);
            }
          }

          // 🎯 제거된 멤버가 있으면 그룹의 memberCount 감소 및 멤버 캐시에서 제거
          if (removedUsernames.isNotEmpty) {
            debugPrint(
              '🔄 [GroupProvider] 그룹 "${group.name}"에서 친구 목록에 없는 멤버 ${removedUsernames.length}명 발견: $removedUsernames',
            );

            // 🎯 멤버 캐시에서 제거
            _cachedGroupMembers[group.id] =
                groupMembers
                    .where(
                      (member) => !removedUsernames.contains(member.userId),
                    )
                    .toList();
            _isMembersCached[group.id] = true; // 캐시 유지 (제거된 상태로)

            // 🎯 memberCount 감소
            final currentGroupMemberCount = group.memberCount ?? 0;
            final newGroupMemberCount =
                (currentGroupMemberCount - removedUsernames.length)
                    .clamp(0, double.infinity)
                    .toInt();

            final updatedGroup = Group(
              id: group.id,
              name: group.name,
              description: group.description,
              ownerId: group.ownerId,
              owner: group.owner,
              createdAt: group.createdAt,
              members: group.members,
              profileImageUrl: group.profileImageUrl,
              memberCount: newGroupMemberCount,
              postCount: group.postCount,
              memberThumbnails: group.memberThumbnails,
              isSystem: group.isSystem,
            );

            _cachedGroups[i] = updatedGroup;
            hasUpdate = true;
          }
        }
      }
    }

    if (hasUpdate) {
      notifyListeners();
    }
  }

  /// 🔄 그룹 순서 변경 (드래그 앤 드롭)
  Future<bool> reorderGroups(List<Map<String, dynamic>> groups) async {
    try {
      debugPrint('🔄 [GroupProvider] 그룹 순서 변경 시작: ${groups.length}개');
      final reorderedGroups = await _groupService.reorderGroups(groups);

      // 🎯 캐시 업데이트
      _cachedGroups = reorderedGroups;
      _isGroupsCached = true;

      notifyListeners();
      debugPrint('✅ [GroupProvider] 그룹 순서 변경 완료');
      return true;
    } catch (e) {
      debugPrint('❌ [GroupProvider] 그룹 순서 변경 에러: $e');
      return false;
    }
  }

  /// 🗑️ 모든 캐시 초기화
  void clearAllCache() {
    debugPrint('🗑️ [GroupProvider] 모든 캐시 초기화');

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
    debugPrint('🚪 [GroupProvider] 로그아웃 - 모든 데이터 초기화');
    clearAllCache();
  }
}
