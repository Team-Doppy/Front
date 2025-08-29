import 'dart:io';
import 'package:doppy/editor/image/image_util.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import '../spatial_manager.dart';
import '../simple_grid.dart';

class DocumentInteractiveFloatingImage extends StatefulWidget {
  final String nodeId;
  final String imageUrl;
  final Size size;
  final SpatialManager? spatialManager;
  final GridSystem gridSystem;
  final Offset? initialPosition;
  final double initialScale;
  final VoidCallback? onLayoutUpdateNeeded;
  final ValueChanged<bool>? onDragModeChanged;

  const DocumentInteractiveFloatingImage({
    super.key,
    required this.nodeId,
    required this.imageUrl,
    required this.size,
    required this.initialScale,
    this.spatialManager,
    required this.gridSystem,
    this.initialPosition,
    this.onLayoutUpdateNeeded,
    this.onDragModeChanged,
  });

  @override
  State<DocumentInteractiveFloatingImage> createState() =>
      _DocumentInteractiveFloatingImageState();
}

class _DocumentInteractiveFloatingImageState
    extends State<DocumentInteractiveFloatingImage>
    with DocumentComponent {
  bool _isDragging = false;
  bool _dragModeActive = false; // 롱프레스 진입 후에만 드래그 허용
  Offset _currentOffset = Offset.zero;
  double _scale = 1.0;
  double? _intrinsicAspect; // 원본 비율 (height / width)
  bool _didAutoSize = false;

  bool _isScaling = false;
  bool _isTapped = false;

  Offset _initialTouchOffset = Offset.zero;
  bool _showTopBorder = false;
  bool _showBottomBorder = false;
  bool isOverlapping = false;
  double _baseY = 0.0;

  Map<String, dynamic> _calculateGridValues() {
    final contentWidth = widget.gridSystem.screenWidth;
    final gridSize = (contentWidth / SystemConstants.gridSize);
    final columns = SystemConstants.gridSize.toInt();
    final displaySize = _displaySize;
    final halfWidth = _displaySize.width / 2;

    // 🎯 이미 경계 체크된 _currentOffset 사용 (연산량 최적화)
    final currentCenterX = contentWidth / 2 + _currentOffset.dx;
    final currentLeft = currentCenterX - halfWidth;

    int gridW = (displaySize.width / gridSize).round().clamp(1, columns);
    int gridH = (displaySize.height / gridSize).round().clamp(1, columns);

    // 🎯 그리드 인덱스 계산 (경계 체크 제거로 연산량 감소)
    int gridX = (currentLeft / gridSize).round();

    // 🎯 maxIndex 계산 개선 - 음수 방지
    int maxIndex = (columns - gridW).clamp(0, columns);
    if (maxIndex < 0) maxIndex = 0;

    // 🎯 gridX를 경계 내로 제한
    gridX = gridX.clamp(0, maxIndex);

    return {
      'gridSize': gridSize,
      'columns': columns,
      'gridW': gridW,
      'gridH': gridH,
      'gridX': gridX,
      'displaySize': displaySize,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_didAutoSize) {
      _ensureIntrinsicAspect();
    }
  }

  @override
  void didUpdateWidget(covariant DocumentInteractiveFloatingImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spatialManager != widget.spatialManager) {
      oldWidget.spatialManager?.removeListener(_onSpatialChanged);
      widget.spatialManager?.addListener(_onSpatialChanged);
    }
    if (oldWidget.imageUrl != widget.imageUrl && widget.imageUrl.isNotEmpty) {
      _ensureIntrinsicAspect();
    }
  }

  void _ensureIntrinsicAspect() {
    if (widget.imageUrl.isEmpty) return;
    final img = Image.network(widget.imageUrl);
    final ImageStream stream = img.image.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w > 0 && h > 0 && mounted) {
          setState(() {
            _intrinsicAspect = h / w;
          });
        }
        stream.removeListener(listener);
      },
      onError: (dynamic _, __) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  Size get _actualSize => ImageSizeCalculator.getActualSize(_scale);
  Size get _rawDisplaySize => ImageSizeCalculator.getDisplaySize(_scale);
  Size get _displaySize => _snappedDisplaySize;

  /// 그리드 배수로 스냅된 표시 크기 (에디터에서는 scale이 즉시 반영되어야 함)
  Size get _snappedDisplaySize {
    final contentWidth = widget.gridSystem.screenWidth;
    final gridSize = (contentWidth / SystemConstants.gridSize);
    final raw = _rawDisplaySize;
    double cols = (raw.width / gridSize).roundToDouble();
    cols = cols.clamp(1.0, SystemConstants.gridSize);
    final snappedW = cols * gridSize;

    // 원본 이미지 비율 우선
    final aspect = _intrinsicAspect ?? (raw.height / raw.width);
    final snappedH = snappedW * aspect;

    return Size(snappedW, snappedH);
  }

  // 컨테이너 높이는 표시 높이만 사용 (여백은 main_style_sheet.dart에서 처리)
  double get _containerHeight => _displaySize.height;

  // 로컬 좌표계에서의 이미지 사각형/중심
  Rect get _localImageRect {
    final left = _computeImageLeftForBuild();
    final top = _currentOffset.dy - 6;
    return Rect.fromLTWH(left, top, _displaySize.width, _displaySize.height);
  }

  Offset get _localImageCenter => _localImageRect.center;

  // DocumentComponent 필수 메서드들 (로컬 좌표 기반)
  @override
  UpstreamDownstreamNodePosition? getPositionAtOffset(Offset localOffset) {
    if (_localImageRect.contains(localOffset)) {
      return UpstreamDownstreamNodePosition.upstream();
    }
    return UpstreamDownstreamNodePosition.upstream();
  }

  @override
  Offset getOffsetForPosition(NodePosition nodePosition) {
    return _localImageCenter;
  }

  @override
  Rect getRectForPosition(NodePosition nodePosition) {
    return _localImageRect;
  }

  @override
  Rect getEdgeForPosition(NodePosition nodePosition) {
    return _localImageRect;
  }

  @override
  Rect getRectForSelection(
    NodePosition basePosition,
    NodePosition extentPosition,
  ) {
    return _localImageRect;
  }

  @override
  UpstreamDownstreamNodePosition getBeginningPosition() {
    return UpstreamDownstreamNodePosition.upstream();
  }

  @override
  UpstreamDownstreamNodePosition getBeginningPositionNearX(double x) {
    return UpstreamDownstreamNodePosition.upstream();
  }

  @override
  UpstreamDownstreamNodePosition? movePositionLeft(
    NodePosition currentPosition, [
    MovementModifier? movementModifier,
  ]) {
    return UpstreamDownstreamNodePosition.upstream();
  }

  @override
  UpstreamDownstreamNodePosition? movePositionRight(
    NodePosition currentPosition, [
    MovementModifier? movementModifier,
  ]) {
    return UpstreamDownstreamNodePosition.upstream();
  }

  @override
  UpstreamDownstreamNodePosition? movePositionUp(NodePosition currentPosition) {
    return UpstreamDownstreamNodePosition.upstream();
  }

  @override
  UpstreamDownstreamNodePosition? movePositionDown(
    NodePosition currentPosition,
  ) {
    return UpstreamDownstreamNodePosition.upstream();
  }

  @override
  UpstreamDownstreamNodePosition getEndPosition() {
    return UpstreamDownstreamNodePosition.upstream();
  }

  @override
  UpstreamDownstreamNodePosition getEndPositionNearX(double x) {
    return UpstreamDownstreamNodePosition.upstream();
  }

  @override
  UpstreamDownstreamNodeSelection? getSelectionInRange(
    Offset localBaseOffset,
    Offset localExtentOffset,
  ) {
    return UpstreamDownstreamNodeSelection(
      base: UpstreamDownstreamNodePosition.upstream(),
      extent: UpstreamDownstreamNodePosition.upstream(),
    );
  }

  @override
  UpstreamDownstreamNodeSelection getCollapsedSelectionAt(
    NodePosition nodePosition,
  ) {
    final position = UpstreamDownstreamNodePosition.upstream();
    return UpstreamDownstreamNodeSelection(base: position, extent: position);
  }

  @override
  UpstreamDownstreamNodeSelection getSelectionBetween({
    required NodePosition basePosition,
    required NodePosition extentPosition,
  }) {
    return UpstreamDownstreamNodeSelection(
      base: UpstreamDownstreamNodePosition.upstream(),
      extent: UpstreamDownstreamNodePosition.downstream(),
    );
  }

  @override
  UpstreamDownstreamNodeSelection getSelectionOfEverything() {
    return UpstreamDownstreamNodeSelection(
      base: UpstreamDownstreamNodePosition.upstream(),
      extent: UpstreamDownstreamNodePosition.downstream(),
    );
  }

  @override
  bool isVisualSelectionSupported() => false;

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) {
    return SystemMouseCursors.grab;
  }

  Offset _applyScreenBounds(Offset targetOffset, Size imageSize) {
    // 🎯 연산량 최적화: 불필요한 계산 제거
    final contentWidth = widget.gridSystem.screenWidth;
    final halfWidth = imageSize.width / 2;
    final contentCenterX = contentWidth / 2;

    // 🎯 경계 체크를 한 번에 계산
    final imageCenterX = contentCenterX + targetOffset.dx;
    final imageLeft = imageCenterX - halfWidth;
    final imageRight = imageCenterX + halfWidth;

    // 🎯 경계를 벗어나지 않으면 early return
    if (imageLeft >= 0 && imageRight <= contentWidth) {
      return targetOffset;
    }

    // 🎯 경계를 벗어난 경우에만 수정
    Offset clampedOffset = targetOffset;

    if (imageLeft < 0) {
      final correctedDx = halfWidth - contentCenterX;
      clampedOffset = Offset(correctedDx, targetOffset.dy);
      print(' 왼쪽 경계 도달: correctedDx=$correctedDx');
    } else if (imageRight > contentWidth) {
      final correctedDx = (contentWidth - halfWidth) - contentCenterX;
      clampedOffset = Offset(correctedDx, targetOffset.dy);
      print(' 오른쪽 경계 도달: correctedDx=$correctedDx');
    }

    return clampedOffset;
  }

  ImageDragInfo? _getCurrentDragInfo() {
    final baseY = _baseY;
    final imageHeight = _actualSize.height;
    final dragXOffset = _currentOffset.dx;
    final dragYOffset = _currentOffset.dy;

    return ImageDragInfo(
      baseY: baseY,
      imageHeight: imageHeight,
      dragXOffset: dragXOffset,
      dragYOffset: dragYOffset,
    );
  }

  /// 🎯 문서 기준 Y 위치 계산
  double _calculateDocumentY() {
    // 🎯 이미지가 문서에서 차지하는 실제 Y 위치
    // _baseY는 이미지의 상단 위치를 나타냄
    return _baseY;
  }

  void _updateImagePosition({required Map<String, dynamic> updatedMetadata}) {
    if (widget.spatialManager == null) return;

    final gridValues = _calculateGridValues();
    final displaySize = gridValues['displaySize'] as Size;

    final newMetadata = {
      'scale': _scale,
      'pxW': displaySize.width,
      'pxH': displaySize.height,
      'gridW': gridValues['gridW'],
      'gridH': gridValues['gridH'],
      'gridX': gridValues['gridX'],
      'isImageNode': true,

      ...updatedMetadata,
    };

    // 🎯 문서 기준 좌표계 사용 (analyzeAndUpdateDocument와 일치)
    // 문서에서 이미지가 차지하는 실제 위치 계산
    final documentX =
        gridValues['gridX'] * gridValues['gridSize']; // 그리드 X를 픽셀로 변환
    final documentY = _calculateDocumentY(); // 🎯 문서 기준 Y 위치 계산

    print('🎯 문서 기준 좌표계: X=$documentX, Y=$documentY');
    print(
      '  └── gridX: ${gridValues['gridX']}, gridSize: ${gridValues['gridSize']}',
    );
    print('  └── _baseY: $_baseY');

    widget.spatialManager!.updateElement(
      id: widget.nodeId,
      type: SpatialElementType.image,
      coordinates: DocumentCoordinates(
        document: Offset(documentX, documentY), // 🎯 문서 기준 좌표
        grid: Offset.zero,
      ),
      size: _displaySize,
      metadata: newMetadata,
    );
  }

  void _resetDragState() {
    setState(() {
      _isDragging = false;
      _showTopBorder = false;
      _showBottomBorder = false;
      _dragModeActive = false;
    });
    // 프리뷰 상태 초기화
    widget.spatialManager?.clearRowPreview();
    widget.onDragModeChanged?.call(false);
  }

  void _beginDragAt(Offset globalPosition) {
    final screenWidth = MediaQuery.of(context).size.width;
    _initialTouchOffset = ImagePositionCalculator.getTouchOffset(
      globalPosition,
      _currentOffset,
      screenWidth,
    );
  }

  void _updateDragFromGlobal(Offset globalPosition) {
    // 한 손가락 - 자유로운 2D 드래그 (경계에서만 이동 제한)
    final currentX = globalPosition.dx;
    final currentY = globalPosition.dy;

    final screenWidth = widget.gridSystem.screenWidth;
    final targetImageCenterX = currentX - _initialTouchOffset.dx;
    final targetImageCenterY = currentY - _initialTouchOffset.dy;

    final dragFactorX = 1.0;
    final dragFactorY = 1.0;

    final adjustedTargetX =
        (targetImageCenterX - (screenWidth / 2)) * dragFactorX;
    final adjustedTargetY = (targetImageCenterY - 70) * dragFactorY;

    final targetOffset = Offset(adjustedTargetX, adjustedTargetY);
    final clampedOffset = _applyScreenBounds(targetOffset, _displaySize);

    setState(() {
      _isDragging = true;
      _isScaling = false;
      _currentOffset = clampedOffset;
    });

    _onImageDragging(currentX, currentY);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    setState(() {
      if (details.pointerCount == 2) {
        _isScaling = true;
        _isDragging = false;
        _isTapped = false;
      } else {
        // 단일 터치는 롱프레스 모드에서만 드래그 허용
        if (!_dragModeActive) {
          return;
        }
        _isScaling = false;
        _isDragging = true;
        _isTapped = false;
        _beginDragAt(details.focalPoint);
      }
    });
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount == 2 && details.scale != 1.0) {
      // 두 손가락 - 스케일링 (경계 제한 적용)
      setState(() {
        final newScale = (_scale * details.scale).clamp(
          SystemConstants.scaleMin,
          SystemConstants.scaleMax,
        );

        // 🎯 새로운 크기로 경계 제한 적용
        final newDisplaySize = ImageSizeCalculator.getDisplaySize(newScale);
        final clampedOffset = _applyScreenBounds(
          _currentOffset,
          newDisplaySize,
        );

        // 경계를 벗어나지 않는 경우에만 스케일 적용
        if (clampedOffset == _currentOffset) {
          _scale = newScale;

          _updateImagePosition(
            updatedMetadata: {
              'scale': _scale,
              'pxW': _displaySize.width,
              'pxH': _displaySize.height,
            },
          );
        }

        _isScaling = true;
        _isDragging = false;
      });
    } else if (details.pointerCount == 1) {
      if (!_dragModeActive) return; // 롱프레스 모드에서만 단일 터치 드래그 허용
      // 한 손가락 - 자유로운 2D 드래그 (경계에서만 이동 제한)
      _updateDragFromGlobal(details.focalPoint);
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _updateImagePosition(updatedMetadata: {});
    if (_isScaling) {
      _isScaling = false;
      //FocusManager.instance.primaryFocus?.requestFocus();
    } else if (_isDragging) {
      _handleDragEnd();
    }
    // 드래그가 끝나면 모드 해제
    if (_dragModeActive) {
      _dragModeActive = false;
      widget.onDragModeChanged?.call(false);
    }
  }

  void _handleDragEnd() {
    final deltaX = _currentOffset.dx;
    final deltaY = _currentOffset.dy;

    final gridValues = _calculateGridValues();
    final gridSize = gridValues['gridSize'] as double;
    final columns = gridValues['columns'] as int;

    final displaySize = gridValues['displaySize'] as Size;
    final halfWidth = displaySize.width / 2;
    final contentWidth = widget.gridSystem.screenWidth;
    final contentCenterX = contentWidth / 2;
    final currentCenterX = contentCenterX + deltaX;
    final currentLeft = currentCenterX - halfWidth;

    final rawIndex = (currentLeft / gridSize).round();
    final imageCols = (displaySize.width / gridSize).clamp(1.0, columns);
    final maxIndex = (columns - imageCols).floor();
    final gridIndex = rawIndex.clamp(0, maxIndex);
    final snappedLeft = gridIndex * gridSize;
    final snappedCenterX = snappedLeft + halfWidth;
    final snappedDx = snappedCenterX - contentCenterX;

    final clampedGridOffset = _applyScreenBounds(
      Offset(snappedDx, 0),
      displaySize,
    );

    if (deltaY.abs() > SystemConstants.verticalSwapThreshold) {
      _handleVerticalMovement(clampedGridOffset.dx);
    } else {
      _handleHorizontalMovement(clampedGridOffset.dx);
    }

    setState(() {
      _currentOffset = Offset(clampedGridOffset.dx, 0);
    });
  }

  void _handleVerticalMovement(double deltaX) {
    _moveImageInDocument(deltaX.abs());
    _baseY = _baseY + _currentOffset.dy;
    _currentOffset = Offset(deltaX, 0); //중요
    _resetDragState();
    //_showKeyboard();
  }

  void _handleHorizontalMovement(double clampedGridX) {
    _currentOffset = Offset(clampedGridX, 0); //중요
    _resetDragState();
  }

  void _onImageDragging(double deltaY, double deltaX) {
    if (_currentOffset.dy.abs() > 5.0) {
      final imageDragInfo = _getCurrentDragInfo();

      if (imageDragInfo != null) {
        // 🎯 겹침 감지 (문서 좌표계 기준)
        if (widget.spatialManager != null) {
          // 연속 문서좌표 중심 계산
          final contentWidth = widget.gridSystem.screenWidth;
          final contentCenterX = contentWidth / 2;
          final halfW = _displaySize.width / 2;
          final leftDoc = (contentCenterX + _currentOffset.dx) - halfW;
          final topDoc = _baseY + _currentOffset.dy;
          final Offset centerDoc = Offset(
            leftDoc + halfW,
            topDoc + _displaySize.height / 2,
          );

          // 드래그 데드존: 10px 이내는 겹침 계산하지 않음
          if (_currentOffset.distance > 10.0) {
            widget.spatialManager!.updateRowPreviewFromDrag(
              draggingId: widget.nodeId,
              draggingCenterDocument: centerDoc,
              draggingSize: _displaySize,
              verticalDelta: _currentOffset.dy,
            );

            final overlaps = widget.spatialManager!.detectOverlapsPrecise(
              draggingId: widget.nodeId,
              draggingCenterDocument: centerDoc,
              draggingSize: _displaySize,
              verticalDelta: _currentOffset.dy,
            );
            final bool anyStrongOverlap = overlaps.isNotEmpty;
            if (anyStrongOverlap != isOverlapping) {
              setState(() {
                isOverlapping = anyStrongOverlap;
              });
            }
          }
        }

        isOverlapping = _shouldHorizontalPlace(deltaY, deltaX);
        if (isOverlapping) {
          return;
        }
        _calculateVerticalLineMovement(imageDragInfo);
      }
    }
  }

  bool _shouldHorizontalPlace(double deltaY, double deltaX) {
    if (widget.spatialManager == null) return false;
    return false;
  }

  void _calculateVerticalLineMovement(ImageDragInfo imageDragInfo) {
    if (widget.spatialManager == null) return;

    final baseY = imageDragInfo.baseY;
    final imageHeight = imageDragInfo.imageHeight;
    final dragOffset = imageDragInfo.dragYOffset;

    final targetY = TargetYCalculator.calculateTargetY(
      baseY: baseY,
      imageHeight: imageHeight,
      dragOffset: dragOffset,
    );

    int linesToMove = widget.spatialManager!.calculateHowManyLinesToMove(
      imageId: widget.nodeId,
      targetY: targetY,
    );

    double triggerThreshold =
        SystemConstants.defaultFontSize * SystemConstants.defaultLineHeight1;

    final isDraggingUp = dragOffset < 0;
    final isDraggingDown = dragOffset > 0;

    if (linesToMove != 0 && dragOffset.abs() > triggerThreshold) {
      _updateInsertionBorder(linesToMove.abs(), isDraggingUp, isDraggingDown);
    } else {
      _updateInsertionBorder(0, false, false);
    }
  }

  void _updateInsertionBorder(
    int linesToMove,
    bool isDraggingUp,
    bool isDraggingDown,
  ) {
    setState(() {
      if (linesToMove > 0 && (isDraggingUp || isDraggingDown)) {
        if (isDraggingUp) {
          _showTopBorder = true;
          _showBottomBorder = false;
        } else if (isDraggingDown) {
          _showTopBorder = false;
          _showBottomBorder = true;
        } else {
          _showTopBorder = false;
          _showBottomBorder = false;
        }
      } else {
        _showTopBorder = false;
        _showBottomBorder = false;
      }
    });
  }

  void _moveImageInDocument(double dragDistance) {
    final moveUp = _currentOffset.dy < -SystemConstants.moveThreshold;
    final moveDown = _currentOffset.dy > SystemConstants.moveThreshold;

    if (!moveUp && !moveDown) {
      return;
    }

    final dragOffset = _currentOffset.dy;
    final targetY = TargetYCalculator.calculateTargetY(
      baseY: _baseY,
      imageHeight: _actualSize.height,
      dragOffset: dragOffset,
    );

    widget.spatialManager!.handleImagePositionUpdate(
      widget.nodeId,
      moveUp ? 'move_up' : 'move_down',
      targetY: targetY,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.spatialManager?.addListener(_onSpatialChanged);
  }

  void _onSpatialChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    widget.spatialManager?.removeListener(_onSpatialChanged);
    super.dispose();
  }

  void _handleTap() {
    print('🎯 이미지 탭 이벤트 발생');
    setState(() {
      _isTapped = false;
    });
  }

  /// 🎯 키보드 다시 표시
  void _showKeyboard() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && widget.spatialManager != null) {
        widget.spatialManager!.showKeyboard?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: _containerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 🎯 투명한 공간 확보용
          Container(
            width: double.infinity,
            height: _containerHeight,
            color: Colors.transparent,
          ),
          // 🎯 절대 위치 이미지
          Positioned(
            left: _computeImageLeftForBuild(),
            top: _currentOffset.dy - 6,
            child: GestureDetector(
              onTap: _handleTap,
              onLongPressStart: (details) {
                if (_isPlaceholder()) return;
                setState(() {
                  _dragModeActive = true;
                  _isDragging = false;
                  _isScaling = false;
                });
                widget.onDragModeChanged?.call(true);
                _beginDragAt(details.globalPosition);
              },
              onLongPressMoveUpdate: (details) {
                if (!_dragModeActive) return;
                _updateDragFromGlobal(details.globalPosition);
              },
              onLongPressEnd: (_) {
                if (!_dragModeActive) return;
                _handleDragEnd();
                _updateImagePosition(updatedMetadata: {});
                _dragModeActive = false;
                widget.onDragModeChanged?.call(false);
              },
              onScaleStart: _isPlaceholder() ? null : _handleScaleStart,
              onScaleUpdate: _isPlaceholder() ? null : _handleScaleUpdate,
              onScaleEnd: _isPlaceholder() ? null : _handleScaleEnd,
              child: _buildImageContainer(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageContainer() {
    return Container(
      width: _displaySize.width,
      height: _displaySize.height,
      decoration: _buildBorderDecoration(),
      child: _buildImageContent(),
    );
  }

  double _computeImageLeftForBuild() {
    final double contentLeft = 0.0;
    final contentWidth = widget.gridSystem.screenWidth;
    final contentCenterX = contentLeft + contentWidth / 2;
    final halfWidth = _displaySize.width / 2;
    final imageCenterX = contentCenterX + _currentOffset.dx;
    return imageCenterX - halfWidth;
  }

  BoxDecoration _buildBorderDecoration() {
    final bool isPreviewTarget =
        widget.spatialManager?.rowPreviewTargetId == widget.nodeId;
    final OverlapSide? previewSide = widget.spatialManager?.rowPreviewSide;

    return BoxDecoration(
      border: Border(
        top:
            _showTopBorder
                ? const BorderSide(color: Colors.orange, width: 3.0)
                : BorderSide.none,
        bottom:
            _showBottomBorder
                ? const BorderSide(color: Colors.orange, width: 3.0)
                : BorderSide.none,
        left: BorderSide(
          color:
              isPreviewTarget && previewSide == OverlapSide.left
                  ? Colors.orange
                  : (_isTapped
                      ? const Color.fromARGB(255, 92, 127, 255)
                      : Colors.transparent),
          width:
              isPreviewTarget && previewSide == OverlapSide.left
                  ? 3.0
                  : (_isTapped ? 3.0 : 0.5),
        ),
        right: BorderSide(
          color:
              isPreviewTarget && previewSide == OverlapSide.right
                  ? Colors.orange
                  : (_isTapped
                      ? const Color.fromARGB(255, 92, 127, 255)
                      : Colors.transparent),
          width:
              isPreviewTarget && previewSide == OverlapSide.right
                  ? 3.0
                  : (_isTapped ? 3.0 : 0.5),
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    if (_isLocalFile()) {
      try {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade400, width: 0.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(widget.imageUrl),
              width: _displaySize.width,
              height: _displaySize.height,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('로컬 파일 로드 실패: $error');
                return _buildPlaceholderContent();
              },
            ),
          ),
        );
      } catch (e) {
        debugPrint('로컬 파일 처리 실패: $e');
        return _buildPlaceholderContent();
      }
    }

    if (widget.imageUrl.isNotEmpty &&
        widget.imageUrl.startsWith('http') &&
        !widget.imageUrl.contains('picsum.photos')) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade400, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            widget.imageUrl,
            width: _displaySize.width,
            height: _displaySize.height,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: Colors.grey[300],
                child: Center(
                  child: CircularProgressIndicator(
                    value:
                        loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                    strokeWidth: 2,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              debugPrint('네트워크 이미지 로드 실패: $error');
              return _buildPlaceholderContent();
            },
          ),
        ),
      );
    }

    return _buildPlaceholderContent();
  }

  Widget _buildPlaceholderContent() {
    return Container(
      color: const Color.fromARGB(255, 232, 232, 232),
      child: SizedBox(width: 22, height: 22),
    );
  }

  /// 로컬 파일인지 확인
  bool _isLocalFile() {
    if (widget.imageUrl.startsWith('file://') ||
        widget.imageUrl.startsWith('/') ||
        widget.imageUrl.contains('tmp/') ||
        widget.imageUrl.contains('flutter-images/')) {
      return true;
    }
    final element = widget.spatialManager?.getElement(widget.nodeId);
    if (element != null && element.metadata['isLocalFile'] == true) {
      return true;
    }
    return false;
  }

  bool _isPlaceholder() {
    final element = widget.spatialManager?.getElement(widget.nodeId);

    if (element != null) {
      if (element.metadata.containsKey('isPlaceholder')) {
        return element.metadata['isPlaceholder'] == true;
      }

      // isRealImage가 true이거나 isLocalImage가 true인 경우 실제 이미지
      if (element.metadata.containsKey('isRealImage') &&
          element.metadata['isRealImage'] == true) {
        return false;
      }

      if (element.metadata.containsKey('isLocalImage') &&
          element.metadata['isLocalImage'] == true) {
        return false;
      }

      return false;
    }

    return true;
  }
}
