import 'package:doppy/data/services/deep_link_service.dart';
import 'package:flutter/foundation.dart';

/// 딥링크/푸시 진입을 "항상 Splash부터" 통일하기 위한 최소 저장소.
///
/// - 어떤 경로로 들어오든(앱 실행 중/종료) pending을 여기 넣고
/// - Navigator 스택을 `/splash`로 리셋한 뒤
/// - Splash bootstrap 완료 후 `consume()` 해서 타겟 이동을 수행한다.
class DeepLinkStore {
  static DeepLinkResult? _pending;
  static String? _pendingKey;
  static DateTime? _pendingAt;
  static String? _source;

  static bool get hasPending => _pending != null;

  static String? get source => _source;

  static DateTime? get pendingAt => _pendingAt;

  static void setPending(DeepLinkResult result, {required String source}) {
    final key = _key(result);
    final now = DateTime.now();

    // ✅ 짧은 시간 내 동일 딥링크 중복 저장 방지
    if (_pendingKey == key && _pendingAt != null) {
      final diff = now.difference(_pendingAt!);
      if (diff.inMilliseconds >= 0 && diff.inMilliseconds < 1500) {
        debugPrint('[DeepLinkStore] 🔁 duplicate pending ignored: $key');
        return;
      }
    }

    _pending = result;
    _pendingKey = key;
    _pendingAt = now;
    _source = source;
    debugPrint('[DeepLinkStore] ✅ pending set: $key (source=$source)');
  }

  static DeepLinkResult? consume() {
    final r = _pending;
    final key = _pendingKey;
    final src = _source;
    _pending = null;
    _pendingKey = null;
    _pendingAt = null;
    _source = null;
    if (r != null) {
      debugPrint('[DeepLinkStore] 📤 pending consumed: $key (source=$src)');
    }
    return r;
  }

  static String _key(DeepLinkResult r) {
    return '${describeEnum(r.type)}|post=${r.postId ?? ''}|comment=${r.commentId ?? ''}|user=${r.username ?? ''}';
  }
}
