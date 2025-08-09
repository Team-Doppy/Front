import 'package:flutter/material.dart';

import '../../data/services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  bool _isLoggedIn = false;

  bool get isLoggedIn => _isLoggedIn;

  AuthProvider() {
    _checkLoginStatus();
  }

  void _checkLoginStatus() async {
    final token = await _authService.getToken();
    if (token != null) {
      _isLoggedIn = true;
    }
    notifyListeners(); // 상태 변경을 구독자들에게 알림
  }

  Future<bool> login(String email, String password) async {
    final success = await _authService.login(email, password);
    if (success) {
      _isLoggedIn = true;
      notifyListeners();
    }
    return success;
  }

  void logout() async {
    await _authService.logout();
    _isLoggedIn = false;
    notifyListeners();
  }
}