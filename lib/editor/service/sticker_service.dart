import 'dart:ui';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';

enum StickerType { image, text, emoji }

class Sticker {
  // 공통 속성: 컨텐츠, 위치, 스케일, 회전, 투명도, zIndex, 잠금
  final String id;
  final StickerType type;
  final dynamic content; // Uint8List | String
  // position은 문서 기준 좌표(스크롤 상관 없이 문서의 (x,y))
  final Offset position;
  final double scale;
  final double rotation;
  final double opacity;
  final int zIndex;
  final bool locked;

  const Sticker({
    required this.id,
    required this.type,
    required this.content,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.zIndex = 0,
    this.locked = false,
  });

  Sticker copyWith({
    Offset? position,
    double? scale,
    double? rotation,
    double? opacity,
    int? zIndex,
    bool? locked,
    dynamic content,
  }) {
    return Sticker(
      id: id,
      type: type,
      content: content ?? this.content,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      zIndex: zIndex ?? this.zIndex,
      locked: locked ?? this.locked,
    );
  }
}

class StickerService extends ChangeNotifier {
  // 스케일 한계
  static const double minScale = 0.4;
  static const double maxScale = 3.0;
  final List<Sticker> _stickers = <Sticker>[];
  String? _selectedId;

  // 드래그 오버레이 상태
  String? _draggingId;
  Offset _dragBasePos = Offset.zero;
  double _dragBaseScale = 1.0;
  double _dragBaseRot = 0.0;
  Offset _dragAccum = Offset.zero;
  double _scaleDelta = 1.0;
  double _rotationDelta = 0.0;
  bool _dragOverDelete = false;

  List<Sticker> get stickers {
    final list = List<Sticker>.from(_stickers);
    list.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return list;
  }

  String? get selectedId => _selectedId;
  String? get draggingId => _draggingId;
  bool get isDragging => _draggingId != null;
  Offset get dragPreviewPos => _dragBasePos + _dragAccum;
  double get dragPreviewScale =>
      (_dragBaseScale * _scaleDelta).clamp(minScale, maxScale);
  double get dragPreviewRotation => _dragBaseRot + _rotationDelta;
  bool get dragOverDelete => _dragOverDelete;

  void addSticker(Sticker sticker) {
    // 새 스티커를 항상 최상단에 배치
    final int maxZ = _stickers.fold<int>(
      0,
      (p, e) => e.zIndex > p ? e.zIndex : p,
    );
    final Sticker withZ = sticker.copyWith(zIndex: maxZ + 1);
    _stickers.add(withZ);
    // 추가 시 바로 선택하여 보더 표시
    _selectedId = withZ.id;
    notifyListeners();
  }

  void addTextSticker(String text, Offset at) {
    addTextStickerWithStyle(text, null, at);
  }

  void addTextStickerWithStyle(
    String text,
    Map<String, dynamic>? style,
    Offset at,
  ) {
    addSticker(
      Sticker(
        id: 'stk_${DateTime.now().millisecondsSinceEpoch}',
        type: StickerType.text,
        content: <String, dynamic>{'text': text, 'style': style},
        position: at,
        scale: 1.4,
      ),
    );
  }

  void addEmojiSticker(String emoji, Offset at) {
    addSticker(
      Sticker(
        id: 'stk_${DateTime.now().millisecondsSinceEpoch}',
        type: StickerType.emoji,
        content: emoji,
        position: at,
        scale: 1.6,
      ),
    );
  }

  void addImageSticker(Uint8List bytes, Offset at) {
    addSticker(
      Sticker(
        id: 'stk_${DateTime.now().millisecondsSinceEpoch}',
        type: StickerType.image,
        content: bytes,
        position: at,
        scale: 1.2,
      ),
    );
  }

  void updateContent(String id, dynamic content) {
    final index = _stickers.indexWhere((s) => s.id == id);
    if (index == -1) return;
    _stickers[index] = _stickers[index].copyWith(content: content);
    notifyListeners();
  }

  void select(String? id) {
    _selectedId = id;
    notifyListeners();
  }

  // ===== Drag Overlay API =====
  void beginDrag(String id) {
    final s = _stickers.firstWhere(
      (e) => e.id == id,
      orElse:
          () => Sticker(
            id: id,
            type: StickerType.text,
            content: '',
            position: Offset.zero,
          ),
    );
    _draggingId = id;
    _dragBasePos = s.position;
    _dragBaseScale = s.scale;
    _dragBaseRot = s.rotation;
    _dragAccum = Offset.zero; // 누적 델타 리셋
    _scaleDelta = 1.0; // 배율은 항상 1.0에서 시작(상대 배율)
    _rotationDelta = 0.0; // 회전도 상대값으로 시작
    notifyListeners();
  }

  void updateDrag(
    Offset delta, {
    double scaleDelta = 1.0,
    double rotationDelta = 0.0,
  }) {
    if (_draggingId == null) return;
    _dragAccum += delta;
    _scaleDelta = scaleDelta;
    _rotationDelta = rotationDelta;
    notifyListeners();
  }

  void endDrag() {
    if (_draggingId == null) return;
    final id = _draggingId!;
    if (_dragOverDelete) {
      remove(id);
    } else {
      var newPos = dragPreviewPos;
      // 수직 위치를 안전 범위로 클램프 (엔드 시 최종 보정)
      // 호출자가 스크롤/뷰포트 정보를 모르므로, 음수나 비정상 큰 값만 간단 방지
      if (newPos.dy.isNaN || newPos.dy.isInfinite) newPos = const Offset(0, 0);
      final newScale = dragPreviewScale.clamp(minScale, maxScale);
      final newRot = dragPreviewRotation;
      transform(id, position: newPos, scale: newScale, rotation: newRot);
    }
    _draggingId = null;
    _dragAccum = Offset.zero;
    _scaleDelta = 1.0;
    _rotationDelta = 0.0;
    _dragOverDelete = false;
    notifyListeners();
  }

  bool isDraggingSticker(String id) => _draggingId == id;

  void setDragOverDelete(bool over) {
    if (_dragOverDelete == over) return;
    _dragOverDelete = over;
    notifyListeners();
  }

  void transform(
    String id, {
    Offset? position,
    double? scale,
    double? rotation,
  }) {
    final index = _stickers.indexWhere((s) => s.id == id);
    if (index == -1) return;
    final current = _stickers[index];
    _stickers[index] = current.copyWith(
      position: position ?? current.position,
      scale: scale ?? current.scale,
      rotation: rotation ?? current.rotation,
    );
    notifyListeners();
  }

  void bringToFront(String id) {
    int maxZ = _stickers.fold<int>(0, (p, e) => e.zIndex > p ? e.zIndex : p);
    final i = _stickers.indexWhere((s) => s.id == id);
    if (i == -1) return;
    _stickers[i] = _stickers[i].copyWith(zIndex: maxZ + 1);
    notifyListeners();
  }

  void removeAll() {
    _stickers.clear();
    _selectedId = null;
    notifyListeners();
  }

  /// 임시저장 데이터에서 스티커 복원
  void addStickerFromData(Map<String, dynamic> stickerData) {
    try {
      final id =
          stickerData['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final typeString = stickerData['type']?.toString() ?? 'text';
      final StickerType type = _parseStickerType(typeString);

      // 위치 복원
      final positionData = stickerData['anchor'];
      Offset position = const Offset(100, 100); // 기본값
      if (positionData is Map) {
        final relX = positionData['relX']?.toDouble() ?? 0.0;
        final relY = positionData['relY']?.toDouble() ?? 0.0;
        position = Offset(relX, relY);
      }

      // 기타 속성들
      final scale = (stickerData['scale'] ?? 1.0).toDouble();
      final rotation = (stickerData['rotation'] ?? 0.0).toDouble();
      final opacity = (stickerData['opacity'] ?? 1.0).toDouble();
      final zIndex = (stickerData['zIndex'] ?? 0).toInt();

      // 컨텐츠 복원
      dynamic content;
      switch (type) {
        case StickerType.text:
          final contentData = stickerData['content'];
          if (contentData is Map) {
            content = contentData; // {text, style} 형태 그대로 저장
          } else {
            content = {'text': contentData?.toString() ?? '', 'style': null};
          }
          break;
        case StickerType.emoji:
          content = stickerData['content']?.toString() ?? '😀';
          break;
        case StickerType.image:
          final contentData = stickerData['content'];
          if (contentData is Map && contentData['bytes'] != null) {
            // base64 문자열을 Uint8List로 복원
            final base64String = contentData['bytes'].toString();
            content = base64Decode(base64String);
          } else {
            return; // 이미지 데이터가 없으면 스킵
          }
          break;
      }

      final sticker = Sticker(
        id: id,
        type: type,
        content: content,
        position: position,
        scale: scale,
        rotation: rotation,
        opacity: opacity,
        zIndex: zIndex,
      );

      _stickers.add(sticker);
      notifyListeners();
    } catch (e) {
      print('[StickerService] Error adding sticker from data: $e');
    }
  }

  StickerType _parseStickerType(String typeString) {
    switch (typeString) {
      case 'text':
        return StickerType.text;
      case 'emoji':
        return StickerType.emoji;
      case 'image':
        return StickerType.image;
      default:
        return StickerType.text;
    }
  }

  void remove(String id) {
    _stickers.removeWhere((s) => s.id == id);
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
  }
}
