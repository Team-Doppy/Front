import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/user_model.dart';
import '../data/services/user_service.dart';
import '../data/services/auth_service.dart';

class UserProvider extends ChangeNotifier {
  static final UserProvider _instance = UserProvider._internal();
  factory UserProvider() => _instance;
  UserProvider._internal();

  final UserService _user = UserService();

  User? _currentUser;
  User? _viewedUser;
  bool _isLoading = false;
  DateTime? _createdAt;
  bool? _notificationEnabled;
  bool? _marketingEnabled;

  User? get currentUser => _currentUser;
  User? get viewedUser => _viewedUser;
  bool get isLoading => _isLoading;
  DateTime? get createdAt => _createdAt;
  bool? get notificationEnabled => _notificationEnabled;
  bool? get marketingEnabled => _marketingEnabled;

  void setViewedUser(User user) {
    _viewedUser = user;
    notifyListeners();
  }

  void updateCurrentUser(User u) {
    _currentUser = u;
    _persistCurrentUser();
    notifyListeners();
  }

  /// 동시/연속 호출 방지: 로딩 중이면 스킵, 한 번만 실행
  Future<void> fetchUserBundle({bool throwOnAuthError = false}) async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      final bundle = await _user.getUserBundle();
      final me = User.fromJson(bundle);
      _currentUser = me;
      await _persistCurrentUser();

      _notificationEnabled =
          me.notificationEnabled ??
          (bundle['notificationEnabled'] as bool?) ??
          true;
      _marketingEnabled = bundle['marketingConsent'] as bool? ?? false;
      if (bundle['createdAt'] != null) {
        try {
          _createdAt = DateTime.parse(bundle['createdAt'].toString());
        } catch (_) {
          _createdAt = null;
        }
      } else {
        _createdAt = null;
      }

      if (me.username.isNotEmpty) {
        try {
          await AuthService().saveUsername(me.username);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[UserProvider] fetchUserBundle: $e');
      _notificationEnabled = true;
      _marketingEnabled = false;
      rethrow; // 401 등 → SplashScreen에서 catch 후 로그인으로 이동
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void logout() {
    _currentUser = null;
    _viewedUser = null;
    _createdAt = null;
    _notificationEnabled = null;
    _marketingEnabled = null;
    _clearPersistedUser();
    notifyListeners();
  }

  static const _kUsername = 'user_username';
  static const _kProfileImageUrl = 'user_profileImageUrl';

  Future<void> _persistCurrentUser() async {
    try {
      final u = _currentUser;
      if (u == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUsername, u.username);
      await prefs.setString(_kProfileImageUrl, u.profileImageUrl ?? '');
    } catch (e) {
      debugPrint('[UserProvider] persist: $e');
    }
  }

  Future<void> loadCurrentUserFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_kUsername)) return;

      _currentUser = User(
        username: prefs.getString(_kUsername) ?? '',
        profileImageUrl: prefs.getString(_kProfileImageUrl),
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[UserProvider] loadFromPrefs: $e');
    }
  }

  Future<void> _clearPersistedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUsername);
      await prefs.remove(_kProfileImageUrl);
    } catch (_) {}
  }
}
