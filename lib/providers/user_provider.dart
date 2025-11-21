import 'dart:convert';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    _persistCurrentUser();
    notifyListeners();
  }

  /// 프로필 정보 업데이트 (API 호출 + 로컬 상태 업데이트)
  Future<bool> updateProfileInfo({
    required String alias,
    required String selfIntroduction,
    List<String>? links,
    Map<String, String>? linkTitles,
    Map<String, String>? linkThumbnails,
  }) async {
    try {
      // API 호출
      await _userService.updateProfileInfo(
        alias: alias,
        selfIntroduction: selfIntroduction,
        links: links,
        linkTitles: linkTitles,
        linkThumbnails: linkThumbnails,
      );

      // 로컬 상태 업데이트
      if (_currentUser != null) {
        // 🎯 빈 배열([])을 전달하면 링크 삭제, null이면 기존 유지
        final updatedUser = _currentUser!.copyWith(
          alias: alias,
          selfIntroduction: selfIntroduction,
          links: links, // null이면 기존 유지, 빈 배열이면 삭제됨
          linkTitles: linkTitles,
          linkThumbnails: linkThumbnails,
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
      // 🎯 User 모델에 이미 selfIntroduction이 포함되어 있으므로 별도 API 호출 불필요
      _selfIntroduction = me.selfIntroduction;
      await _persistCurrentUser();
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
      ErrorHandler.showError(
        context,
        context.tr('profile_image_delete_failed'),
      );
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
    _clearPersistedUser();
    notifyListeners();
    print('[UserProvider] 로그아웃 - 사용자 데이터 초기화 완료');
  }

  // ====== 로컬 퍼시스턴스 ======
  static const _kUserId = 'user_id';
  static const _kUsername = 'user_username';
  static const _kAlias = 'user_alias';
  static const _kProfileImageUrl = 'user_profileImageUrl';
  static const _kSelfIntroduction = 'user_selfIntroduction';
  static const _kLinks = 'user_links'; // 🎯 프로필 링크 목록
  static const _kLinkTitles = 'user_linkTitles'; // 🎯 링크 타이틀 맵
  static const _kLinkThumbnails = 'user_linkThumbnails'; // 🎯 링크 썸네일 맵
  static const _kFriendCount = 'user_friendCount';

  Future<void> _persistCurrentUser() async {
    try {
      final u = _currentUser;
      if (u == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUsername, u.username);
      await prefs.setString(_kAlias, u.alias ?? '');
      await prefs.setString(_kProfileImageUrl, u.profileImageUrl ?? '');
      await prefs.setString(_kSelfIntroduction, u.selfIntroduction ?? '');
      // 🎯 links 저장 (JSON 문자열로 변환)
      if (u.links != null && u.links!.isNotEmpty) {
        await prefs.setStringList(_kLinks, u.links!);
      } else {
        await prefs.remove(_kLinks);
      }
      // 🎯 linkTitles 저장 (JSON 문자열로 변환)
      if (u.linkTitles != null && u.linkTitles!.isNotEmpty) {
        await prefs.setString(_kLinkTitles, jsonEncode(u.linkTitles));
      } else {
        await prefs.remove(_kLinkTitles);
      }
      // 🎯 linkThumbnails 저장 (JSON 문자열로 변환)
      if (u.linkThumbnails != null && u.linkThumbnails!.isNotEmpty) {
        await prefs.setString(_kLinkThumbnails, jsonEncode(u.linkThumbnails));
      } else {
        await prefs.remove(_kLinkThumbnails);
      }
      await prefs.setInt(_kFriendCount, u.friendCount ?? 0);
      print('[UserProvider] 사용자 정보 로컬 저장 완료');
    } catch (e) {
      print('[UserProvider] 사용자 정보 저장 실패: $e');
    }
  }

  Future<void> loadCurrentUserFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_kUserId) || !prefs.containsKey(_kUsername)) {
        return;
      }
      // 🎯 links 복구
      List<String>? links;
      if (prefs.containsKey(_kLinks)) {
        final linksList = prefs.getStringList(_kLinks);
        if (linksList != null && linksList.isNotEmpty) {
          links = linksList;
        }
      }

      // 🎯 linkTitles 복구 (JSON 문자열에서 Map으로 변환)
      Map<String, String>? linkTitles;
      if (prefs.containsKey(_kLinkTitles)) {
        try {
          final linkTitlesStr = prefs.getString(_kLinkTitles);
          if (linkTitlesStr != null && linkTitlesStr.isNotEmpty) {
            final decoded = jsonDecode(linkTitlesStr);
            if (decoded is Map) {
              linkTitles = Map<String, String>.from(
                decoded.map(
                  (key, value) => MapEntry(key.toString(), value.toString()),
                ),
              );
            }
          }
        } catch (e) {
          print('[UserProvider] linkTitles 복구 실패: $e');
        }
      }

      // 🎯 linkThumbnails 복구 (JSON 문자열에서 Map으로 변환)
      Map<String, String>? linkThumbnails;
      if (prefs.containsKey(_kLinkThumbnails)) {
        try {
          final linkThumbnailsStr = prefs.getString(_kLinkThumbnails);
          if (linkThumbnailsStr != null && linkThumbnailsStr.isNotEmpty) {
            final decoded = jsonDecode(linkThumbnailsStr);
            if (decoded is Map) {
              linkThumbnails = Map<String, String>.from(
                decoded.map(
                  (key, value) => MapEntry(key.toString(), value.toString()),
                ),
              );
            }
          }
        } catch (e) {
          print('[UserProvider] linkThumbnails 복구 실패: $e');
        }
      }

      final user = User(
        username: prefs.getString(_kUsername) ?? '',
        role: null,
        alias: prefs.getString(_kAlias),
        profileImageUrl: prefs.getString(_kProfileImageUrl),
        selfIntroduction: prefs.getString(_kSelfIntroduction),
        links: links,
        linkTitles: linkTitles,
        linkThumbnails: linkThumbnails,
        friendCount: prefs.getInt(_kFriendCount),
      );
      _currentUser = user;
      notifyListeners();
      print('[UserProvider] 로컬 사용자 정보 복구 완료');
    } catch (e) {
      print('[UserProvider] 사용자 정보 복구 실패: $e');
    }
  }

  Future<void> _clearPersistedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUsername);
      await prefs.remove(_kAlias);
      await prefs.remove(_kProfileImageUrl);
      await prefs.remove(_kSelfIntroduction);
      await prefs.remove(_kLinks); // 🎯 links 삭제
      await prefs.remove(_kLinkTitles); // 🎯 linkTitles 삭제
      await prefs.remove(_kLinkThumbnails); // 🎯 linkThumbnails 삭제
      await prefs.remove(_kFriendCount);
      print('[UserProvider] 로컬 사용자 정보 삭제 완료');
    } catch (e) {
      print('[UserProvider] 사용자 정보 삭제 실패: $e');
    }
  }
}
