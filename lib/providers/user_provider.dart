import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import '../data/models/user_model.dart';
import '../data/services/user_service.dart';

class UserProvider with ChangeNotifier {
  final UserService _userService = UserService();

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

  /// 다른 사용자 정보 설정
  void setViewedUser(User user) {
    _viewedUser = user;
    notifyListeners();
  }

  /// 현재 사용자 정보 업데이트
  void updateCurrentUser(User updatedUser) {
    _currentUser = updatedUser;
    notifyListeners();
  }

  /// 프로필 정보 업데이트 (API 호출 + 로컬 상태 업데이트)
  Future<bool> updateProfileInfo({
    required String alias,
    required String selfIntroduction,
  }) async {
    try {
      // API 호출
      await _userService.updateProfileInfo(
        alias: alias,
        selfIntroduction: selfIntroduction,
      );

      // 로컬 상태 업데이트
      if (_currentUser != null) {
        final updatedUser = _currentUser!.copyWith(
          alias: alias,
          selfIntroduction: selfIntroduction,
        );
        _currentUser = updatedUser;

        // 별도 selfIntroduction 필드도 업데이트
        _selfIntroduction = selfIntroduction;

        notifyListeners();
      }

      return true;
    } catch (e) {
      debugPrint('[UserProvider] updateProfileInfo failed: $e');
      return false;
    }
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

  /// 프로필 이미지 삭제 (기본 이미지로 되돌리기)
  Future<bool> deleteProfileImage(BuildContext context) async {
    try {
      // 서버에 삭제 요청
      await _userService.deleteProfileImage();

      // 로컬 상태 업데이트 (빈 문자열로 설정)
      if (_currentUser != null) {
        final u = _currentUser!;
        _currentUser = User(
          id: u.id,
          username: u.username,
          role: u.role,
          alias: u.alias,
          profileImageUrl: '',
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
          profileImageUrl: '',
          selfIntroduction: v.selfIntroduction,
          friendCount: v.friendCount,
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[UserProvider] deleteProfileImage failed: $e');
      ErrorHandler.showError(context, '프로필 이미지 삭제에 실패했습니다');
      return false;
    }
  }

  /// 로그아웃 시 모든 사용자 데이터 초기화
  void logout() {
    _currentUser = null;
    _friendCount = null;
    _selfIntroduction = null;
    _viewedUser = null;
    _viewedUserSelfIntroduction = null;
    _isLoading = false;
    notifyListeners();
    print('[UserProvider] 로그아웃 - 사용자 데이터 초기화 완료');
  }
}
