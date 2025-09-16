import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/single_image_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/title_component.dart';
import 'package:doppy/editor/component/paragraph_component.dart';
import 'package:doppy/editor/component/location_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/image/custom_image_editor_screen.dart';
import 'package:doppy/editor/overlay/drag_overlay_widget.dart';
import 'package:doppy/editor/publish/post_export_screen.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/image_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/style/image_toolbar.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart';
import 'package:doppy/editor/sticker_canvas.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/overlay/save_draft_overlay.dart';
import 'package:doppy/editor/publish/post_exporter.dart';

/// 글 공개 범위 옵션
enum VisibilityOption { public, partial, private }

enum NodeType { paragraph, image, imageRow, location, unknown }

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
  late final FocusNode _editorFocusNode;

  //service
  late final EditorService editorService;
  late final DragService dragService;

  OverlayEntry? overlayEntry;
  GlobalKey overlayKey = GlobalKey();
  final GlobalKey _documentLayoutKey = GlobalKey();

  ScrollController scrollController = ScrollController();
  Offset? _lastTapPosition; // 마지막 탭 위치 저장
  bool _isKeyboardVisible = false; // 키보드 표시 상태

  @override
  void initState() {
    super.initState();

    document = MutableDocument(
      nodes: [
        ParagraphNode(
          id: '1',
          text: AttributedText(''),
          metadata: {'isTitle': true, 'textAlign': 'center'},
        ),
        ParagraphNode(
          id: '2',
          text: AttributedText(''),
          metadata: {'textAlign': 'center'},
        ),
      ],
    );
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    _editorFocusNode = FocusNode(debugLabel: 'editor_focus');

    editorService = EditorService(editor: editor, document: document);
    editorService.setDocumentLayoutKey(_documentLayoutKey);
    // ImageService는 build 메서드에서 설정
    dragService = DragService(
      editorService: editorService,
      scrollController: scrollController,
    );
    dragService.attachScrollController(scrollController);
    dragService.addListener(_onDragChange);

    // 선택 범위가 바뀔 때 이미지 하이라이트 갱신
    composer.selectionNotifier.addListener(_updateImageSelectionHighlight);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateImageSelectionHighlight();
      // 초기 진입 시 제목 아래 문단(id: '2')로 커서 이동 및 포커스 요청
      final node = document.getNodeById('2');
      if (node is ParagraphNode) {
        final offset = node.text.text.length;
        composer.setSelectionWithReason(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: node.id,
              nodePosition: TextNodePosition(offset: offset),
            ),
          ),
          SelectionReason.userInteraction,
        );
        _editorFocusNode.requestFocus();
      }
    });
  }

  /// 키보드가 현재 표시되고 있는지 확인
  bool get isKeyboardVisible => _isKeyboardVisible;

  /// 키보드 높이 가져오기
  double get keyboardHeight => MediaQuery.of(context).viewInsets.bottom;

  @override
  void dispose() {
    // 이미지 선택 상태 초기화 (조용히)
    ImageService().clearHighlightedSelectionSilently();
    ImageService().clearSelectionSilently();

    editorService.dispose();
    dragService.removeListener(_onDragChange);
    try {
      composer.selectionNotifier.removeListener(_updateImageSelectionHighlight);
    } catch (_) {}
    try {
      _editorFocusNode.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _cleanupAndExit() {
    try {
      // 1) 키보드/포커스 정리
      FocusScope.of(context).unfocus();

      // 2) 이미지 서비스 상태 초기화
      final img = ImageService();
      img.clearHighlightedSelection();
      img.selectImage(null);

      // 3) 스티커 서비스 상태 초기화(선택/드래그/리스트)
      try {
        final stickerSvc = context.read<StickerService>();
        stickerSvc.select(null);
        stickerSvc.removeAll();
        // 드래그 상태 리셋을 위해 begin/ end 없이 내부 플래그만 초기화
        // 리스트는 그대로 두되, 화면 이탈이므로 선택/플래그만 리셋
      } catch (_) {}

      // 4) 드래그 서비스 플래그 정리
      try {
        dragService.endDrag();
      } catch (_) {}

      // 5) 에디터 선택/하이라이트 제거
      try {
        composer.clearSelection();
      } catch (_) {}

      // 6) overlay 등 정리 후 종료
      Navigator.of(context).pop();
    } catch (_) {
      Navigator.of(context).pop();
    }
  }

  // 드래그 프리뷰 렌더링을 위한 리스너
  void _onDragChange() {
    if (mounted) setState(() {});
  }

  /// 텍스트 선택 범위에 포함된 이미지/이미지행을 회색 하이라이트로 표시
  void _updateImageSelectionHighlight() {
    try {
      final sel = composer.selection;
      if (sel == null) {
        ImageService().clearHighlightedSelection();
        return;
      }

      final baseIndex = document.getNodeIndexById(sel.base.nodeId);
      final extentIndex = document.getNodeIndexById(sel.extent.nodeId);
      if (baseIndex == -1 || extentIndex == -1) {
        ImageService().clearHighlightedSelection();
        return;
      }

      final start = baseIndex <= extentIndex ? baseIndex : extentIndex;
      final end = baseIndex <= extentIndex ? extentIndex : baseIndex;
      final ids = <String>{};
      for (int i = start; i <= end; i++) {
        final node = document.getNodeAt(i);
        if (node == null) continue;
        if (node is ImageNode || node is ImageRowNode) {
          ids.add(node.id);
        }
      }

      ImageService().setHighlightedSelection(ids);
    } catch (_) {
      ImageService().clearHighlightedSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 키보드 상태 업데이트
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    _isKeyboardVisible = keyboardHeight > 0;

    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.darkSurface,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: AppColors.darkSurface,
          toolbarHeight: 40,
          scrolledUnderElevation: 0,
          leading: GestureDetector(
            onTap: () async {
              final decision = await Navigator.of(context).push<ExitDecision>(
                PageRouteBuilder(
                  opaque: false,
                  barrierDismissible: true,
                  pageBuilder: (_, __, ___) => const SaveDraftOverlay(),
                ),
              );
              if (decision == ExitDecision.saveDraft) {
                // TODO: 실제 임시저장 로직 연결 (스토리지/로컬 DB)
                Navigator.of(context).pop();
              }
              if (decision == ExitDecision.discard) {
                // 오버레이 닫힘 애니메이션이 끝난 뒤 안전하게 종료
                await Future.delayed(const Duration(milliseconds: 180));
                _cleanupAndExit();
              }
            },
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.darkTextPrimary,
              size: 20,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // 테스트: JSON 추출 후 콘솔 출력 및 Reader 화면으로 이동
                final exported = PostExporter.exportToMap(
                  editorService: editorService,
                  stickerService: context.read<StickerService>(),
                  viewportSize: MediaQuery.of(context).size,
                );
                final json = PostExporter.exportToJsonString(
                  editorService: editorService,
                  stickerService: context.read<StickerService>(),
                  viewportSize: MediaQuery.of(context).size,
                  pretty: true,
                );
                // ignore: avoid_print
                print('===== POST JSON =====\n$json');
                Navigator.of(context).push(
                  PageRouteBuilder(
                    opaque: false,
                    barrierDismissible: true,
                    pageBuilder:
                        (_, __, ___) => PostExportScreen(exported: exported),
                  ),
                );
              },
              child: Text(
                '다음',
                style: TextStyle(
                  color: AppColors.darkTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: 10),
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
                      padding: const EdgeInsets.only(
                        bottom: 10.0,
                      ), // 하단 여유 공간 추가
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 타이틀 문단은 SuperEditor 안에서 metadata로 스타일링 처리
                          Expanded(
                            child: Focus(
                              focusNode: _editorFocusNode,
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  textSelectionTheme: TextSelectionThemeData(
                                    cursorColor: AppColors.primary,
                                    selectionColor: AppColors.primary
                                        .withOpacity(0.3),
                                  ),
                                ),
                                child: SuperEditor(
                                  gestureMode: DocumentGestureMode.iOS,
                                  editor: editor,
                                  stylesheet: buildCustomStylesheet(),
                                  documentLayoutKey: _documentLayoutKey,
                                  scrollController: scrollController,
                                  selectionStyle: SelectionStyles(
                                    selectionColor: AppColors.primary
                                        .withOpacity(0.3),
                                  ),
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
                                    // 커스텀 위치 노드 컴포넌트
                                    LocationComponentBuilder(
                                      dragService: dragService,
                                    ),
                                    // 커스텀 언급 노드 컴포넌트
                                    MentionComponentBuilder(
                                      dragService: dragService,
                                    ),
                                    // 구분선 전용 컴포넌트
                                    DividerComponentBuilder(
                                      dragService: dragService,
                                    ),

                                    LinkComponentBuilder(
                                      dragService: dragService,
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
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  !context.read<StickerService>().isDragging
                      ? Positioned.fill(
                        child: GestureDetector(
                          onTapDown: (details) {
                            // 탭 다운 시 위치 저장
                            _lastTapPosition = details.globalPosition;
                            print('탭 다운: ${details.globalPosition}');
                          },
                          onTap: () {
                            // 짧은 클릭 처리
                            if (_lastTapPosition != null) {
                              final nodeId =
                                  editorService
                                      .findNodeAtPosition(_lastTapPosition!)
                                      ?.id;
                              if (nodeId != null) {
                                // 이미지 또는 이미지 행 클릭
                                final node = document.getNodeById(nodeId);
                                if (node is ImageNode || node is ImageRowNode) {
                                  ImageService().selectImage(nodeId);
                                }
                              }
                            }
                          },
                          onLongPressStart: (details) {
                            final node = editorService.findNodeAtPosition(
                              details.globalPosition,
                            );
                            print('클릭한 노드: $node');
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
                                  _startImageRowDrag(
                                    nodeId,
                                    details.globalPosition,
                                  );
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
                            dragService.updateDrag(
                              details.globalPosition,
                              context,
                            );
                          },
                          onLongPressEnd: (details) {
                            dragService.endDrag();
                          },
                          behavior: HitTestBehavior.translucent,
                        ),
                      )
                      : SizedBox.shrink(),

                  // 드래그 오버레이 (개선된 Stack 방식)
                  if (dragService.draggingNodeId != null) _buildDragOverlay(),
                ],
              ),
            ),
            // 스티커 캔버스(문서 위 오버레이)
            Positioned.fill(
              child: StickerCanvas(scrollController: scrollController),
            ),
          ],
        ),
        bottomNavigationBar: AnimatedPadding(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: Consumer<ImageService>(
              builder: (context, imageService, child) {
                return imageService.selectedImageId != null
                    ? _buildImageToolbar()
                    : _buildDefaultToolbar();
              },
            ),
          ),
        ),
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
    } else if (node is LocationNode) {
      nodeType = 'location';
    }

    return DragOverlayWidget(
      nodeId: nodeId,
      nodeType: nodeType,
      position: pos,
      document: document,
    );
  }

  Widget _buildDefaultToolbar() {
    return DefaultToolbar(
      stylingService: TextStylingService(editor: editor, composer: composer),
      editorService: editorService,
      scrollController: scrollController,
      isKeyboardVisible: _isKeyboardVisible,

      onDismissKeyboard: () {
        // 키보드 내리기
        FocusScope.of(context).unfocus();
      },
    );
  }

  Widget _buildImageToolbar() {
    final selectedId = ImageService().selectedImageId;
    if (selectedId == null) return const SizedBox.shrink();

    final node = document.getNodeById(selectedId);
    if (node is! ImageNode && node is! ImageRowNode)
      return const SizedBox.shrink();

    // 이미지 URL 가져오기
    String imageUrl;
    if (node is ImageNode) {
      imageUrl = node.imageUrl;
    } else if (node is ImageRowNode) {
      // ImageRowNode의 경우 첫 번째 이미지 사용
      imageUrl = node.imageUrls.isNotEmpty ? node.imageUrls.first : '';
    } else {
      return const SizedBox.shrink();
    }

    return ImageEditingToolbar(
      onAdjust: () async {
        try {
          final bundle = NetworkAssetBundle(Uri.parse(imageUrl));
          final bytes = await bundle
              .load('')
              .then((data) => data.buffer.asUint8List());
          final editedBytes = await openImageEditorPlus(
            context,
            imageBytes: bytes,
          );
          if (editedBytes != null) {
            print('이미지가 편집되었습니다');
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('이미지 보정을 불러올 수 없습니다: $e')));
        }
      },
      onDelete: () {
        _deleteImageSafely(selectedId);
      },
    );
  }

  /// 안전한 이미지 삭제 메서드
  void _deleteImageSafely(String imageId) {
    try {
      // 1단계: 모든 선택 상태를 먼저 초기화
      ImageService().selectImage(null);
      ImageService().clearHighlightedSelection();
      composer.clearSelection();

      // 2단계: 포커스 해제
      FocusScope.of(context).unfocus();

      // 3단계: 다음 프레임에서 이미지 삭제 실행
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          try {
            // 삭제할 노드의 인덱스 찾기
            final nodeIndex = document.getNodeIndexById(imageId);

            // 이미지 삭제
            document.deleteNode(imageId);

            // 마진 재계산 (삭제된 노드 주변)
            if (nodeIndex != -1) {
              editorService.recomputeParagraphMarginsAround(nodeIndex);
            }

            // 에디터 상태 강제 업데이트
            setState(() {});
          } catch (e) {
            print('이미지 삭제 중 오류: $e');
          }
        }
      });
    } catch (e) {
      print('이미지 삭제 준비 중 오류: $e');
    }
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
