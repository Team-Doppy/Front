import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'simple_grid.dart';
import 'dart:math' as math;
import 'image/image_util.dart';

// 🎯 경량 Uniform Grid 인덱스 - 이미지 충돌 후보를 빠르게 조회
class _GridIndex {
  final double cellSize;
  final Map<String, Rect> _idToRect = {};
  final Map<String, Set<String>> _cellToIds = {};

  _GridIndex({required this.cellSize});

  void clear() {
    _idToRect.clear();
    _cellToIds.clear();
  }

  void insert(String id, Rect rect) {
    _idToRect[id] = rect;
    for (final key in _keysForRect(rect)) {
      (_cellToIds[key] ??= <String>{}).add(id);
    }
  }

  void remove(String id) {
    final rect = _idToRect.remove(id);
    if (rect == null) return;
    for (final key in _keysForRect(rect)) {
      final bucket = _cellToIds[key];
      bucket?.remove(id);
      if (bucket != null && bucket.isEmpty) {
        _cellToIds.remove(key);
      }
    }
  }

  Set<String> query(Rect rect) {
    final Set<String> result = <String>{};
    for (final key in _keysForRect(rect)) {
      final bucket = _cellToIds[key];
      if (bucket != null) result.addAll(bucket);
    }
    return result;
  }

  Iterable<String> _keysForRect(Rect rect) sync* {
    final int x0 = (rect.left / cellSize).floor();
    final int x1 = (rect.right / cellSize).floor();
    final int y0 = (rect.top / cellSize).floor();
    final int y1 = (rect.bottom / cellSize).floor();
    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        yield '$x,$y';
      }
    }
  }
}

/// 좌표계 타입
enum CoordinateSystem {
  document, // 문서 내 절대 좌표 (기준점)
  grid, // 그리드 시스템 기준 좌표
}

/// 각 노드의 모든 좌표계 정보
class DocumentCoordinates {
  final Offset document; // 문서 내 절대 좌표
  final Offset grid; // 그리드 기준 좌표

  const DocumentCoordinates({required this.document, required this.grid});

  // 편의 메서드
  double get documentX => document.dx;
  double get documentY => document.dy;
  double get gridX => grid.dx;
  double get gridY => grid.dy;

  // 좌표 변환
  DocumentCoordinates withDocumentOffset(Offset offset) {
    return DocumentCoordinates(
      document: document + offset,
      grid: grid + offset,
    );
  }

  DocumentCoordinates withGridOffset(Offset offset) {
    return DocumentCoordinates(
      document: document + offset,
      grid: grid + offset,
    );
  }
}

/// 공간 요소 타입
enum SpatialElementType { textNode, dragPreview, image }

/// 공간 요소 정보
class SpatialElement {
  final String id;
  final SpatialElementType type;
  final DocumentCoordinates coordinates;
  final Size size;
  final Map<String, dynamic> metadata;

  const SpatialElement({
    required this.id,
    required this.type,
    required this.coordinates,
    required this.size,
    required this.metadata,
  });

  // 🎯 문서 좌표를 좌상단 기준으로 해석 (LTWH)
  Rect get documentRect => Rect.fromLTWH(
    coordinates.document.dx,
    coordinates.document.dy,
    size.width,
    size.height,
  );

  Rect get gridRect => Rect.fromLTWH(
    coordinates.grid.dx,
    coordinates.grid.dy,
    size.width,
    size.height,
  );

  // 🎯 문서 좌표 기준 경계값들 (LTWH 기반)
  double get documentTop => documentRect.top;
  double get documentBottom => documentRect.bottom;
  double get documentLeft => documentRect.left;
  double get documentRight => documentRect.right;
  double get documentCenterY => documentRect.center.dy;
  double get documentCenterX => documentRect.center.dx;

  // 🎯 그리드 좌표 기준 경계값들 (LTWH 기반)
  double get gridTop => gridRect.top;
  double get gridBottom => gridRect.bottom;
  double get gridLeft => gridRect.left;
  double get gridRight => gridRect.right;
  double get gridCenterY => gridRect.center.dy;
  double get gridCenterX => gridRect.center.dx;

  // 🎯 기존 호환성을 위한 getter (점진적 제거 예정)
  Rect get rect => documentRect;
  double get top => documentTop;
  double get bottom => documentBottom;
  double get left => documentLeft;
  double get right => documentRight;
  double get centerY => documentCenterY;
}

/// 겹침 방향
enum OverlapSide { left, right, top, bottom, inside, none }

/// 겹침 결과
class OverlapResult {
  final String targetId;
  final SpatialElementType targetType;
  final Rect targetRect;
  final Rect draggingRect;
  final Rect intersection;
  final double area; // 교차 면적 (px^2)
  final double areaRatioAgainstDrag; // dragging 대비 면적 비율 (0~1)
  final double xRatio; // 가로 겹침 비율 (0~1)
  final double yRatio; // 세로 겹침 비율 (0~1)
  final OverlapSide side; // 주된 접촉 방향

  const OverlapResult({
    required this.targetId,
    required this.targetType,
    required this.targetRect,
    required this.draggingRect,
    required this.intersection,
    required this.area,
    required this.areaRatioAgainstDrag,
    required this.xRatio,
    required this.yRatio,
    required this.side,
  });

  @override
  String toString() {
    return 'Overlap(target=$targetId, side=$side, area=${area.toStringAsFixed(1)}, ratio=${(areaRatioAgainstDrag * 100).toStringAsFixed(1)}%, xRatio=${xRatio.toStringAsFixed(2)}, yRatio=${yRatio.toStringAsFixed(2)})';
  }
}

class SpatialManager extends ChangeNotifier {
  final GridSystem gridSystem;
  final Map<String, SpatialElement> _elements = {};
  Editor? _documentEditor;
  MutableDocument? _document;
  final _GridIndex _gridIndex = _GridIndex(cellSize: 128);
  double _viewScale = 1.0; // 편집기 전역 스케일 (레이아웃 스케일)

  double get viewScale => _viewScale;
  void setViewScale(double scale) {
    if ((scale - _viewScale).abs() < 0.001) return;
    _viewScale = scale.clamp(0.5, 1.5);
    if (_document != null) {
      analyzeAndUpdateDocument(
        document: _document!,
        screenWidth: gridSystem.screenWidth,
        documentPadding: 0.0,
      );
    }
  }

  // 🎯 가로 배치 프리뷰 상태 및 히스테리시스
  String? _rowPreviewTargetId;
  OverlapSide? _rowPreviewSide;
  String? _rowPreviewCandidateId;
  OverlapSide? _rowPreviewCandidateSide;
  DateTime? _rowPreviewCandidateSince;
  int _rowPreviewHysteresisMs = 70; // 50~80ms 권장

  String? get rowPreviewTargetId => _rowPreviewTargetId;
  OverlapSide? get rowPreviewSide => _rowPreviewSide;

  void setRowPreview({String? targetId, OverlapSide? side}) {
    _rowPreviewTargetId = targetId;
    _rowPreviewSide = side;
    notifyListeners();
  }

  void clearRowPreview() {
    _rowPreviewTargetId = null;
    _rowPreviewSide = null;
    _rowPreviewCandidateId = null;
    _rowPreviewCandidateSide = null;
    _rowPreviewCandidateSince = null;
    notifyListeners();
  }

  void updateRowPreviewFromDrag({
    required String draggingId,
    required Offset draggingCenterDocument,
    required Size draggingSize,
    double verticalDelta = 0.0,
  }) {
    final overlaps = detectOverlapsPrecise(
      draggingId: draggingId,
      draggingCenterDocument: draggingCenterDocument,
      draggingSize: draggingSize,
      verticalDelta: verticalDelta,
    );

    if (overlaps.isEmpty) {
      if (_rowPreviewTargetId != null) {
        clearRowPreview();
      }
      return;
    }

    final top = overlaps.first;
    final OverlapSide side =
        (top.side == OverlapSide.left || top.side == OverlapSide.right)
            ? top.side
            : (draggingCenterDocument.dx < top.targetRect.center.dx
                ? OverlapSide.left
                : OverlapSide.right);

    // 스티키 유지
    if (_rowPreviewTargetId == top.targetId && _rowPreviewSide == side) {
      return;
    }

    final now = DateTime.now();
    if (_rowPreviewCandidateId == top.targetId &&
        _rowPreviewCandidateSide == side) {
      final ms =
          now.difference(_rowPreviewCandidateSince ?? now).inMilliseconds;
      if (ms >= _rowPreviewHysteresisMs) {
        setRowPreview(targetId: top.targetId, side: side);
        _rowPreviewCandidateSince = now;
      }
    } else {
      _rowPreviewCandidateId = top.targetId;
      _rowPreviewCandidateSide = side;
      _rowPreviewCandidateSince = now;
    }
  }

  SpatialManager({required this.gridSystem});

  Function(String imageId, String newTextId)? updateImagePosition;
  VoidCallback? showKeyboard;
  Function(String imageId, int newIndex)? onImageMoved;

  // 문서 변경 감지 → 좌표/인덱스 자동 재계산
  void _onDocumentChanged(DocumentChangeLog changeLog) {
    if (_document == null) return;
    analyzeAndUpdateDocument(
      document: _document!,
      screenWidth: gridSystem.screenWidth,
      documentPadding: 0.0,
    );
    // 문서 구조가 바뀌면 프리뷰 상태가 남아있지 않도록 정리
    clearRowPreview();
  }

  void setDocumentReferences({
    required Editor editor,
    required MutableDocument document,
  }) {
    _documentEditor = editor;
    // 기존 문서 리스너 해제 후 새로운 문서로 교체
    _document?.removeListener(_onDocumentChanged);
    _document = document;
    _document!.addListener(_onDocumentChanged);

    analyzeAndUpdateDocument(
      document: document,
      screenWidth: gridSystem.screenWidth,
      documentPadding: 0.0,
    );
  }

  SpatialElement? getElement(String id) => _elements[id];

  // 🎯 새로운 좌표계 접근 메서드들
  DocumentCoordinates? getCoordinates(String id) {
    return _elements[id]?.coordinates;
  }

  Offset getDocumentPosition(String id) {
    return _elements[id]?.coordinates.document ?? Offset.zero;
  }

  Offset getGridPosition(String id) {
    return _elements[id]?.coordinates.grid ?? Offset.zero;
  }

  void updateElement({
    required String id,
    required SpatialElementType type,
    required DocumentCoordinates coordinates,
    required Size size,
    Map<String, dynamic>? metadata,
  }) {
    _elements[id] = SpatialElement(
      id: id,
      type: type,
      coordinates: coordinates,
      size: size,
      metadata: metadata ?? {},
    );
    //printDocStructure();
  }

  // 🎯 그리드 좌표 계산
  Offset _calculateGridPosition(Offset documentPos) {
    final gridSize = gridSystem.gridSize;
    final gridX = (documentPos.dx / gridSize).round() * gridSize;
    final gridY = (documentPos.dy / gridSize).round() * gridSize;
    return Offset(gridX, gridY);
  }

  void analyzeAndUpdateDocumentCallBack(String imageId) {
    if (_document == null) {
      return;
    }

    analyzeAndUpdateDocument(
      document: _document!,
      screenWidth: SystemConstants.displayWidth,
      documentPadding: 0.0,
    );
  }

  void analyzeAndUpdateDocument({
    required MutableDocument document,
    required double screenWidth,
    required double documentPadding,
  }) {
    final Set<String> docNodeIds = <String>{};
    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node != null) {
        docNodeIds.add(node.id);
      }
    }
    _elements.removeWhere((id, _) => !docNodeIds.contains(id));

    double currentY = 0.0;
    // ignore: unused_local_variable
    int processedNodes = 0;

    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);

      if (node is ParagraphNode) {
        final text = node.text.text;
        final nodeHeight = _calculatePreciseTextHeight(text);
        final contentWidth = screenWidth;
        final nodePosition = Offset(0, currentY);
        final nodeSize = Size(contentWidth, nodeHeight);

        final coordinates = DocumentCoordinates(
          document: nodePosition,
          grid: _calculateGridPosition(nodePosition),
        );

        updateElement(
          id: node.id,
          type: SpatialElementType.textNode,
          coordinates: coordinates,
          size: nodeSize,
          metadata: {
            'text': text,
            'length': text.length,
            'textAlign': node.metadata['textAlign'] ?? 'center',
          },
        );

        currentY += nodeHeight;
        processedNodes++;
      } else if (node is ImageNode) {
        final prev = _elements[node.id];
        final prevScale = (prev?.metadata['scale'] as double?) ?? 1.0;
        final prevPxW = (prev?.metadata['pxW'] as num?)?.toDouble();
        final prevPxH = (prev?.metadata['pxH'] as num?)?.toDouble();
        final prevGridX = (prev?.metadata['gridX'] as num?)?.toDouble() ?? 0.0;
        final actualWidth = prevPxW ?? SystemConstants.baseWidth;
        final actualHeight = prevPxH ?? SystemConstants.baseHeight;
        final displayWidth = actualWidth * prevScale;
        final displayHeight = actualHeight * prevScale;
        final totalImageHeight = displayHeight + SystemConstants.imagePadding;
        final nodePosition = Offset(prevGridX, currentY);
        final nodeSize = Size(displayWidth, displayHeight);

        final coordinates = DocumentCoordinates(
          document: nodePosition,
          grid: _calculateGridPosition(nodePosition),
        );

        updateElement(
          id: node.id,
          type: SpatialElementType.image,
          coordinates: coordinates,
          size: nodeSize,
          metadata: {
            'isImageNode': true,
            'imageUrl': node.imageUrl,
            'text': '이미지 ${node.id.substring(node.id.length)}',
            'scale': prevScale,
            'gridX': prevGridX,
            'pxW': prevPxW ?? actualWidth,
            'pxH': prevPxH ?? actualHeight,
          },
        );

        currentY += totalImageHeight;
        processedNodes++;
      }
    }
    printDocStructure();

    // 🎯 공간 인덱스 재구성 (이미지들만)
    _rebuildSpatialIndex();
  }

  void _rebuildSpatialIndex() {
    _gridIndex.clear();
    for (final element in _elements.values) {
      if (element.type != SpatialElementType.image) continue;
      final Offset topLeft = element.coordinates.document;
      final Size sz = element.size;
      if (sz.width <= 1 || sz.height <= 1) continue;
      final Rect r = Rect.fromLTWH(topLeft.dx, topLeft.dy, sz.width, sz.height);
      _gridIndex.insert(element.id, r);
    }
  }

  List<SpatialElement> get _sortedElements {
    return _elements.values.toList()..sort(
      (a, b) => a.coordinates.document.dy.compareTo(b.coordinates.document.dy),
    );
  }

  double calculateImageOverlapRatio({
    required String imageId,
    required Offset imagePosition,
    required Size imageSize,
  }) {
    final currentElement = _elements[imageId];
    if (currentElement == null) {
      return 0.0;
    }

    // 현재 이미지의 경계 계산 (메타데이터 우선, 없으면 파라미터)
    final currentCenterX =
        currentElement.metadata['centerXDoc'] as double? ?? imagePosition.dx;
    final currentCenterY =
        currentElement.metadata['centerYDoc'] as double? ?? imagePosition.dy;
    final currentHalfWidth = imageSize.width / 2;
    final currentHalfHeight = imageSize.height / 2;

    final currentRect = Rect.fromLTWH(
      currentCenterX - currentHalfWidth,
      currentCenterY - currentHalfHeight,
      imageSize.width,
      imageSize.height,
    );

    // 다른 모든 이미지와 겹침 검사
    double maxOverlapRatio = 0.0;

    for (final element in _elements.values) {
      if (element.id == imageId || element.type != SpatialElementType.image) {
        continue; // 자기 자신과 텍스트 노드는 제외
      }

      // 다른 이미지의 경계 계산 (메타데이터의 xOffset, yOffset 고려)
      final otherXOffset = element.metadata['xOffset'] as double? ?? 0.0;
      final otherYOffset = element.metadata['yOffset'] as double? ?? 0.0;
      final otherCenterX = element.coordinates.document.dx + otherXOffset;
      final otherCenterY = element.coordinates.document.dy + otherYOffset;
      final otherHalfWidth = element.size.width / 2;
      final otherHalfHeight = element.size.height / 2;

      final otherRect = Rect.fromLTWH(
        otherCenterX - otherHalfWidth,
        otherCenterY - otherHalfHeight,
        element.size.width,
        element.size.height,
      );

      // 겹침 영역 계산
      final overlapRect = currentRect.intersect(otherRect);
      if (overlapRect.width > 0 && overlapRect.height > 0) {
        // 겹침 비율 계산 (겹침 영역 / 현재 이미지 영역)
        final overlapArea = overlapRect.width * overlapRect.height;
        final currentArea = imageSize.width * imageSize.height;
        final overlapRatio = overlapArea / currentArea;

        if (overlapRatio > maxOverlapRatio) {
          maxOverlapRatio = overlapRatio;
        }
      }
    }

    return maxOverlapRatio;
  }

  int calculateHowManyLinesToMove({required String imageId, double? targetY}) {
    if (targetY == null) return 0;

    final currentElement = _elements[imageId];
    if (currentElement == null) {
      return 0;
    }

    // 드래그 방향 판단
    final currentImageY = currentElement.coordinates.document.dy;
    final isDraggingUp = targetY < currentImageY;

    final yDistance = (targetY - currentImageY).abs();
    double expectedLineHeight;

    if (isDraggingUp) {
      final currentIndex = _sortedElements.indexWhere((e) => e.id == imageId);
      if (currentIndex > 0) {
        expectedLineHeight =
            SystemConstants.defaultFontSize *
            SystemConstants.defaultLineHeight1;
      } else {
        expectedLineHeight =
            SystemConstants.defaultFontSize *
            SystemConstants.defaultLineHeight1;
      }
    } else {
      final currentIndex = _sortedElements.indexWhere((e) => e.id == imageId);
      if (currentIndex < _sortedElements.length - 1) {
        expectedLineHeight =
            SystemConstants.defaultFontSize *
            SystemConstants.defaultLineHeight1;
      } else {
        expectedLineHeight =
            SystemConstants.defaultFontSize *
            SystemConstants.defaultLineHeight1;
      }
    }

    final expectedLinesFromDistance = (yDistance / expectedLineHeight).round();

    final currentIndex = _sortedElements.indexWhere((e) => e.id == imageId);
    if (currentIndex == -1) return 0;

    // 거리 기반으로 이동할 줄 수 계산
    int linesToMove = expectedLinesFromDistance;

    // 방향에 따라 부호 결정
    if (isDraggingUp) {
      linesToMove = -linesToMove; // 위로는 음수
    }

    final totalElements = _sortedElements.length;
    final maxUpward = currentIndex; // 현재 위치까지 위로 이동 가능
    final maxDownward = totalElements - 1 - currentIndex; // 마지막까지 아래로 이동 가능

    int clampedLinesToMove;
    if (isDraggingUp) {
      final reasonableMaxUpward = math.max(
        maxUpward,
        expectedLinesFromDistance.abs(),
      );
      clampedLinesToMove = linesToMove.clamp(-reasonableMaxUpward, 0);
    } else {
      final reasonableMaxDownward = math.max(
        maxDownward,
        expectedLinesFromDistance,
      );
      clampedLinesToMove = linesToMove.clamp(0, reasonableMaxDownward);
    }
    return clampedLinesToMove;
  }

  void printDocStructure() {
    // Y 위치 기준으로 정렬
    final sortedElements =
        _elements.values.toList()..sort(
          (a, b) =>
              a.coordinates.document.dy.compareTo(b.coordinates.document.dy),
        );
    print('===============================================');

    for (final element in sortedElements) {
      final isImage = element.metadata['isImageNode'] == true;
      final displayType = isImage ? 'IMAGE(textNode)' : 'textNode';
      print(
        '• $displayType ${element.coordinates.document}, ${isImage ? element.size : ''}',
      );
    }
    print('===============================================');
  }

  void removeElement(String id) {
    _elements.remove(id);
    _documentEditor!.execute([DeleteNodeRequest(nodeId: id)]);
    notifyListeners();
  }

  @override
  void dispose() {
    _document?.removeListener(_onDocumentChanged);
    super.dispose();
  }

  void handleImagePositionUpdate(
    String imageId,
    String direction, {
    double? targetY,
  }) {
    final linesToMove = calculateHowManyLinesToMove(
      imageId: imageId,
      targetY: targetY,
    );

    if (linesToMove == 0 && direction == 'horizontal') {
    } else if (linesToMove < 0) {
      _moveImageUp(imageId, linesToMove: linesToMove.abs());
    } else {
      _moveImageDown(imageId, linesToMove: linesToMove);
    }
  }

  void _moveImageUp(String imageId, {int linesToMove = 1}) {
    if (_documentEditor == null || _document == null) {
      return;
    }

    try {
      int currentIndex = -1;
      DocumentNode? imageNode;

      for (int i = 0; i < _document!.nodeCount; i++) {
        final node = _document!.getNodeAt(i);
        if (node?.id == imageId) {
          currentIndex = i;
          imageNode = node;
          break;
        }
      }

      if (currentIndex < 0 || imageNode == null) {
        return;
      }

      final newIndex = (currentIndex - linesToMove).clamp(
        0,
        _document!.nodeCount - 1,
      );

      if (newIndex == currentIndex) {
        return;
      }

      _documentEditor!.execute([
        DeleteNodeRequest(nodeId: imageId),
        InsertNodeAtIndexRequest(nodeIndex: newIndex, newNode: imageNode),
      ]);

      onImageMoved?.call(imageId, newIndex);
      analyzeAndUpdateDocument(
        document: _document!,
        screenWidth: SystemConstants.displayWidth,
        documentPadding: 0.0,
      );
    } catch (e) {
      print('❌ 이미지 위로 이동 실패: $e');
    }
  }

  void _moveImageDown(String imageId, {int linesToMove = 1}) {
    if (_documentEditor == null || _document == null) {
      return;
    }

    try {
      int currentIndex = -1;
      DocumentNode? imageNode;

      for (int i = 0; i < _document!.nodeCount; i++) {
        final node = _document!.getNodeAt(i);
        if (node?.id == imageId) {
          currentIndex = i;
          imageNode = node;
          break;
        }
      }

      if (currentIndex < 0 ||
          currentIndex >= _document!.nodeCount ||
          imageNode == null) {
        print('❌ 이미지를 아래로 이동할 수 없습니다. (currentIndex: $currentIndex)');
        return;
      }

      final newIndex = (currentIndex + linesToMove).clamp(
        0,
        _document!.nodeCount - 1,
      );

      if (newIndex == currentIndex) {
        return;
      }

      _documentEditor!.execute([
        DeleteNodeRequest(nodeId: imageId),
        InsertNodeAtIndexRequest(nodeIndex: newIndex, newNode: imageNode),
      ]);

      onImageMoved?.call(imageId, newIndex);
      analyzeAndUpdateDocument(
        document: _document!,
        screenWidth: SystemConstants.displayWidth,
        documentPadding: 0.0,
      );
    } catch (e) {
      print('❌ 이미지 아래로 이동 실패: $e');
    }
  }

  double _calculatePreciseTextHeight(String text) {
    if (text.isEmpty) {
      return SystemConstants.defaultFontSize *
          SystemConstants.defaultLineHeight1;
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: SystemConstants.defaultFontSize,
          height: SystemConstants.defaultLineHeight1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );

    textPainter.layout(maxWidth: double.infinity);
    return textPainter.height;
  }

  List<OverlapResult> detectOverlapsForDrag({
    required String draggingId,
    required Offset draggingCenterDocument,
    required Size draggingSize,
    double verticalDelta = 0.0,
    bool includeTextNodes = false,
  }) {
    final Rect dragRect = Rect.fromCenter(
      center: draggingCenterDocument,
      width: draggingSize.width,
      height: draggingSize.height,
    );

    final List<OverlapResult> results = [];

    _elements.forEach((id, element) {
      if (id == draggingId) return; // 자기 자신 제외
      if (element.type != SpatialElementType.image) {
        return;
      }

      final Rect target = element.documentRect;
      final Rect? intersection = _intersectRects(dragRect, target);
      if (intersection == null) return; // 겹침 없음

      final double area = intersection.width * intersection.height;
      final double dragArea = (dragRect.width * dragRect.height).clamp(
        1,
        double.infinity,
      );
      final double targetArea = (target.width * target.height).clamp(
        1,
        double.infinity,
      );
      final double areaRatio = area / math.min(dragArea, targetArea);
      // 기존: min(height/width) 기준 → 작은 이미지에서 과소평가되는 문제 발생
      final double xCoverageDrag = (intersection.width / dragRect.width).clamp(
        0.0,
        1.0,
      );
      final double xCoverageTarget = (intersection.width / target.width).clamp(
        0.0,
        1.0,
      );
      final double xRatio = math.max(xCoverageDrag, xCoverageTarget);

      final double yCoverageDrag = (intersection.height / dragRect.height)
          .clamp(0.0, 1.0);
      final double yCoverageTarget = (intersection.height / target.height)
          .clamp(0.0, 1.0);
      final double yRatio = math.max(yCoverageDrag, yCoverageTarget);

      final OverlapSide side = _primaryOverlapSide(
        dragRect,
        target,
        verticalDelta,
      );

      results.add(
        OverlapResult(
          targetId: id,
          targetType: element.type,
          targetRect: target,
          draggingRect: dragRect,
          intersection: intersection,
          area: area,
          areaRatioAgainstDrag: areaRatio,
          xRatio: xRatio,
          yRatio: yRatio,
          side: side,
        ),
      );
    });

    // 면적 비율 우선, 그 다음 yRatio로 정렬 (수직 배치 우선)
    results.sort((a, b) {
      final byArea = b.areaRatioAgainstDrag.compareTo(a.areaRatioAgainstDrag);
      if (byArea != 0) return byArea;
      return b.yRatio.compareTo(a.yRatio);
    });
    return results;
  }

  // 🎯 새 정교 겹침 탐지 (연속 문서좌표 + 공간 인덱스, 메타 의존 없음)
  List<OverlapResult> detectOverlapsPrecise({
    required String draggingId,
    required Offset draggingCenterDocument,
    required Size draggingSize,
    double verticalDelta = 0.0,
  }) {
    final Rect dragRect = Rect.fromCenter(
      center: draggingCenterDocument,
      width: draggingSize.width,
      height: draggingSize.height,
    );

    // 인덱스에서 후보 조회 (약간 inflate)
    final Set<String> candidates =
        _gridIndex
            .query(dragRect.inflate(32))
            .where((id) => id != draggingId)
            .toSet();

    debugPrint(
      '🎯 precise: center=(${draggingCenterDocument.dx.toStringAsFixed(1)}, ${draggingCenterDocument.dy.toStringAsFixed(1)}) size=(${draggingSize.width.toStringAsFixed(1)}x${draggingSize.height.toStringAsFixed(1)}), candidates=${candidates.length}',
    );

    final List<OverlapResult> results = [];
    for (final id in candidates) {
      final element = _elements[id];
      if (element == null || element.type != SpatialElementType.image) continue;

      final Offset topLeft = element.coordinates.document;
      final Size sz = element.size;
      if (sz.width <= 1 || sz.height <= 1) continue;
      final Rect target = Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        sz.width,
        sz.height,
      );

      final Rect? isect = _intersectRects(dragRect, target);
      if (isect == null) continue;

      // 임계값들
      if (isect.height < 8.0 || isect.width < 4.0) continue;

      final double dragArea = (dragRect.width * dragRect.height).clamp(
        1,
        double.infinity,
      );
      final double targetArea = (target.width * target.height).clamp(
        1,
        double.infinity,
      );
      final double area = isect.width * isect.height;
      final double areaRatio = area / math.min(dragArea, targetArea);

      final double xr = math.max(
        (isect.width / dragRect.width).clamp(0.0, 1.0),
        (isect.width / target.width).clamp(0.0, 1.0),
      );
      final double yr = math.max(
        (isect.height / dragRect.height).clamp(0.0, 1.0),
        (isect.height / target.height).clamp(0.0, 1.0),
      );

      if (xr < 0.12 || yr < 0.25 || areaRatio < 0.02) continue;

      final OverlapSide side = _primaryOverlapSide(
        dragRect,
        target,
        verticalDelta,
      );

      debugPrint(
        '🎯 overlap: drag=$draggingId → target=$id | side=${side.name} | area=${(areaRatio * 100).toStringAsFixed(1)}% x=${(xr * 100).toStringAsFixed(1)}% y=${(yr * 100).toStringAsFixed(1)}% | inter=${isect.width.toStringAsFixed(1)}x${isect.height.toStringAsFixed(1)}',
      );
      results.add(
        OverlapResult(
          targetId: id,
          targetType: SpatialElementType.image,
          targetRect: target,
          draggingRect: dragRect,
          intersection: isect,
          area: area,
          areaRatioAgainstDrag: areaRatio,
          xRatio: xr,
          yRatio: yr,
          side: side,
        ),
      );
    }

    results.sort((a, b) {
      final byArea = b.areaRatioAgainstDrag.compareTo(a.areaRatioAgainstDrag);
      if (byArea != 0) return byArea;
      return b.yRatio.compareTo(a.yRatio);
    });
    debugPrint(
      '🎯 precise: results=${results.length}${results.isNotEmpty ? ", top=" + results.first.targetId : ''}',
    );
    return results;
  }

  // 사각형 교차 (없으면 null)
  Rect? _intersectRects(Rect a, Rect b) {
    final double left = math.max(a.left, b.left);
    final double top = math.max(a.top, b.top);
    final double right = math.min(a.right, b.right);
    final double bottom = math.min(a.bottom, b.bottom);
    if (right <= left || bottom <= top) return null;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  OverlapSide _primaryOverlapSide(
    Rect drag,
    Rect target,
    double verticalDelta,
  ) {
    // 세로 이동량을 우선 고려하여 주된 방향을 결정
    if (verticalDelta.abs() > (drag.height * 0.1)) {
      return verticalDelta < 0 ? OverlapSide.top : OverlapSide.bottom;
    }
    // 그렇지 않으면 중심 거리로 판정
    final Offset dc = drag.center;
    final Offset tc = target.center;
    final double dx = dc.dx - tc.dx;
    final double dy = dc.dy - tc.dy;
    if (dx.abs() > dy.abs()) {
      return dx < 0 ? OverlapSide.left : OverlapSide.right;
    } else {
      return dy < 0 ? OverlapSide.top : OverlapSide.bottom;
    }
  }
}
