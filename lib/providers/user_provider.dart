import 'dart:convert';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/main.dart' show navigatorKey;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../data/models/user_model.dart';
import '../data/models/military_info_model.dart';
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
    MilitaryInfo? militaryInfo,
    bool shouldRethrow = false, // 🎯 exception을 다시 던질지 여부
  }) async {
    try {
      // API 호출
      await _userService.updateProfileInfo(
        alias: alias,
        links: links,
        linkTitles: linkTitles,
        linkThumbnails: linkThumbnails,
        militaryInfo: militaryInfo,
      );

      // 로컬 상태 업데이트
      if (_currentUser != null) {
        // 🎯 빈 배열([])을 전달하면 링크 삭제, null이면 기존 유지
        final updatedUser = _currentUser!.copyWith(
          alias: alias,
          links: links, // null이면 기존 유지, 빈 배열이면 삭제됨
          linkTitles: linkTitles,
          linkThumbnails: linkThumbnails,
          militaryInfo: militaryInfo,
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
      // 🎯 shouldRethrow가 true면 exception을 다시 던짐 (에러 메시지 파싱을 위해)
      if (shouldRethrow) {
        rethrow;
      }
      return false;
    }
  }

  /// 입대일/진급일/계급 보정 (PATCH /api/military/state-adjustment)
  /// 대상: 군인(military) + 입대 후(afterEnlistment)만 사용 가능
  /// currentRank는 수정 불가 (서버가 자동 계산)
  Future<bool> adjustMilitaryState({
    DateTime? enlistmentDate,
    Map<String, String>? manualPromotionDates,
  }) async {
    try {
      final response = await _userService.adjustMilitaryState(
        enlistmentDate: enlistmentDate,
        manualPromotionDates: manualPromotionDates,
      );

      // ✅ 응답에서 militaryInfo 추출하여 로컬 상태 업데이트
      if (_currentUser != null && response['militaryInfo'] != null) {
        final updatedMilitaryInfo = MilitaryInfo.fromJson(
          response['militaryInfo'] as Map<String, dynamic>,
        );
        final updatedUser = _currentUser!.copyWith(
          militaryInfo: updatedMilitaryInfo,
        );
        _currentUser = updatedUser;
        await _persistCurrentUser();
        notifyListeners();
      }

      return true;
    } catch (e) {
      debugPrint('[UserProvider] adjustMilitaryState failed: $e');
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
      debugPrint(
        '[UserProvider] UserBundle 수신: '
        'militaryInfo=${userData['militaryInfo']}, '
        'connectedMilitaryUser=${userData['connectedMilitaryUser']}',
      );
      // ✅ militaryInfo에 nextPromotionDate와 dischargeDate가 포함되어 있는지 확인
      if (userData['militaryInfo'] != null) {
        final militaryInfo = userData['militaryInfo'] as Map<String, dynamic>;
        debugPrint(
          '[UserProvider] militaryInfo 상세: '
          'nextPromotionDate=${militaryInfo['nextPromotionDate']}, '
          'dischargeDate=${militaryInfo['dischargeDate']}, '
          '전체 키: ${militaryInfo.keys.toList()}',
        );
      }
      final me = User.fromJson(userData);
      debugPrint(
        '[UserProvider] User 파싱 완료: username=${me.username}, '
        'militaryInfo=${me.militaryInfo != null ? "있음 (${me.militaryInfo!.status})" : "없음"}, '
        'connectedMilitaryUser=${me.connectedMilitaryUser != null ? "있음 (${me.connectedMilitaryUser!.username})" : "없음"}, '
        'connectedMilitaryUser.militaryInfo=${me.connectedMilitaryUser?.militaryInfo != null ? "있음 (${me.connectedMilitaryUser!.militaryInfo!.status})" : "없음"}',
      );
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
    } catch (e, stackTrace) {
      debugPrint('❌ [UserProvider] 유저 번들 로드 실패: $e');
      debugPrint('❌ [UserProvider] Stack trace: $stackTrace');

      // 에러 스낵바 표시 및 로딩 취소
      _isLoading = false;
      notifyListeners();

      // 스낵바 표시 (navigatorKey를 통해 전역 컨텍스트 사용)
      final context = navigatorKey.currentContext;
      if (context != null) {
        ErrorHandler.showError(context, '정보를 불러오는 중 오류가 발생했어요');
      }

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
  static const _kOnboardingCompleted =
      'user_onboardingCompleted'; // ✅ 온보딩 완료 상태
  static const _kMilitaryInfo = 'user_militaryInfo'; // ✅ 군인 정보
  static const _kConnectedMilitaryUser =
      'user_connectedMilitaryUser'; // ✅ 연결된 남친 정보 (곰신용)

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
      // ✅ onboardingCompleted 저장 (로컬 캐시로 오프라인/빠른 로딩 지원)
      if (u.onboardingCompleted != null) {
        await prefs.setBool(_kOnboardingCompleted, u.onboardingCompleted!);
      } else {
        await prefs.remove(_kOnboardingCompleted);
      }
      // ✅ militaryInfo 저장 (JSON 문자열로 변환)
      if (u.militaryInfo != null) {
        final militaryInfoJson = u.militaryInfo!.toJson();
        await prefs.setString(_kMilitaryInfo, jsonEncode(militaryInfoJson));
        debugPrint(
          '[UserProvider] militaryInfo 저장: status=${u.militaryInfo!.status}',
        );
      } else {
        await prefs.remove(_kMilitaryInfo);
      }
      // ✅ connectedMilitaryUser 저장 (곰신용 - JSON 문자열로 변환)
      if (u.connectedMilitaryUser != null) {
        final connectedUserJson = u.connectedMilitaryUser!.toJson();
        await prefs.setString(
          _kConnectedMilitaryUser,
          jsonEncode(connectedUserJson),
        );
        debugPrint(
          '[UserProvider] connectedMilitaryUser 저장: '
          'username=${u.connectedMilitaryUser!.username}, '
          'militaryInfo=${u.connectedMilitaryUser!.militaryInfo != null ? "있음" : "없음"}',
        );
      } else {
        await prefs.remove(_kConnectedMilitaryUser);
      }
      debugPrint('[UserProvider] 사용자 정보 로컬 저장 완료');
    } catch (e) {
      debugPrint('[UserProvider] 사용자 정보 저장 실패: $e');
    }
  }

  /// 로컬 캐시에서 사용자 정보 복구 (네트워크 오류 시 최소 UI 제공용)
  /// 주의: 서버 데이터가 있으면 서버 데이터를 우선 사용해야 함
  Future<void> loadCurrentUserFromPrefs() async {
    try {
      // ✅ 이미 서버에서 데이터를 받았으면 로컬 캐시 사용 안 함
      if (_currentUser != null) {
        debugPrint(
          '[UserProvider] 서버 데이터가 이미 있음 - 로컬 캐시 스킵: '
          'militaryInfo=${_currentUser!.militaryInfo != null ? "있음" : "없음"}',
        );
        return;
      }

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

      // ✅ onboardingCompleted 복구 (로컬 캐시에서)
      bool? onboardingCompleted;
      if (prefs.containsKey(_kOnboardingCompleted)) {
        onboardingCompleted = prefs.getBool(_kOnboardingCompleted);
      }

      // ✅ militaryInfo 복구 (JSON 문자열에서)
      MilitaryInfo? militaryInfo;
      if (prefs.containsKey(_kMilitaryInfo)) {
        try {
          final militaryInfoStr = prefs.getString(_kMilitaryInfo);
          if (militaryInfoStr != null && militaryInfoStr.isNotEmpty) {
            final militaryInfoJson =
                jsonDecode(militaryInfoStr) as Map<String, dynamic>;
            militaryInfo = MilitaryInfo.fromJson(militaryInfoJson);
            debugPrint(
              '[UserProvider] militaryInfo 복구: status=${militaryInfo.status}',
            );
          }
        } catch (e) {
          debugPrint('[UserProvider] militaryInfo 복구 실패: $e');
        }
      }

      // ✅ connectedMilitaryUser 복구 (곰신용 - JSON 문자열에서)
      User? connectedMilitaryUser;
      if (prefs.containsKey(_kConnectedMilitaryUser)) {
        try {
          final connectedUserStr = prefs.getString(_kConnectedMilitaryUser);
          if (connectedUserStr != null && connectedUserStr.isNotEmpty) {
            final connectedUserJson =
                jsonDecode(connectedUserStr) as Map<String, dynamic>;
            connectedMilitaryUser = User.fromJson(connectedUserJson);
            debugPrint(
              '[UserProvider] connectedMilitaryUser 복구: '
              'username=${connectedMilitaryUser.username}, '
              'militaryInfo=${connectedMilitaryUser.militaryInfo != null ? "있음" : "없음"}',
            );
          }
        } catch (e) {
          debugPrint('[UserProvider] connectedMilitaryUser 복구 실패: $e');
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
        onboardingCompleted: onboardingCompleted, // ✅ 로컬에서 복구
        militaryInfo: militaryInfo, // ✅ 로컬에서 복구
        connectedMilitaryUser: connectedMilitaryUser, // ✅ 로컬에서 복구
      );
      _currentUser = user;
      notifyListeners();
      debugPrint(
        '[UserProvider] 로컬 사용자 정보 복구 완료: '
        'militaryInfo=${militaryInfo != null ? "있음 (${militaryInfo.status})" : "없음"}',
      );
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
      await prefs.remove(_kOnboardingCompleted); // ✅ onboardingCompleted 삭제
      await prefs.remove(_kMilitaryInfo); // ✅ militaryInfo 삭제
      await prefs.remove(_kConnectedMilitaryUser); // ✅ connectedMilitaryUser 삭제
      debugPrint('[UserProvider] 로컬 사용자 정보 삭제 완료');
    } catch (e) {
      debugPrint('[UserProvider] 사용자 정보 삭제 실패: $e');
    }
  }

  // ====== 곰신 요청 관리 ======

  /// 곰신 요청 수락
  /// 응답: 최신 UserMeResponse(bundle 형태) → 로컬 유저 캐시를 그대로 덮어쓰기
  Future<void> acceptGirlfriendRequest(String requestId) async {
    try {
      debugPrint('[UserProvider] 곰신 요청 수락 시작: requestId=$requestId');
      final response = await _userService.acceptGirlfriendRequest(requestId);

      // ✅ 응답이 최신 UserMeResponse(bundle 형태)이므로 그대로 파싱해서 덮어쓰기
      final updatedUser = User.fromJson(response);
      _currentUser = updatedUser;
      await _persistCurrentUser();
      notifyListeners();
      debugPrint('[UserProvider] 곰신 요청 수락 완료 - 로컬 유저 캐시 덮어쓰기 완료');
    } catch (e) {
      debugPrint('[UserProvider] 곰신 요청 수락 실패: $e');
      rethrow;
    }
  }

  /// 곰신 요청 거절
  /// 응답: 최신 UserMeResponse(bundle 형태) → 로컬 유저 캐시를 그대로 덮어쓰기
  Future<void> rejectGirlfriendRequest(String requestId) async {
    try {
      debugPrint('[UserProvider] 곰신 요청 거절 시작: requestId=$requestId');
      final response = await _userService.rejectGirlfriendRequest(requestId);

      // ✅ 응답이 최신 UserMeResponse(bundle 형태)이므로 그대로 파싱해서 덮어쓰기
      final updatedUser = User.fromJson(response);
      _currentUser = updatedUser;
      await _persistCurrentUser();
      notifyListeners();
      debugPrint('[UserProvider] 곰신 요청 거절 완료 - 로컬 유저 캐시 덮어쓰기 완료');
    } catch (e) {
      debugPrint('[UserProvider] 곰신 요청 거절 실패: $e');
      rethrow;
    }
  }

  /// 곰신 요청 보내기 (온보딩에서 사용)
  Future<void> sendGirlfriendRequest(String targetUsername) async {
    try {
      debugPrint('[UserProvider] 곰신 요청 보내기 시작: targetUsername=$targetUsername');
      await _userService.sendGirlfriendRequest(targetUsername);
      debugPrint('[UserProvider] 곰신 요청 보내기 완료');
    } catch (e) {
      debugPrint('[UserProvider] 곰신 요청 보내기 실패: $e');
      rethrow;
    }
  }

  /// 헤어짐(연결 해제)
  /// 응답: 최신 UserMeResponse(bundle 형태) → 로컬 유저 캐시를 그대로 덮어쓰기
  /// 결과: 다음 부팅부터 connectedMilitaryUser, connectedToMeByUser, girlfriendRequest가 모두 null
  Future<void> disconnectMilitaryConnection() async {
    try {
      debugPrint('[UserProvider] 헤어짐(연결 해제) 시작');
      final response = await _userService.disconnectMilitaryConnection();

      // ✅ 응답이 최신 UserMeResponse(bundle 형태)이므로 그대로 파싱해서 덮어쓰기
      final updatedUser = User.fromJson(response);
      _currentUser = updatedUser;
      await _persistCurrentUser();
      notifyListeners();
      debugPrint('[UserProvider] 헤어짐(연결 해제) 완료 - 로컬 유저 캐시 덮어쓰기 완료');
    } catch (e) {
      debugPrint('[UserProvider] 헤어짐(연결 해제) 실패: $e');
      rethrow;
    }
  }

  /// 커플 애칭 업데이트
  /// 응답: 최신 UserMeResponse(bundle 형태) → 로컬 유저 캐시를 그대로 덮어쓰기
  Future<void> updatePairAlias(String? pairAlias) async {
    try {
      debugPrint('[UserProvider] 커플 애칭 업데이트 시작: pairAlias=$pairAlias');
      final response = await _userService.updatePairAlias(pairAlias);

      // ✅ 응답이 최신 UserMeResponse(bundle 형태)이므로 그대로 파싱해서 덮어쓰기
      final updatedUser = User.fromJson(response);
      _currentUser = updatedUser;
      await _persistCurrentUser();
      notifyListeners();
      debugPrint('[UserProvider] 커플 애칭 업데이트 완료 - 로컬 유저 캐시 덮어쓰기 완료');
    } catch (e) {
      debugPrint('[UserProvider] 커플 애칭 업데이트 실패: $e');
      rethrow;
    }
  }
}
