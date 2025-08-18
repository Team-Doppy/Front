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
  final GridSystem? gridSystem;
  final Offset? initialPosition;
  final double initialScale;
  final VoidCallback? onLayoutUpdateNeeded;

  const DocumentInteractiveFloatingImage({
    super.key,
    required this.nodeId,
    required this.imageUrl,
    required this.size,
    required this.initialScale,
    this.spatialManager,
    this.gridSystem,
    this.initialPosition,
    this.onLayoutUpdateNeeded,
  });

  @override
  State<DocumentInteractiveFloatingImage> createState() =>
      _DocumentInteractiveFloatingImageState();
}

class _DocumentInteractiveFloatingImageState
    extends State<DocumentInteractiveFloatingImage>
    with DocumentComponent {
  bool _isDragging = false;
  Offset _currentOffset = Offset.zero;
  double _scale = 1.0;
  double? _intrinsicAspect; // 원본 비율 (height / width)
  bool _didAutoSize = false;

  double _initialDragX = 0;
  double _initialDragY = 0;
  bool _isScaling = false;
  bool _isTapped = false;

  Offset _initialTouchOffset = Offset.zero;
  bool _showTopBorder = false;
  bool _showBottomBorder = false;

  // 초기화 시에만 설정되는 baseY (문서 내 실제 Y 위치)
  double _baseY = 0.0;

  Map<String, dynamic> _calculateGridValues() {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = widget.gridSystem?.screenWidth ?? screenWidth;
    final gridSize =
        (widget.gridSystem != null)
            ? widget.gridSystem!.gridSize
            : (contentWidth / SystemConstants.gridSize);
    final columns = SystemConstants.gridSize.toInt();

    final displaySize = _displaySize;
    final halfWidth = displaySize.width / 2;
    final contentCenterX = contentWidth / 2;
    final currentCenterX = contentCenterX + _currentOffset.dx;
    final currentLeft = currentCenterX - halfWidth;
    int gridW = (displaySize.width / gridSize).round().clamp(1, columns);
    int gridH = (displaySize.height / gridSize).round().clamp(1, columns);
    int gridX = (currentLeft / gridSize).round();
    final maxIndex = (columns - gridW).clamp(0, columns);
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
  void initState() {
    super.initState();
    _initializeFromSpatialManager();

    // 🔑 MediaQuery 사용을 didChangeDependencies로 이동
    // _ensureIntrinsicAspect();
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
          _autoSizeIfNeeded();
        }
        stream.removeListener(listener);
      },
      onError: (dynamic _, __) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  void _autoSizeIfNeeded() {
    if (_didAutoSize) return;
    if (!mounted) return;
    if (_intrinsicAspect == null) return;

    final element = widget.spatialManager?.getElement(widget.nodeId);
    final hasSaved =
        element?.metadata.containsKey('scale') == true ||
        element?.metadata.containsKey('gridW') == true;
    if (hasSaved) return;

    // 🔑 MediaQuery 사용을 안전하게 처리
    double screenWidth;
    try {
      screenWidth = MediaQuery.of(context).size.width;
    } catch (e) {
      screenWidth = 400.0; // 기본값
      return; // MediaQuery 사용 불가시 자동 크기 조정 건너뛰기
    }

    final contentWidth = widget.gridSystem?.screenWidth ?? screenWidth;
    final gridSize =
        (widget.gridSystem != null)
            ? widget.gridSystem!.gridSize
            : (contentWidth / SystemConstants.gridSize);
    final columns = SystemConstants.gridSize.toDouble();

    final aspect = _intrinsicAspect!;
    double desiredCols;
    if (aspect < 0.8) {
      desiredCols = columns * 0.8;
    } else if (aspect > 1.2) {
      desiredCols = columns * 0.5;
    } else {
      desiredCols = columns * 0.6;
    }
    desiredCols = desiredCols.clamp(1.0, columns);

    final desiredWidthPx = desiredCols * gridSize;
    final baseDisplayWidthPx = SystemConstants.displayWidth;
    final newScale = (desiredWidthPx / baseDisplayWidthPx).clamp(
      SystemConstants.scaleMin,
      SystemConstants.scaleMax,
    );

    setState(() {
      _scale = newScale;
      _didAutoSize = true;
      _currentOffset = const Offset(0, 0);
    });

    _updateRealTimePosition(updatedMetadata: {'scale': _scale});
    widget.onLayoutUpdateNeeded?.call();
  }

  /// 🎯 SpatialManager에서 초기 상태 복원
  void _initializeFromSpatialManager() {
    if (widget.spatialManager == null) {
      _scale = widget.initialScale;
      _baseY = widget.initialPosition?.dy ?? 0.0;
      return;
    }

    final element = widget.spatialManager!.getElement(widget.nodeId);
    if (element != null) {
      // 스케일 복원
      if (element.metadata.containsKey('scale')) {
        _scale = element.metadata['scale'] as double;
      } else {
        _scale = widget.initialScale;
      }

      // X 위치 복원
      if (element.metadata.containsKey('xOffset')) {
        final savedXOffset = element.metadata['xOffset'] as double;
        _currentOffset = Offset(savedXOffset, 0);
      }

      // 초기화 시에만 baseY 설정 (문서 내 실제 Y 위치)
      _baseY = element.position.dy;
    } else {
      _scale = widget.initialScale;
      _baseY = widget.initialPosition?.dy ?? 0.0;
    }
  }

  /// 🎯 현재 이미지 크기 계산
  Size get _actualSize => ImageSizeCalculator.getActualSize(_scale);
  Size get _rawDisplaySize => ImageSizeCalculator.getDisplaySize(_scale);
  Size get _displaySize => _snappedDisplaySize;

  /// 그리드 배수로 스냅된 표시 크기 (에디터에서는 scale이 즉시 반영되어야 함)
  Size get _snappedDisplaySize {
    double screenWidth;
    try {
      screenWidth = MediaQuery.of(context).size.width;
    } catch (e) {
      screenWidth = 400.0; // 기본값
    }

    final contentWidth = widget.gridSystem?.screenWidth ?? screenWidth;
    final gridSize =
        (widget.gridSystem != null)
            ? widget.gridSystem!.gridSize
            : (contentWidth / SystemConstants.gridSize);

    final raw = _rawDisplaySize; // <-- scale 반영됨
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

  /// 🎯 현재 이미지 위치 계산
  Offset get _imageCenterOffset {
    final screenWidth = MediaQuery.of(context).size.width;
    return ImagePositionCalculator.getImageCenterOffset(
      _currentOffset,
      screenWidth,
      _actualSize.width,
    );
  }

  Rect get _imageRect {
    final screenWidth = MediaQuery.of(context).size.width;
    return ImagePositionCalculator.getImageRect(
      _currentOffset,
      screenWidth,
      _actualSize,
    );
  }

  // DocumentComponent 필수 메서드들 (절대 좌표 기반)
  @override
  UpstreamDownstreamNodePosition? getPositionAtOffset(Offset localOffset) {
    if (_imageRect.contains(localOffset)) {
      // 이미지 영역에서는 upstream() 반환하여 커서가 이미지 아래 텍스트를 가리키도록 함
      return UpstreamDownstreamNodePosition.upstream();
    }
    return UpstreamDownstreamNodePosition.upstream();
  }

  @override
  Offset getOffsetForPosition(NodePosition nodePosition) {
    return _imageCenterOffset;
  }

  @override
  Rect getRectForPosition(NodePosition nodePosition) {
    return _imageRect;
  }

  @override
  Rect getEdgeForPosition(NodePosition nodePosition) {
    return getRectForPosition(nodePosition);
  }

  @override
  Rect getRectForSelection(
    NodePosition basePosition,
    NodePosition extentPosition,
  ) {
    return getRectForPosition(basePosition);
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
    return null;
  }

  @override
  UpstreamDownstreamNodePosition? movePositionRight(
    NodePosition currentPosition, [
    MovementModifier? movementModifier,
  ]) {
    return null;
  }

  @override
  UpstreamDownstreamNodePosition? movePositionUp(NodePosition currentPosition) {
    return null;
  }

  @override
  UpstreamDownstreamNodePosition? movePositionDown(
    NodePosition currentPosition,
  ) {
    return null;
  }

  @override
  UpstreamDownstreamNodePosition getEndPosition() {
    // 이미지 노드의 끝 위치도 upstream()으로 처리하여 커서가 다음 텍스트를 가리키도록 함
    return UpstreamDownstreamNodePosition.upstream();
  }

  @override
  UpstreamDownstreamNodePosition getEndPositionNearX(double x) {
    return UpstreamDownstreamNodePosition.downstream();
  }

  @override
  UpstreamDownstreamNodeSelection? getSelectionInRange(
    Offset localBaseOffset,
    Offset localExtentOffset,
  ) {
    return null;
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
  bool isVisualSelectionSupported() => true;

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) {
    return SystemMouseCursors.grab;
  }

  /// 🎯 가로 경계 제한 함수 (X축만)
  Offset _applyScreenBounds(Offset targetOffset, Size imageSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double contentLeft = 0.0;
    final contentWidth = widget.gridSystem?.screenWidth ?? screenWidth;

    final halfWidth = imageSize.width / 2;
    final contentCenterX = contentLeft + contentWidth / 2;
    final imageCenterX = contentCenterX + targetOffset.dx;
    final imageLeft = imageCenterX - halfWidth;
    final imageRight = imageCenterX + halfWidth;

    final rightBound = contentLeft + contentWidth;
    if (imageLeft < contentLeft) {
      final correctedCenterX = contentLeft + halfWidth;
      final correctedDx = correctedCenterX - contentCenterX;
      return Offset(correctedDx, targetOffset.dy);
    }
    if (imageRight > rightBound) {
      final correctedCenterX = rightBound - halfWidth;
      final correctedDx = correctedCenterX - contentCenterX;
      return Offset(correctedDx, targetOffset.dy);
    }

    return targetOffset;
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

  void _updateRealTimePosition({
    required Map<String, dynamic> updatedMetadata,
  }) {
    if (widget.spatialManager == null) return;

    // 🎯 xOffset을 position에 반영
    final currentPosition = Offset(_currentOffset.dx, _baseY);

    // 🎯 캐시된 그리드 계산 사용
    final gridValues = _calculateGridValues();
    final displaySize = gridValues['displaySize'] as Size;

    final newMetadata = {
      'scale': _scale,
      'pxW': displaySize.width,
      'pxH': displaySize.height,
      'gridW': gridValues['gridW'],
      'gridH': gridValues['gridH'],
      'gridX': gridValues['gridX'], //중요
      'isImageNode': true,
      ...updatedMetadata,
    };

    print('🎯 newMetadata: $newMetadata');

    widget.spatialManager!.updateElement(
      id: widget.nodeId,
      type: SpatialElementType.image,
      position: currentPosition,
      size: _actualSize,
      metadata: newMetadata,
    );
  }

  void _resetDragState() {
    setState(() {
      _isDragging = false;
      _showTopBorder = false;
      _showBottomBorder = false;
    });
  }

  void _handleScaleStart(ScaleStartDetails details) {
    setState(() {
      if (details.pointerCount == 2) {
        _isScaling = true;
        _isDragging = false;
        _isTapped = false;
      } else {
        _isScaling = false;
        _isDragging = true;
        _isTapped = false;
        _initialDragX = details.focalPoint.dx;
        _initialDragY = details.focalPoint.dy;

        final screenWidth = MediaQuery.of(context).size.width;
        _initialTouchOffset = ImagePositionCalculator.getTouchOffset(
          details.focalPoint,
          _currentOffset,
          screenWidth,
        );
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
        }

        _isScaling = true;
        _isDragging = false;
      });
    } else if (details.pointerCount == 1) {
      // 한 손가락 - 자유로운 2D 드래그 (경계에서만 이동 제한)
      final currentX = details.focalPoint.dx;
      final currentY = details.focalPoint.dy;

      setState(() {
        _isDragging = true;
        _isScaling = false;

        // 터치 기준점을 유지한 정확한 이동
        final screenWidth = MediaQuery.of(context).size.width;
        final targetImageCenterX = currentX - _initialTouchOffset.dx;
        final targetImageCenterY = currentY - _initialTouchOffset.dy;

        // 🎯 공통 경계 제한 함수 사용
        final targetOffset = Offset(
          targetImageCenterX - (screenWidth / 2),
          targetImageCenterY - 70,
        );

        _currentOffset = _applyScreenBounds(targetOffset, _displaySize);

        // 방향 힌트 계산
        final deltaX = currentX - _initialDragX;
        final deltaY = currentY - _initialDragY;
        DragDirectionDetector.detectDirection(deltaX, deltaY);
      });

      _onImageDragging();
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_isScaling) {
      setState(() {
        _isScaling = false;
      });

      if (widget.spatialManager != null) {
        final display = _displaySize;
        _updateRealTimePosition(
          updatedMetadata: {
            'scale': _scale,
            'xOffset': _currentOffset.dx,
            'yOffset': _currentOffset.dy,
            'pxW': display.width,
            'pxH': display.height,
          },
        );
      }

      FocusManager.instance.primaryFocus?.requestFocus();
    } else if (_isDragging) {
      _handleDragEnd();
    }
  }

  void _handleDragEnd() {
    final deltaX = _currentOffset.dx;
    final deltaY = _currentOffset.dy;

    // 🎯 기존 그리드 계산 함수 재사용
    final gridValues = _calculateGridValues();
    final gridSize = gridValues['gridSize'] as double;
    final columns = gridValues['columns'] as int;

    // 현재 이미지 좌측 좌표(컨텐츠 기준)
    final displaySize = gridValues['displaySize'] as Size;
    final halfWidth = displaySize.width / 2;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = widget.gridSystem?.screenWidth ?? screenWidth;
    final contentCenterX = contentWidth / 2;
    final currentCenterX = contentCenterX + deltaX;
    final currentLeft = currentCenterX - halfWidth;

    // 스냅 인덱스 및 스냅 좌표 (열 기준 클램프 포함)
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
      // 세로 이동이 충분하면 → 문서 순서 변경 + X 위치 경계 제한 적용
      _handleVerticalMovement(clampedGridOffset.dx);
    } else {
      // 가로 이동만 → 격자 위치로 스냅 (경계 제한 적용)
      _handleHorizontalMovement(clampedGridOffset.dx);
    }

    // ✅ 드래그 종료 시점에 반드시 최종 위치 업데이트
    _updateRealTimePosition(
      updatedMetadata: {
        'xOffset': _currentOffset.dx,
        'yOffset': _currentOffset.dy,
      },
    );
  }

  /// 🎯 세로 이동 처리
  void _handleVerticalMovement(double deltaX) {
    if (widget.spatialManager != null) {
      _updateRealTimePosition(
        updatedMetadata: {'xOffset': deltaX, 'yOffset': 0.0},
      );
    }

    _moveImageInDocument(deltaX.abs());
    setState(() {
      _currentOffset = Offset(deltaX, 0);
    });
    _resetDragState();
    _showKeyboard();
  }

  /// 🎯 가로 이동 처리
  void _handleHorizontalMovement(double clampedGridX) {
    if (widget.spatialManager != null) {
      _updateRealTimePosition(
        updatedMetadata: {'xOffset': clampedGridX, 'yOffset': 0.0},
      );
    }

    setState(() {
      _currentOffset = Offset(clampedGridX, 0);
    });
    _resetDragState();
  }

  void _onImageDragging() {
    if (_currentOffset.dy.abs() > 5.0) {
      final imageDragInfo = _getCurrentDragInfo();
      if (imageDragInfo != null) {
        _calculateVerticalLineMovement(imageDragInfo);
      }
    }
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

    final linesToMove = widget.spatialManager!.calculateHowManyLinesToMove(
      imageId: widget.nodeId,
      targetY: targetY,
    );

    final isDraggingUp = dragOffset < 0;
    final isDraggingDown = dragOffset > 0;

    if (linesToMove != 0) {
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

  /// 🎯 이미지 컨테이너 위젯
  Widget _buildImageContainer() {
    return Container(
      width: _displaySize.width,
      height: _displaySize.height,
      // margin 제거 (여백은 main_style_sheet.dart에서 처리)
      decoration: _buildBorderDecoration(),
      child: _buildImageContent(),
    );
  }

  double _computeImageLeftForBuild() {
    final screenWidth = MediaQuery.of(context).size.width;
    final double contentLeft = 0.0;
    final contentWidth = widget.gridSystem?.screenWidth ?? screenWidth;
    final contentCenterX = contentLeft + contentWidth / 2;
    final halfWidth = _displaySize.width / 2;
    final imageCenterX = contentCenterX + _currentOffset.dx;
    return imageCenterX - halfWidth;
  }

  /// 🎯 보더 데코레이션
  BoxDecoration _buildBorderDecoration() {
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
              _isTapped
                  ? const Color.fromARGB(255, 92, 127, 255)
                  : Colors.transparent,
          width: _isTapped ? 3.0 : 0.5,
        ),
        right: BorderSide(
          color:
              _isTapped
                  ? const Color.fromARGB(255, 92, 127, 255)
                  : Colors.transparent,
          width: _isTapped ? 3.0 : 0.5,
        ),
      ),
    );
  }

  /// 🎯 이미지 내용 위젯
  Widget _buildImageContent() {
    // 실제 이미지 URL이 있으면 네트워크 이미지로 렌더링
    if (widget.imageUrl.isNotEmpty &&
        !widget.imageUrl.contains('picsum.photos')) {
      return ClipRRect(
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
            debugPrint('이미지 로드 실패: $error');
            return _buildPlaceholderContent();
          },
        ),
      );
    }

    // 기본 플레이스홀더
    return _buildPlaceholderContent();
  }

  /// 플레이스홀더 이미지 내용
  Widget _buildPlaceholderContent() {
    return Container(
      color: const Color.fromARGB(255, 232, 232, 232),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                const Color.fromARGB(179, 127, 127, 127),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isPlaceholder() {
    // 🔑 metadata의 isPlaceholder 값을 우선적으로 확인
    final element = widget.spatialManager?.getElement(widget.nodeId);

    // 🔑 SpatialManager에 등록된 이미지는 실제 이미지
    if (element != null) {
      // isPlaceholder가 명시적으로 true인 경우만 플레이스홀더
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

      // 🔑 SpatialManager에 등록된 이미지는 기본적으로 실제 이미지로 간주
      return false;
    }

    // 🔑 SpatialManager에 등록되지 않은 이미지는 플레이스홀더로 간주
    return true;
  }
}
