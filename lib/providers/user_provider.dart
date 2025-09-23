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

  // 런타임 캐시: username -> User, 및 페치 시각
  final Map<String, User> _userCache = {};
  final Map<String, DateTime> _userCacheTime = {};
  Duration userCacheTtl = const Duration(minutes: 5);

  User? get currentUser => _currentUser;
  int? get friendCount => _friendCount;
  String? get selfIntroduction => _selfIntroduction;
  User? get viewedUser => _viewedUser;
  String? get viewedUserSelfIntroduction => _viewedUserSelfIntroduction;
  bool get isLoading => _isLoading;

  /// 다른 사용자 정보 설정
  void setViewedUser(User user) {
    _viewedUser = user;
    notifyListeners();
  }

  /// 내 프로필 정보 로드 (단일 엔드포인트 게이트)
  Future<void> fetchMyProfile() async {
    _isLoading = true;
    notifyListeners();
    try {
      final me = await _userService.getMyProfile();
      _currentUser = me;
      // 별도 필드가 오지 않으면 기존 API 유지 시도 (선택)
      try {
        _friendCount = await _userService.getFriendCount();
      } catch (_) {}
      try {
        _selfIntroduction = await _userService.getSelfIntroduction();
      } catch (_) {}
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 다른 사용자 프로필 정보 로드
  Future<void> fetchUserProfile(String username) async {
    _isLoading = true;
    // 캐시 유효하면 먼저 반영 (UI 즉시 표시)
    final cached = _userCache[username];
    final cachedAt = _userCacheTime[username];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < userCacheTtl) {
      _viewedUser = cached;
    }
    notifyListeners();
    try {
      final results = await Future.wait([
        _authService.getUserInfo(username),
        _userService.getOtherUserSelfIntroduction(username),
      ]);
      final user = results[0] as User?;
      _viewedUser = user;
      _viewedUserSelfIntroduction = results[1] as String?;
      if (user != null) {
        _userCache[username] = user;
        _userCacheTime[username] = DateTime.now();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 프로필 이미지 업데이트(서버 반영 후 로컬 상태 갱신)
  Future<bool> updateProfileImage({
    required String imageUrl,
    String? imageId,
  }) async {
    try {
      if (_currentUser != null) {
        final u = _currentUser!;
        _currentUser = User(
          id: u.id,
          username: u.username,
          role: u.role,
          alias: u.alias,
          profileImageUrl: imageUrl,
          selfIntroduction: u.selfIntroduction,
          friendCount: u.friendCount,
        );
      }
      if (_viewedUser != null &&
          _currentUser != null &&
          _viewedUser!.username == _currentUser!.username) {
        final v = _viewedUser!;
        _viewedUser = User(
          id: v.id,
          username: v.username,
          role: v.role,
          alias: v.alias,
          profileImageUrl: imageUrl,
          selfIntroduction: v.selfIntroduction,
          friendCount: v.friendCount,
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[UserProvider] updateProfileImage failed: $e');
      return false;
    }
  }
}
