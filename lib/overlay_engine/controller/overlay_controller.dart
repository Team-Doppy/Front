import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/overlay_item.dart';
import '../models/overlay_transform.dart';

class OverlayController extends ChangeNotifier {
  OverlayController({List<OverlayItem>? initialItems})
    : _items = List<OverlayItem>.from(initialItems ?? const []);

  final List<OverlayItem> _items;
  String? _selectedId;
  final Set<String> _justCreatedIds = {}; // ✅ 최초 생성된 아이템 ID (첫 드래그에서 clamp 지연)

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
    final isNew = i < 0;
    if (isNew) {
      _items.add(item);
      // ✅ 새로 추가된 아이템은 최초 생성 플래그에 추가
      _justCreatedIds.add(item.id);
    } else {
      _items[i] = item;
    }
    notifyListeners();
  }

  /// ✅ 아이템이 첫 드래그를 완료했는지 확인
  bool isJustCreated(String id) => _justCreatedIds.contains(id);

  /// ✅ 아이템이 첫 드래그를 완료했음을 표시 (제스처 종료 시 호출)
  void markAsUsed(String id) {
    _justCreatedIds.remove(id);
  }

  /// MVP: 테스트용 더미 사각형 1개 생성(화면에 보이는 이미지 영역 중앙) + 바로 선택
  /// ✅ displayImageRect와 containerSize를 고려하여 visibleImageRect 기준으로 생성
  void ensureDemoItems({
    required Size imageSize,
    required Rect displayImageRect,
    required Size containerSize,
  }) {
    // ✅ 이미 생성된 경우에도 displayImageRect가 변경되었으면 재생성
    // (바텀시트가 올라오면서 displayImageRect가 축소되는 경우 대응)
    if (_items.isNotEmpty) {
      // 기존 아이템이 있으면 그대로 유지 (재생성하지 않음)
      return;
    }

    // ✅ 초기 생성 조건 (반드시 만족해야 함)
    // ⚠️ 중요: anchorImage는 반드시 이미지의 정확한 중앙 (image space)
    //          - displayRect.center 사용 금지 (displayRect는 screen space)
    //          - imageSize.center 사용 (이미지 좌표계의 절대 중앙)
    // ⚠️ 중요: baseSizeImage는 이미지 좌표계의 절대 크기(불변, logical size)
    //          - displayRect와 무관한 논리적 크기로 설정
    //          - 렌더링 시 displayRect scale × userScale이 적용됨
    // ⚠️ 중요: scale은 1.0으로 시작
    // ⚠️ 중요: 생성 시 clamp 절대 호출 금지
    // ⚠️ 중요: 이 함수가 정합성을 보장하는 유일한 곳 (OverlayStage는 신뢰만 함)
    final center = Offset(imageSize.width / 2, imageSize.height / 2);
    // ✅ baseSizeImage는 이미지 좌표계의 절대 크기 (예: 이미지 크기의 25%)
    //    렌더링 시 displayRect scale이 자동으로 적용됨
    final baseSize = Size(imageSize.width * 0.25, imageSize.height * 0.25);

    final newItem = OverlayItem(
      id: 'rect_1',
      type: OverlayItemType.rect,
      zIndex: 1,
      color: const Color(0xFF00BCD4),
      transform: OverlayTransform(
        anchorImage: center, // ✅ 반드시 중심
        baseSizeImage: baseSize, // ✅ visible 기준
        scale: 1.0, // ✅ 초기 스케일 1.0
        rotationRad: 0.0, // ✅ 초기 회전 0
      ),
    );

    _items.add(newItem);
    _justCreatedIds.add(newItem.id); // ✅ 최초 생성 플래그 설정
    _selectedId = 'rect_1';
    notifyListeners();
  }
}
