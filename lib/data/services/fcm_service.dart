import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:doppy/data/services/auth_service.dart';

/// Firebase Cloud Messaging 서비스
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  String? _fcmToken;
  bool _tokenRefreshListenerRegistered = false;

  /// 알림 권한 상태 확인
  Future<bool> isNotificationPermissionGranted() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final settings = await _firebaseMessaging.getNotificationSettings();
        return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.status;
        return status.isGranted;
      }
      return false;
    } catch (e) {
      debugPrint('[FcmService] 알림 권한 확인 실패: $e');
      return false;
    }
  }

  /// 알림 권한 상태 변경 감지 (iOS만 지원)
  Future<AuthorizationStatus?> getNotificationSettings() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final settings = await _firebaseMessaging.getNotificationSettings();
        return settings.authorizationStatus;
      }
      return null;
    } catch (e) {
      debugPrint('[FcmService] 알림 설정 확인 실패: $e');
      return null;
    }
  }

  /// FCM 토큰 유효성 검사 (토큰이 있고 유효한지 확인)
  Future<bool> isTokenValid() async {
    try {
      final token = _fcmToken ?? await _firebaseMessaging.getToken();
      if (token == null || token.isEmpty) {
        return false;
      }

      // 권한 확인
      final hasPermission = await isNotificationPermissionGranted();
      if (!hasPermission) {
        return false;
      }

      // 현재 저장된 토큰과 실제 토큰 비교
      final currentToken = await _firebaseMessaging.getToken();
      if (currentToken == null || currentToken.isEmpty) {
        return false;
      }

      // 토큰이 다르면 무효 (Firebase가 자동으로 갱신했을 수 있음)
      if (_fcmToken != null && _fcmToken != currentToken) {
        debugPrint(
          '[FcmService] ⚠️ FCM 토큰 불일치 감지 - 캐시된 토큰과 실제 토큰이 다름 (Firebase 자동 갱신 가능)',
        );
        // 캐시된 토큰을 실제 토큰으로 업데이트
        _fcmToken = currentToken;
        return false; // 업데이트는 했지만 재발급이 필요하다고 표시
      }

      return true;
    } catch (e) {
      debugPrint('[FcmService] FCM 토큰 유효성 검사 실패: $e');
      return false;
    }
  }

  /// FCM 토큰 가져오기 (캐시된 토큰이 있으면 반환, 없으면 발급)
  Future<String?> getToken({bool forceRefresh = false}) async {
    try {
      // 강제 갱신이 아니고 이미 토큰이 있으면 반환
      if (!forceRefresh && _fcmToken != null && _fcmToken!.isNotEmpty) {
        return _fcmToken;
      }

      // 🎯 권한 요청 (iOS)
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final settings = await _firebaseMessaging.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          debugPrint('[FcmService] iOS 알림 권한 허용됨');
        } else if (settings.authorizationStatus ==
            AuthorizationStatus.provisional) {
          debugPrint('[FcmService] iOS 임시 알림 권한 허용됨');
        } else {
          debugPrint('[FcmService] iOS 알림 권한 거부됨');
          _fcmToken = null;
          return null;
        }
      }

      // 🎯 FCM 토큰 발급
      _fcmToken = await _firebaseMessaging.getToken();
      if (_fcmToken != null && _fcmToken!.isNotEmpty) {
        debugPrint(
          '[FcmService] ✅ FCM 토큰 발급 완료: ${_fcmToken!.substring(0, 20)}...',
        );
      } else {
        debugPrint('[FcmService] ❌ FCM 토큰 발급 실패: 토큰이 null이거나 비어있음');
      }

      // 🎯 토큰 갱신 리스너 등록 (한 번만 등록)
      if (!_tokenRefreshListenerRegistered) {
        _firebaseMessaging.onTokenRefresh.listen((newToken) async {
          debugPrint(
            '[FcmService] 🔄 FCM 토큰 갱신됨: ${newToken.substring(0, 20)}...',
          );
          _fcmToken = newToken;

          // 🎯 토큰 갱신 시 서버에도 자동 전송
          try {
            final authService = AuthService();
            await authService.syncFcmTokenAndSettings();
            debugPrint('[FcmService] ✅ FCM 토큰 갱신 후 서버 동기화 완료');
          } catch (e) {
            debugPrint('[FcmService] ❌ FCM 토큰 갱신 후 서버 동기화 실패: $e');
          }
        });
        _tokenRefreshListenerRegistered = true;
        debugPrint('[FcmService] FCM 토큰 갱신 리스너 등록 완료');
      }

      return _fcmToken;
    } catch (e) {
      debugPrint('[FcmService] FCM 토큰 발급 실패: $e');
      _fcmToken = null;
      return null;
    }
  }

  /// FCM 토큰 재발급 (알림 권한이 있을 때만)
  /// 반환값: (성공 여부, 새 토큰)
  Future<({bool success, String? token})> refreshTokenIfNeeded() async {
    try {
      // 알림 권한 확인
      final hasPermission = await isNotificationPermissionGranted();
      if (!hasPermission) {
        debugPrint('[FcmService] 알림 권한이 없어 토큰 재발급 불가');
        return (success: false, token: null);
      }

      // 강제로 새 토큰 발급
      _fcmToken = null; // 캐시 초기화
      final newToken = await getToken(forceRefresh: true);

      if (newToken != null && newToken.isNotEmpty) {
        debugPrint('[FcmService] FCM 토큰 재발급 성공: $newToken');
        return (success: true, token: newToken);
      } else {
        debugPrint('[FcmService] FCM 토큰 재발급 실패');
        return (success: false, token: null);
      }
    } catch (e) {
      debugPrint('[FcmService] FCM 토큰 재발급 오류: $e');
      return (success: false, token: null);
    }
  }

  /// FCM 토큰 검사 및 필요시 재발급
  /// 알림이 켜져있고 FCM에 문제가 있다면 새로 발급
  ///
  /// 동작:
  /// 1. 알림 권한 확인
  /// 2. 토큰 유효성 검사 (캐시된 토큰과 실제 토큰 비교)
  /// 3. 무효하면 재발급 후 서버에 전송 필요
  Future<String?> checkAndRefreshTokenIfNeeded() async {
    try {
      // 알림 권한 확인
      final hasPermission = await isNotificationPermissionGranted();
      if (!hasPermission) {
        debugPrint('[FcmService] 알림 권한이 없어 토큰 검사 건너뜀');
        return null;
      }

      // 토큰 유효성 검사 (내부에서 토큰 불일치 시 자동 업데이트)
      final isValid = await isTokenValid();
      if (isValid) {
        final currentToken = _fcmToken ?? await getToken();
        debugPrint(
          '[FcmService] ✅ FCM 토큰 유효: ${currentToken?.substring(0, 20)}...',
        );
        return currentToken;
      }

      // 토큰이 무효하면 재발급 (만료되었거나 불일치한 경우)
      debugPrint('[FcmService] 🔄 FCM 토큰 무효 감지, 재발급 시도...');
      final result = await refreshTokenIfNeeded();

      if (result.success && result.token != null) {
        debugPrint(
          '[FcmService] ✅ FCM 토큰 재발급 성공: ${result.token!.substring(0, 20)}...',
        );
        return result.token;
      } else {
        debugPrint('[FcmService] ❌ FCM 토큰 재발급 실패');
        return null;
      }
    } catch (e) {
      debugPrint('[FcmService] ❌ FCM 토큰 검사 및 재발급 오류: $e');
      return null;
    }
  }

  /// FCM 토큰 초기화 (로그아웃 시 호출)
  void clearToken() {
    _fcmToken = null;
    debugPrint('[FcmService] FCM 토큰 초기화');
  }

  /// 현재 저장된 FCM 토큰 가져오기 (비동기 호출 없이)
  String? get cachedToken => _fcmToken;
}
