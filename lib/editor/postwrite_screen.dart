import 'package:doppy/editor/component/single_image_component_builder.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/title_paragraph_component.dart';
import 'package:doppy/editor/custom_nodes/image_row_node.dart';
import 'package:doppy/editor/component/custom_paragraph_component.dart';

import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/overlay/drag_overlay_widget.dart';
import 'package:doppy/editor/image/image_edit.dart';
import 'package:doppy/editor/image/image_editor_plus_screen.dart';
import 'package:flutter/services.dart';
import 'package:doppy/editor/style/style_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  Offset? _lastTapPosition; // 마지막 탭 위치 저장

  @override
  void initState() {
    super.initState();

    document = MutableDocument(
      nodes: [
        ParagraphNode(
          id: '1',
          text: AttributedText(''),
          metadata: {'isTitle': true},
        ),
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
        // 스크롤 영역 확보를 위한 여유 공간
        ImageNode(
          id: '21',
          imageUrl:
              'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQWfMSIOQpP83ncpDgty8qB2tgKjCpqCFVTIRUdflGvJJS44tHiQjwZjMCzTBnfwARtHjc&usqp=CAU',
        ),
        ParagraphNode(id: '11', text: AttributedText(' ')),
        ParagraphNode(id: '12', text: AttributedText(' ')),
        ParagraphNode(id: '13', text: AttributedText(' ')),
        ParagraphNode(id: '14', text: AttributedText(' ')),
        ParagraphNode(id: '15', text: AttributedText(' ')),
        ParagraphNode(id: '16', text: AttributedText(' ')),
        ParagraphNode(id: '17', text: AttributedText(' ')),
        ParagraphNode(id: '18', text: AttributedText(' ')),
        ParagraphNode(id: '19', text: AttributedText(' ')),
        ParagraphNode(id: '20', text: AttributedText(' ')),
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
      imageService: context.read<ImageService>(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 32,
        scrolledUnderElevation: 0,
        leading: TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: GestureDetector(
            onTap: () {
              Navigator.pop(context);
            },
            child: Icon(Icons.arrow_back_ios_new_rounded),
          ),
        ),
        actions: [
          AnimatedBuilder(
            animation: editorService,
            builder: (context, _) {
              final enabled = editorService.canPublish;
              return TextButton(
                onPressed: enabled ? () {} : null,
                child: Text(
                  '다음',
                  style: TextStyle(
                    color:
                        enabled
                            ? const Color.fromARGB(255, 9, 144, 255)
                            : const Color.fromARGB(255, 182, 211, 255),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          AnimatedScale(
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
                    padding: const EdgeInsets.only(bottom: 10.0), // 하단 여유 공간 추가
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 타이틀 문단은 SuperEditor 안에서 metadata로 스타일링 처리
                        Expanded(
                          child: SuperEditor(
                            gestureMode: DocumentGestureMode.iOS,
                            editor: editor,
                            stylesheet: buildCustomStylesheet(),
                            documentLayoutKey: _documentLayoutKey,
                            scrollController: scrollController,
                            componentBuilders: [
                              // 타이틀 문단 전용 빌더(드래그 없음)
                              TitleParagraphComponentBuilder(
                                editorService: editorService,
                              ),
                              // 커스텀 이미지 컴포넌트들
                              SingleImageComponentBuilder(
                                dragService: dragService,
                              ),
                              RowImageComponentBuilder(
                                dragService: dragService,
                              ),
                              CustomParagraphComponentBuilder(
                                dragService: dragService,
                                editorService: editorService,
                              ),
                              // 기본 컴포넌트들 (Paragraph 제외)
                              ...defaultComponentBuilders.where(
                                (builder) =>
                                    builder.runtimeType.toString() !=
                                    'ParagraphComponentBuilder',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Positioned.fill(
                  child: GestureDetector(
                    onTapDown: (details) {
                      // 탭 다운 시 위치 저장
                      _lastTapPosition = details.globalPosition;
                    },
                    onTap: () {
                      // 짧은 클릭 처리
                      if (_lastTapPosition != null) {
                        final nodeId =
                            editorService
                                .findNodeAtPosition(_lastTapPosition!)
                                ?.id;
                        if (nodeId != null) {
                          final node = document.getNodeById(nodeId);
                          if (node is ImageNode || node is ImageRowNode) {
                            // 이미지 또는 이미지 행 클릭
                            ImageService().selectImage(nodeId);
                          }
                        }
                      }
                    },
                    onLongPressStart: (details) {
                      final node = editorService.findNodeAtPosition(
                        details.globalPosition,
                      );
                      if (node != null) {
                        final nodeId = node.id;
                        final imageService = context.read<ImageService>();

                        if (node is ParagraphNode &&
                            node.metadata['isTitle'] == true) {
                          return;
                        }

                        if (node is ImageRowNode) {
                          // 이미지 행이 선택된 상태라면 전체 행 드래그
                          if (imageService.selectedImageId == nodeId) {
                            dragService.startDrag(
                              nodeId,
                              context,
                              details.globalPosition,
                            );
                          } else {
                            // 손가락이 클릭한 쪽의 가장 근접한 이미지를 분리해서 드래그
                            _startImageRowDrag(nodeId, details.globalPosition);
                          }
                        } else if (node is ImageNode) {
                          // 단일 이미지 드래그
                          dragService.startDrag(
                            nodeId,
                            context,
                            details.globalPosition,
                          );
                        } else {
                          // 이미지가 아닌 요소 드래그
                          dragService.startDrag(
                            nodeId,
                            context,
                            details.globalPosition,
                          );
                        }
                      }
                    },
                    onLongPressMoveUpdate: (details) {
                      dragService.updateDrag(details.globalPosition, context);
                    },
                    onLongPressEnd: (details) {
                      dragService.endDrag();
                    },
                    behavior: HitTestBehavior.translucent,
                  ),
                ),

                // 드래그 오버레이 (개선된 Stack 방식)
                if (dragService.draggingNodeId != null) _buildDragOverlay(),
              ],
            ),
          ),
          // 하단 툴바: 이미지 선택 시 이미지 퀵툴바, 아니면 텍스트 스타일 툴바
          Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: _buildBottomToolbar(),
          ),
        ],
      ),
    );
  }

  // 드래그 오버레이 빌드 (노션 스타일 컴포넌트 미리보기)
  Widget _buildDragOverlay() {
    final pos = dragService.dragPosition;
    final nodeId = dragService.draggingNodeId;
    if (pos == null || nodeId == null) return const SizedBox.shrink();

    // 분리할 이미지 정보가 있으면 해당 이미지의 오버레이 표시
    if (dragService.hasSplitImageInfo) {
      // DragService에서 분리 정보 가져오기
      final splitInfo = dragService.getSplitImageInfo();
      if (splitInfo != null) {
        final rowId = splitInfo['rowId'] as String;
        final imageIndex = splitInfo['imageIndex'] as int;

        // 분리할 이미지의 URL 가져오기
        final rowNode = document.getNodeById(rowId);
        if (rowNode is ImageRowNode && imageIndex < rowNode.imageUrls.length) {
          final splitImageUrl = rowNode.imageUrls[imageIndex];

          // 분리할 이미지의 오버레이 표시
          return DragOverlayWidget(
            nodeId: 'temp_split_image',
            nodeType: 'image',
            position: pos,
            document: document,
            splitImageUrl: splitImageUrl, // 분리용 임시 이미지 URL 전달
          );
        }
      }
    }

    // 일반적인 경우 (분리할 이미지 정보가 없을 때)
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

  // 하단 이미지 전용 퀵툴바 (이미지 선택 시에만 등장)
  Widget _buildImageQuickToolbar() {
    final selectedId = ImageService().selectedImageId;
    if (selectedId == null) return const SizedBox.shrink();

    final node = document.getNodeById(selectedId);
    if (node is! ImageNode) return const SizedBox.shrink();

    return Center(
      child: ImageBarWidget(
        imageUrl: node.imageUrl,
        onAdjust: () async {
          try {
            final bundle = NetworkAssetBundle(Uri.parse(node.imageUrl));
            final data = await bundle.load('');
            final bytes = data.buffer.asUint8List();
            final edited = await openImageEditorPlus(
              context,
              imageBytes: bytes,
            );
            if (edited != null) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('편집 완료 (반영 로직은 추후 연결)')),
              );
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('이미지 로드 실패: $e')));
          }
        },
        onCrop: () async {
          // 현재는 onAdjust와 동일 동작. 별도 크롭 UI 원하면 분기
          try {
            final bundle = NetworkAssetBundle(Uri.parse(node.imageUrl));
            final data = await bundle.load('');
            final bytes = data.buffer.asUint8List();
            final edited = await openImageEditorPlus(
              context,
              imageBytes: bytes,
            );
            if (edited != null) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('크롭 완료 (반영 로직은 추후 연결)')),
              );
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('이미지 로드 실패: $e')));
          }
        },
        onDelete: () {
          // TODO: 삭제 연동
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('삭제 기능은 추후 연동 예정')));
        },
      ),
    );
  }

  Widget _buildBottomToolbar() {
    final selectedId = context.watch<ImageService>().selectedImageId;

    return selectedId != null
        ? _buildImageQuickToolbar()
        : TextStylingToolbar(
          stylingService: TextStylingService(
            editor: editor,
            composer: composer,
          ),
          scrollController: scrollController,
          onInsertImage: () async {},
        );
  }

  // 이미지 행에서 특정 이미지 드래그 시작 (분리는 드롭 시)
  void _startImageRowDrag(String imageRowId, Offset globalPosition) {
    // 클릭한 위치에서 가장 근접한 이미지 인덱스 찾기
    final rowNode = document.getNodeById(imageRowId) as ImageRowNode?;
    if (rowNode != null) {
      final imageIndex = _findClickedImageIndex(rowNode, globalPosition);

      if (imageIndex != null) {
        print('분리할 이미지 인덱스: $imageIndex');

        // 이미지 행 전체를 드래그하되, 분리할 이미지 정보를 저장
        dragService.startDrag(imageRowId, context, globalPosition);

        // 분리할 이미지 정보를 DragService에 저장
        dragService.setSplitImageInfo(imageRowId, imageIndex);
      }
    }
  }

  // 클릭한 위치에서 가장 근접한 이미지 인덱스 찾기
  int? _findClickedImageIndex(ImageRowNode rowNode, Offset globalPosition) {
    try {
      // 간단한 방법: 화면 너비를 기반으로 이미지 인덱스 계산
      final imageCount = rowNode.imageUrls.length;
      final screenWidth = MediaQuery.of(context).size.width;
      final imageWidth = screenWidth / imageCount;

      // 클릭한 X 좌표에 따라 이미지 인덱스 계산
      final clickedIndex = (globalPosition.dx / imageWidth).floor();

      // 유효한 인덱스 범위 확인
      if (clickedIndex >= 0 && clickedIndex < imageCount) {
        print('계산된 이미지 인덱스: $clickedIndex (전체: $imageCount)');
        return clickedIndex;
      }

      // 기본값으로 첫 번째 이미지 반환
      print('기본값으로 첫 번째 이미지 선택');
      return 0;
    } catch (e) {
      print('이미지 인덱스 계산 에러: $e');
      return 0; // 에러 시 첫 번째 이미지 반환
    }
  }
}
