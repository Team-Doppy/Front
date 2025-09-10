import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';

enum StickerType { image, text, emoji }

class Sticker {
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
  final List<Sticker> _stickers = <Sticker>[];
  String? _selectedId;

  List<Sticker> get stickers {
    final list = List<Sticker>.from(_stickers);
    list.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return list;
  }

  String? get selectedId => _selectedId;

  void addSticker(Sticker sticker) {
    _stickers.add(sticker);
    _selectedId = sticker.id;
    notifyListeners();
  }

  void addTextSticker(String text, Offset at) {
    addSticker(
      Sticker(
        id: 'stk_${DateTime.now().millisecondsSinceEpoch}',
        type: StickerType.text,
        content: text,
        position: at,
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

  void remove(String id) {
    _stickers.removeWhere((s) => s.id == id);
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
  }
}
