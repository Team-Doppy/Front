import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'simple_grid.dart';
import 'dart:math' as math;
import 'image/image_util.dart';

/// 공간 요소 타입
enum SpatialElementType { textNode, dragPreview, image }

/// 공간 요소 정보
class SpatialElement {
  final String id;
  final SpatialElementType type;
  final Offset position;
  final Size size;
  final Map<String, dynamic> metadata;

  SpatialElement({
    required this.id,
    required this.type,
    required this.position,
    required this.size,
    required this.metadata,
  });

  Rect get rect =>
      Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  double get top => position.dy;
  double get bottom => position.dy + size.height;
  double get left => position.dx;
  double get right => position.dx + size.width;
  double get centerY => position.dy + (size.height / 2);
}

class SpatialManager extends ChangeNotifier {
  final GridSystem gridSystem;
  final Map<String, SpatialElement> _elements = {};
  Editor? _documentEditor;
  MutableDocument? _document;

  SpatialManager({required this.gridSystem});

  Function(String imageId, String newTextId)? updateImagePosition;
  VoidCallback? showKeyboard;
  Function(String imageId, int newIndex)? onImageMoved;

  void setDocumentReferences({
    required Editor editor,
    required MutableDocument document,
  }) {
    _documentEditor = editor;
    _document = document;

    analyzeAndUpdateDocument(
      document: document,
      screenWidth: 400,
      documentPadding: 0.0,
    );
  }

  SpatialElement? getElement(String id) => _elements[id];

  void updateElement({
    required String id,
    required SpatialElementType type,
    required Offset position,
    required Size size,
    Map<String, dynamic>? metadata,
  }) {
    _elements[id] = SpatialElement(
      id: id,
      type: type,
      position: position,
      size: size,
      metadata: metadata ?? {},
    );

    printDocStructure();
  }

  void analyzeAndUpdateDocument({
    required MutableDocument document,
    required double screenWidth,
    required double documentPadding,
  }) {
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

        updateElement(
          id: node.id,
          type: SpatialElementType.textNode,
          position: nodePosition,
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
        final prevX = (prev?.metadata['xOffset'] as double?) ?? 0.0;
        final prevPxW = (prev?.metadata['pxW'] as num?)?.toDouble();
        final prevPxH = (prev?.metadata['pxH'] as num?)?.toDouble();
        final prevGridX = (prev?.metadata['gridX'] as num?)?.toDouble() ?? 0.0;
        final actualWidth = prevPxW ?? SystemConstants.baseWidth;
        final actualHeight = prevPxH ?? SystemConstants.baseHeight;
        final displayWidth = actualWidth * prevScale;
        final displayHeight = actualHeight * prevScale;
        final totalImageHeight = displayHeight + SystemConstants.imagePadding;
        final nodePosition = Offset(prevX, currentY);
        final nodeSize = Size(displayWidth, displayHeight);

        updateElement(
          id: node.id,
          type: SpatialElementType.image,
          position: nodePosition,
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
  }

  List<SpatialElement> get _sortedElements {
    return _elements.values.toList()
      ..sort((a, b) => a.position.dy.compareTo(b.position.dy));
  }

  /// 🎯 이미지 간 겹침 판단 (중앙점 ± 가로/세로/2 기준)
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
      final otherCenterX = element.position.dx + otherXOffset;
      final otherCenterY = element.position.dy + otherYOffset;
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

    print(
      '🎯 calculateImageOverlapRatio: $imageId, $imagePosition, $imageSize, $maxOverlapRatio',
    );

    return maxOverlapRatio;
  }

  int calculateHowManyLinesToMove({required String imageId, double? targetY}) {
    if (targetY == null) return 0;

    final currentElement = _elements[imageId];
    if (currentElement == null) {
      return 0;
    }

    // 드래그 방향 판단
    final currentImageY = currentElement.position.dy;
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
        _elements.values.toList()
          ..sort((a, b) => a.position.dy.compareTo(b.position.dy));
    print('===============================================');

    for (final element in sortedElements) {
      final isImage = element.metadata['isImageNode'] == true;
      final displayType = isImage ? 'IMAGE(textNode)' : 'textNode';
      print('• $displayType ${element.position}, ${element.size}');
      if (isImage) {
        final scale = element.metadata['scale'] as double? ?? 1.0;
        final pxW = (element.metadata['pxW'] as num?)?.toInt() ?? 0;
        final pxH = (element.metadata['pxH'] as num?)?.toInt() ?? 0;
        final xOffset = element.metadata['xOffset'] as double? ?? 0.0;
        final yOffset = element.metadata['yOffset'] as double? ?? 0.0;
        final gridX = (element.metadata['gridX'] as num?)?.toInt() ?? 0;
        final gridW = (element.metadata['gridW'] as num?)?.toInt() ?? 0;
        final gridH = (element.metadata['gridH'] as num?)?.toInt() ?? 0;

        print(
          '  └── 이미지: ${element.metadata['text']} (scale: ${scale.toStringAsFixed(2)}, px: ${pxW.toInt()}x${pxH.toInt()})',
        );
        print(
          '      └── 좌표: xOffset=${xOffset.toStringAsFixed(1)}, yOffset=${yOffset.toStringAsFixed(1)}, gridX=$gridX, gridW=$gridW, gridH=$gridH',
        );
      } else {
        final text = element.metadata['text'] ?? '';
        final shortText =
            text.length > 20 ? '${text.substring(0, 20)}...' : text;
        print('  └── 텍스트: "$shortText"');
      }
    }
    print('===============================================');
  }

  void removeElement(String id) {
    _elements.remove(id);
    _documentEditor!.execute([DeleteNodeRequest(nodeId: id)]);
    notifyListeners();
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

    if (linesToMove < 0) {
      _moveImageUp(imageId, linesToMove: linesToMove.abs());
    } else if (linesToMove > 0) {
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

      print('✅ 이미지 위로 이동 완료: $currentIndex → $newIndex');

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

      print('✅ 이미지 아래로 이동 완료: $currentIndex → $newIndex');

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
}
