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

        // 🎯 캐시된 텍스트 높이 계산
        final nodeHeight = _calculatePreciseTextHeight(text);
        final contentWidth = screenWidth; // 🎯 패딩 제거

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

        currentY += nodeHeight; // 🎯 패딩 제거
        processedNodes++;
      } else if (node is ImageNode) {
        // 기존 메타데이터가 있으면 보존: scale/size/xOffset
        final prev = _elements[node.id];
        final prevScale = (prev?.metadata['scale'] as double?) ?? 1.0;
        final prevX = (prev?.metadata['xOffset'] as double?) ?? 0.0;

        // 🎯 실제 이미지 크기 사용 (기존 pxW/pxH 우선, 없으면 기본값)
        final prevPxW = (prev?.metadata['pxW'] as num?)?.toDouble();
        final prevPxH = (prev?.metadata['pxH'] as num?)?.toDouble();

        final prevGridX = (prev?.metadata['gridX'] as num?)?.toDouble() ?? 0.0;

        // 실제 이미지 크기 계산
        final actualWidth = prevPxW ?? SystemConstants.baseWidth;
        final actualHeight = prevPxH ?? SystemConstants.baseHeight;

        // 스케일에 따른 표시 크기 계산
        final displayWidth = actualWidth * prevScale;
        final displayHeight = actualHeight * prevScale;

        // 문단 흐름을 위한 라인 높이는 디스플레이 높이 기준으로 산정
        final totalImageHeight = displayHeight + SystemConstants.imagePadding;

        // 🎯 xOffset을 position에 반영
        final nodePosition = Offset(prevX, currentY);
        // 🎯 요소 자체의 사이즈는 실제 표시 크기로 설정 (렌더링 크기 반영)
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

  // 최적화된 줄 수 계산
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
        final pxW = element.metadata['pxW'] as double? ?? 0.0;
        final pxH = element.metadata['pxH'] as double? ?? 0.0;
        print(
          '  └── 이미지: ${element.metadata['text']} (scale: ${scale.toStringAsFixed(2)}, px: ${pxW.toInt()}x${pxH.toInt()})',
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

  // 🎯 요소 제거
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
}
