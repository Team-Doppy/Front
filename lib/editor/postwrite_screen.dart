import 'package:doppy/editor/component/image_component.dart';
import 'package:doppy/editor/component/image_row_component_builder.dart';
import 'package:doppy/editor/config/config.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart' hide DragMode;

/// 글 공개 범위 옵션
enum VisibilityOption { public, partial, private }

enum NodeType { paragraph, image, unknown }

class PostwriteScreen extends StatefulWidget {
  final double screenWidth;
  const PostwriteScreen({super.key, required this.screenWidth});

  @override
  State<PostwriteScreen> createState() => _PostwriteScreenState();
}

class _PostwriteScreenState extends State<PostwriteScreen> {
  late final Editor editor;
  late final MutableDocument document;
  late final MutableDocumentComposer composer;

  //service
  late final EditorService editorService;
  late final DragService dragService;

  OverlayEntry? overlayEntry;
  GlobalKey overlayKey = GlobalKey();
  final GlobalKey _documentLayoutKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    document = MutableDocument(
      nodes: [
        ParagraphNode(id: '1', text: AttributedText('Hello, World1!')),
        ParagraphNode(id: '2', text: AttributedText('Hello, World2!')),
        ParagraphNode(id: '3', text: AttributedText('Hello, World3!')),
        ParagraphNode(id: '4', text: AttributedText('Hello, World4!')),
        ParagraphNode(id: '5', text: AttributedText('Hello, World5!')),
        ParagraphNode(id: '6', text: AttributedText('Hello, World6!')),
        ImageNode(
          id: '7',
          imageUrl:
              'https://media.istockphoto.com/id/1317323736/ko/%EC%82%AC%EC%A7%84/%EB%82%98%EB%AC%B4-%EB%B0%A9%ED%96%A5%EC%9C%BC%EB%A1%9C-%ED%95%98%EB%8A%98%EB%A1%9C-%EB%B0%94%EB%9D%BC%EB%B3%B4%EB%8A%94-%EA%B2%BD%EC%B9%98.jpg?s=612x612&w=0&k=20&c=0xTghmMTXJ5ITCZ-LKTABbaPIK_1kWNf0FSFl_GL_7I=',
        ),
        ImageNode(
          id: '8',
          imageUrl:
              'https://image.utoimage.com/preview/cp872722/2022/12/202212008462_500.jpg',
        ),
      ],
    );
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    editorService = EditorService(editor: editor);
    editorService.setDocumentLayoutKey(_documentLayoutKey);
    dragService = DragService(editorService: editorService);
    dragService.addListener(_onDragChange);
  }

  @override
  void dispose() {
    super.dispose();
    editorService.dispose();
    dragService.removeListener(_onDragChange);
  }

  // 드래그 프리뷰 렌더링을 위한 리스너
  void _onDragChange() {
    if (mounted) setState(() {});
  }

  // 드래그 오버레이 빌드 (실시간 위치 사용)
  Widget _buildDragOverlay() {
    final pos = dragService.dragPosition;
    if (pos == null) return const SizedBox.shrink();

    return Positioned(
      left: pos.dx - 50,
      top: pos.dy - EditorConfig.complementOfGlobalToDocument,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withAlpha(220),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.drag_indicator, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              "Dragging ${dragService.draggingNodeId}",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 드롭 라인 빌드 (실시간 위치 사용)
  Widget _buildDropLine() {
    final pos = dragService.dragPosition;
    if (pos == null) return const SizedBox.shrink();

    // 이미지 가로 배치 모드일 때 세로 라인 표시
    if (dragService.dragMode == DragMode.imageRowMerge) {
      // 타겟 이미지의 경계를 가져와서 방향에 따라 세로 라인 표시
      final targetNode = editorService.editor.document.getNodeById(
        dragService.targetNodeId ?? '',
      );
      if (targetNode == null) return const SizedBox.shrink();

      final bounds = dragService.getNodeGlobalBounds(targetNode.id);
      if (bounds == null) return const SizedBox.shrink();

      // 드래그 방향에 따라 다른 라인 표시
      final isFromLeft = dragService.isDraggingFromLeft;

      return Stack(
        children: [
          // 왼쪽에서 오는 경우 왼쪽 라인만
          if (isFromLeft)
            Positioned(
              left: bounds.left - 2,
              top: bounds.top,
              child: Container(
                width: 4,
                height: bounds.size.height,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF007AFF).withAlpha(150),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          // 오른쪽에서 오는 경우 오른쪽 라인만
          if (!isFromLeft)
            Positioned(
              left: bounds.right - 2,
              top: bounds.top,
              child: Container(
                width: 4,
                height: bounds.size.height,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF007AFF).withAlpha(150),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    // 일반 모드일 때 가로 라인 표시
    final dropInfo = dragService.computeDropInfo(pos);
    final linePos = dropInfo?['linePosition'] as Offset?;
    if (linePos == null) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      top: linePos.dy,
      right: 0,
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          color: const Color(0xFF007AFF),
          borderRadius: BorderRadius.circular(1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF007AFF).withAlpha(150),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Stack(
        children: [
          SuperEditor(
            gestureMode: DocumentGestureMode.iOS,
            editor: editor,
            stylesheet: buildCustomStylesheet(),
            documentLayoutKey: _documentLayoutKey,
            componentBuilders: [
              ...defaultComponentBuilders,
              CustomImageComponentBuilder(),
              ImageRowComponentBuilder(),
            ],
          ),

          Positioned.fill(
            child: RawGestureDetector(
              gestures: {
                LongPressGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      LongPressGestureRecognizer
                    >(() => LongPressGestureRecognizer(), (
                      LongPressGestureRecognizer instance,
                    ) {
                      instance.onLongPressStart = (details) {
                        final nodeId =
                            editorService
                                .findNodeAtPosition(details.globalPosition)
                                ?.id;
                        if (nodeId != null) {
                          dragService.startDrag(
                            nodeId,
                            context,
                            details.globalPosition,
                          );
                        }
                      };
                      instance.onLongPressMoveUpdate = (details) {
                        dragService.updateDrag(details.globalPosition, context);
                      };
                      instance.onLongPressEnd = (details) {
                        dragService.endDrag();
                      };
                    }),
              },
              behavior: HitTestBehavior.translucent,
            ),
          ),

          // 드래그 오버레이 (개선된 Stack 방식)
          if (dragService.draggingNodeId != null) _buildDragOverlay(),

          // 드롭 라인 (개선된 Stack 방식)
          if (dragService.dropIndex != null) _buildDropLine(),
        ],
      ),
    );
  }
}
