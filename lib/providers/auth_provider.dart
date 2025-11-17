import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/feed_provider/other_profile_feed_provider.dart';
import 'package:flutter/material.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/blog_service.dart';
import 'user_provider.dart';
import 'friend_provider.dart';
import 'group_provider.dart';
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
    GroupProvider().logout();

    // 4. 모든 서비스 캐시 초기화
    BlogService.clearAllCache();

    // 5. UI 업데이트
    notifyListeners();

    print('[AuthProvider] 로그아웃 완료 - 모든 데이터 초기화됨');
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
      print('로그인 성공 : token: $_token, username: $_username');

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
        print('[AuthProvider] SharedPreferences에 최소 사용자 정보 저장 완료');
      } catch (e) {
        print('[AuthProvider] 로그인 직후 사용자 저장 실패: $e');
      }

      // 🎯 UserCollection 업데이트는 서버에서 처리됨 (로그인 API에서 FCM 토큰을 받아 처리)
    }
    return result != null;
  }

  Future<bool> checkLoginStatus() async {
    _token = await _authService.getToken();
    _username = await _authService.getUsername();

    print('[AuthProvider] checkLoginStatus - token: $_token');
    print('[AuthProvider] checkLoginStatus - username: $_username');

    if (_token != null && _username != null) {
      _isLoggedIn = true;
      print('[AuthProvider] User is logged in');
    } else {
      _isLoggedIn = false;
      print('[AuthProvider] User is not logged in');
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
    _isLoggedIn = isLoggedIn;
    _token = token;
    _username = username;
    notifyListeners();
    print('[-] [AuthProvider] 인증 상태 업데이트: $username');
  }

  Future<void> updateUserRegionAndRefreshToken(String region) async {
    await _authService.updateUserRegion(region);
  }
}
