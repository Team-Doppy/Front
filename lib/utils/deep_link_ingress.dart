import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:doppy/data/services/deep_link_service.dart';
import 'package:doppy/main.dart';
import 'package:doppy/utils/deep_link_store.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 딥링크/푸시 알림 진입 이벤트를 한 곳에서 받아서
/// "pending 저장 → /splash로 스택 리셋"으로 통일한다.
class DeepLinkIngress with WidgetsBindingObserver {
  static final DeepLinkIngress _instance = DeepLinkIngress._internal();
  factory DeepLinkIngress() => _instance;
  DeepLinkIngress._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _appLinksSub;
  StreamSubscription<RemoteMessage>? _fcmOpenedSub;
  bool _started = false;

  /// 앱 종료 상태에서 들어온 초기 진입(FCM initialMessage / app_links initialLink)을 캡처.
  /// - 이 시점에서는 navigator가 없을 수 있어 스택 리셋은 하지 않고 pending만 저장한다.
  Future<void> captureInitialEntry() async {
    try {
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        // AppLinks initialLink와 중복 방지 (기존 DeepLinkService 플래그 재사용)
        DeepLinkService().setHasInitialFcmMessage();

        final deepLink = initialMessage.data['deepLink'] as String?;
        final type = initialMessage.data['type'] as String?;
        final url =
            (deepLink != null && deepLink.isNotEmpty)
                ? deepLink
                : (type == 'FRIEND_REQUEST'
                    ? 'doppy://friends/requests'
                    : null);
        if (url != null) {
          final result = DeepLinkService.parseDeepLink(url);
          if (result != null && result.type != DeepLinkType.unknown) {
            DeepLinkStore.setPending(result, source: 'fcm_initial');
            debugPrint('[DeepLinkIngress] captured initial FCM: $url');
            return;
          }
        }
      }
    } catch (e) {
      debugPrint(
        '[DeepLinkIngress] captureInitialEntry(Fcm) failed (ignored): $e',
      );
    }

    // FCM initial이 없을 때만 AppLinks initialLink 캡처
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        final url = uri.toString();
        final result = DeepLinkService.parseDeepLink(url);
        if (result != null && result.type != DeepLinkType.unknown) {
          DeepLinkStore.setPending(result, source: 'app_links_initial');
          debugPrint('[DeepLinkIngress] captured initial AppLinks: $url');
        }
      }
    } catch (e) {
      debugPrint(
        '[DeepLinkIngress] captureInitialEntry(AppLinks) failed (ignored): $e',
      );
    }
  }

  /// 앱 실행 중 이벤트 리스너 시작.
  /// - 딥링크/푸시 탭 이벤트가 오면 pending 저장 후 /splash로 스택 리셋
  void start() {
    if (_started) return;
    _started = true;

    // ✅ 플랫폼에서 pushRoute(/334, /username 등)가 들어오는 경우가 있어
    // WidgetsBindingObserver로 가로채서 Navigator가 "라우트를 push"하지 않게 막는다.
    // (그 대신 pending 저장 → /splash 리셋으로 통일)
    WidgetsBinding.instance.addObserver(this);

    _appLinksSub?.cancel();
    _appLinksSub = _appLinks.uriLinkStream.listen(
      (uri) => _handleUrl(uri.toString(), source: 'app_links'),
      onError:
          (err) => debugPrint('[DeepLinkIngress] app_links stream error: $err'),
    );

    _fcmOpenedSub?.cancel();
    _fcmOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final deepLink = message.data['deepLink'] as String?;
      final type = message.data['type'] as String?;
      final url =
          (deepLink != null && deepLink.isNotEmpty)
              ? deepLink
              : (type == 'FRIEND_REQUEST' ? 'doppy://friends/requests' : null);
      if (url != null) {
        _handleUrl(url, source: 'fcm_opened');
      }
    });
  }

  /// 외부(예: 포그라운드 오버레이 알림 탭)에서 URL을 전달해 처리.
  void ingestUrl(String url, {required String source}) {
    _handleUrl(url, source: source);
  }

  void dispose() {
    _appLinksSub?.cancel();
    _fcmOpenedSub?.cancel();
    _appLinksSub = null;
    _fcmOpenedSub = null;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  bool _isInternalRouteName(String? route) {
    if (route == null || route.isEmpty) return true;
    // Navigator 기본 루트
    if (route == Navigator.defaultRouteName) return true;
    // 앱 내부에서 사용하는 named route들
    if (route == '/splash' || route == '/login' || route == '/post-write') {
      return true;
    }
    return false;
  }

  Future<bool> _handlePlatformRoute(
    String route, {
    required String source,
  }) async {
    if (_isInternalRouteName(route)) return false;

    // ✅ iOS에서 app_links와 platform pushRoute가 거의 동시에 들어오는 케이스가 있어
    // app_links가 이미 pending을 잡았으면 platform 경로는 "handled"로 처리하고 무시한다.
    if (DeepLinkStore.hasPending) {
      final src = DeepLinkStore.source ?? '';
      final at = DeepLinkStore.pendingAt;
      final now = DateTime.now();
      final isRecent =
          at != null && now.difference(at).inMilliseconds.abs() < 1200;
      final isAppLinks = src.startsWith('app_links');
      final isPlatform = source.startsWith('platform_push_route');
      if (isRecent && isAppLinks && isPlatform) {
        debugPrint(
          '[DeepLinkIngress] platform route ignored (recent pending exists): $route (pendingSource=$src)',
        );
        return true; // handled: Navigator push 방지
      }
    }

    final result = DeepLinkService.parseDeepLink(route);
    if (result == null || result.type == DeepLinkType.unknown) return false;

    DeepLinkStore.setPending(result, source: source);
    _restartToSplash();
    return true; // ✅ handled: Navigator가 route를 push하지 않도록 막는다.
  }

  @override
  Future<bool> didPushRoute(String route) {
    return _handlePlatformRoute(route, source: 'platform_push_route');
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    final location = routeInformation.location;
    // location은 null일 수 없지만(현재 Flutter 구현상), 방어적으로 빈 값만 체크한다.
    if (location.isEmpty) return Future.value(false);
    return _handlePlatformRoute(location, source: 'platform_push_route_info');
  }

  void _handleUrl(String url, {required String source}) {
    final result = DeepLinkService.parseDeepLink(url);
    if (result == null || result.type == DeepLinkType.unknown) {
      debugPrint(
        '[DeepLinkIngress] ignored unknown url: $url (source=$source)',
      );
      return;
    }

    DeepLinkStore.setPending(result, source: source);
    _restartToSplash();
  }

  void _restartToSplash() {
    // ✅ Navigator 조작은 레이아웃/빌드 중 실행되면 RenderObject assert가 터질 수 있어
    // 반드시 "다음 프레임"으로 미룬다.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      try {
        final nav = navigatorKey.currentState;
        if (nav == null) {
          debugPrint('[DeepLinkIngress] navigator is null (ignored)');
          return;
        }
        nav.pushNamedAndRemoveUntil('/splash', (route) => false);
      } catch (e) {
        debugPrint('[DeepLinkIngress] restartToSplash failed (ignored): $e');
      }
    });
  }
}
