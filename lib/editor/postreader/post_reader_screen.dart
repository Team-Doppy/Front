import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';
import '../../editor/component/clip_component.dart';
import '../../editor/component/divider_component.dart';
import '../../editor/component/link_component.dart';
import '../../editor/component/pageview_image_component.dart';
import '../../editor/component/row_image_component.dart';
import '../../editor/component/paragraph_component.dart';
import '../../editor/component/single_image_component.dart';
import '../../editor/data/draft.dart';
import '../../editor/service/document_restore_service.dart';
import '../../editor/service/drag_service.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/service/post_reader_scroll_preload_service.dart';
import '../../editor/style/style_sheet.dart';
import '../../editor/utils/dialog_util.dart';
import '../../editor/utils/edit_image_cache_manager.dart';
import '../../editor/utils/editor_localization.dart';
import '../../editor/utils/scrollbar_util.dart';
import '../../editor/postreader/post_reader_appbar.dart';

/// 읽기 전용: DraftData 기반으로 문서를 렌더링합니다.
/// 진입 시 [loadingBuilder]로 로딩 화면을 보여주고, 초기 프리로드 후 콘텐츠로 전환합니다.
/// 스크롤 시 [PostReaderScrollPreloadService]가 이어서 프리로드를 수행합니다.
class PostReaderScreen extends StatefulWidget {
  const PostReaderScreen({
    super.key,
    required this.draft,
    this.loadingBuilder,
    this.onEdit,
  });

  final DraftData draft;

  /// 진입 시 표시할 로딩 위젯. null이면 기본 로딩(원형 인디케이터) 사용.
  final Widget Function(BuildContext context)? loadingBuilder;

  /// 수정 탭 시 호출. 현재 [draft]를 넘겨 편집 화면(PostwriteScreen)으로 push하는 역할은 호출측에서 수행.
  final void Function(DraftData draft)? onEdit;

  @override
  State<PostReaderScreen> createState() => _PostReaderScreenState();
}

class _PostReaderScreenState extends State<PostReaderScreen> {
  // 문서 및 에디터
  late MutableDocument _document;
  late final MutableDocumentComposer _composer;
  late Editor _editor;
  late EditorService _editorService;
  late DragService _dragService;
  late NodeComponentService _nodeComponentService;
  late final FocusNode _readOnlyFocus;

  // UI 상태
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _layoutKey = GlobalKey();
  bool _showAppBar = true;
  double _currentScrollOffset = 0.0;
  int _bottomBarAnimationDuration = 300;
  bool _isInitialLoading = true;

  // 프리로드
  final PostReaderScrollPreloadService _scrollPreloadService =
      PostReaderScrollPreloadService();

  // 컴포넌트 빌더 캐싱
  List<ComponentBuilder>? _cachedComponentBuilders;
  double? _cachedScreenWidth;
  bool? _cachedIsDarkMode;

  @override
  void initState() {
    super.initState();
    _initializeDocument();
    _initializeServices();
    _scrollCtrl.addListener(_onScroll);
    _startInitialPreload();
  }

  /// 진입 시: 페이로드 없으면 로딩 스킵, 네트워크 이미지 전부 디스크 캐시면 스킵 후 백그라운드 프리로드, 아니면 로딩 잠깐 표시 후 프리로드
  void _startInitialPreload() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final initialUrls = _scrollPreloadService.getInitialBatchImageUrls(
        widget.draft,
      );

      // 네트워크 이미지 없음 → 로딩 스킵, 콘텐츠 바로 표시
      if (initialUrls.isEmpty) {
        if (mounted) setState(() => _isInitialLoading = false);
        return;
      }

      // 디스크 캐시 확인: 전부 캐시되어 있으면 로딩 스킵, 프리로드는 백그라운드로만 실행
      final cache = EditImageCacheManager.instance;
      bool allCached = true;
      for (final url in initialUrls) {
        final fileInfo = await cache.getFileFromCache(url);
        if (fileInfo == null) {
          allCached = false;
          break;
        }
      }

      if (allCached) {
        if (mounted) setState(() => _isInitialLoading = false);
        // 디스크 캐시만 있어도 메모리 워밍을 위해 백그라운드 프리로드 (로딩 UI 없음)
        _scrollPreloadService.preloadInitialBatch(
          draft: widget.draft,
          context: context,
          mounted: () => mounted,
        );
        return;
      }

      // 캐시 안 된 네트워크 이미지 있음 → 로딩 표시 후 프리로드 완료까지 대기
      await _scrollPreloadService.preloadInitialBatch(
        draft: widget.draft,
        context: context,
        mounted: () => mounted,
      );
      if (mounted) setState(() => _isInitialLoading = false);
    });
  }

  /// 문서 초기화
  void _initializeDocument() {
    final documentRestoreService = DocumentRestoreService();
    _document = documentRestoreService.restoreFromDraftData(widget.draft);
  }

  /// 서비스 초기화
  void _initializeServices() {
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _composer,
    );
    _editorService = EditorService(
      editor: _editor,
      document: _document,
      enableInitialStateSave: false,
    );
    _editorService.setDocumentLayoutKey(_layoutKey);
    _dragService = DragService(editorService: _editorService);
    _nodeComponentService = NodeComponentService();
    _readOnlyFocus = FocusNode(canRequestFocus: false);
  }

  /// 스크롤 리스너
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;

    final offset = _scrollCtrl.offset;
    final delta = offset - _currentScrollOffset;
    const threshold = 10.0;

    bool nextShowAppBar = _showAppBar;
    if (delta < -threshold) {
      nextShowAppBar = true;
    } else if (delta > threshold) {
      nextShowAppBar = false;
    }

    if (nextShowAppBar != _showAppBar || offset != _currentScrollOffset) {
      setState(() {
        _showAppBar = nextShowAppBar;
        _currentScrollOffset = offset;
        _bottomBarAnimationDuration = 300;
      });
    }

    // 프리로드 트리거
    if (delta > threshold && !_scrollPreloadService.isPreloading) {
      _scrollPreloadService.preloadNextBatch(
        draft: widget.draft,
        context: context,
        mounted: () => mounted,
      );
    }
  }

  /// 삭제 버튼 탭: 컨펌 다이얼로그 후 삭제 API 호출
  Future<void> _onDeleteTap() async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context,
      title: context.tr('editor_post_delete_confirm_title'),
      message: context.tr('editor_post_delete_confirm_message'),
      confirmText: context.tr('delete'),
      cancelText: context.tr('editor_cancel'),
      isDestructive: true,
    );
    if (!mounted || confirmed != true) return;

    // TODO: 삭제 API 호출 (예: widget.draft.id로 서버 삭제 후 아래 pop)
    // await someApi.deletePost(widget.draft.id);
    if (mounted) Navigator.of(context).pop();
  }

  /// 기본 로딩 위젯 (loadingBuilder 미지정 시 사용)
  Widget _defaultLoadingWidget(BuildContext context, ThemeData theme) {
    return Center(
      child: CircularProgressIndicator(color: theme.colorScheme.primary),
    );
  }

  /// 컴포넌트 빌더 생성
  List<ComponentBuilder> _buildComponentBuilders(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (_cachedComponentBuilders != null &&
        _cachedScreenWidth == screenWidth &&
        _cachedIsDarkMode == isDarkMode) {
      return _cachedComponentBuilders!;
    }

    final builders = [
      SingleImageComponentBuilder(
        screenWidth: screenWidth,
        dragService: _dragService,
        isEditing: false,
        isDarkMode: isDarkMode,
      ),
      RowImageComponentBuilder(
        screenWidth: screenWidth,
        dragService: _dragService,
        isEditing: false,
        isDarkMode: isDarkMode,
      ),
      PageViewImageComponentBuilder(
        screenWidth: screenWidth,
        dragService: _dragService,
        isEditing: false,
        isDarkMode: isDarkMode,
      ),
      LinkComponentBuilder(isEditing: false, isDarkMode: isDarkMode),
      DividerComponentBuilder(),
      ClipComponentBuilder(
        screenWidth: screenWidth,
        dragService: _dragService,
        isDarkMode: isDarkMode,
      ),
      CustomParagraphComponentBuilder(
        dragService: _dragService,
        editorService: _editorService,
        isEditing: false,
      ),
    ];

    _cachedComponentBuilders = builders;
    _cachedScreenWidth = screenWidth;
    _cachedIsDarkMode = isDarkMode;

    return builders;
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _readOnlyFocus.dispose();
    _editorService.dispose();
    _scrollPreloadService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    const toolbarHeight = 44.0;
    final barHeight = toolbarHeight + topPadding;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: ChangeNotifierProvider<NodeComponentService>.value(
        value: _nodeComponentService,
        child: Stack(
          children: [
            // 로딩 화면 (진입 시, 초기 프리로드 중)
            if (_isInitialLoading)
              Positioned.fill(
                child: widget.loadingBuilder != null
                    ? widget.loadingBuilder!(context)
                    : _defaultLoadingWidget(context, theme),
              ),

            // 메인 콘텐츠 (로딩 완료 후 표시)
            if (!_isInitialLoading)
              ScrollbarUtil.buildScrollbar(
                controller: _scrollCtrl,
                child: CustomScrollView(
                  controller: _scrollCtrl,
                  slivers: [
                    // 상단 여백
                    SliverToBoxAdapter(child: SizedBox(height: barHeight + 20)),

                    // 문서 (SuperEditor는 sliver이므로 SliverToBoxAdapter로 감싸면 안 됨)
                    Builder(
                      builder: (context) {
                        return SuperEditor(
                          editor: _editor,
                          stylesheet: buildCustomStylesheet(
                            context,
                            isReadOnly: true,
                          ),
                          selectionStyle: SelectionStyles(
                            selectionColor: Colors.transparent,
                            highlightEmptyTextBlocks: false,
                          ),
                          componentBuilders: _buildComponentBuilders(context),
                          documentLayoutKey: _layoutKey,
                          focusNode: _readOnlyFocus,
                          gestureMode: DocumentGestureMode.mouse,
                        );
                      },
                    ),

                    // 하단 여백
                    SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
              ),

            // 앱바
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: PostReaderAppBar(
                showAppBar: _showAppBar,
                title: widget.draft.title,
                scrollOffset: _currentScrollOffset,
                onBack: () => Navigator.of(context).pop(),
                onEdit: widget.onEdit != null ? () => widget.onEdit!(widget.draft) : null,
                editSvgPath: 'assets/icons/edit.svg',
                onDelete: _onDeleteTap,
                deleteSvgPath: 'assets/icons/delete.svg',

                animationDuration: _bottomBarAnimationDuration,
                backIcon: Icons.arrow_back_ios_new_rounded,
              ),
            ),

            // 바텀바
            /*
            PostReaderBottomBar(
              showBottomBar: _showAppBar,
              animationDuration: _bottomBarAnimationDuration,
              likeCount: 0,
              commentCount: 0,
              isLiked: false,
              visibility: widget.draft.visibility,
            ),*/
          ],
        ),
      ),
    );
  }
}
