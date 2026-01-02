import 'dart:async';

import 'package:doppy/data/services/deep_link_service.dart';
import 'package:doppy/main.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/utils/deep_link_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 딥링크 처리 타이밍을 "앱 준비 완료 이후"로 보장하기 위한 코디네이터.
///
/// - 스플래시 부트스트랩 도중 딥링크가 들어오면 큐에 쌓아둠
/// - RootShell이 화면에 올라온 이후(`markReady`)에 큐를 플러시하며 실제 네비게이션 수행
/// - 동일 딥링크가 여러 경로(FCM 초기 메시지 + app_links initialLink 등)로 중복 수신될 수 있어 간단히 디듀프 처리
class DeepLinkCoordinator {
  static final DeepLinkCoordinator _instance = DeepLinkCoordinator._internal();
  factory DeepLinkCoordinator() => _instance;
  DeepLinkCoordinator._internal();

  bool _ready = false;
  bool _executing = false;
  bool _navigatingToLogin = false;
  final List<DeepLinkResult> _queue = <DeepLinkResult>[];

  /// 딥링크가 큐에 대기 중인지 확인
  bool get hasPendingDeepLink => _queue.isNotEmpty;

  String? _lastHandledKey;
  DateTime? _lastHandledAt;

  /// RootShell이 실제로 화면에 렌더된 이후 호출.
  void markReady() {
    if (_ready) return;
    _ready = true;
    _flush();
  }

  /// 앱이 리셋/로그아웃 등으로 다시 초기화되는 경우 필요하면 사용.
  void markNotReady() {
    _ready = false;
  }

  /// 외부에서 딥링크가 들어왔을 때의 단일 진입점.
  Future<void> handle(
    DeepLinkResult result, {
    String source = 'unknown',
  }) async {
    debugPrint(
      '[DeepLinkCoordinator] handle 호출: type=${result.type}, postId=${result.postId}, source=$source, ready=$_ready',
    );
    if (_isDuplicate(result)) {
      debugPrint('[DeepLinkCoordinator] 중복으로 인해 처리 건너뜀: ${_key(result)}');
      return;
    }

    if (!_ready) {
      // ✅ 최신 우선 정책:
      // - 앱 준비 전(스플래시/로그인 전환 등) 여러 딥링크가 연달아 들어오면
      //   마지막 링크 1개만 유지해서 "연타로 꼬이는 네비게이션"을 방지한다.
      _queue
        ..clear()
        ..add(result);
      debugPrint(
        '[DeepLinkCoordinator] ⏳ not ready -> queued(latest): ${_key(result)} (source=$source)',
      );
      return;
    }

    await _execute(result, source: source);
  }

  void _flush() {
    if (_queue.isEmpty) {
      debugPrint('[DeepLinkCoordinator] flush: 큐가 비어있음');
      return;
    }
    debugPrint('[DeepLinkCoordinator] 🚀 flush: ${_queue.length} item(s)');

    // FIFO 순서로 처리
    final pending = List<DeepLinkResult>.from(_queue);
    _queue.clear();

    Future.microtask(() async {
      for (final r in pending) {
        if (_isDuplicate(r)) {
          debugPrint('[DeepLinkCoordinator] flush: 중복 무시 - ${_key(r)}');
          continue;
        }
        debugPrint('[DeepLinkCoordinator] flush: 처리 시작 - ${_key(r)}');
        await _execute(r, source: 'flush');
      }
    });
  }

  Future<void> _execute(
    DeepLinkResult result, {
    String source = 'unknown',
  }) async {
    if (_executing) {
      // ✅ 최신 우선 정책:
      // - 딥링크 처리(네비/로딩)가 진행 중일 때 새 딥링크가 들어오면
      //   대기열을 "마지막 1개"로 덮어써서 연타 시 꼬임을 방지한다.
      _queue
        ..clear()
        ..add(result);
      debugPrint(
        '[DeepLinkCoordinator] ⏳ executing -> queued(latest): ${_key(result)} (source=$source)',
      );
      return;
    }

    final BuildContext? context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('[DeepLinkCoordinator] ❌ navigator context is null');
      return;
    }

    _executing = true;
    try {
      // ✅ 로그인 필수 정책:
      // - 로그인되지 않은 상태에서는 딥링크 네비게이션을 실행하지 않는다.
      // - 딥링크는 큐에 보관하고, 로그인 화면으로 보낸 뒤
      //   로그인 완료 후 RootShell이 markReady()를 호출할 때 플러시한다.
      final bool loggedIn = AuthProvider().isLoggedIn;
      if (!loggedIn) {
        final key = _key(result);
        final alreadyQueued = _queue.any((e) => _key(e) == key);
        if (!alreadyQueued) {
          // 우선순위: 로그인 직후 바로 처리되도록 앞쪽에 넣는다.
          _queue.insert(0, result);
        }
        debugPrint(
          '[DeepLinkCoordinator] 🔒 not logged in -> queued & go login: $key (source=$source)',
        );

        // RootShell이 아니므로 ready를 내려서, 로그인 이후 RootShell에서 다시 flush되게 함
        markNotReady();

        if (!_navigatingToLogin) {
          _navigatingToLogin = true;
          Future.microtask(() {
            try {
              navigatorKey.currentState?.pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
            } catch (e) {
              debugPrint('[DeepLinkCoordinator] go login failed (ignored): $e');
            } finally {
              // 약간의 여유 후 다시 허용 (중복 네비 방지)
              Future.delayed(const Duration(milliseconds: 800), () {
                _navigatingToLogin = false;
              });
            }
          });
        }
        return;
      }

      _rememberHandled(result);
      debugPrint(
        '[DeepLinkCoordinator] ▶️ execute: ${_key(result)} (source=$source)',
      );

      // ✅ IMPORTANT:
      // 딥링크/푸시 진입 시 홈이 "보이는" 순간을 없애기 위해 popUntil을 하지 않는다.
      // - popUntil을 하면 RootShell(Home)이 노출되며, 네트워크 로딩 동안 홈 플레이스홀더가 보일 수 있음
      // - 앱이 실행 중이라면 현재 화면 위에 타겟을 그대로 push(혹은 loading -> replacement)하는 편이 UX가 안정적
      await Future<void>.delayed(Duration.zero);

      final BuildContext? freshContext = navigatorKey.currentContext;
      if (freshContext == null) {
        debugPrint(
          '[DeepLinkCoordinator] ❌ navigator context is null (after pop)',
        );
        return;
      }

      await DeepLinkHandler.handleDeepLink(freshContext, result);
    } catch (e, stackTrace) {
      // ✅ 딥링크 처리 중 에러 발생 시 상세 로그
      debugPrint('[DeepLinkCoordinator] ❌ 딥링크 처리 오류: $e');
      debugPrint('[DeepLinkCoordinator] 스택 트레이스: $stackTrace');
    } finally {
      _executing = false;
      // 처리 중에 큐가 쌓였으면 바로 플러시
      if (_ready && _queue.isNotEmpty) {
        _flush();
      }
    }
  }

  bool _isDuplicate(DeepLinkResult r) {
    final key = _key(r);
    final now = DateTime.now();
    if (_lastHandledKey == key && _lastHandledAt != null) {
      // 짧은 시간(3초) 내 동일 링크는 중복으로 간주
      final diff = now.difference(_lastHandledAt!);
      if (diff.inMilliseconds >= 0 && diff.inMilliseconds < 3000) {
        debugPrint('[DeepLinkCoordinator] 🔁 duplicate ignored: $key');
        return true;
      }
    }
    return false;
  }

  void _rememberHandled(DeepLinkResult r) {
    _lastHandledKey = _key(r);
    _lastHandledAt = DateTime.now();
  }

  String _key(DeepLinkResult r) {
    return '${describeEnum(r.type)}|post=${r.postId ?? ''}|comment=${r.commentId ?? ''}|user=${r.username ?? ''}';
  }
}
