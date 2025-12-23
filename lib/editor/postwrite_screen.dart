import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:doppy/editor/editor_appbar.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show ClipComponentBuilder, cleanupAllVideoPlayers;

import 'package:doppy/editor/style/selected_toolbar.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/single_image_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/component/title_component.dart';
import 'package:doppy/editor/component/paragraph_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/overlay/drag_overlay_widget.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/post_reader_service.dart';
import 'package:doppy/editor/service/content_change_detector.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart';
import 'package:doppy/editor/writer_sticker_canvas.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/theme/app_theme.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/overlay/draft_list_overlay.dart';
import 'package:doppy/editor/publish/post_exporter.dart';
import 'package:doppy/data/services/draft_service.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/theme_provider.dart';

/// 글 공개 범위 옵션
enum VisibilityOption { public, partial, private }

enum NodeType { paragraph, image, imageRow, location, unknown }

class PostwriteScreen extends StatefulWidget {
  final bool isEditingMode;
  final Map<String, dynamic>? exportedDataForEdit;
  final String? postId; // 수정 모드용 post ID

  const PostwriteScreen({
    super.key,
    this.isEditingMode = false,
    this.exportedDataForEdit,
    this.postId,
  });

  @override
  State<PostwriteScreen> createState() => _PostwriteScreenState();
}

class _PostwriteScreenState extends State<PostwriteScreen> {
  //super_editor
  late final Editor editor;
  late final MutableDocument document;
  late final MutableDocumentComposer composer;
  late final FocusNode _editorFocusNode;

  //service
  late final EditorService editorService;
  late final StickerService stickerService;
  late final NodeComponentService nodeComponentService;
  late final DragService dragService;
  late final DraftService draftService;
  late final TextStylingService textStylingService;

  //overlay
  OverlayEntry? overlayEntry;
  GlobalKey overlayKey = GlobalKey();
  final GlobalKey _documentLayoutKey = GlobalKey();

  //manipulation
  ScrollController scrollController = ScrollController();

  //keyboard
  // 🎯 성능 최적화: isKeyboardVisible은 build에서 MediaQuery로 직접 읽음
  String? currentDraftId; // 🎯 UUID 기반 임시저장 ID (글쓰기 시작 시 생성)

  // 영상 업로드 인디케이터 상태
  final ValueNotifier<bool> _videoUploadIndicatorNotifier = ValueNotifier<bool>(
    false,
  );

  // 공개범위 설정 (편집 모드용)
  String _editVisibility = 'public';
  List<int> _editGroupIds = [];

  // 서버에 적용된 제목 (썸네일 오버레이에서 변경 시 업데이트)
  String? _serverAppliedTitle;
  // 서버에 적용된 요약 (썸네일 오버레이에서 변경 시 업데이트)
  String? _serverAppliedSummary;
  // 서버에 적용된 썸네일 URL (썸네일 오버레이에서 변경 시 업데이트)
  String? _serverAppliedThumbnailUrl;

  // 저장 중 상태
  bool _isSaving = false;
  bool _isAutoSaving = false; // 자동 저장 중 상태
  Timer? _autoSaveTimer; // 자동 저장 타이머
  bool _shouldRefreshMyFeed = false; // 수정사항 발생 시 한 번만 새로고침
  bool _categoryChanged = false; // 카테고리 변경 여부

  // 🎯 제목 변경 감지용 (수정 완료 버튼에서 체크)
  String? _lastTitleText; // 마지막으로 서버에 저장한 제목

  @override
  void initState() {
    super.initState();

    // 편집 모드이면 전달된 exportedDataForEdit를 기반으로 문서를 복원
    // 새 글 작성 모드이면 빈 문서 생성
    if (widget.isEditingMode && widget.exportedDataForEdit != null) {
      try {
        // PostReaderService를 사용하여 문서 복원 (제목 포함)
        final postReaderService = PostReaderService();
        document = postReaderService.rebuildDocumentForRead(
          widget.exportedDataForEdit!,
          includeTitleNode: true, // 편집 모드에서는 제목도 포함
        );

        // 기존 공개범위 정보 복원
        final metadata =
            widget.exportedDataForEdit!['metadata'] as Map<String, dynamic>?;
        if (metadata != null) {
          final rawVis = (metadata['visibility'] ?? 'PUBLIC').toString();
          final visUpper = rawVis.toUpperCase();
          if (visUpper == 'PRIVATE') {
            _editVisibility = 'private';
            _editGroupIds = [];
          } else if (visUpper == 'GROUPS' || visUpper == 'PARTIAL') {
            _editVisibility = 'partial';
            final groupIds = metadata['groupIds'] as List<dynamic>?;
            _editGroupIds =
                groupIds?.map((e) => (e as num).toInt()).toList() ?? [];
          } else {
            _editVisibility = 'public';
            _editGroupIds = [];
          }
        }

        // 🎯 편집 모드: 초기 제목 설정 (수정 완료 버튼에서 변경 체크용)
        if (document.isNotEmpty) {
          final firstNode = document.getNodeAt(0);
          if (firstNode is ParagraphNode &&
              firstNode.metadata['isTitle'] == true) {
            _lastTitleText = firstNode.text.text;
            _serverAppliedTitle = _lastTitleText;
            debugPrint('[PostwriteScreen] 초기 제목 설정: "$_lastTitleText"');
          }
        }
      } catch (e) {
        // 실패 시 빈 문서로 초기화
        document = MutableDocument(
          nodes: [
            ParagraphNode(id: Editor.createNodeId(), text: AttributedText()),
          ],
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final translatedText = context.tr('load_failed');
            debugPrint(
              '[PostwriteScreen] 번역 테스트: load_failed = "$translatedText"',
            );
            ErrorHandler.showError(context, translatedText);
          }
        });
      }
    } else {
      debugPrint('🔄 새 글 작성 모드');
      // 새 글 작성 모드 - 빈 문서 생성
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
    }
    composer = MutableDocumentComposer();

    // FocusNode 초기화
    _editorFocusNode = FocusNode(debugLabel: 'editor_focus');

    // 🎯 성능 최적화: 포커스 상태는 MediaQuery로 자동 감지되므로
    // 별도 리스너 없이 build에서 직접 읽어서 사용
    // (키보드 높이 변화는 AnimatedPadding이 자동 처리)

    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    editorService = EditorService(editor: editor, document: document);
    editorService.setDocumentLayoutKey(_documentLayoutKey);
    textStylingService = TextStylingService(editor: editor, composer: composer);

    //service 초기화2

    stickerService = StickerService();
    nodeComponentService = NodeComponentService();

    // 전역 스타일링 서비스 설정 (렌더링용)
    setGlobalTextStylingService(textStylingService);

    // ImageService는 build 메서드에서 설정
    dragService = DragService(
      editorService: editorService,
      scrollController: scrollController,
    );
    dragService.attachScrollController(scrollController);
    dragService.addListener(_onDragging);

    // 임시저장 서비스 초기화
    draftService = DraftService();

    // 🎯 새 글 작성 모드: UUID 기반 draftId 생성
    if (!widget.isEditingMode) {
      const uuid = Uuid();
      currentDraftId = 'draft_${uuid.v4()}';
      debugPrint('[PostwriteScreen] 🆔 UUID 기반 draftId 생성: $currentDraftId');
    }

    // 문서 변경 시 다음 버튼 상태 업데이트
    editorService.addListener(_onEditorServiceChange);

    // 폰트 변경 감지
    textStylingService.addListener(_onEditorServiceChange);

    // 스티커(그리기 포함) 변경 감지
    stickerService.addListener(_onEditorServiceChange);

    // 🎯 자동 저장 시작 (편집 모드가 아닐 때만)
    if (!widget.isEditingMode) {
      _startAutoSave();
    }

    // 🎯 노드 선택 변경 감지: 노드가 선택되면 키보드 내리기
    nodeComponentService.addListener(_onNodeSelectionChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 편집 모드일 때 스티커 복원
      if (widget.isEditingMode && widget.exportedDataForEdit != null) {
        try {
          final postReaderService = PostReaderService();
          postReaderService.restoreStickers(
            exported: widget.exportedDataForEdit!,
            stickerService: stickerService,
          );
        } catch (e) {
          debugPrint('[PostwriteScreen] 스티커 복원 실패: $e');
        }
      }

      // 편집 모드가 아닐 때만 커서 이동
      if (!widget.isEditingMode) {
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
        }
      }
      try {
        // 최초 진입 스냅샷 마크(현재 상태를 저장 기준으로 간주)
        editorService.markSavedSnapshot();
        stickerService.saveInitialState();
      } catch (_) {}

      // 스크롤 리스너 추가
      scrollController.addListener(_onScrollChanged);

      // 🎯 폰트 미리 로드 시작 (백그라운드에서 병렬 처리)
      _preloadFonts();
    });
  }

  /// 폰트 미리 로드 (에디터 초기화 시 백그라운드에서 실행)
  Future<void> _preloadFonts() async {
    try {
      // 폰트 프리로드는 폰트 선택 시에만 수행 (필요할 때만 로드)
    } catch (e) {
      debugPrint('[PostwriteScreen] 초기화 실패 (무시): $e');
    }
  }

  bool _showAppBar = true;
  double _lastOffset = 0.0;
  bool _isScrollingUp = false;
  bool _previousKeyboardVisible = false; // 🎯 키보드 상태 추적

  // 🎯 성능 최적화: 키보드 상태 감지는 MediaQuery 변화로 자동 처리됨
  // 이 메서드는 더 이상 사용하지 않음 (스크롤 기반 앱바 제어로 분리)

  void _onScrollChanged() {
    // 🎯 스크롤 시에는 캐시 무효화 불필요 (노드 구조 변경이 아니므로)
    // 앱바 표시/숨김만 처리
    _handleAppBarVisibility();
  }

  /// 🎯 성능 최적화: 앱바 표시/숨김 전용 메서드 (스크롤 기반)
  void _handleAppBarVisibility() {
    if (!mounted || !scrollController.hasClients) return;

    final currentOffset = scrollController.offset;
    final maxScroll = scrollController.position.maxScrollExtent;
    final delta = currentOffset - _lastOffset;

    const scrollThreshold = 3.0;
    const topThreshold = 15.0;

    // 🎯 스크롤할 내용이 없으면 (maxScrollExtent가 0이면) 항상 앱바 표시
    if (maxScroll <= 0) {
      if (!_showAppBar) {
        setState(() {
          _showAppBar = true;
          _isScrollingUp = true;
        });
      }
      _lastOffset = currentOffset;
      return;
    }

    // 맨 위에 있을 때는 항상 앱바 표시
    if (currentOffset <= topThreshold) {
      if (!_showAppBar) {
        setState(() {
          _showAppBar = true;
          _isScrollingUp = true;
        });
      }
      _lastOffset = currentOffset;
      return;
    }

    // 스크롤 방향에 따른 앱바 표시/숨김
    if (delta.abs() > scrollThreshold) {
      if (delta < 0) {
        // 위로 스크롤 (앱바 표시)
        if (!_isScrollingUp || !_showAppBar) {
          setState(() {
            _isScrollingUp = true;
            _showAppBar = true;
          });
        }
      } else {
        // 아래로 스크롤 (앱바 숨김)
        if (_isScrollingUp && _showAppBar) {
          setState(() {
            _isScrollingUp = false;
            _showAppBar = false;
          });
        }
      }
    }

    _lastOffset = currentOffset;
  }

  void _onEditorServiceChange() {
    if (mounted) {
      // 🎯 노드 추가/변경 시 캐시 무효화 (다음 프레임에 한 번만)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          dragService.invalidateNodeRectCache();
          // 🎯 드래그 중이 아닐 때 선택 해제 확인 (드래그 종료 후 다른 로직에서 선택이 다시 설정되는 경우 방지)
          // 🎯 텍스트 입력 중이 아닐 때만 선택 해제 (텍스트 입력 중에는 키보드 유지)
          if (dragService.draggingNodeId == null) {
            final keyboardVisible =
                MediaQuery.of(context).viewInsets.bottom > 0;
            final hasFocus = _editorFocusNode.hasFocus;
            // 텍스트 입력 중이 아니면 선택 해제
            // 🎯 하지만 포커스가 없고 키보드도 없을 때만 선택 해제 (텍스트 입력 중에는 키보드 유지)
            if (!keyboardVisible && !hasFocus) {
              final nodeService = context.read<NodeComponentService>();
              // 🎯 이미지 분리/병합 후에는 명시적으로 모든 셀렉션 클리어
              nodeService.clearSelection();
              nodeService.clearHighlightedSelection();
              // 🎯 composer.clearSelection()은 호출하지 않음 - 키보드가 내려갈 수 있음
            }
          }
          // 🎯 특수 노드 삭제/복원 시 앱바 표시 상태 재확인 (스크롤 불가 상태에서는 항상 표시)
          _handleAppBarVisibility();
        }
      });
      setState(() {});
    }
  }

  // 드래그 프리뷰 렌더링을 위한 리스너
  void _onDragging() {
    if (mounted) setState(() {});
  }

  // 🎯 노드 선택 변경 리스너: 노드가 선택되면 키보드 내리기
  void _onNodeSelectionChanged() {
    if (mounted && nodeComponentService.selectedNodeId != null) {
      // 노드가 선택되면 키보드 내리기
      _editorFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _cleanupAndExit() {
    try {
      dragService.endDrag();
      composer.clearSelection();
      nodeComponentService.clearAll();
    } catch (_) {}

    try {
      stickerService.select(null);
      stickerService.removeAll();
    } catch (_) {}

    // 🎯 영상 파일 정리
    try {
      nodeComponentService.clearTempVideoFile('default');
    } catch (_) {}

    if (mounted) Navigator.of(context).pop();
  }

  // 서버에 적용된 제목을 원본 데이터에 반영 (변경 감지 시 사용)
  Map<String, dynamic> _updateOriginalWithServerTitle(
    Map<String, dynamic> original,
  ) {
    if (_serverAppliedTitle == null) return original;

    try {
      // Deep copy
      final updated = Map<String, dynamic>.from(original);
      final content = updated['content'] as Map<String, dynamic>?;
      if (content == null) return original;

      final nodes = content['nodes'] as List?;
      if (nodes == null || nodes.isEmpty) return original;

      // 첫 번째 노드가 제목 노드인지 확인
      final firstNode = nodes[0] as Map<String, dynamic>?;
      if (firstNode == null || firstNode['type'] != 'paragraph') {
        return original;
      }

      // 제목 텍스트만 업데이트
      final updatedNodes = List.from(nodes);
      final updatedFirstNode = Map<String, dynamic>.from(firstNode);
      updatedFirstNode['text'] = _serverAppliedTitle;

      updatedNodes[0] = updatedFirstNode;

      final updatedContent = Map<String, dynamic>.from(content);
      updatedContent['nodes'] = updatedNodes;

      updated['content'] = updatedContent;

      debugPrint('[PostwriteScreen] 원본 데이터에 서버 제목 반영: $_serverAppliedTitle');
      return updated;
    } catch (e) {
      debugPrint('[PostwriteScreen] 원본 데이터 업데이트 실패: $e');
      return original;
    }
  }

  // moved to EditorService (getNodeGlobalRect)
  // _detectVerticalGapAt은 각 컴포넌트의 _handleSpecialNodeTap에서 처리하므로 제거됨

  /// 마지막 특수 노드 아래 빈 공간 클릭 시 빈 문단 추가
  void _handleTapBelowLastSpecialNode(Offset globalPosition) {
    final lastIndex = document.nodeCount - 1;
    if (lastIndex < 0) return;

    final lastNode = document.getNodeAt(lastIndex);
    if (lastNode == null) return;

    // 마지막 노드가 특수 노드인지 확인
    final isSpecial = NodeTypeChecker.isSpecialNode(lastNode);
    if (!isSpecial) return;

    // 마지막 노드의 Rect 확인
    final nodeRect = dragService.getNodeGlobalRect(lastNode.id);
    if (nodeRect == null) return;

    // 🎯 노드 영역 아래 모든 여백을 클릭 가능 영역으로 확장
    final tapY = globalPosition.dy;
    final isBelowNode = tapY > nodeRect.bottom;

    debugPrint(
      '[PostWrite] 빈 공간 탭 체크: tapY=$tapY, nodeBottom=${nodeRect.bottom}, isBelowNode=$isBelowNode',
    );

    if (isBelowNode) {
      // 🎯 실제로 그 위치가 비어있는지 확인 (다른 노드가 있는지 체크)
      final hitTestResult = editorService.findNodeByHitTest(
        globalPosition,
        dragService,
      );

      debugPrint(
        '[PostWrite] hitTestResult: ${hitTestResult?.key?.id}, lastNode: ${lastNode.id}',
      );

      // hit test 결과가 없거나, 마지막 노드인 경우만 빈 공간으로 간주
      final isEmpty =
          hitTestResult == null ||
          hitTestResult.key == null ||
          hitTestResult.key!.id == lastNode.id;

      debugPrint(
        '[PostWrite] isEmpty=$isEmpty → 빈 텍스트 추가 ${isEmpty ? "실행" : "스킵"}',
      );

      if (isEmpty) {
        editorService.insertEmptyParagraphAtIndex(lastIndex + 1);
        nodeComponentService.selectNode(null);

        // 🎯 새로 추가된 노드에 즉시 포커스
        Future.delayed(const Duration(milliseconds: 50), () {
          if (!mounted) return;

          final newLastIndex = document.nodeCount - 1;
          if (newLastIndex >= 0) {
            final newNode = document.getNodeAt(newLastIndex);
            if (newNode != null) {
              composer.setSelectionWithReason(
                DocumentSelection.collapsed(
                  position: DocumentPosition(
                    nodeId: newNode.id,
                    nodePosition: const TextNodePosition(offset: 0),
                  ),
                ),
                'user_tap_after_special_node',
              );
              _editorFocusNode.requestFocus();
            }
          }
        });
      }
    }
  }

  Stylesheet _buildStylesheet(BuildContext context) {
    return buildCustomStylesheet(context).copyWith(
      documentPadding: EdgeInsets.only(top: 0, left: 0, right: 0, bottom: 100),
    );
  }

  /// 🎯 자동 저장 시작 (30초마다)
  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (!mounted || widget.isEditingMode) {
        timer.cancel();
        return;
      }
      _autoSave();
    });
  }

  /// 🎯 자동 저장 실행
  Future<void> _autoSave() async {
    // 이미 저장 중이면 스킵
    if (_isAutoSaving || _isSaving) return;

    // 변경사항이 없으면 스킵
    if (!editorService.shouldPromptSaveOnExit(context)) return;

    // 🎯 업로드 중이면 자동 저장 스킵
    if (editorService.hasUnuploadedImages()) {
      return;
    }

    setState(() {
      _isAutoSaving = true;
    });

    try {
      // 🎯 제목 자동 추출 (없으면 본문에서 발췌)
      String title = PostExporter.getTitleOrExtractFromBody(document);

      // 본문도 없으면 로케일 적용된 "제목 없음" 사용
      if (title.trim().isEmpty) {
        title = context.tr('no_title');
      }

      // 🎯 UUID 기반 draftId 사용 (제목 기반 제거)
      if (currentDraftId == null) {
        // 혹시 UUID가 없으면 생성 (안전장치)
        const uuid = Uuid();
        currentDraftId = 'draft_${uuid.v4()}';
        debugPrint('[PostwriteScreen] ⚠️ UUID가 없어서 생성: $currentDraftId');
      }

      // 현재 draft ID를 sessionKey로 영상 파일만 가져오기
      final sessionKey = currentDraftId!;

      final videoFilePath = nodeComponentService.getTempVideoFilePath(
        sessionKey,
      );
      final videoThumbnailPath = nodeComponentService.getTempVideoThumbnailPath(
        sessionKey,
      );

      // 썸네일은 항상 첫 번째 이미지를 자동으로 설정
      String thumbnailUrl = '';
      final firstImageUrl = editorService.findFirstImageUrl();
      if (firstImageUrl != null && firstImageUrl.isNotEmpty) {
        thumbnailUrl = firstImageUrl;
      }

      // 🎯 UUID 기반 자동 저장 (제목은 자동 추출)
      currentDraftId = await draftService.saveDraft(
        editorService: editorService,
        stickerService: stickerService,
        title: title,
        summary: '',
        thumbnailUrl: thumbnailUrl,
        videoFilePath: videoFilePath,
        videoThumbnailPath: videoThumbnailPath,
        visibility: 'public',
        selectedGroupIds: [],
        existingDraftId: currentDraftId, // UUID 기반 ID 사용
      );

      // 저장 스냅샷 마크
      editorService.markSavedSnapshot();
      stickerService.saveInitialState();

      debugPrint('[PostwriteScreen] ✅ 자동 저장 완료: $title');
    } catch (e) {
      debugPrint('[PostwriteScreen] ⚠️ 자동 저장 실패: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isAutoSaving = false;
        });
      }
    }
  }

  void dispose() {
    // 🎯 자동 저장 타이머 정리
    _autoSaveTimer?.cancel();
    // 🎯 에디터 종료 시 진행 중인 비디오 압축 취소
    final uploadService = UploadService();
    uploadService.cancelEditorCompressions('editor_${editorService.hashCode}');

    // 영상 업로드 인디케이터 정리
    _videoUploadIndicatorNotifier.dispose();

    // 🎯 에디터 종료 시 모든 비디오 플레이어 정리
    try {
      cleanupAllVideoPlayers();
      debugPrint('[PostwriteScreen] 모든 비디오 플레이어 정리 완료');
    } catch (e) {
      debugPrint('[PostwriteScreen] 비디오 정리 오류: $e');
    }

    // 이미지 선택 상태 초기화
    nodeComponentService.clearHighlightedSelectionSilently();
    nodeComponentService.clearSelectionSilently();

    textStylingService.removeListener(_onEditorServiceChange);
    textStylingService.dispose();
    editorService.removeListener(_onEditorServiceChange);
    editorService.dispose();
    stickerService.removeListener(_onEditorServiceChange);
    nodeComponentService.removeListener(_onNodeSelectionChanged);
    dragService.removeListener(_onDragging);
    scrollController.removeListener(_onScrollChanged);
    _editorFocusNode.dispose();

    // 🎯 카테고리 변경 시 피드 프로바이더 캐시 초기화 + 새로고침
    if (_categoryChanged) {
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final feed = MyProfileFeedProvider();
          feed.invalidateCache();
          feed.refresh().catchError((_) {});
          debugPrint('[PostwriteScreen] 카테고리 변경 후 피드 프로바이더 캐시 초기화 + 새로고침 완료');
        } catch (e) {
          debugPrint('[PostwriteScreen] 카테고리 변경 후 피드 새로고침 실패: $e');
        }
      });
    }
    // 🎯 수정 도중 변경이 있었다면 내 피드 선택적 업데이트 (전체 새로고침 생략)
    else if (_shouldRefreshMyFeed && widget.postId != null) {
      // 비디오 컨트롤러 정리가 완전히 완료될 때까지 약간 지연
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final feed = MyProfileFeedProvider(); // 싱글톤 직접 접근
          final postId = widget.postId!;

          // 변경된 메타데이터만 선택적 업데이트
          feed.updatePostMetadata(
            postId,
            thumbnailImageUrl: _serverAppliedThumbnailUrl,
            title: _serverAppliedTitle,
            summary: _serverAppliedSummary,
          );
          debugPrint('[PostwriteScreen] 프로필 피드 선택적 업데이트 완료 (썸네일/제목/요약 변경)');
        } catch (e) {
          debugPrint('[PostwriteScreen] 프로필 피드 선택적 업데이트 실패: $e');
          // 실패 시 fallback으로 전체 새로고침
          try {
            final feed = MyProfileFeedProvider();
            feed.invalidateCache();
            feed.refresh().catchError((_) {});
          } catch (_) {}
        }
      });
    } else if (_shouldRefreshMyFeed && widget.postId == null) {
      // 새 포스트 생성 시에는 전체 새로고침 필요 (포스트 ID가 없음)
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final feed = MyProfileFeedProvider();
          feed.invalidateCache();
          feed.refresh().catchError((_) {});
        } catch (_) {}
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 EditorService에 context 설정 (노드 선택 해제용)
    editorService.setContext(context);

    // 🎯 성능 최적화: 키보드 상태는 MediaQuery에서 직접 읽기 (변수 저장 제거)
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    // 🎯 키보드가 내려가면 앱바 강제 표시
    if (_previousKeyboardVisible && !isKeyboardVisible) {
      // 키보드가 내려갔을 때
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_showAppBar) {
          setState(() {
            _showAppBar = true;
            _isScrollingUp = true;
          });
        }
      });
    }
    _previousKeyboardVisible = isKeyboardVisible;

    return WillPopScope(
      onWillPop: () async {
        if (widget.isEditingMode) {
          // 수정 모드: 변경사항이 있는지 확인
          // 서버에 적용된 제목이 있으면 원본 데이터를 업데이트해서 비교
          final originalForComparison =
              _serverAppliedTitle != null
                  ? _updateOriginalWithServerTitle(widget.exportedDataForEdit!)
                  : widget.exportedDataForEdit!;

          final hasChanges = ContentChangeDetector.hasContentChanged(
            originalExported: originalForComparison,
            editorService: editorService,
            stickerService: stickerService,
          );

          // 변경사항이 없으면 바로 나가기
          if (!hasChanges) {
            _cleanupAndExit();
            return false;
          }

          // 변경사항이 있을 때만 다이얼로그 표시
          final shouldCancel = await DialogUtils.showConfirmDialog(
            context,
            title: context.tr('cancel_edit_title'),
            message: context.tr('cancel_edit_message'),
            confirmText: context.tr('cancel'),
            cancelText: context.tr('continue_editing'),
            isDestructive: true,
          );
          if (shouldCancel == true) {
            _cleanupAndExit();
          }
          return false;
        }

        // 새 글 작성 모드: 변경사항이 있으면 임시저장 다이얼로그
        final needPrompt = editorService.shouldPromptSaveOnExit(context);
        if (needPrompt) {
          final shouldSave = await DialogUtils.showConfirmDialog(
            context,
            title: context.tr('discard_or_save_title'),
            message: context.tr('discard_or_save_message'),
            confirmText: context.tr('save_and_exit'),
            cancelText: context.tr('discard_without_save'),
            isDestructive: false,
          );
          if (shouldSave == true) {
            final success = await _saveDraft();
            // ✅ 임시저장 성공했을 때만 편집기 닫기
            if (success) {
              _cleanupAndExit();
            }
            // 실패하면 편집기 유지 (다이얼로그만 닫힘)
          } else if (shouldSave == false) {
            _cleanupAndExit();
          }
          // null이면 아무 것도 안 함 (다이얼로그만 닫힘)
        } else {
          _cleanupAndExit();
        }
        return false;
      },

      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Theme(
                            data: AppTheme.lightTheme,
                            child: Stack(
                              children: [
                                Builder(
                                  builder: (context) {
                                    final screenWidth =
                                        MediaQuery.of(
                                          context,
                                        ).size.width; // 🚀 최고 효율: 한 번만 계산
                                    return RawScrollbar(
                                      controller: scrollController,
                                      thumbColor: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.3),
                                      thickness: 4,
                                      radius: const Radius.circular(12),
                                      child: Listener(
                                        behavior: HitTestBehavior.translucent,
                                        onPointerDown: (details) {
                                          // 🎯 마지막 특수 노드 아래 빈 공간 클릭 감지
                                          // Listener는 터치를 소비하지 않아 다른 위젯도 정상 작동
                                          _handleTapBelowLastSpecialNode(
                                            details.position,
                                          );
                                        },
                                        child: SuperEditor(
                                          gestureMode:
                                              Platform.isIOS
                                                  ? DocumentGestureMode.iOS
                                                  : DocumentGestureMode.android,
                                          editor: editor,
                                          focusNode: _editorFocusNode,
                                          stylesheet: _buildStylesheet(context),
                                          selectionStyle: SelectionStyles(
                                            selectionColor: AppColors.primary
                                                .withValues(alpha: 0.3),
                                            highlightEmptyTextBlocks: false,
                                          ),
                                          documentLayoutKey: _documentLayoutKey,
                                          scrollController: scrollController,

                                          componentBuilders: [
                                            // 타이틀 문단 전용 빌더(드래그 없음)
                                            TitleParagraphComponentBuilder(
                                              editorService: editorService,
                                            ),
                                            // 커스텀 이미지 컴포넌트들
                                            SingleImageComponentBuilder(
                                              screenWidth:
                                                  screenWidth, // 🚀 최고 효율: 전달
                                              dragService: dragService,
                                              isDarkMode:
                                                  context
                                                      .read<ThemeProvider>()
                                                      .themeMode ==
                                                  ThemeMode.dark,
                                            ),
                                            RowImageComponentBuilder(
                                              screenWidth:
                                                  screenWidth, // 🚀 최고 효율: 전달
                                              dragService: dragService,
                                              isDarkMode:
                                                  context
                                                      .read<ThemeProvider>()
                                                      .themeMode ==
                                                  ThemeMode.dark,
                                            ),
                                            PageViewImageComponentBuilder(
                                              screenWidth:
                                                  screenWidth, // 🚀 최고 효율: 전달
                                              dragService: dragService,
                                              isDarkMode:
                                                  context
                                                      .read<ThemeProvider>()
                                                      .themeMode ==
                                                  ThemeMode.dark,
                                            ),
                                            CustomParagraphComponentBuilder(
                                              dragService: dragService,
                                              editorService: editorService,
                                            ),

                                            // 구분선 전용 컴포넌트
                                            DividerComponentBuilder(
                                              dragService: dragService,
                                            ),

                                            LinkComponentBuilder(
                                              dragService: dragService,
                                              isDarkMode:
                                                  context
                                                      .read<ThemeProvider>()
                                                      .themeMode ==
                                                  ThemeMode.dark,
                                            ),

                                            ClipComponentBuilder(
                                              dragService: dragService,
                                              isEditing: true,
                                              isDarkMode:
                                                  context
                                                      .read<ThemeProvider>()
                                                      .themeMode ==
                                                  ThemeMode.dark,
                                            ),

                                            // 기본 컴포넌트들 (Paragraph 제외)
                                            ...defaultComponentBuilders.where(
                                              (builder) =>
                                                  builder.runtimeType
                                                      .toString() !=
                                                  'ParagraphComponentBuilder',
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 🎯 하단 패딩 영역(bottom: 100) 클릭 감지

                  // 드래그 오버레이 (키보드가 내려가 있을 때만 표시)
                  if (dragService.draggingNodeId != null && !isKeyboardVisible)
                    _buildDragOverlay(),

                  // 스티커 캔버스 (최상위 레이어 - 터치 우선권)
                  Positioned.fill(
                    child: StickerCanvas(scrollController: scrollController),
                  ),

                  // 저장 중 전체 화면 블록 오버레이
                  if (_isSaving)
                    Positioned.fill(
                      child: AbsorbPointer(
                        absorbing: true,
                        child: Container(color: Colors.transparent),
                      ),
                    ),

                  // 앱바
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    top: _showAppBar ? -5 : -100,
                    child:
                        widget.isEditingMode
                            ? EditModeAppBar(
                              editorService: editorService,
                              onSave: _saveEditedPost,
                              currentVisibility: _editVisibility,
                              currentGroupIds: _editGroupIds,
                              postId: widget.postId,
                              isSaving: _isSaving, // 저장 중 상태 전달
                              isAutoSaving: _isAutoSaving, // 자동 저장 중 상태 전달
                              videoUploadIndicatorNotifier:
                                  _videoUploadIndicatorNotifier,
                              onVisibilityChanged: (visibility, groupIds) {
                                setState(() {
                                  _editVisibility = visibility;
                                  _editGroupIds = groupIds;
                                });
                                _shouldRefreshMyFeed = true;
                                // 공개범위 변경 플래그만 설정 (dispose에서 새로고침)
                              },
                              onTitleSummaryChanged: (title, summary) {
                                // 썸네일 오버레이에서 제목/요약이 변경되면 에디터 제목 노드 업데이트
                                editorService.updateTitleNode(title);
                                // 서버에 적용된 제목/요약 저장 (선택적 업데이트용)
                                setState(() {
                                  _serverAppliedTitle = title;
                                  _serverAppliedSummary = summary;
                                });
                                debugPrint(
                                  '[PostwriteScreen] 제목/요약 업데이트 및 서버 적용: title=$title, summary=$summary',
                                );
                                _shouldRefreshMyFeed = true;
                              },
                              onCategoryChanged: () {
                                _categoryChanged = true;
                                // 카테고리 변경 플래그 설정 (dispose에서 캐시 초기화 + 새로고침)
                              },
                              onThumbnailChanged: (url, id) {
                                debugPrint(
                                  '[PostwriteScreen] onThumbnailChanged 콜백 받음: url=$url, id=$id',
                                );
                                // 서버에 적용된 썸네일 URL 저장 (선택적 업데이트용)
                                setState(() {
                                  _serverAppliedThumbnailUrl = url;
                                });
                                _shouldRefreshMyFeed = true;
                                // 썸네일 변경 플래그만 설정 (dispose에서 선택적 업데이트)
                              },
                            )
                            : EditorAppBar(
                              editorService: editorService,
                              stickerService: stickerService,
                              onSaveDraft: _saveDraft,
                              onLoadDraft: _showDraftList,
                              currentDraftId: currentDraftId,
                              videoUploadIndicatorNotifier:
                                  _videoUploadIndicatorNotifier,
                            ),
                  ),

                  // 툴바 위 패딩
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: MediaQuery.of(context).padding.top,
                    child: TopPadding(),
                  ),
                ],
              ),
            ),
          ],
        ),

        bottomNavigationBar: Consumer<StickerService>(
          builder: (context, stickerService, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: stickerService.isDraggingNotifier,
              builder: (context, isDragging, child) {
                // 스티커 드래그 중이면 툴바 숨김
                if (isDragging) {
                  return const SizedBox.shrink();
                }

                // 🎯 성능 최적화: AnimatedPadding으로 고정 duration 애니메이션
                // MediaQuery 변화가 20번 발생해도 Flutter는 1번만 애니메이션
                final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
                final bottomPadding =
                    keyboardHeight <= 30 ? 20.0 : keyboardHeight;

                final theme = Theme.of(context);

                return Container(
                  color: theme.colorScheme.background,
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 20),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(bottom: bottomPadding),
                    child: Consumer<NodeComponentService>(
                      builder: (context, nodeService, child) {
                        return nodeService.selectedNodeId != null
                            ? _buildSelectedToolbar()
                            : _buildDefaultToolbar();
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildDragOverlay() {
    final pos = dragService.dragPosition;
    final nodeId = dragService.draggingNodeId;
    if (pos == null || nodeId == null) return const SizedBox.shrink();

    // 이미지 행 분리 모드
    if (dragService.hasSplitImageInfo) {
      final splitInfo = dragService.getSplitImageInfo();
      final rowNode =
          document.getNodeById(splitInfo?['rowId']) as ImageRowNode?;
      final imageIndex = splitInfo?['imageIndex'] as int?;

      if (rowNode != null &&
          imageIndex != null &&
          imageIndex < rowNode.imageUrls.length) {
        return DragOverlayWidget(
          position: pos,
          document: document,
          splitImageUrl: rowNode.imageUrls[imageIndex],
        );
      }
    }

    // 일반 노드 드래그
    final node = document.getNodeById(nodeId);
    if (node == null) return const SizedBox.shrink();

    return DragOverlayWidget(
      node: node,
      position: pos,
      document: document,
      previewImageLocalPath:
          dragService.previewImageLocalPath, // 🎯 클립 썸네일 깜빡임 방지
      previewImageUrl:
          dragService.previewImageUrl, // 🚀 네트워크 URL (로컬-네트워크 혼용 구조)
    );
  }

  Widget _buildDefaultToolbar() {
    return DefaultToolbar(
      stylingService: textStylingService,
      editorService: editorService,
      scrollController: scrollController,
      onDismissKeyboard: () {
        _editorFocusNode.unfocus();
      },
      onShowDraftList: _showDraftList,
      videoUploadIndicatorNotifier: _videoUploadIndicatorNotifier,
    );
  }

  Widget _buildSelectedToolbar() {
    final selectedId = nodeComponentService.selectedNodeId;
    if (selectedId == null) return const SizedBox.shrink();
    final node = document.getNodeById(selectedId);
    // 링크/멘션/이미지 공통 삭제 전용 툴바
    return SelectedToolbar(
      node: node,
      selectedId: selectedId,
      onEdit:
          () => nodeComponentService.editImage(
            context: context,
            imageId: selectedId,
            node: node as ImageNode,
            editorService: editorService,
            document: document,
          ),
      onDelete: (node, selectedId) => document.deleteNode(selectedId),
      onChangeAlignment: (node, selectedId) {
        editorService.changeMediaAlignment(selectedId);
        nodeComponentService.clearSelection();
      },
    );
  }

  /// 수동 임시저장 (새 버전 생성)
  Future<bool> _saveDraft() async {
    try {
      // 🎯 임시저장 후 포커스 해제 (키보드가 올라오지 않도록)
      if (mounted) {
        _editorFocusNode.unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      }
      // 제목만 검증
      final hasTitle = editorService.hasNonEmptyTitle();

      if (!hasTitle) {
        if (mounted) {
          await DialogUtils.showInfoDialog(
            context,
            title: context.tr('enter_title_first'),
            message: context.tr('title_required_for_draft'),
          );
        }
        return false; // ✅ 실패 반환
      }

      // 🎯 업로드 중이면 차단
      if (editorService.hasUnuploadedImages()) {
        if (mounted) {
          ErrorHandler.showError(context, context.tr('please_wait_for_upload'));
        }
        return false;
      }

      // 🎯 제목 자동 추출
      final title = PostExporter.getTitleFromDocument(document);

      // 🎯 UUID 기반 draftId 사용 (제목 기반 제거)
      if (currentDraftId == null) {
        // 혹시 UUID가 없으면 생성 (안전장치)
        const uuid = Uuid();
        currentDraftId = 'draft_${uuid.v4()}';
        debugPrint('[PostwriteScreen] ⚠️ UUID가 없어서 생성: $currentDraftId');
      }

      // 현재 draft ID를 sessionKey로 영상 파일만 가져오기
      final sessionKey = currentDraftId!;

      final videoFilePath = nodeComponentService.getTempVideoFilePath(
        sessionKey,
      );
      final videoThumbnailPath = nodeComponentService.getTempVideoThumbnailPath(
        sessionKey,
      );

      // 🎯 썸네일은 항상 첫 번째 이미지를 자동으로 설정
      String thumbnailUrl = '';
      final firstImageUrl = editorService.findFirstImageUrl();
      if (firstImageUrl != null && firstImageUrl.isNotEmpty) {
        thumbnailUrl = firstImageUrl;
      }

      // 🎯 UUID 기반 임시저장 (제목은 자동 추출)
      currentDraftId = await draftService.saveDraft(
        editorService: editorService,
        stickerService: stickerService,
        title: title,
        summary: '', // 🎯 summary는 항상 빈 문자열 (자동 추출)
        thumbnailUrl: thumbnailUrl,
        videoFilePath: videoFilePath,
        videoThumbnailPath: videoThumbnailPath,
        visibility: 'public', // 기본값
        selectedGroupIds: [],
        existingDraftId: currentDraftId, // UUID 기반 ID 사용
      );

      // 저장 스냅샷 마크
      editorService.markSavedSnapshot();
      stickerService.saveInitialState();

      if (mounted) {
        ErrorHandler.showInfo(context, context.tr('draft_saved'));
      }

      return true; // ✅ 성공 반환
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, context.tr('draft_save_failed'));
      }
      return false; // ✅ 실패 반환
    }
  }

  /// 수정된 포스트 저장 (편집 모드 전용)
  Future<void> _saveEditedPost() async {
    debugPrint('[PostwriteScreen] ===== 수정 완료 버튼 클릭 =====');

    // 이미 저장 중이면 무시
    if (_isSaving) return;

    // 업로드 중이면 차단
    if (editorService.hasUnuploadedImages()) {
      await DialogUtils.showInfoDialog(
        context,
        title: context.tr('wait_for_media_upload'),
        message: context.tr('media_still_uploading'),
      );
      return;
    }

    // 1. 제목 검증
    final hasTitle = editorService.hasNonEmptyTitle();
    if (!hasTitle) {
      await DialogUtils.showInfoDialog(
        context,
        title: context.tr('enter_title_first'),
        message: context.tr('title_required_for_edit'),
      );
      return;
    }

    // 2. 변경사항 확인
    final originalForComparison =
        _serverAppliedTitle != null
            ? _updateOriginalWithServerTitle(widget.exportedDataForEdit!)
            : widget.exportedDataForEdit!;

    final hasChanges = ContentChangeDetector.hasContentChanged(
      originalExported: originalForComparison,
      editorService: editorService,
      stickerService: stickerService,
    );

    if (!hasChanges) {
      // 변경사항이 없으면 조용히 나가기
      Navigator.of(context).pop();
      return;
    }

    // 3. 저장 중 상태로 변경
    setState(() => _isSaving = true);

    try {
      // 4. 현재 문서 상태를 export
      final exported = PostExporter.exportToMap(
        editorService: editorService,
        stickerService: stickerService,
        forPublishing: true, // 🚀 임시저장도 네트워크 이미지로 변환 (로드 속도 향상)
        allowPartialUpload: true, // 🚀 임시저장 시 업로드 미완료 이미지 허용 (로컬 경로로 저장)
      );

      // 5. content 추출
      final content = exported['content'] as Map<String, dynamic>?;
      if (content == null) {
        throw Exception('본문 데이터를 추출할 수 없습니다.');
      }

      // 6. 제목 추출 (항상 현재 document의 제목 사용)
      final title = PostExporter.getTitleFromDocument(document);

      // 7. 사용된 이미지/비디오 URL 수집
      final usedImageUrls = PostExporter.collectUsedMediaUrls(exported);

      debugPrint('[PostwriteScreen] Export 완료');
      debugPrint('  - 제목: $title');
      debugPrint('  - 사용된 미디어: ${usedImageUrls.length}개');

      // 8. 제목 변경 체크 및 서버 저장 (스마트 동기화)
      if (title != _lastTitleText && _lastTitleText != null) {
        debugPrint(
          '[PostwriteScreen] 🎯 제목 변경 감지, 서버 저장: "$_lastTitleText" → "$title"',
        );
        try {
          await BlogService().updatePostThumbnail(
            postId: int.parse(widget.postId!),
            title: title,
          );
          _lastTitleText = title;
          _serverAppliedTitle = title;
          _shouldRefreshMyFeed = true; // 🎯 프로필 피드 스마트 동기화 플래그 설정
          debugPrint('[PostwriteScreen] ✅ 제목 서버 저장 완료: "$title"');
        } catch (e) {
          debugPrint('[PostwriteScreen] ❌ 제목 서버 저장 실패: $e');
          // 제목 저장 실패해도 본문 저장은 계속 진행
        }
      }

      // 9. 서버에 본문 업데이트 요청
      await BlogService().updatePostContent(
        postId: int.parse(widget.postId!),
        content: content,
        title: title,
        usedImageUrls: usedImageUrls,
      );

      debugPrint('[PostwriteScreen] ✅ 본문 수정 완료');

      // 10. 안정화 시간 (0.5초) 후 완료
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() => _isSaving = false);
        _shouldRefreshMyFeed = true;

        // 🎯 스티커 및 드로잉 데이터 정리
        try {
          stickerService.select(null);
          stickerService.removeAll();
          debugPrint('[PostwriteScreen] 드로잉 캔버스 정리 완료');
        } catch (_) {}

        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[PostwriteScreen] ❌ 본문 수정 실패: $e');

      // 저장 중 상태 해제
      if (mounted) {
        setState(() => _isSaving = false);
        ErrorHandler.handleError(context, e);
      }
    } finally {}
  }

  /// 임시저장 목록 보기
  Future<void> _showDraftList() async {
    try {
      if (!mounted) return;

      // 🎯 툴바의 오른쪽 끝 화살표를 눌렀을 때와 완전히 같은 방식으로 키보드 닫기
      _editorFocusNode.unfocus();

      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          pageBuilder:
              (_, __, ___) => DraftListOverlay(
                currentDraftId: currentDraftId,
                onLoadDraft: (draftId) async {
                  try {
                    nodeComponentService.clearHighlightedSelectionSilently();
                    nodeComponentService.clearSelectionSilently();
                    composer.clearSelection();

                    // 🎯 포커스 해제
                    _editorFocusNode.unfocus();
                    FocusManager.instance.primaryFocus?.unfocus();
                  } catch (_) {}

                  final success = await draftService.loadDraft(
                    draftId: draftId,
                    editorService: editorService,
                    stickerService: stickerService,
                    nodeComponentService: nodeComponentService,
                    dragService: dragService,
                    context: context, // 🚀 이미지 프리로드용 컨텍스트
                  );

                  if (success && mounted) {
                    currentDraftId = draftId;

                    // 🎯 불러온 상태를 저장 스냅샷으로 간주
                    editorService.markSavedSnapshot();
                    stickerService.saveInitialState();

                    // 🎯 포커스 확실히 해제
                    _editorFocusNode.unfocus();
                    FocusManager.instance.primaryFocus?.unfocus();

                    // 🎯 레이아웃 재동기화를 위해 다음 프레임에 캐시 무효화
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        // 🎯 캐시 무효화 및 셀렉션 재확인
                        dragService.invalidateNodeRectCache();
                        nodeComponentService.clearSelection();
                        nodeComponentService.clearHighlightedSelection();
                        composer.clearSelection();

                        // 🎯 포커스 재확인 및 플래그 해제
                        _editorFocusNode.unfocus();
                        FocusManager.instance.primaryFocus?.unfocus();
                      }
                    });
                  }

                  if (!success && mounted) {
                    ErrorHandler.showError(
                      context,
                      context.tr('draft_load_failed'),
                    );
                  }
                },
              ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          '${context.tr('draft_list_failed')}: $e',
        );
      }
    }
  }
}
