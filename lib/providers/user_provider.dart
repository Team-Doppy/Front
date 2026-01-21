import 'dart:convert';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../data/models/user_model.dart';
import '../data/services/user_service.dart';
import '../data/services/auth_service.dart';

class UserProvider with ChangeNotifier {
  final UserService _userService = UserService();

  // 내 프로필 정보
  User? _currentUser;
  int? _friendCount;

  // 다른 사용자 프로필 정보
  User? _viewedUser;
  bool _isLoading = false;

  // 🎯 설정 정보 (알림, 마케팅)
  bool? _notificationEnabled;
  bool? _marketingEnabled;

  // ✅ 가입일 (ProfileInfoBundle의 createdAt)
  DateTime? _createdAt;

  User? get currentUser => _currentUser;
  int? get friendCount => _friendCount;
  User? get viewedUser => _viewedUser;
  bool get isLoading => _isLoading;
  bool? get notificationEnabled => _notificationEnabled;
  bool? get marketingEnabled => _marketingEnabled;
  DateTime? get createdAt => _createdAt;
  bool? get onboardingCompleted => _currentUser?.onboardingCompleted;

  /// 서버 플래그 기반 온보딩 완료 상태를 로컬 메모리/캐시에 반영
  /// (분기 판단은 Splash에서 서버 번들 로드 이후 수행됨)
  void setOnboardingCompleted(bool value) {
    final current = _currentUser;
    if (current == null) return;
    updateCurrentUser(current.copyWith(onboardingCompleted: value));
  }

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
    List<String>? links,
    Map<String, String>? linkTitles,
    Map<String, String>? linkThumbnails,
  }) async {
    try {
      // API 호출
      await _userService.updateProfileInfo(
        alias: alias,
        links: links,
        linkTitles: linkTitles,
        linkThumbnails: linkThumbnails,
      );

      // 로컬 상태 업데이트
      if (_currentUser != null) {
        // 🎯 빈 배열([])을 전달하면 링크 삭제, null이면 기존 유지
        final updatedUser = _currentUser!.copyWith(
          alias: alias,
          links: links, // null이면 기존 유지, 빈 배열이면 삭제됨
          linkTitles: linkTitles,
          linkThumbnails: linkThumbnails,
        );
        _currentUser = updatedUser;

        notifyListeners();
      }

      return true;
    } catch (e) {
      debugPrint('[UserProvider] updateProfileInfo failed: $e');
      debugPrint(
        '[UserProvider] updateProfileInfo 스택 트레이스: ${StackTrace.current}',
      );
      return false;
    }
  }

  /// 유저 + 세팅 번들 로드 (GET /api/users/bundle)
  Future<void> fetchUserBundle({bool throwOnAuthError = false}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final bundle = await _userService.getUserBundle();

      // User 정보 파싱
      final userData = bundle;
      final me = User.fromJson(userData);
      _currentUser = me;
      await _persistCurrentUser();

      // 설정 정보 파싱
      _notificationEnabled = userData['notificationEnabled'] as bool? ?? true;
      _marketingEnabled = userData['marketingConsent'] as bool? ?? false;

      // ✅ createdAt 파싱 (ProfileInfoBundle에서)
      // 서버에서 UTC ISO 8601 형식으로 내려옴 (예: "2025-11-07T08:32:25.513108")
      if (userData['createdAt'] != null) {
        try {
          final createdAtString = userData['createdAt'] as String;
          // DateTime.parse는 UTC 문자열을 UTC DateTime으로 파싱
          final parsed = DateTime.parse(createdAtString);
          // UTC로 저장 (나중에 toLocal()로 변환하여 사용)
          _createdAt = parsed.isUtc ? parsed : parsed.toUtc();
          debugPrint('[UserProvider] createdAt 파싱 성공: $_createdAt (UTC)');
        } catch (e) {
          debugPrint('[UserProvider] createdAt 파싱 실패: $e');
          _createdAt = null;
        }
      } else {
        _createdAt = null;
      }

      // 🎯 서버에서 유저 정보를 재로드했을 때 AuthService 캐시도 업데이트
      if (me.username.isNotEmpty) {
        try {
          await AuthService().saveUsername(me.username);
          debugPrint('[UserProvider] ✅ AuthService 캐시 업데이트: ${me.username}');
        } catch (e) {
          debugPrint('[UserProvider] ⚠️ AuthService 캐시 업데이트 실패: $e');
        }
      }

      debugPrint(
        '[UserProvider] 유저 번들 로드 완료: notification=$_notificationEnabled, marketing=$_marketingEnabled',
      );
    } catch (e) {
      debugPrint('[UserProvider] 유저 번들 로드 실패: $e');
      // 실패 시 기본값 사용
      _notificationEnabled = true;
      _marketingEnabled = false;

      // ✅ 부트스트랩에서는 인증 실패를 삼키지 말고 위로 올려서 로그인으로 보내야 한다.
      if (throwOnAuthError) {
        final s = e.toString().toLowerCase();
        final isAuthError =
            (e is DioException &&
                (e.response?.statusCode == 401 ||
                    e.response?.statusCode == 403)) ||
            s.contains('401') ||
            s.contains('403') ||
            s.contains('unauthorized') ||
            s.contains('인증이 필요');
        if (isAuthError) {
          rethrow;
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 내 프로필 정보 로드 (단일 엔드포인트 게이트) - 하위 호환성 유지
  Future<void> fetchMyProfile() async {
    _isLoading = true;
    notifyListeners();
    try {
      final me = await _userService.getMyProfile();
      _currentUser = me;
      await _persistCurrentUser();

      // 🎯 서버에서 유저 정보를 재로드했을 때 AuthService 캐시도 업데이트
      if (me.username.isNotEmpty) {
        try {
          await AuthService().saveUsername(me.username);
          debugPrint('[UserProvider] ✅ AuthService 캐시 업데이트: ${me.username}');
        } catch (e) {
          debugPrint('[UserProvider] ⚠️ AuthService 캐시 업데이트 실패: $e');
        }
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
          username: u.username,
          role: u.role,
          alias: u.alias,
          profileImageUrl: imageUrl,
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

  /// 🎯 설정 정보 로드 (알림, 마케팅)
  Future<void> loadSettings() async {
    // TODO: 알림 데이터 호출 주석처리
    /*
    try {
      final settings = await _userService.getSettings();
      _notificationEnabled = settings['notificationEnabled'] ?? true;
      _marketingEnabled = settings['marketingConsent'] ?? false;
      notifyListeners();
      debugPrint(
        '[UserProvider] 설정 정보 로드 완료: notification=$_notificationEnabled, marketing=$_marketingEnabled',
      );
    } catch (e) {
      debugPrint('[UserProvider] 설정 정보 로드 실패: $e');
      // 실패 시 기본값 사용
      _notificationEnabled = true;
      _marketingEnabled = false;
    }
    */
    // 기본값 사용
    _notificationEnabled = true;
    _marketingEnabled = false;
    notifyListeners();
  }

  /// 🎯 알림 설정 업데이트
  void updateNotificationEnabled(bool value) {
    _notificationEnabled = value;
    notifyListeners();
  }

  /// 🎯 마케팅 동의 설정 업데이트
  void updateMarketingEnabled(bool value) {
    _marketingEnabled = value;
    notifyListeners();
  }

  /// 로그아웃 시 모든 사용자 데이터 초기화
  void logout() {
    _currentUser = null;
    _friendCount = null;
    _viewedUser = null;
    _isLoading = false;
    _notificationEnabled = null;
    _marketingEnabled = null;
    _createdAt = null;
    _clearPersistedUser();
    notifyListeners();
    debugPrint('[UserProvider] 로그아웃 - 사용자 데이터 초기화 완료');
  }

  // ====== 로컬 퍼시스턴스 ======
  static const _kUserId = 'user_id';
  static const _kUsername = 'user_username';
  static const _kAlias = 'user_alias';
  static const _kProfileImageUrl = 'user_profileImageUrl';
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
      debugPrint('[UserProvider] 사용자 정보 로컬 저장 완료');
    } catch (e) {
      debugPrint('[UserProvider] 사용자 정보 저장 실패: $e');
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
          debugPrint('[UserProvider] linkTitles 복구 실패: $e');
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
          debugPrint('[UserProvider] linkThumbnails 복구 실패: $e');
        }
      }

      final user = User(
        username: prefs.getString(_kUsername) ?? '',
        role: null,
        alias: prefs.getString(_kAlias),
        profileImageUrl: prefs.getString(_kProfileImageUrl),
        links: links,
        linkTitles: linkTitles,
        linkThumbnails: linkThumbnails,
        friendCount: prefs.getInt(_kFriendCount),
      );
      _currentUser = user;
      notifyListeners();
      debugPrint('[UserProvider] 로컬 사용자 정보 복구 완료');
    } catch (e) {
      debugPrint('[UserProvider] 사용자 정보 복구 실패: $e');
    }
  }

  Future<void> _clearPersistedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUsername);
      await prefs.remove(_kAlias);
      await prefs.remove(_kProfileImageUrl);
      await prefs.remove(_kLinks); // 🎯 links 삭제
      await prefs.remove(_kLinkTitles); // 🎯 linkTitles 삭제
      await prefs.remove(_kLinkThumbnails); // 🎯 linkThumbnails 삭제
      await prefs.remove(_kFriendCount);
      debugPrint('[UserProvider] 로컬 사용자 정보 삭제 완료');
    } catch (e) {
      debugPrint('[UserProvider] 사용자 정보 삭제 실패: $e');
    }
  }
}
