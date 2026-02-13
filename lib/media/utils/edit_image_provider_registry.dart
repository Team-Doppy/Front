import 'dart:collection';

import 'package:flutter/widgets.dart';

/// 편집 화면에서 노드 타입(Row ↔ Single ↔ PageView)이 바뀌어도
/// 같은 URL 이미지를 즉시 다시 그릴 수 있게 ImageProvider를 공유한다.
///
/// - 목적: split/merge 시 placeholder 구간의 "깜빡임" 최소화
/// - 주의: 너무 커지면 메모리 압박이 올 수 있으니 상한을 둔다.
class EditImageProviderRegistry {
  static const int _maxEntries = 200;
  // ✅ LinkedHashMap: insertion order 유지 + get 시 "touch"해서 LRU처럼 사용
  static final LinkedHashMap<String, ImageProvider> _providers =
      LinkedHashMap<String, ImageProvider>();

  static ImageProvider? get(String url) {
    if (url.isEmpty) return null;
    final existing = _providers.remove(url);
    if (existing == null) return null;
    // 최근 접근 항목을 뒤로 보내 LRU로 취급
    _providers[url] = existing;
    return existing;
  }

  static void set(String url, ImageProvider provider) {
    if (url.isEmpty) return;
    // update도 "touch"로 취급
    _providers.remove(url);
    // 상한 초과 시: 가장 오래된 것부터 제거
    while (_providers.length >= _maxEntries) {
      _providers.remove(_providers.keys.first);
    }
    _providers[url] = provider;
  }
}
