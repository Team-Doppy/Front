import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Firebase Cloud Messaging 서비스
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  String? _fcmToken;

  /// FCM 토큰 가져오기 (캐시된 토큰이 있으면 반환, 없으면 발급)
  Future<String?> getToken() async {
    try {
      // 이미 토큰이 있으면 반환
      if (_fcmToken != null && _fcmToken!.isNotEmpty) {
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
          return null;
        }
      }

      // 🎯 FCM 토큰 발급
      _fcmToken = await _firebaseMessaging.getToken();
      debugPrint('[FcmService] FCM 토큰 발급 완료: $_fcmToken');

      // 🎯 토큰 갱신 리스너 등록 (토큰이 변경될 때 호출)
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        debugPrint('[FcmService] FCM 토큰 갱신: $newToken');
        _fcmToken = newToken;
      });

      return _fcmToken;
    } catch (e) {
      debugPrint('[FcmService] FCM 토큰 발급 실패: $e');
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
