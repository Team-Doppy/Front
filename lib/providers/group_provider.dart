// lib/providers/group_provider.dart
import 'package:flutter/material.dart';
import '../data/models/group_model.dart';
import '../data/services/group_service.dart';

class GroupProvider with ChangeNotifier {
  final GroupService _groupService = GroupService();

  List<Group> _myGroups = [];
  bool _isLoading = false;
  DateTime? _lastFetchedAt;
  Duration _ttl = const Duration(minutes: 5);

  List<Group> get myGroups => _myGroups;
  bool get isLoading => _isLoading;
  bool get _isCacheValid =>
      _lastFetchedAt != null &&
      DateTime.now().difference(_lastFetchedAt!) < _ttl &&
      _myGroups.isNotEmpty;

  /// 외부에서 캐시 TTL 조정 가능
  void setCacheTtl(Duration ttl) {
    _ttl = ttl;
  }

  /// 캐시 무효화(그룹 생성/수정/삭제 후 호출)
  void invalidateGroupsCache() {
    _lastFetchedAt = null;
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
}
