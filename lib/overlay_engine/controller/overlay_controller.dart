import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/overlay_item.dart';
import '../models/overlay_transform.dart';

class OverlayController extends ChangeNotifier {
  OverlayController({List<OverlayItem>? initialItems})
    : _items = List<OverlayItem>.from(initialItems ?? const []);

  final List<OverlayItem> _items;
  String? _selectedId;

  List<OverlayItem> get items =>
      List.unmodifiable(_items..sort((a, b) => a.zIndex.compareTo(b.zIndex)));

  String? get selectedId => _selectedId;

  void setSelected(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  void upsert(OverlayItem item) {
    final i = _items.indexWhere((e) => e.id == item.id);
    if (i >= 0) {
      _items[i] = item;
    } else {
      _items.add(item);
    }
    notifyListeners();
  }

  /// MVP: 테스트용 더미 사각형 1개 생성(이미지 중앙) + 바로 선택
  void ensureDemoItems(Size imageSize) {
    if (_items.isNotEmpty) return;
    _items.add(
      OverlayItem(
        id: 'rect_1',
        type: OverlayItemType.rect,
        zIndex: 1,
        color: const Color(0xFF00BCD4),
        transform: OverlayTransform(
          anchorImage: Offset(imageSize.width * 0.5, imageSize.height * 0.5),
          baseSizeImage: Size(imageSize.width * 0.28, imageSize.height * 0.18),
        ),
      ),
    );
    _selectedId = 'rect_1';
    notifyListeners();
  }
}
