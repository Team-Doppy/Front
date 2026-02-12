import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/user_model.dart';
import '../data/services/auth_service.dart';
import 'graph_provider.dart';
import 'user_provider.dart';

class AuthProvider extends ChangeNotifier {
  static final AuthProvider _instance = AuthProvider._internal();
  factory AuthProvider() => _instance;
  AuthProvider._internal();

  final AuthService _auth = AuthService();
  String? _token;
  String? _username;
  bool _isLoggedIn = false;
  String? _lastLoginError;

  String? get username => _username;
  bool get isLoggedIn => _isLoggedIn;
  String? get lastLoginError => _lastLoginError;

  Future<void> logout() async {
    await _auth.logout();
    _token = null;
    _username = null;
    _isLoggedIn = false;

    UserProvider().logout();
    GraphProvider().clear();

    notifyListeners();
    debugPrint('[AuthProvider] 로그아웃');
  }

  Future<bool> login(String username, String password, {String? region}) async {
    _lastLoginError = null;
    try {
      final result = await _auth.login(username, password, region: region);
      if (result != null) {
        _isLoggedIn = true;
        _token = result.token;
        _username = result.username;

        try {
          UserProvider().updateCurrentUser(
            User(username: _username ?? username, profileImageUrl: ''),
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_username', _username ?? username);
        } catch (e) {
          debugPrint('[AuthProvider] 로그인 직후 유저 저장 실패: $e');
        }

        notifyListeners();
        return true;
      }
    } catch (e) {
      _lastLoginError = e.toString().replaceFirst('Exception: ', '');
      return false;
    }
    return false;
  }

  Future<bool> checkLoginStatus() async {
    _token = await _auth.getToken();
    _username = await _auth.getUsername();

    if (_token != null && _username != null) {
      _isLoggedIn = true;
    } else {
      _isLoggedIn = false;
    }
    notifyListeners();
    return _isLoggedIn;
  }

  Future<bool> validateAndRefreshToken() async {
    final ok = await _auth.validateAndRefreshToken();
    if (ok) {
      _isLoggedIn = true;
      _token = await _auth.getToken();
      _username = await _auth.getUsername();
      notifyListeners();
    } else {
      _isLoggedIn = false;
      _token = null;
      _username = null;
      notifyListeners();
    }
    return ok;
  }
}
