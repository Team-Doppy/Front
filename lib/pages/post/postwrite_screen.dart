import 'package:doppy/editor/image/component_builder.dart';
import 'package:doppy/editor/image/image_util.dart';
import 'package:doppy/editor/image/gallery_bottom_sheet.dart';
import 'package:doppy/editor/image/image_service.dart';
import 'package:doppy/editor/simple_grid.dart';
import 'package:doppy/editor/spatial_manager.dart';
import 'package:doppy/editor/styling/main_style_sheet.dart';
import 'package:doppy/editor/styling/text_styling_service.dart';
import 'package:doppy/editor/styling/text_styling_toolbar.dart';
import 'package:doppy/editor/util/view_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'dart:io';
import 'package:doppy/editor/publish/publish_service.dart';
import 'package:doppy/editor/publish/publishing_screen.dart';
import 'package:super_editor/super_editor.dart';

/// 글 공개 범위 옵션
enum VisibilityOption { public, partial, private }

class PostwriteScreen extends StatefulWidget {
  final double screenWidth;
  const PostwriteScreen({super.key, required this.screenWidth});

  @override
  State<PostwriteScreen> createState() => _PostwriteScreenState();
}

class _PostwriteScreenState extends State<PostwriteScreen> {
  late MutableDocument _document; //실제 데이터 관리
  late MutableDocumentComposer _composer; //문서 편집 상태와 커서 관리
  late Editor _editor; //문서 편집 기능 제공
  late FocusNode _editorFocusNode; //텍스트 입력 커서 관리
  bool showPublishButton = false;
  bool isDragging = false; // 🎯 드래그 상태 (오타 수정)
  bool _dragModeActive = false; // 롱프레스 드래그 모드

  final TextEditingController _titleController = TextEditingController();
  TextAlign _titleAlign = TextAlign.center;

  late GridSystem _gridSystem; //그리드 시스템
  late SpatialManager _spatialManager; //문서 내 요소 위치 관리

  late TextStylingSystem _stylingSystem; //텍스트 스타일링 관리

  // 앱바 드롭다운(공개 범위) 상태
  VisibilityOption _visibilityOption = VisibilityOption.public;

  // 이미지 롱프레스 드래그 모드 on/off 콜백
  void _onDragModeChanged(bool active) {
    setState(() {
      _dragModeActive = active;
    });
  }

  String _visibilityLabel(VisibilityOption option) {
    switch (option) {
      case VisibilityOption.public:
        return '전체공개';
      case VisibilityOption.partial:
        return '일부공개';
      case VisibilityOption.private:
        return '나만보기';
    }
  }

  void _onSubmit() {
    final preview = PublishService().extractPreviewData(
      _titleController,
      _document,
    );

    PublishService().prepareForPublishing(
      title: _titleController.text,
      document: _document,
      spatialManager: _spatialManager,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => PublishingScreen(
              preview: preview,
              document: _document,
              spatialManager: _spatialManager,
              visibilityOption: _visibilityOption,
            ),
      ),
    );
  }

  void _showKeyboard() {
    _editorFocusNode.requestFocus();
  }

  Future<void> _showGalleryBottomSheet() async {
    // 웹에서는 컴퓨터 폴더에서 선택, 모바일에서는 갤러리 선택
    if (kIsWeb) {
      await ImageService().pickImagesFromComputer(
        _editor,
        _document,
        _analyzeAndUpdateDocument,
        spatialManager: _spatialManager,
        context: context,
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder:
            (context) => GalleryBottomSheet(
              onImagesSelected: (List<File> imageFiles) async {
                try {
                  await ImageService().processMobileGalleryImages(
                    imageFiles,
                    _editor,
                    _document,
                    _analyzeAndUpdateDocument,
                    spatialManager: _spatialManager,
                    context: context,
                  );
                } catch (e) {
                  print('❌ 이미지 추가 중 오류: $e');
                }
              },
            ),
      );
    }
  }

  @override
  void initState() {
    super.initState();

    // 문서 초기화
    _document = MutableDocument(
      nodes: [
        ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText('오늘의 도피는 무엇인가요?'),
        ),
      ],
    );

    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _composer,
    );
    final contentWidth = widget.screenWidth - SystemConstants.documentMargin;
    _editorFocusNode = FocusNode();
    _gridSystem = GridSystem(screenWidth: contentWidth);
    _spatialManager = SpatialManager(gridSystem: _gridSystem);
    _stylingSystem = TextStylingSystem(editor: _editor, composer: _composer);
    _spatialManager.setDocumentReferences(editor: _editor, document: _document);
    _spatialManager.showKeyboard = _showKeyboard;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _analyzeAndUpdateDocument();
      }
    });
  }

  @override
  void dispose() {
    _editorFocusNode.dispose();
    _spatialManager.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: PopupMenuButton<VisibilityOption>(
          initialValue: _visibilityOption,
          onSelected: (value) {
            setState(() {
              _visibilityOption = value;
            });
          },
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.withOpacity(0.15)),
          ),
          itemBuilder:
              (context) => [
                PopupMenuItem(
                  value: VisibilityOption.public,
                  child: Text(
                    _visibilityLabel(VisibilityOption.public),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                PopupMenuItem(
                  value: VisibilityOption.partial,
                  child: Text(
                    _visibilityLabel(VisibilityOption.partial),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                PopupMenuItem(
                  value: VisibilityOption.private,
                  child: Text(
                    _visibilityLabel(VisibilityOption.private),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _visibilityLabel(_visibilityOption),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.black,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (_titleController.text.isNotEmpty) {
                _onSubmit();
              }
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            ),
            child: Text(
              '등록',
              style: TextStyle(
                color:
                    (_titleController.text.isNotEmpty)
                        ? const Color.fromARGB(255, 102, 145, 255)
                        : const Color.fromARGB(255, 177, 177, 177),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: TextField(
              controller: _titleController,
              onChanged: (val) {
                setState(() {
                  showPublishButton = _titleController.text.isNotEmpty;
                });
              },
              minLines: 1,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              cursorColor: Colors.black,
              decoration: const InputDecoration(
                hintText: '제목을 입력하세요',
                hintStyle: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 194, 194, 194),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),

              textAlign: _titleAlign,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Listener(
      onPointerDown: (event) {},
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        child: ListenableBuilder(
          listenable: _composer,
          builder: (context, child) {
            final editorContent = Stack(
              clipBehavior: Clip.none,
              children: [
                // Super Editor
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final contentWidth = constraints.maxWidth;
                      _gridSystem = GridSystem(screenWidth: contentWidth);
                      final editor = Container(
                        margin: EdgeInsets.zero,
                        padding: EdgeInsets.only(bottom: 30),
                        child: EditorViewScale(
                          scale: _dragModeActive ? 0.8 : 1.0,
                          child: SuperEditor(
                            editor: _editor,
                            focusNode: _editorFocusNode,
                            stylesheet: buildCustomStylesheet(context),
                            selectionStyle: SelectionStyles(
                              selectionColor: Colors.grey.withOpacity(0.3),
                            ),
                            documentOverlayBuilders: [
                              SuperEditorIosHandlesDocumentLayerBuilder(),
                            ],
                            gestureMode:
                                kIsWeb
                                    ? DocumentGestureMode.mouse
                                    : DocumentGestureMode.iOS,
                            inputSource: TextInputSource.ime,
                            componentBuilders: [
                              InteractiveFloatingImageComponentBuilder(
                                spatialManager: _spatialManager,
                                gridSystem: _gridSystem,
                                onDragModeChanged: _onDragModeChanged,
                              ),
                              ...defaultComponentBuilders,
                            ],
                          ),
                        ),
                      );
                      // 드래그 모드에서는 화면을 시각적으로만 축소하되,
                      // 위아래 컨텐츠가 잘리지 않도록 OverflowBox + Transform.scale 조합 사용
                      // 뷰포트가 무한 높이를 받는 문제를 피하기 위해, 제약은 유지하고 시각적으로만 축소
                      final scale = _dragModeActive ? 0.8 : 1.0;
                      final viewHeight = constraints.maxHeight;
                      final dy = (viewHeight - viewHeight * scale) / 2;
                      return Transform(
                        alignment: Alignment.topCenter,
                        transform:
                            Matrix4.identity()
                              ..translate(0.0, dy)
                              ..scale(scale, scale, 1.0),
                        child: editor,
                      );
                    },
                  ),
                ),
                Positioned(
                  bottom: 0,
                  child: TextStylingToolbar(
                    stylingSystem: _stylingSystem,
                    onInsertImage: () async {
                      _showGalleryBottomSheet();
                    },
                  ),
                ),
              ],
            );

            // 편집기 루트를 전체적으로 감싸 시각적 축소만 적용.
            // 좌우 끝까지 이동 가능하도록 내부 로직은 기존 screenWidth를 그대로 사용.
            return editorContent;
          },
        ),
      ),
    );
  }

  //중요
  void _analyzeAndUpdateDocument() {
    if (!mounted) return;

    _spatialManager.analyzeAndUpdateDocument(
      document: _document,
      screenWidth: _gridSystem.screenWidth,
      documentPadding: 0.0,
    );

    _spatialManager.printDocStructure();
  }
}
