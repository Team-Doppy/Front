import 'package:doppy/editor/component/single_image_component_builder.dart';
import 'package:doppy/editor/component/row_image_component_builder.dart';
import 'package:doppy/editor/custom_nodes/image_row_node.dart';
import 'package:doppy/editor/custom_nodes/paragraph.dart' as custom;
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
        custom.ParagraphNode(id: '1', text: AttributedText('Hello, World1!')),
        custom.ParagraphNode(id: '2', text: AttributedText('Hello, World2!')),
        custom.ParagraphNode(id: '3', text: AttributedText('Hello, World3!')),
        custom.ParagraphNode(id: '4', text: AttributedText('Hello, World4!')),
        custom.ParagraphNode(id: '5', text: AttributedText('Hello, World5!')),
        custom.ParagraphNode(id: '6', text: AttributedText('Hello, World6!')),
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
        custom.ParagraphNode(id: '9', text: AttributedText('Hello, World8!')),
        custom.ParagraphNode(id: '10', text: AttributedText('Hello, World9!')),
        // 스크롤 영역 확보를 위한 여유 공간
        ImageNode(
          id: '21',
          imageUrl:
              'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQWfMSIOQpP83ncpDgty8qB2tgKjCpqCFVTIRUdflGvJJS44tHiQjwZjMCzTBnfwARtHjc&usqp=CAU',
        ),
        custom.ParagraphNode(id: '11', text: AttributedText(' ')),
        custom.ParagraphNode(id: '12', text: AttributedText(' ')),
        custom.ParagraphNode(id: '13', text: AttributedText(' ')),
        custom.ParagraphNode(id: '14', text: AttributedText(' ')),
        custom.ParagraphNode(id: '15', text: AttributedText(' ')),
        custom.ParagraphNode(id: '16', text: AttributedText(' ')),
        custom.ParagraphNode(id: '17', text: AttributedText(' ')),
        custom.ParagraphNode(id: '18', text: AttributedText(' ')),
        custom.ParagraphNode(id: '19', text: AttributedText(' ')),
        custom.ParagraphNode(id: '20', text: AttributedText(' ')),
      ],
    );
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    editorService = EditorService(editor: editor, document: document);
    editorService.setDocumentLayoutKey(_documentLayoutKey);
    dragService = DragService(
      editorService: editorService,
      scrollController: scrollController,
    );
    dragService.attachScrollController(scrollController);
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
    } else if (node is custom.ParagraphNode) {
      nodeType = 'paragraph';
    }

    return DragOverlayWidget(
      nodeId: nodeId,
      nodeType: nodeType,
      position: pos,
      document: document,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: AnimatedScale(
        duration: const Duration(milliseconds: 100),
        scale: dragService.draggingNodeId != null ? 0.9 : 1.0,
        child: Stack(
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 100),

              opacity:
                  dragService.draggingNodeId != null
                      ? 0.6
                      : 1.0, // 드래그 중일 때 투명도 조정
              child: Padding(
                padding: const EdgeInsets.only(bottom: 30.0), // 하단 여유 공간 추가
                child: SuperEditor(
                  gestureMode: DocumentGestureMode.iOS,
                  editor: editor,
                  stylesheet: buildCustomStylesheet(),
                  documentLayoutKey: _documentLayoutKey,
                  scrollController: scrollController,
                  componentBuilders: [
                    // 커스텀 이미지 컴포넌트들
                    SingleImageComponentBuilder(dragService: dragService),
                    RowImageComponentBuilder(dragService: dragService),
                    // 커스텀 ParagraphComponentBuilder (드래그 서비스 포함)
                    custom.CustomParagraphComponentBuilder(
                      dragService: dragService,
                    ),
                  ],
                ),
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
                            print(
                              '전역 RawGestureDetector: 롱프레스 시작 - 노드 ID: $nodeId',
                            );
                            dragService.startDrag(
                              nodeId,
                              context,
                              details.globalPosition,
                            );
                          }
                        };
                        instance.onLongPressMoveUpdate = (details) {
                          dragService.updateDrag(
                            details.globalPosition,
                            context,
                          );
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
          ],
        ),
      ),
    );
  }
}
