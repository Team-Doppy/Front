import 'package:flutter/material.dart';
import '../../data/services/auth_service.dart'; //상대 경로 에러 발생

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
    await _authService.logout();
    _token = null;
    _username = null;
    _isLoggedIn = false;
    print('로그아웃 성공');
  }

  Future<bool> login(String username, String password) async {
    final result = await _authService.login(username, password);
    if (result != null) {
      _isLoggedIn = true;
      _token = result.token;
      _username = result.username;
      print('로그인 성공 : token: $_token, username: $_username');

      notifyListeners();
    }
    return result != null;
  }

  Future<bool> checkLoginStatus() async {
    _token = await _authService.getToken();
    print('token: $_token');
    _username = await _authService.getUsername();
    if (_token != null && _username != null) {
      _isLoggedIn = true;
    } else {
      _isLoggedIn = false;
    }
    return _isLoggedIn;
  }
}
