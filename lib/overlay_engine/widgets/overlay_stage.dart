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
    required this.containerSize,
    this.enabled = true,
    this.controller,
  });

  final Size imageSize;
  final Rect displayImageRect;
  final Size containerSize; // ✅ 크롭박스와 동일: containerSize 필요
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

  // ✅ 크롭 에디터와 동일한 방식: enabled가 true일 때만 생성
  //    enabled는 이미 _isBottomSheetAnimationComplete를 고려한 값
  bool _hasRequestedCreation = false; // ✅ 생성 요청 중복 방지

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

    // ✅ enabled가 false -> true로 변경되었을 때 생성 준비
    if (!oldWidget.enabled && widget.enabled) {
      _hasRequestedCreation = false; // ✅ enabled가 true가 되면 생성 가능
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // ✅ Controller에서 최초 생성 플래그를 관리하므로 여기서는 상태만 갱신
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
    if (!widget.enabled) {
      // ✅ disabled 시 상태 리셋
      _hasRequestedCreation = false;
      return const SizedBox.shrink();
    }

    // ✅ 크롭 에디터와 동일한 방식: enabled가 true이고 아이템이 없을 때만 생성
    //    enabled는 이미 _isBottomSheetAnimationComplete를 고려한 값
    if (widget.enabled && _c.items.isEmpty && !_hasRequestedCreation) {
      _hasRequestedCreation = true;

      debugPrint('📐 [OverlayStage] displayImageRect 확정 (크롭과 동일한 방식):');
      debugPrint(
        '   displayImageRect: ${widget.displayImageRect.left.toStringAsFixed(1)}, ${widget.displayImageRect.top.toStringAsFixed(1)}, ${widget.displayImageRect.width.toStringAsFixed(1)}x${widget.displayImageRect.height.toStringAsFixed(1)}',
      );
      debugPrint(
        '   containerSize: ${widget.containerSize.width.toStringAsFixed(1)}x${widget.containerSize.height.toStringAsFixed(1)} (전체 컨테이너 크기)',
      );
      debugPrint(
        '   imageSize: ${widget.imageSize.width.toStringAsFixed(1)}x${widget.imageSize.height.toStringAsFixed(1)} (원본 이미지 크기)',
      );
      debugPrint(
        '   scale: ${(widget.imageSize.width / widget.displayImageRect.width).toStringAsFixed(3)} (이미지→화면 스케일)',
      );
      debugPrint(
        '   ✅ displayImageRect는 이미지가 실제로 그려진 영역 (containerSize 내에서 fit)',
      );

      // ✅ 크롭과 동일: PostFrameCallback 사용
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _c.items.isNotEmpty) return;

        // ✅ 이제 안정된 displayImageRect로 생성
        _c.ensureDemoItems(
          imageSize: widget.imageSize,
          displayImageRect: widget.displayImageRect,
          containerSize: widget.containerSize,
        );
      });
    }

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
        // ✅ 제스처 종료 시 최초 생성 플래그 제거 (이제부터 clamp 적용)
        // ⚠️ 중요: 재투영은 하지 않음
        //          overlay state는 displayRect 변화를 모르고, 렌더링만 displayRect를 사용
        if (_activeId != null) {
          _c.markAsUsed(_activeId!);
        }

        _activeId = null;
        _lastFocalLocal = null;
        _startScale = null;
        _startRotation = null;
        _startAnchorImage = null;
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

    // ✅ 좌표 기준 통일: deltaLocal은 OverlayStage local 좌표계
    //    displayRect를 local 기준으로 정규화하여 사용
    final displayRect = _gestureDisplayRect ?? widget.displayImageRect;
    final localDisplayRect = Rect.fromLTWH(
      0,
      0,
      displayRect.width,
      displayRect.height,
    );
    final imageDelta = OverlayCoords.screenDeltaToImageDelta(
      screenDelta: deltaLocal,
      imageSize: widget.imageSize,
      displayRect: localDisplayRect,
    );

    // ✅ 회전까지 고려한 "외접 AABB" 반경으로 clamp
    // ⚠️ 중요: clamp는 100% image space에서만 수행
    //          - halfW/halfH는 image space 값 (displayScale 절대 사용 금지)
    //          - baseSizeImage는 이미지 좌표계의 절대 크기(불변)
    //          - userScale만 적용 (displayScale은 렌더링 전용)
    final halfW0 =
        (item.transform.baseSizeImage.width * item.transform.scale) / 2;
    final halfH0 =
        (item.transform.baseSizeImage.height * item.transform.scale) / 2;
    final eff = _effectiveHalfExtents(
      halfW: halfW0,
      halfH: halfH0,
      rotationRad: item.transform.rotationRad,
    );
    // ✅ 최초 생성된 아이템은 첫 드래그에서 clamp 생략 (자유롭게 이동 가능)
    // Controller에서 최초 생성 플래그 관리
    final rawAnchor = item.transform.anchorImage + imageDelta;
    final nextAnchor =
        _c.isJustCreated(id)
            ? rawAnchor // ✅ 최초 생성: clamp 생략
            : _clampAnchorImage(
              anchor: rawAnchor,
              imageSize: widget.imageSize,
              halfW: eff.$1,
              halfH: eff.$2,
              displayRect: _gestureDisplayRect ?? widget.displayImageRect,
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

    // ✅ 인스타식: 핀치/회전은 스티커 중심 기준 (anchor는 변하지 않음)
    final startScale = _startScale ?? item.transform.scale;
    final startRotation = _startRotation ?? item.transform.rotationRad;
    final startAnchor = _startAnchorImage ?? item.transform.anchorImage;

    final nextScale = (startScale * details.scale).clamp(0.2, 8.0);
    final nextRotation = _normalizeRad(startRotation + details.rotation);

    // ✅ 스케일/회전 후에도 경계 내에 있는지 clamp만 체크
    // ⚠️ 중요: clamp는 100% image space에서만 수행
    //          - halfW/halfH는 image space 값 (displayScale 절대 사용 금지)
    //          - baseSizeImage는 이미지 좌표계의 절대 크기(불변)
    //          - userScale만 적용 (displayScale은 렌더링 전용)
    final halfW0 = (item.transform.baseSizeImage.width * nextScale) / 2;
    final halfH0 = (item.transform.baseSizeImage.height * nextScale) / 2;
    final eff = _effectiveHalfExtents(
      halfW: halfW0,
      halfH: halfH0,
      rotationRad: nextRotation,
    );
    final displayRect = _gestureDisplayRect ?? widget.displayImageRect;
    final nextAnchor = _clampAnchorImage(
      anchor: startAnchor, // ✅ 핀치/회전은 anchor 이동 없음 (중심 고정)
      imageSize: widget.imageSize,
      halfW: eff.$1,
      halfH: eff.$2,
      displayRect: displayRect,
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
    // ✅ 제스처 중에는 freeze된 displayRect 사용 (렌더링도 동일한 기준)
    //    제스처 없을 때는 최신 displayRect 사용
    final displayRect = _gestureDisplayRect ?? widget.displayImageRect;
    final anchorScreen = OverlayCoords.imageToScreenOffset(
      imageOffset: t.anchorImage,
      imageSize: widget.imageSize,
      displayRect: displayRect,
    );
    final baseScreenSize = OverlayCoords.imageToScreenSize(
      imageSizeValue: t.baseSizeImage,
      imageSize: widget.imageSize,
      displayRect: displayRect,
    );

    final isSelected = _c.selectedId == item.id;
    final stroke = isSelected ? 3.0 : 2.0;
    final borderColor = isSelected ? Colors.white : item.color;
    final fill = item.color.withOpacity(0.18);

    // ✅ 안전한 중심 기준 Transform 패턴
    // anchorScreen = 스티커 중심
    // 회전/스케일 = 중심 기준
    // 마지막에 위젯 좌상단 보정
    final widgetCenter = Offset(
      baseScreenSize.width / 2,
      baseScreenSize.height / 2,
    );
    final m =
        Matrix4.identity()
          ..translate(anchorScreen.dx, anchorScreen.dy) // anchorScreen(중심)으로 이동
          ..rotateZ(t.rotationRad) // 중심 기준 회전
          ..scale(t.scale, t.scale) // 중심 기준 스케일
          ..translate(-widgetCenter.dx, -widgetCenter.dy); // 위젯 좌상단 보정

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

  /// ✅ 크롭박스와 동일한 방식: visibleImageRect 기반으로 clamp
  ///
  /// ⚠️ 중요: clamp는 100% image space에서만 수행
  /// - anchor: image space 좌표
  /// - halfW/halfH: image space 반경 (displayScale 절대 사용 금지)
  /// - displayRect는 visibleImageRect 계산용으로만 사용 (clamp 계산에는 사용 안 함)
  ///
  /// 크롭박스 로직:
  /// 1. visibleImageRect = displayImageRect.intersect(containerRect)
  /// 2. 화면 좌표를 이미지 좌표로 변환: scaleX = imageSize.width / displayImageRect.width
  /// 3. clamp는 visibleImageRect에 해당하는 이미지 좌표 영역 내에서만 수행
  Offset _clampAnchorImage({
    required Offset anchor, // image space 좌표
    required Size imageSize,
    required double halfW, // image space 반경 (displayScale 미적용)
    required double halfH, // image space 반경 (displayScale 미적용)
    required Rect displayRect, // displayRect는 이미 container 기준으로 계산된 값
  }) {
    // ✅ 1. displayRect는 이미지가 화면에 그려진 영역
    // ⚠️ 중요: displayRect.width * (imageSize.width / displayRect.width) = imageSize.width (항상)
    //          displayRect.height * (imageSize.height / displayRect.height) = imageSize.height (항상)
    //          따라서 displayRect는 항상 이미지 전체를 보여줌
    //          clamp는 전체 이미지 내에서 수행
    // ✅ displayRect는 이미지 전체를 보여주므로, clamp는 전체 이미지 내에서 수행
    //    displayRect의 위치는 clamp 계산에 필요 없음 (이미지 전체가 기준)
    final visibleImageRectImage = Rect.fromLTWH(
      0,
      0,
      imageSize.width, // ✅ 항상 전체 이미지 너비
      imageSize.height, // ✅ 항상 전체 이미지 높이
    );

    // ✅ 3. visibleImageRect 내에서만 clamp (크롭박스와 동일)
    // 스티커 중심이 visibleImageRect 내에 있도록 제한
    // ⚠️ 중요: clamp는 스티커의 중심이 경계를 벗어나지 않도록 하는 것
    // 따라서 스티커의 반경(halfW, halfH)만큼 여유를 두어야 함
    final minX = visibleImageRectImage.left + halfW;
    final maxX = visibleImageRectImage.right - halfW;
    final minY = visibleImageRectImage.top + halfH;
    final maxY = visibleImageRectImage.bottom - halfH;

    // ✅ clamp 범위가 유효한지 확인
    if (minX >= maxX || minY >= maxY) {
      // clamp 불가능한 경우 중앙에 위치
      return visibleImageRectImage.center;
    }

    // ✅ 스티커가 visible 영역보다 크면 중앙에 위치
    if (halfW >= visibleImageRectImage.width / 2) {
      return Offset(
        visibleImageRectImage.center.dx,
        anchor.dy.clamp(minY, maxY),
      );
    }
    if (halfH >= visibleImageRectImage.height / 2) {
      return Offset(
        anchor.dx.clamp(minX, maxX),
        visibleImageRectImage.center.dy,
      );
    }

    // ✅ 정상적인 clamp 수행
    // ⚠️ 중요: clamp는 min/max 범위 내로 제한
    final clampedX = anchor.dx.clamp(minX, maxX);
    final clampedY = anchor.dy.clamp(minY, maxY);

    // ✅ 디버그: clamp 범위와 결과 확인
    debugPrint('🔒 [OverlayStage] clamp 범위:');
    debugPrint(
      '   imageSize: ${imageSize.width.toStringAsFixed(1)}x${imageSize.height.toStringAsFixed(1)}',
    );
    debugPrint(
      '   halfW: ${halfW.toStringAsFixed(1)}, halfH: ${halfH.toStringAsFixed(1)}',
    );
    debugPrint(
      '   minX: ${minX.toStringAsFixed(1)}, maxX: ${maxX.toStringAsFixed(1)}',
    );
    debugPrint(
      '   minY: ${minY.toStringAsFixed(1)}, maxY: ${maxY.toStringAsFixed(1)}',
    );
    debugPrint(
      '   입력 anchor: (${anchor.dx.toStringAsFixed(1)}, ${anchor.dy.toStringAsFixed(1)})',
    );
    debugPrint(
      '   출력 clamped: (${clampedX.toStringAsFixed(1)}, ${clampedY.toStringAsFixed(1)})',
    );

    // 디버그: clamp가 실제로 제한하는지 확인
    if (clampedX != anchor.dx || clampedY != anchor.dy) {
      debugPrint('🔒 [OverlayStage] clamp 적용:');
      debugPrint(
        '   입력: (${anchor.dx.toStringAsFixed(1)}, ${anchor.dy.toStringAsFixed(1)})',
      );
      debugPrint(
        '   출력: (${clampedX.toStringAsFixed(1)}, ${clampedY.toStringAsFixed(1)})',
      );
      debugPrint(
        '   범위: X[${minX.toStringAsFixed(1)}, ${maxX.toStringAsFixed(1)}], Y[${minY.toStringAsFixed(1)}, ${maxY.toStringAsFixed(1)}]',
      );
      debugPrint(
        '   halfW: ${halfW.toStringAsFixed(1)}, halfH: ${halfH.toStringAsFixed(1)}',
      );
      debugPrint(
        '   visibleImageRectImage: ${visibleImageRectImage.left.toStringAsFixed(1)}, ${visibleImageRectImage.top.toStringAsFixed(1)}, ${visibleImageRectImage.width.toStringAsFixed(1)}x${visibleImageRectImage.height.toStringAsFixed(1)}',
      );
    }

    return Offset(clampedX, clampedY);
  }

  bool _containsPoint(OverlayItem item, Offset screenPoint) {
    final t = item.transform;
    // ✅ 좌표계 통일: 모든 계산을 OverlayStage의 local 좌표계로 통일
    // screenPoint는 이미 OverlayStage의 local 좌표계 (Positioned.fill 기준)
    // anchorScreen도 같은 좌표계로 변환해야 함
    // ✅ 제스처 중에는 freeze된 displayRect 사용 (hit test도 동일한 기준)
    final displayRect = _gestureDisplayRect ?? widget.displayImageRect;

    // anchorScreen을 OverlayStage local 좌표계로 변환
    final anchorScreenInDisplayRect = OverlayCoords.imageToScreenOffset(
      imageOffset: t.anchorImage,
      imageSize: widget.imageSize,
      displayRect: displayRect,
    );
    // displayImageRect의 offset을 빼서 OverlayStage local 좌표계로 변환
    final anchorScreen = Offset(
      anchorScreenInDisplayRect.dx - displayRect.left,
      anchorScreenInDisplayRect.dy - displayRect.top,
    );

    final baseScreenSize = OverlayCoords.imageToScreenSize(
      imageSizeValue: t.baseSizeImage,
      imageSize: widget.imageSize,
      displayRect: displayRect,
    );

    // ✅ MVP 안정성 우선:
    // 회전까지 고려한 정확 히트테스트는 좌표계/행렬 이슈가 생기면 "특정 지점만" 잡히는 현상이 나기 쉽다.
    // 우선 화면상의 AABB(축정렬 박스)로 히트테스트하여 사각형 영역 어디를 눌러도 즉시 선택되게 한다.
    final w = baseScreenSize.width * t.scale;
    final h = baseScreenSize.height * t.scale;
    final rect = Rect.fromCenter(center: anchorScreen, width: w, height: h);

    // ✅ 이제 screenPoint와 rect 모두 OverlayStage local 좌표계
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
