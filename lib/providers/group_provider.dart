// lib/providers/group_provider.dart
import 'package:flutter/material.dart';
import '../data/models/group_model.dart';
import '../data/services/group_service.dart';

class GroupProvider with ChangeNotifier {
  final GroupService _groupService = GroupService();

  List<Group> _myGroups = [];
  bool _isLoading = false;

  List<Group> get myGroups => _myGroups;
  bool get isLoading => _isLoading;

  Future<void> fetchMyGroups() async {
    _isLoading = true;
    notifyListeners();
    try {
      _myGroups = await _groupService.getMyGroups();
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
      // 그룹 생성 성공 후, 목록을 새로고침하여 바로 반영
      await fetchMyGroups();
      return true;
    } catch (e) {
      print("그룹 생성 에러: $e");
      return false;
    }
  }
}