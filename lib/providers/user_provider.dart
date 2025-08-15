import 'package:flutter/material.dart';
import '../data/models/user_model.dart';
import '../data/services/user_service.dart';
import '../data/services/auth_service.dart'; // AuthService for user info

class UserProvider with ChangeNotifier {
  final UserService _userService = UserService();
  final AuthService _authService = AuthService(); // UserInfo 조회를 위해 추가

  // 내 프로필 정보
  User? _currentUser;
  int? _friendCount;
  String? _selfIntroduction;

  // 다른 사용자 프로필 정보
  User? _viewedUser;
  String? _viewedUserSelfIntroduction;

  bool _isLoading = false;

  User? get currentUser => _currentUser;
  int? get friendCount => _friendCount;
  String? get selfIntroduction => _selfIntroduction;
  User? get viewedUser => _viewedUser;
  String? get viewedUserSelfIntroduction => _viewedUserSelfIntroduction;
  bool get isLoading => _isLoading;

  /// 내 프로필 정보 전체 로드
  Future<void> fetchMyProfile() async {
    _isLoading = true;
    notifyListeners();
    try {
      final username = await _authService.getUsername();
      if (username == null) throw Exception("Not logged in");

      final results = await Future.wait([
        _authService.getUserInfo(username),
        _userService.getFriendCount(),
        _userService.getSelfIntroduction(),
      ]);
      _currentUser = results[0] as User?;
      _friendCount = results[1] as int?;
      _selfIntroduction = results[2] as String?;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 다른 사용자 프로필 정보 로드
  Future<void> fetchUserProfile(String username) async {
    _isLoading = true;
    _viewedUser = null; // 이전 정보 초기화
    _viewedUserSelfIntroduction = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _authService.getUserInfo(username),
        _userService.getOtherUserSelfIntroduction(username),
      ]);
      _viewedUser = results[0] as User?;
      _viewedUserSelfIntroduction = results[1] as String?;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}