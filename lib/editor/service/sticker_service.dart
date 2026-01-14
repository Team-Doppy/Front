import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';

enum StickerType { image } // 🎯 PNG 드로잉만 지원

/// 스티커 변경 종류 (에디터 히스토리 연동용)
enum StickerChangeKind { none, add, remove, clear, transform, restore }

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
  static final StickerService _instance = StickerService._internal();
  factory StickerService() => _instance;
  StickerService._internal();

  // 스케일 한계
  static const double minScale = 0.4;
  static const double maxScale = 3.0;
  final List<Sticker> _stickers = <Sticker>[];
  String? _selectedId;

  // 변화 감지를 위한 초기 상태 저장
  List<Sticker> _initialStickers = <Sticker>[];

  // 🎯 에디터 히스토리 연동(추가/삭제만 기록하기 위한 change kind)
  StickerChangeKind _lastChangeKind = StickerChangeKind.none;
  String? _lastChangedStickerId;
  bool _isRestoringFromHistory = false;

  // 🎯 transform 히스토리 스팸 방지용 임계치 (endDrag에서만 판정)
  static const double _kMoveThresholdPx = 12.0;
  static const double _kScaleThreshold = 0.03; // 3%
  static const double _kRotationThresholdRad = 0.05; // ~2.9°

  // 드래그 오버레이 상태
  String? _draggingId;
  Offset _dragBasePos = Offset.zero;
  double _dragBaseScale = 1.0;
  double _dragBaseRot = 0.0;
  Offset _dragAccum = Offset.zero;
  double _scaleDelta = 1.0;
  double _rotationDelta = 0.0;
  bool _dragOverDelete = false;
  bool _isPanning = false; // 팬 제스처 진행 중 여부

  // 드래그 중 실시간 위치 업데이트용 ValueNotifier (rebuild 없이)
  final ValueNotifier<Offset?> dragPreviewPosNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isDraggingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> dragOverDeleteNotifier = ValueNotifier(false);
  // 🎯 툴바가 내려간 후 휴지통 표시용 (툴바 애니메이션 완료 후 표시)
  final ValueNotifier<bool> shouldShowTrashNotifier = ValueNotifier(false);

  Timer? _trashDisplayTimer; // 휴지통 표시 타이머

  List<Sticker> get stickers {
    final list = List<Sticker>.from(_stickers);
    list.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return list;
  }

  StickerChangeKind get lastChangeKind => _lastChangeKind;
  String? get lastChangedStickerId => _lastChangedStickerId;
  bool get isRestoringFromHistory => _isRestoringFromHistory;

  String? get selectedId => _selectedId;
  String? get draggingId => _draggingId;
  bool get isDragging => _draggingId != null;
  bool get isPanning => _isPanning; // 팬 제스처 진행 중
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
    _lastChangeKind = StickerChangeKind.add;
    _lastChangedStickerId = withZ.id;
    notifyListeners();
  }

  void addImageSticker(Uint8List bytes, Offset at) {
    addSticker(
      Sticker(
        id: 'stk_${DateTime.now().millisecondsSinceEpoch}',
        type: StickerType.image,
        content: bytes,
        position: at,
        scale: 1,
      ),
    );
  }

  /// 그리기 스티커 추가 (PNG 또는 벡터)
  void addDrawingSticker(
    List<Map<String, dynamic>> strokes,
    Offset at, {
    int? groupIndex,
  }) {
    // groupIndex가 있으면 고유 ID 생성을 위해 추가
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uniqueId =
        groupIndex != null ? 'stk_${timestamp}_$groupIndex' : 'stk_$timestamp';

    // 🎯 PNG 이미지인지 확인 (type: 'png_image')
    if (strokes.length == 1 && strokes[0]['type'] == 'png_image') {
      final pngData = strokes[0];
      final url = pngData['url'] as String?; // DrawingOverlay에서 업로드 완료된 URL
      final width = pngData['width']; // 논리 픽셀 크기
      final height = pngData['height']; // 논리 픽셀 크기

      if (url != null) {
        // ✅ 이미 업로드 완료된 URL + 크기 정보
        addSticker(
          Sticker(
            id: uniqueId,
            type: StickerType.image,
            content: {'url': url, 'width': width, 'height': height},
            position: at,
            scale: 1.0,
          ),
        );
      } else {
        // ⚠️ URL이 없으면 (레거시 또는 에러)
        final imageData = pngData['imageData'] as Uint8List?;
        if (imageData != null) {
          addSticker(
            Sticker(
              id: uniqueId,
              type: StickerType.image,
              content: imageData,
              position: at,
              scale: 1.0,
            ),
          );
        }
      }
    }
    // 🎯 벡터 드로잉 제거됨 (PNG만 지원)
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
            type: StickerType.image,
            content: '',
            position: Offset.zero,
          ),
    );
    // 이미 드래그 중이면 무시 (중복 beginDrag 방지)
    if (_draggingId == id && _isPanning) {
      // ignore: avoid_print
      debugPrint('[StickerService] beginDrag ignored - already dragging $id');
      return;
    }

    _draggingId = id;
    _dragBasePos = s.position;
    _dragBaseScale = s.scale;
    _dragBaseRot = s.rotation;
    _dragAccum = Offset.zero; // 누적 델타 리셋
    _isPanning = true; // 팬 제스처 시작
    _scaleDelta = 1.0; // 배율은 항상 1.0에서 시작(상대 배율)
    _rotationDelta = 0.0; // 회전도 상대값으로 시작

    // ValueNotifier 초기화
    dragPreviewPosNotifier.value = _dragBasePos;
    isDraggingNotifier.value = true;
    dragOverDeleteNotifier.value = false;
    // 🎯 휴지통은 툴바가 내려간 후(200ms 후) 표시
    shouldShowTrashNotifier.value = false;

    // 기존 타이머 취소 (중복 방지)
    _trashDisplayTimer?.cancel();
    _trashDisplayTimer = Timer(const Duration(milliseconds: 300), () {
      if (_draggingId == id) {
        // 드래그가 여전히 진행 중인지 확인
        shouldShowTrashNotifier.value = true;
      }
    });

    // notifyListeners() 완전 제거: 제스처 취소 방지
    // ValueNotifier 변경으로 UI는 자동 업데이트됨
  }

  void updateDrag(
    Offset delta, {
    double scaleDelta = 1.0,
    double rotationDelta = 0.0,
  }) {
    if (_draggingId == null) return;
    _dragAccum += delta;
    _scaleDelta *= scaleDelta; // 누적 곱셈
    _rotationDelta += rotationDelta; // 누적 덧셈

    // ValueNotifier로 실시간 위치 업데이트 (rebuild 없이)
    dragPreviewPosNotifier.value = dragPreviewPos;

    // notifyListeners() 제거: ValueNotifier로 대체하여 성능 향상
  }

  void endDrag() {
    if (_draggingId == null) return;
    final id = _draggingId!;

    if (_dragOverDelete) {
      // ignore: avoid_print
      debugPrint('[StickerService] endDrag delete id=' + id);
      remove(id);
    } else {
      var newPos = dragPreviewPos;
      // 수직 위치를 안전 범위로 클램프 (엔드 시 최종 보정)
      // 호출자가 스크롤/뷰포트 정보를 모르므로, 음수나 비정상 큰 값만 간단 방지
      if (newPos.dy.isNaN || newPos.dy.isInfinite) newPos = const Offset(0, 0);
      final newScale = dragPreviewScale.clamp(minScale, maxScale);
      final newRot = dragPreviewRotation;
      // ignore: avoid_print
      debugPrint(
        '[StickerService] endDrag commit id=' +
            id +
            ' pos=' +
            newPos.toString() +
            ' scale=' +
            newScale.toString() +
            ' rot=' +
            newRot.toString(),
      );
      // 드래그 종료 시 zIndex 업데이트 (최상단으로)
      bringToFront(id, silent: true); // 아직 notify 안함

      // 🎯 "의미 있는 이동/변형"인지 판정 (히스토리 기록용)
      final moved = (newPos - _dragBasePos).distance > _kMoveThresholdPx;
      final scaled = (newScale - _dragBaseScale).abs() > _kScaleThreshold;
      final rotated = (newRot - _dragBaseRot).abs() > _kRotationThresholdRad;
      final significantTransform = moved || scaled || rotated;

      // endDrag에서는 notify 1회만 발생시키기 위해 silent 적용
      transform(
        id,
        position: newPos,
        scale: newScale,
        rotation: newRot,
        silent: true,
      );

      _lastChangeKind =
          significantTransform
              ? StickerChangeKind.transform
              : StickerChangeKind.none;
      _lastChangedStickerId = significantTransform ? id : null;
    }
    _draggingId = null;
    _dragAccum = Offset.zero;
    _scaleDelta = 1.0;
    _rotationDelta = 0.0;
    _dragOverDelete = false;
    _isPanning = false; // 팬 제스처 종료

    // ValueNotifier 리셋
    dragPreviewPosNotifier.value = null;
    isDraggingNotifier.value = false;
    dragOverDeleteNotifier.value = false;
    shouldShowTrashNotifier.value = false;

    // 휴지통 표시 타이머 취소
    _trashDisplayTimer?.cancel();
    _trashDisplayTimer = null;

    // ignore: avoid_print
    debugPrint('[StickerService] endDrag reset');
    notifyListeners(); // 드래그 종료 시 한 번만 notify
  }

  /// 드래그가 비정상적으로 남아있을 때 안전하게 종료한다. (탭/취소 케이스 방어)
  void cancelDragIfNeeded() {
    if (_draggingId == null && !isDraggingNotifier.value) return;
    try {
      _draggingId = null;
      _dragAccum = Offset.zero;
      _scaleDelta = 1.0;
      _rotationDelta = 0.0;
      _dragOverDelete = false;
      _isPanning = false;
      dragPreviewPosNotifier.value = null;
      isDraggingNotifier.value = false;
      dragOverDeleteNotifier.value = false;
      shouldShowTrashNotifier.value = false;

      // 휴지통 표시 타이머 취소
      _trashDisplayTimer?.cancel();
      _trashDisplayTimer = null;
    } catch (_) {}
  }

  bool isDraggingSticker(String id) => _draggingId == id;

  void setDragOverDelete(bool over) {
    if (_dragOverDelete == over) return;
    _dragOverDelete = over;
    dragOverDeleteNotifier.value = over; // ValueNotifier로 대체
    // notifyListeners() 제거: 제스처 취소 방지
  }

  void transform(
    String id, {
    Offset? position,
    double? scale,
    double? rotation,
    bool silent = false,
  }) {
    final index = _stickers.indexWhere((s) => s.id == id);
    if (index == -1) return;
    final current = _stickers[index];
    _stickers[index] = current.copyWith(
      position: position ?? current.position,
      scale: scale ?? current.scale,
      rotation: rotation ?? current.rotation,
    );
    if (!silent) {
      _lastChangeKind = StickerChangeKind.transform;
      _lastChangedStickerId = id;
      notifyListeners();
    }
  }

  void bringToFront(String id, {bool silent = false}) {
    int maxZ = _stickers.fold<int>(0, (p, e) => e.zIndex > p ? e.zIndex : p);
    final i = _stickers.indexWhere((s) => s.id == id);
    if (i == -1) return;
    _stickers[i] = _stickers[i].copyWith(zIndex: maxZ + 1);
    if (!silent) {
      notifyListeners();
    }
  }

  void removeAll() {
    _stickers.clear();
    _initialStickers.clear(); // 🎯 초기 상태도 함께 초기화
    _selectedId = null;
    cancelDragIfNeeded();
    _lastChangeKind = StickerChangeKind.clear;
    _lastChangedStickerId = null;
    notifyListeners();
  }

  /// 초기 상태 저장 (임시저장 불러오기 후 호출)
  void saveInitialState() {
    _initialStickers = List<Sticker>.from(_stickers);
  }

  /// 변화 감지
  bool get hasChanges {
    if (_initialStickers.length != _stickers.length) {
      return true;
    }

    // 각 스티커의 위치, 스케일, 회전, 투명도 비교
    for (int i = 0; i < _stickers.length; i++) {
      final current = _stickers[i];
      final initial = _initialStickers.firstWhere(
        (s) => s.id == current.id,
        orElse: () => current, // ID가 없으면 변화로 간주
      );

      if (initial.id != current.id) return true;

      // 위치 변화 (1픽셀 이상)
      if ((current.position - initial.position).distance > 1.0) {
        return true;
      }

      // 스케일 변화 (0.01 이상)
      if ((current.scale - initial.scale).abs() > 0.01) {
        return true;
      }

      // 회전 변화 (0.01 이상)
      if ((current.rotation - initial.rotation).abs() > 0.01) {
        return true;
      }

      // 투명도 변화 (0.01 이상)
      if ((current.opacity - initial.opacity).abs() > 0.01) {
        return true;
      }
    }

    return false;
  }

  /// 변화 상태 강제 설정
  void markAsChanged() {}

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
      final fallbackData = stickerData['positionFallback'];
      Offset position = const Offset(100, 100); // 기본값

      if (fallbackData is Map) {
        // positionFallback 기반 위치 (문서 절대 좌표): 초안/수정 화면에서는 이것을 우선 사용
        final x = (fallbackData['xPx'] as num?)?.toDouble() ?? 100.0;
        final y = (fallbackData['yPx'] as num?)?.toDouble() ?? 100.0;
        position = Offset(x, y);
        // debug
        // debugPrint('DEBUG: 스티커 위치 복원 (fallback) - x: $x, y: $y');
      } else if (positionData is Map) {
        // anchor는 비율값(relX/relY)만 있으므로 여기서 절대좌표로 정확히 환산할 수 없음
        // 잘못된 위로 치우침을 방지하기 위해 anchor만 있는 경우 기본값 유지
        // 필요 시, 레이아웃이 준비된 컨텍스트에서 별도 해석 로직으로 보완 가능
      }

      // 기타 속성들
      final scale = (stickerData['scale'] ?? 1.0).toDouble();
      final rotation = (stickerData['rotation'] ?? 0.0).toDouble();
      final opacity = (stickerData['opacity'] ?? 1.0).toDouble();
      final zIndex = (stickerData['zIndex'] ?? 0).toInt();

      // 🎯 PNG 드로잉만 지원
      dynamic content;
      if (type == StickerType.image) {
        final contentData = stickerData['content'];
        if (contentData is Map) {
          // URL + 크기 정보 또는 bytes
          if (contentData['url'] != null) {
            content = contentData; // {url, width, height} 그대로
          } else if (contentData['bytes'] != null) {
            // base64 문자열을 Uint8List로 복원 (레거시)
            final base64String = contentData['bytes'].toString();
            content = base64Decode(base64String);
          } else {
            return;
          }
        } else {
          return;
        }
      } else {
        // text, emoji, drawing 타입은 무시
        return;
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
      debugPrint('[StickerService] Error adding sticker from data: $e');
    }
  }

  /// Exported 데이터(서버/임시저장)로부터 스티커를 "조용히" 복원한다.
  /// - 편집 모드 진입 시 호출되며, 이 과정은 히스토리에 기록되면 안 된다.
  /// - 따라서 undo/redo 복원과 동일하게 restore 플래그를 켜고, notify를 1회만 발생시킨다.
  void restoreFromExportedData(List<dynamic> stickersData) {
    _isRestoringFromHistory = true;
    try {
      cancelDragIfNeeded();

      // ✅ 아무 것도 없고 현재도 비어있으면 노티하지 않음 (히스토리/리빌드 오염 방지)
      if (stickersData.isEmpty && _stickers.isEmpty) {
        _lastChangeKind = StickerChangeKind.none;
        _lastChangedStickerId = null;
        return;
      }

      _stickers.clear();
      _initialStickers.clear();
      _selectedId = null;

      for (final raw in stickersData) {
        if (raw is Map<String, dynamic>) {
          _addStickerFromDataSilent(raw);
        } else if (raw is Map) {
          _addStickerFromDataSilent(raw.cast<String, dynamic>());
        }
      }

      _lastChangeKind = StickerChangeKind.restore;
      _lastChangedStickerId = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[StickerService] Error restoring from exported data: $e');
    } finally {
      _isRestoringFromHistory = false;
    }
  }

  /// `addStickerFromData`와 동일한 파싱 로직이지만 notify를 발생시키지 않는다.
  void _addStickerFromDataSilent(Map<String, dynamic> stickerData) {
    try {
      final id = stickerData['id']?.toString() ?? '';
      if (id.isEmpty) return;

      final typeString = stickerData['type']?.toString() ?? '';
      final type = _parseStickerType(typeString);

      // ✅ Exported 데이터(서버/임시저장)에서는 positionFallback/anchor를 사용한다.
      // 레거시/내부 포맷만 'position{dx,dy}'를 갖는다.
      // 편집 모드 진입 시 위치가 크게 틀어지는 문제를 방지하기 위해
      // addStickerFromData와 동일하게 positionFallback을 우선 사용한다.
      Offset position = const Offset(100, 100);
      final fallbackData =
          (stickerData['positionFallback'] as Map?)?.cast<String, dynamic>();
      if (fallbackData != null) {
        final x = (fallbackData['xPx'] as num?)?.toDouble() ?? 100.0;
        final y = (fallbackData['yPx'] as num?)?.toDouble() ?? 100.0;
        position = Offset(x, y);
      } else {
        final pos = (stickerData['position'] as Map?)?.cast<String, dynamic>();
        if (pos != null) {
          position = Offset(
            (pos['dx'] as num?)?.toDouble() ?? 100.0,
            (pos['dy'] as num?)?.toDouble() ?? 100.0,
          );
        }
      }

      final scale = (stickerData['scale'] as num?)?.toDouble() ?? 1.0;
      final rotation = (stickerData['rotation'] as num?)?.toDouble() ?? 0.0;
      final opacity = (stickerData['opacity'] as num?)?.toDouble() ?? 1.0;
      final zIndex = (stickerData['zIndex'] as num?)?.toInt() ?? 0;

      // 🎯 PNG 드로잉만 지원
      dynamic content;
      if (type == StickerType.image) {
        final contentData = stickerData['content'];
        if (contentData is Map) {
          if (contentData['url'] != null) {
            content = contentData;
          } else if (contentData['bytes'] != null) {
            final base64String = contentData['bytes'].toString();
            content = base64Decode(base64String);
          } else {
            return;
          }
        } else {
          return;
        }
      } else {
        return;
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
    } catch (e) {
      debugPrint('[StickerService] Error adding sticker from data(silent): $e');
    }
  }

  StickerType _parseStickerType(String typeString) {
    // 🎯 PNG 드로잉만 지원
    return StickerType.image;
  }

  void remove(String id) {
    _stickers.removeWhere((s) => s.id == id);
    if (_selectedId == id) _selectedId = null;
    _lastChangeKind = StickerChangeKind.remove;
    _lastChangedStickerId = id;
    notifyListeners();
  }

  /// undo/redo 히스토리에서 스티커 상태를 복원한다.
  /// - 이 과정에서 발생하는 notify는 "히스토리 복원"으로 표시되어,
  ///   외부(에디터)에서 히스토리 재저장을 트리거하지 않도록 한다.
  void restoreFromSnapshot(List<Sticker> stickers) {
    _isRestoringFromHistory = true;
    try {
      cancelDragIfNeeded();
      _stickers
        ..clear()
        ..addAll(stickers);
      _selectedId = null;
      _lastChangeKind = StickerChangeKind.restore;
      _lastChangedStickerId = null;
      notifyListeners();
    } finally {
      _isRestoringFromHistory = false;
    }
  }

  /// 에디터 세션 종료 시 스티커 관련 상태를 완전히 정리한다.
  /// [shouldNotify]가 false이면 notifyListeners()를 호출하지 않는다.
  /// dispose() 중 호출 시 위젯 트리가 잠겨있을 수 있으므로 false로 설정해야 한다.
  void resetSession({bool shouldNotify = true}) {
    _isRestoringFromHistory = false;
    _lastChangeKind = StickerChangeKind.none;
    _lastChangedStickerId = null;
    cancelDragIfNeeded();
    _stickers.clear();
    _initialStickers.clear();
    _selectedId = null;
    if (shouldNotify) {
      notifyListeners();
    }
  }
}
