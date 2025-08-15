import 'package:flutter/material.dart';
import '../../data/services/auth_service.dart'; //상대 경로 에러 발생

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  String? _token;
  String? _username;
  bool _isLoggedIn = false;

  String? get username => _username;
  bool get isLoggedIn => _isLoggedIn;

  AuthProvider() {
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    _token = await _authService.getToken();
    _username = await _authService.getUsername();
    if (_token != null && _username != null) {
      _isLoggedIn = true;
    } else {
      _isLoggedIn = false;
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    final response = await _authService.login(username, password);
    if (response != null) {
      await _checkLoginStatus(); // 로그인 성공 후 상태 갱신
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    await _authService.logout();
    await _checkLoginStatus(); // 로그아웃 후 상태 갱신
  }
}