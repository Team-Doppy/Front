import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../controller/overlay_controller.dart';
import '../models/overlay_item.dart';
import '../utils/overlay_coords.dart';

/// 이미지 프리뷰 위에 오버레이들을 얹는 Stage.
///
/// MVP:
/// - 사각형 오버레이 2개 자동 생성
/// - 탭으로 선택
/// - 선택된 오버레이: 드래그/핀치(스케일)/회전
class OverlayStage extends StatefulWidget {
  const OverlayStage({
    super.key,
    required this.imageSize,
    required this.displayImageRect,
    this.enabled = true,
    this.controller,
  });

  final Size imageSize;
  final Rect displayImageRect;
  final bool enabled;
  final OverlayController? controller;

  @override
  State<OverlayStage> createState() => _OverlayStageState();
}

class _OverlayStageState extends State<OverlayStage> {
  late final OverlayController _ownedController = OverlayController();
  OverlayController get _c => widget.controller ?? _ownedController;

  // gesture state
  String? _activeId;
  Offset? _lastFocalLocal;
  Rect? _gestureDisplayRect; // ✅ 제스처 시작 시점의 display rect를 고정(freeze)
  double? _startScale;
  double? _startRotation;
  Offset? _startAnchorImage;
  Offset? _startFocalScreen;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant OverlayStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      _c.addListener(_onControllerChanged);
    }
    // 이미지 크기가 확정되면 더미 아이템 생성
    _c.ensureDemoItems(widget.imageSize);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChanged);
    _ownedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    // 첫 build에서도 ensure
    _c.ensureDemoItems(widget.imageSize);

    // ✅ 인스타 방식:
    // - 1손가락: 드래그
    // - 2손가락+: 핀치 줌 + 회전
    // ✅ 바텀시트/레이아웃 변화로 display rect가 흔들려도 튀지 않도록,
    // 제스처 시작 시점의 rect를 고정해서 변환에 사용한다.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onTapDown: (d) {
        final id = _hitTestTopMost(d.localPosition);
        if (id == null && _c.items.length == 1) {
          _c.setSelected(_c.items.first.id);
        } else {
          _c.setSelected(id);
        }
      },
      onScaleStart: (details) {
        _gestureDisplayRect = widget.displayImageRect;

        final id =
            _hitTestTopMost(details.localFocalPoint) ??
            _c.selectedId ??
            (_c.items.length == 1 ? _c.items.first.id : null);
        _activeId = id;
        if (id != null) {
          _c.setSelected(id);
          final item = _c.items.where((e) => e.id == id).firstOrNull;
          if (item != null) {
            _startScale = item.transform.scale;
            _startRotation = item.transform.rotationRad;
            _startAnchorImage = item.transform.anchorImage;
            _startFocalScreen = details.localFocalPoint;
          }
        }
        _lastFocalLocal = details.localFocalPoint;
      },
      onScaleUpdate: (details) {
        // pointerCount == 1: 드래그
        if (details.pointerCount <= 1) {
          final last = _lastFocalLocal;
          final now = details.localFocalPoint;
          if (last != null) {
            _applyDragDelta(now - last);
          }
          _lastFocalLocal = now;
          return;
        }

        // pointerCount >= 2: 핀치/회전
        _applyScale(details);
        _lastFocalLocal = details.localFocalPoint;
      },
      onScaleEnd: (_) {
        _activeId = null;
        _lastFocalLocal = null;
        _startScale = null;
        _startRotation = null;
        _startAnchorImage = null;
        _startFocalScreen = null;
        _gestureDisplayRect = null;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [for (final item in _c.items) _buildItemView(item)],
      ),
    );
  }

  void _applyDragDelta(Offset deltaLocal) {
    final id = _activeId ?? _c.selectedId;
    if (id == null) return;
    final item = _c.items.where((e) => e.id == id).firstOrNull;
    if (item == null) return;

    final imageDelta = OverlayCoords.screenDeltaToImageDelta(
      screenDelta: deltaLocal,
      imageSize: widget.imageSize,
      displayRect: _gestureDisplayRect ?? widget.displayImageRect,
    );

    // ✅ 회전까지 고려한 "외접 AABB" 반경으로 clamp
    final halfW0 =
        (item.transform.baseSizeImage.width * item.transform.scale) / 2;
    final halfH0 =
        (item.transform.baseSizeImage.height * item.transform.scale) / 2;
    final eff = _effectiveHalfExtents(
      halfW: halfW0,
      halfH: halfH0,
      rotationRad: item.transform.rotationRad,
    );
    final nextAnchor = _clampAnchorImage(
      anchor: item.transform.anchorImage + imageDelta,
      imageSize: widget.imageSize,
      halfW: eff.$1,
      halfH: eff.$2,
    );

    _c.upsert(
      item.copyWith(
        transform: item.transform.copyWith(anchorImage: nextAnchor),
      ),
    );
  }

  void _applyScale(ScaleUpdateDetails details) {
    final id = _activeId ?? _c.selectedId;
    if (id == null) return;
    final item = _c.items.where((e) => e.id == id).firstOrNull;
    if (item == null) return;

    final startScale = _startScale ?? item.transform.scale;
    final startRotation = _startRotation ?? item.transform.rotationRad;
    final startAnchor = _startAnchorImage ?? item.transform.anchorImage;
    final startFocal = _startFocalScreen ?? details.localFocalPoint;

    final imageDelta = OverlayCoords.screenDeltaToImageDelta(
      screenDelta: details.localFocalPoint - startFocal,
      imageSize: widget.imageSize,
      displayRect: _gestureDisplayRect ?? widget.displayImageRect,
    );

    final nextScale = (startScale * details.scale).clamp(0.2, 8.0);
    final nextRotation = _normalizeRad(startRotation + details.rotation);

    final halfW0 = (item.transform.baseSizeImage.width * nextScale) / 2;
    final halfH0 = (item.transform.baseSizeImage.height * nextScale) / 2;
    final eff = _effectiveHalfExtents(
      halfW: halfW0,
      halfH: halfH0,
      rotationRad: nextRotation,
    );
    final nextAnchor = _clampAnchorImage(
      anchor: startAnchor + imageDelta,
      imageSize: widget.imageSize,
      halfW: eff.$1,
      halfH: eff.$2,
    );

    _c.upsert(
      item.copyWith(
        transform: item.transform.copyWith(
          anchorImage: nextAnchor,
          scale: nextScale,
          rotationRad: nextRotation,
        ),
      ),
    );
  }

  Widget _buildItemView(OverlayItem item) {
    final t = item.transform;
    final anchorScreen = OverlayCoords.imageToScreenOffset(
      imageOffset: t.anchorImage,
      imageSize: widget.imageSize,
      displayRect: widget.displayImageRect,
    );
    final baseScreenSize = OverlayCoords.imageToScreenSize(
      imageSizeValue: t.baseSizeImage,
      imageSize: widget.imageSize,
      displayRect: widget.displayImageRect,
    );

    final isSelected = _c.selectedId == item.id;
    final stroke = isSelected ? 3.0 : 2.0;
    final borderColor = isSelected ? Colors.white : item.color;
    final fill = item.color.withOpacity(0.18);

    // 중심 기준 Transform
    final m =
        Matrix4.identity()
          ..translate(anchorScreen.dx, anchorScreen.dy)
          ..rotateZ(t.rotationRad)
          ..scale(t.scale, t.scale)
          ..translate(-baseScreenSize.width / 2, -baseScreenSize.height / 2);

    return IgnorePointer(
      // stage에서 제스처를 일괄 처리(충돌 최소화)
      ignoring: true,
      child: Transform(
        transform: m,
        child: SizedBox(
          width: baseScreenSize.width,
          height: baseScreenSize.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: borderColor, width: stroke),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }

  String? _hitTestTopMost(Offset screenPoint) {
    // zIndex 높은 것부터
    final sorted = [..._c.items]..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    for (final item in sorted) {
      if (_containsPoint(item, screenPoint)) return item.id;
    }
    return null;
  }

  Offset _clampAnchorImage({
    required Offset anchor,
    required Size imageSize,
    required double halfW,
    required double halfH,
  }) {
    final minX = halfW;
    final maxX = math.max(halfW, imageSize.width - halfW);
    final minY = halfH;
    final maxY = math.max(halfH, imageSize.height - halfH);
    return Offset(anchor.dx.clamp(minX, maxX), anchor.dy.clamp(minY, maxY));
  }

  bool _containsPoint(OverlayItem item, Offset screenPoint) {
    final t = item.transform;
    final anchorScreen = OverlayCoords.imageToScreenOffset(
      imageOffset: t.anchorImage,
      imageSize: widget.imageSize,
      displayRect: widget.displayImageRect,
    );
    final baseScreenSize = OverlayCoords.imageToScreenSize(
      imageSizeValue: t.baseSizeImage,
      imageSize: widget.imageSize,
      displayRect: widget.displayImageRect,
    );

    // ✅ MVP 안정성 우선:
    // 회전까지 고려한 정확 히트테스트는 좌표계/행렬 이슈가 생기면 "특정 지점만" 잡히는 현상이 나기 쉽다.
    // 우선 화면상의 AABB(축정렬 박스)로 히트테스트하여 사각형 영역 어디를 눌러도 즉시 선택되게 한다.
    final w = baseScreenSize.width * t.scale;
    final h = baseScreenSize.height * t.scale;
    final rect = Rect.fromCenter(center: anchorScreen, width: w, height: h);
    return rect.contains(screenPoint);
  }

  /// 회전된 사각형의 외접 AABB 반경(half extents)을 계산한다.
  (double, double) _effectiveHalfExtents({
    required double halfW,
    required double halfH,
    required double rotationRad,
  }) {
    final c = math.cos(rotationRad).abs();
    final s = math.sin(rotationRad).abs();
    final effHalfW = (c * halfW) + (s * halfH);
    final effHalfH = (s * halfW) + (c * halfH);
    return (effHalfW, effHalfH);
  }

  double _normalizeRad(double rad) {
    // -pi..pi 범위로 정규화
    var r = rad;
    while (r > math.pi) r -= math.pi * 2;
    while (r < -math.pi) r += math.pi * 2;
    return r;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
