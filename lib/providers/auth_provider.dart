import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/feed_provider/other_profile_feed_provider.dart';
import 'package:flutter/material.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/blog_service.dart';
import 'package:doppy/image/utils/read_image_cache_manager.dart';
import 'user_provider.dart';
import 'friend_provider.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  static final AuthProvider _instance = AuthProvider._internal();
  factory AuthProvider() => _instance;
  AuthProvider._internal();

  final AuthService _authService = AuthService();
  String? _token;
  String? _username;
  bool _isLoggedIn = false;

  String? get username => _username;
  bool get isLoggedIn => _isLoggedIn;

  Future<void> logout() async {
    // ✅ 계정 전환/로그아웃 시 read 이미지 디스크 캐시 purge (다른 계정 이미지 섞임 방지)
    await ReadImageCacheManager.purge();

    // 1. AuthService에서 토큰 삭제
    await _authService.logout();

    // 2. AuthProvider 상태 초기화
    _token = null;
    _username = null;
    _isLoggedIn = false;

    // 3. 모든 Provider 초기화
    UserProvider().logout();
    FriendProvider().logout();
    OtherProfileFeedProvider().logout();
    MyProfileFeedProvider().logout();

    // 4. 모든 서비스 캐시 초기화
    BlogService.clearAllCache();

    // 5. UI 업데이트
    notifyListeners();

    debugPrint('[AuthProvider] 로그아웃 완료 - 모든 데이터 초기화됨');
  }

  Future<bool> login(
    String username,
    String password, {
    bool setAsCurrent = true,
    String? region,
  }) async {
    final result = await _authService.login(
      username,
      password,
      setAsCurrent: setAsCurrent,
      region: region,
    );
    if (result != null) {
      _isLoggedIn = true;
      _token = result.token;
      _username = result.username;
      debugPrint('로그인 성공 : token: $_token, username: $_username');

      // 로그인 직후 사용자 프로필 최소 정보 저장 (오프라인 대비)
      try {
        // 1) Provider 경유 저장 (있으면 즉시 반영)
        final userProv = UserProvider();
        userProv.updateCurrentUser(
          User(
            username: _username ?? username,
            role: null,
            alias: '',
            profileImageUrl: '',
            selfIntroduction: '',
            friendCount: 0,
          ),
        );

        // 2) SharedPreferences 직접 저장 (Provider 컨텍스트가 없을 경우 보강)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', 0);
        await prefs.setString('user_username', _username ?? username);
        await prefs.setString('user_alias', '');
        await prefs.setString('user_profileImageUrl', '');
        await prefs.setString('user_selfIntroduction', '');
        await prefs.setInt('user_friendCount', 0);
        debugPrint('[AuthProvider] SharedPreferences에 최소 사용자 정보 저장 완료');
      } catch (e) {
        debugPrint('[AuthProvider] 로그인 직후 사용자 저장 실패: $e');
      }

      // 🎯 UserCollection 업데이트는 서버에서 처리됨 (로그인 API에서 FCM 토큰을 받아 처리)
    }
    return result != null;
  }

  Future<bool> checkLoginStatus() async {
    _token = await _authService.getToken();
    _username = await _authService.getUsername();

    debugPrint('[AuthProvider] checkLoginStatus - token: $_token');
    debugPrint('[AuthProvider] checkLoginStatus - username: $_username');

    // 🎯 username을 가져왔을 때 AuthService 캐시도 업데이트
    if (_username != null && _username!.isNotEmpty) {
      try {
        await _authService.saveUsername(_username!);
        debugPrint('[AuthProvider] ✅ AuthService 캐시 업데이트: $_username');
      } catch (e) {
        debugPrint('[AuthProvider] ⚠️ AuthService 캐시 업데이트 실패: $e');
      }
    }

    if (_token != null && _username != null) {
      _isLoggedIn = true;
      debugPrint('[AuthProvider] User is logged in');
    } else {
      _isLoggedIn = false;
      debugPrint('[AuthProvider] User is not logged in');
    }
    return _isLoggedIn;
  }

  /// 토큰 검증 및 갱신
  Future<bool> validateAndRefreshToken() async {
    final isValid = await _authService.validateAndRefreshToken();
    if (isValid) {
      _isLoggedIn = true;
      _token = await _authService.getToken();
      _username = await _authService.getUsername();

      // 🎯 username을 가져왔을 때 AuthService 캐시도 업데이트
      if (_username != null && _username!.isNotEmpty) {
        try {
          await _authService.saveUsername(_username!);
          debugPrint('[AuthProvider] ✅ AuthService 캐시 업데이트: $_username');
        } catch (e) {
          debugPrint('[AuthProvider] ⚠️ AuthService 캐시 업데이트 실패: $e');
        }
      }

      notifyListeners();
    } else {
      _isLoggedIn = false;
      _token = null;
      _username = null;
      notifyListeners();
    }
    return isValid;
  }

  /// 인증 상태 업데이트 (계정 전환/연동 시 사용)
  void updateAuthState({
    required bool isLoggedIn,
    required String token,
    required String username,
  }) {
    // ✅ 계정 전환(사용자명 변경) 케이스에서 read 디스크 캐시 purge
    // (메모리 이미지 캐시는 Flutter가 관리하지만, 디스크 캐시는 계정 간 섞임 방지를 위해 비운다)
    final prev = _username;
    if (prev != null && prev.isNotEmpty && prev != username) {
      // sync 메서드이므로 best-effort로 비동기 실행
      Future.microtask(() => ReadImageCacheManager.purge());
    }

    _isLoggedIn = isLoggedIn;
    _token = token;
    _username = username;
    notifyListeners();
    debugPrint('[-] [AuthProvider] 인증 상태 업데이트: $username');
  }
}
