import 'package:doppy/editor/component/single_image_component_builder.dart';
import 'package:doppy/editor/component/row_image_component_builder.dart';
import 'package:doppy/editor/config/config.dart';
import 'package:doppy/editor/custom_nodes/image_row_node.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/overlay/drag_overlay_widget.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart' hide DragMode;

/// 글 공개 범위 옵션
enum VisibilityOption { public, partial, private }

enum NodeType { paragraph, image, imageRow, unknown }

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

  ScrollController scrollController = ScrollController();

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
              'https://image.utoimage.com/preview/cp872722/2022/12/202212008462_500.jpg',
        ),
        ImageNode(
          id: '8',
          imageUrl:
              'https://media.istockphoto.com/id/1317323736/ko/%EC%82%AC%EC%A7%84/%EB%82%98%EB%AC%B4-%EB%B0%A9%ED%96%A5%EC%9C%BC%EB%A1%9C-%ED%95%98%EB%8A%98%EB%A1%9C-%EB%B0%94%EB%9D%BC%EB%B3%B4%EB%8A%94-%EA%B2%BD%EC%B9%98.jpg?s=612x612&w=0&k=20&c=0xTghmMTXJ5ITCZ-LKTABbaPIK_1kWNf0FSFl_GL_7I=',
        ),
        ParagraphNode(id: '9', text: AttributedText('Hello, World8!')),
        ParagraphNode(id: '10', text: AttributedText('Hello, World9!')),
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

  // 드래그 오버레이 빌드 (노션 스타일 컴포넌트 미리보기)
  Widget _buildDragOverlay() {
    final pos = dragService.dragPosition;
    final nodeId = dragService.draggingNodeId;
    if (pos == null || nodeId == null) return const SizedBox.shrink();

    // 노드 타입 확인
    final node = document.getNodeById(nodeId);
    if (node == null) return const SizedBox.shrink();

    String nodeType = 'default';
    if (node is ImageNode) {
      nodeType = 'image';
    } else if (node is ImageRowNode) {
      nodeType = 'imageRow';
    } else if (node is ParagraphNode) {
      nodeType = 'paragraph';
    }

    return DragOverlayWidget(
      nodeId: nodeId,
      nodeType: nodeType,
      position: pos,
      document: document,
    );
  }

  // 드롭 라인 빌드 (실시간 위치 사용)
  Widget _buildDropLine(BuildContext context) {
    final pos = dragService.dragPosition;
    if (pos == null) return const SizedBox.shrink();

    // computeDropInfo에서 모든 라인 정보를 가져옴
    final dropInfo = dragService.computeDropInfo(pos);
    if (dropInfo == null) return const SizedBox.shrink();

    // 이미지 가로 배치 모드일 때 세로 라인 표시
    final imageRowLineInfo =
        dropInfo['imageRowLineInfo'] as Map<String, dynamic>?;
    if (imageRowLineInfo != null) {
      final bounds = imageRowLineInfo['bounds'] as NodeBounds;
      final isFromLeft = imageRowLineInfo['isFromLeft'] as bool;

      return Stack(
        children: [
          // 왼쪽에서 오는 경우 왼쪽 라인만
          if (isFromLeft)
            Positioned(
              left: bounds.left - 2,
              top:
                  bounds.top -
                  EditorConfig.getComplementOfGlobalToDocument(context),
              child: Container(
                width: 4,
                height: bounds.size.height,
                decoration: BoxDecoration(color: const Color(0xFF007AFF)),
              ),
            ),
          // 오른쪽에서 오는 경우 오른쪽 라인만
          if (!isFromLeft)
            Positioned(
              left: bounds.right - 2,
              top:
                  bounds.top -
                  EditorConfig.getComplementOfGlobalToDocument(context),
              child: Container(
                width: 4,
                height: bounds.size.height,
                decoration: BoxDecoration(color: const Color(0xFF007AFF)),
              ),
            ),
        ],
      );
    }

    // 일반 모드일 때 가로 라인 표시
    final linePos = dropInfo['linePosition'] as Offset?;
    if (linePos == null) return const SizedBox.shrink();

    return Positioned(
      left: EditorConfig.documentPadding,
      top: linePos.dy - EditorConfig.getComplementOfGlobalToDocument(context),
      right: EditorConfig.documentPadding,
      child: Container(
        height: 3,
        decoration: BoxDecoration(color: const Color(0xFF007AFF)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Stack(
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 100),
            opacity:
                dragService.draggingNodeId != null
                    ? 0.7
                    : 1.0, // 드래그 중일 때 투명도 조정
            child: SuperEditor(
              gestureMode: DocumentGestureMode.iOS,
              editor: editor,
              stylesheet: buildCustomStylesheet(),
              documentLayoutKey: _documentLayoutKey,
              scrollController: scrollController,
              componentBuilders: [
                ...defaultComponentBuilders,
                SingleImageComponentBuilder(),
                RowImageComponentBuilder(),
              ],
            ),
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
          if (dragService.dropIndex != null) _buildDropLine(context),
        ],
      ),
    );
  }
}
