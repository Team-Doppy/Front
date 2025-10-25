import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:doppy/editor/component/single_image_component.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart';
import 'package:doppy/editor/component/row_image_component.dart'
    show ImageRowNode, RowImageComponentBuilder;
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/components/comment_bottom_sheet.dart';
import 'package:doppy/pages/components/comment_preview_section.dart';

// 읽기 전용에서는 에디터 전용 컴포넌트를 사용하지 않음
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/drag_service.dart';

/// 읽기 전용: 작성 화면에서 Export된 Map을 받아 그대로 복원하여 보여준다.
class PostReaderScreen extends StatefulWidget {
  const PostReaderScreen({super.key, required this.exported, this.heroTag});
  final Map<String, dynamic> exported;
  final String? heroTag; // 홈 썸네일과 자연스러운 연결(Hero)

  @override
  State<PostReaderScreen> createState() => _PostReaderScreenState();
}

class _PostReaderScreenState extends State<PostReaderScreen>
    with TickerProviderStateMixin {
  late MutableDocument _document;
  late final MutableDocumentComposer _composer;
  late Editor _editor;
  late EditorService _editorService;
  late DragService _dragService;
  late final FocusNode _readOnlyFocus;
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _layoutKey = GlobalKey();
  static final GlobalKey _stackKey = GlobalKey();
  final BlogService _blogService = BlogService();
  Future<Map<String, dynamic>>? _contentFuture;
  Map<String, dynamic>? _currentExportedData; // 최신 컨텐츠를 저장
  bool _showLoadingLogo = false; // 로딩 로고 표시 여부

  // 스크롤 애니메이션을 위한 변수들
  static const double _appBarHeight = 52.0; // AppBar 높이
  double _lastScrollOffset = 0.0;
  double _pullAccum = 0.0; // 상단에서 아래로 당겨 닫기 누적 거리

  // 앱바 표시/숨김을 위한 변수들
  bool _showAppBar = true; // 상단 이미지 제거 → 기본 표시

  // 댓글 진입 시 순차 등장 애니메이션
  late final AnimationController _commentsAnimCtrl;
  bool _commentsAnimStarted = false;

  // 댓글 오버레이 상태/애니메이션
  bool _showCommentsOverlay = false;
  late final AnimationController _commentOverlayCtrl;
  late final Animation<double> _commentFade;

  // 좋아요/댓글 데이터
  final CommentService _commentService = CommentService();
  final LikeService _likeService = LikeService();

  void _toggleLike() async {
    final postId = widget.exported['id']?.toString();
    if (postId == null || postId.isEmpty) {
      print('[PostReaderScreen] 유효하지 않은 포스트 ID: $postId');
      return;
    }

    try {
      await _likeService.togglePostLike(postId);
      // setState() 제거 - LikeService 리스너가 자동으로 UI 업데이트
    } catch (e) {
      print('[PostReaderScreen] 좋아요 토글 오류: $e');
      // 오류 발생 시 사용자에게 알림
      if (mounted) {
        ErrorHandler.showError(context, '좋아요 처리 중 오류가 발생했습니다');
      }
    }
  }

  void _deletePost() async {
    final postId = widget.exported['id']?.toString();
    if (postId == null || postId.isEmpty) {
      print('[PostReaderScreen] 유효하지 않은 포스트 ID: $postId');
      return;
    }

    // 삭제 확인 다이얼로그
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('게시물 삭제'),
          content: const Text(
            '정말로 이 게시물을 삭제하시겠습니까?\n30일 이후 자동 영구 삭제됩니다.\n삭제된 게시물의 조회수, 댓글, 좋아요 등의 데이터는 복구할 수 없습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      await _blogService.deletePost(postId);

      if (mounted) {
        ErrorHandler.showInfo(context, '게시물이 삭제되었습니다');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, '게시물 삭제 중 오류가 발생했습니다');
      }
    }
  }

  void _showCommentBottomSheet() {
    // 오버레이로 표시
    final id = widget.exported['id']?.toString() ?? '';
    _commentService.setPostId(id);
    _commentService.connectWebSocketForCurrentPost();
    setState(() {
      _showCommentsOverlay = true;
    });
    _commentOverlayCtrl.forward(from: 0.0);
  }

  void _closeCommentsOverlay() {
    _commentOverlayCtrl.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() {
        _showCommentsOverlay = false;
      });
      _commentService.disconnectWebSocket();
    });
  }

  void _onCommentServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onLikeServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // 본문 로드 + 상위 6개 이미지 미리 디코딩
  Future<Map<String, dynamic>> _loadContentWithImages(String postId) async {
    final content = await _blogService.getPostContent(postId);

    // 이미지 URL 추출
    final List<String> imageUrls = [];
    final nodes = (content['nodes'] as List?) ?? [];

    for (final raw in nodes) {
      if (imageUrls.length >= 6) break;

      final m = (raw as Map).cast<String, dynamic>();
      final type = (m['type'] ?? '').toString();

      if (type == 'image') {
        final url = (m['url'] ?? '').toString();
        if (url.isNotEmpty) imageUrls.add(url);
      } else if (type == 'imageRow') {
        final urls =
            ((m['urls'] as List?) ?? const [])
                .map((e) => e.toString())
                .where((u) => u.isNotEmpty)
                .toList();
        imageUrls.addAll(urls);
      }
    }

    // 상위 6개 이미지만 미리 캐싱
    final imagesToPreload = imageUrls.take(6).toList();
    if (imagesToPreload.isNotEmpty && mounted) {
      print('[PostReader] 이미지 ${imagesToPreload.length}개 미리 로드 시작');
      await Future.wait(
        imagesToPreload.map((url) {
          return precacheImage(
            NetworkImage(url),
            context,
            onError: (e, stack) {
              print('[PostReader] 이미지 프리캐싱 실패: $url - $e');
            },
          );
        }),
      );
      print('[PostReader] 이미지 프리캐싱 완료');
    }

    return content;
  }

  @override
  void initState() {
    super.initState();
    _document = _rebuildDocument(widget.exported);
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _composer,
    );
    _editorService = EditorService(editor: _editor, document: _document);
    _dragService = DragService(editorService: _editorService);
    _readOnlyFocus = FocusNode(canRequestFocus: false);
    _scrollCtrl.addListener(_onScroll);

    _commentsAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addListener(() {
      if (mounted) setState(() {});
    });

    _commentOverlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _commentFade = CurvedAnimation(
      parent: _commentOverlayCtrl,
      curve: Curves.easeOutCubic,
    );

    // 포스트 ID 설정 및 서비스 초기화
    print('[PostReaderScreen] exported 데이터: ${widget.exported}');
    final postId = widget.exported['id']?.toString();
    if (postId != null && postId.isNotEmpty) {
      print('[PostReaderScreen] 포스트 ID: $postId');
      _commentService.setPostId(postId);

      // 초기 좋아요 상태와 수 설정
      final initialLikeCount = widget.exported['likeCount'] ?? 0;
      final initialIsLiked = widget.exported['isLiked'] == true;
      _likeService.setInitialLikeData(postId, initialIsLiked, initialLikeCount);

      print(
        '[PostReaderScreen] 초기 좋아요 상태: $initialIsLiked, 카운트: $initialLikeCount',
      );
      // 본문 로드 + 상위 6개 이미지 미리 디코딩
      _contentFuture = _loadContentWithImages(postId);

      // 0.5초 후 로딩 로고 표시
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          setState(() {
            _showLoadingLogo = true;
          });
        }
      });
    } else {
      print('[PostReaderScreen] 유효하지 않은 포스트 ID: $postId');
      print('[PostReaderScreen] exported 키들: ${widget.exported.keys.toList()}');
    }

    // 서비스 변경사항 감지
    _commentService.addListener(_onCommentServiceChanged);
    _likeService.addListener(_onLikeServiceChanged);

    try {
      _composer.clearSelection();
    } catch (_) {}
  }

  @override
  void dispose() {
    _commentService.removeListener(_onCommentServiceChanged);
    _likeService.removeListener(_onLikeServiceChanged);

    // WebSocket 연결 해제
    _commentService.disconnectWebSocket();

    _readOnlyFocus.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _commentsAnimCtrl.dispose();
    _commentOverlayCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final double nextOffset = _scrollCtrl.offset;
    final double delta = nextOffset - _lastScrollOffset;
    const double threshold = 4.0; // 미세 스크롤 무시

    bool nextShow = _showAppBar;
    if (delta < -threshold) {
      // 위로 스크롤 → 앱바 표시
      nextShow = true;
    } else if (delta > threshold) {
      // 아래로 스크롤 → 앱바 숨김
      nextShow = false;
    }
    if (nextShow != _showAppBar) {
      setState(() {
        _showAppBar = nextShow;
      });
    }
    _lastScrollOffset = nextOffset;

    // 댓글 섹션이 화면 하단 근처에 들어오기 시작하면 순차 애니메이션 시작
    if (!_commentsAnimStarted && _scrollCtrl.hasClients) {
      final pos = _scrollCtrl.position;
      if (pos.extentAfter <= 360.0) {
        _commentsAnimStarted = true;
        _commentsAnimCtrl.forward(from: 0.0);
      }
    }
  }

  // 상단 이미지 제거됨: 배경 이미지 빌더 삭제

  @override
  Widget build(BuildContext context) {
    final stickers = (widget.exported['stickers'] as List?) ?? const [];

    final currentUser = context.read<UserProvider>().currentUser;
    final String postAuthor = (widget.exported['author'] ?? '').toString();
    final bool isMyPost =
        currentUser != null && currentUser.username == postAuthor;

    // 권한 디버깅 로그
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔐 [PostReader 권한 체크]');
    print('현재 사용자: ${currentUser?.username ?? "null"}');
    print('포스트 작성자: $postAuthor');
    print('내 글인가? $isMyPost');
    print('exported 키: ${widget.exported.keys.toList()}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    return WillPopScope(
      onWillPop: () async {
        if (_showCommentsOverlay) {
          _closeCommentsOverlay();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        body: FutureBuilder<Map<String, dynamic>>(
          future: _contentFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(
                child: AnimatedOpacity(
                  opacity: _showLoadingLogo ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeIn,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "d",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        "ppy",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (snap.hasError) {
              return Scaffold(
                backgroundColor: Theme.of(context).colorScheme.background,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          '본문을 불러오지 못했어요',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            if (snap.hasData && (snap.data?.isNotEmpty ?? false)) {
              final merged = Map<String, dynamic>.from(widget.exported);
              merged['content'] = snap.data!;

              // 최신 데이터 저장 (수정하기에서 사용)
              _currentExportedData = merged;

              // 최신 본문으로 문서 재구성
              _document = _rebuildDocument(merged);
              _editor = createDefaultDocumentEditor(
                document: _document,
                composer: _composer,
              );
              _editorService = EditorService(
                editor: _editor,
                document: _document,
              );
              _dragService = DragService(editorService: _editorService);
            }

            return Stack(
              children: [
                // 전체 스크롤
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      // 상단에서 아래로 당길 때 누적
                      if (n is OverscrollNotification &&
                          n.overscroll < 0 &&
                          _scrollCtrl.hasClients &&
                          _scrollCtrl.offset <= 0.0) {
                        _pullAccum += (-n.overscroll);
                      }
                      // 드래그 종료 시 닫기 판단
                      if (n is ScrollEndNotification) {
                        if (_pullAccum >= 80.0) {
                          Navigator.of(context).maybePop();
                        }
                        _pullAccum = 0.0;
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      controller: _scrollCtrl,
                      physics: const ClampingScrollPhysics(),
                      slivers: [
                        SliverSafeArea(
                          top: true,
                          bottom: false,
                          sliver: SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                40,
                                20,
                                30,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: 300),
                                  Text(
                                    widget.exported['title'] ?? '포스트',
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.surfaceVariant,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant
                                                .withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: CommonProfileAvatar(
                                          username: postAuthor,
                                          imageUrl:
                                              widget
                                                  .exported['authorProfileImageUrl'] ??
                                              '',
                                          size: 30,
                                          borderWidth: 1,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          (widget.exported['author'] ?? '')
                                              .toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.8),
                                            fontSize: 18,
                                            fontWeight: FontWeight.w300,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // SuperEditor 슬리버
                        SuperEditor(
                          editor: _editor,
                          stylesheet: buildCustomStylesheet(context),
                          selectionStyle: SelectionStyles(
                            selectionColor: Colors.transparent,
                            highlightEmptyTextBlocks: false,
                          ),
                          componentBuilders: [
                            SingleImageComponentBuilder(
                              dragService: _dragService,
                            ),
                            RowImageComponentBuilder(dragService: _dragService),
                            LinkComponentBuilder(),
                            MentionComponentBuilder(dragService: _dragService),
                            ...defaultComponentBuilders,
                          ],
                          documentLayoutKey: _layoutKey,
                          focusNode: _readOnlyFocus,
                          gestureMode: DocumentGestureMode.mouse,
                        ),
                        SliverToBoxAdapter(child: SizedBox(height: 100)),

                        // 댓글 미리보기 (추출된 위젯)
                        SliverToBoxAdapter(
                          child: CommentPreviewSection(
                            commentService: _commentService,
                            likeService: _likeService,
                            postId: widget.exported['id']?.toString() ?? '',
                            onToggleLike: _toggleLike,
                            onShowComments: _showCommentBottomSheet,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 스티커 오버레이
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: _ReadOnlyStickers(
                      stickers: stickers,
                      layoutKey: _layoutKey,
                      stackKey: _stackKey,
                      scrollController: _scrollCtrl,
                    ),
                  ),
                ),

                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        height: 35,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.background.withOpacity(0.9),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 동적 AppBar (완전 숨김: 음수 높이만큼 이동 + 터치 차단)
                Builder(
                  builder: (context) {
                    final double barHeight =
                        _appBarHeight + MediaQuery.of(context).padding.top;
                    return AnimatedPositioned(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      top: _showAppBar ? 0 : -barHeight,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        ignoring: !_showAppBar,
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              height: barHeight,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.background.withOpacity(0.8),
                              ),

                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: MediaQuery.of(context).padding.top,

                                  bottom: 5.0,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(width: 15),
                                    GestureDetector(
                                      onTap: () => Navigator.of(context).pop(),
                                      child: Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.7),
                                        size: 22,
                                      ),
                                    ),

                                    Spacer(),
                                    if (isMyPost) ...[
                                      GestureDetector(
                                        onTap: () {
                                          final dataToEdit =
                                              _currentExportedData ??
                                              widget.exported;
                                          if (dataToEdit['id'] != null) {
                                            print(
                                              '[PostReader] 수정 모드로 진입: ${dataToEdit.keys.toList()}',
                                            );
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder:
                                                    (_) => PostwriteScreen(
                                                      isEditingMode: true,
                                                      exportedDataForEdit:
                                                          dataToEdit,
                                                    ),
                                              ),
                                            );
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            '수정',
                                            style: TextStyle(
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      GestureDetector(
                                        onTap: _deletePost,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          child: Icon(
                                            Icons.delete_outline_rounded,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.7),
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 15),
                                    ] else ...[
                                      GestureDetector(
                                        onTap: _showCommentBottomSheet,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.chat_bubble_outline_rounded,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.7),
                                              size: 24,
                                            ),

                                            SizedBox(width: 15),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // 댓글 Glass 카드 오버레이
                if (_showCommentsOverlay)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _commentFade,
                      builder: (context, _) {
                        return CommentBottomSheet(
                          title: widget.exported['title'] ?? '',
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // 프리캐싱 제거

  MutableDocument _rebuildDocument(Map<String, dynamic> data) {
    dynamic content = data['content'];
    if (content is String) {
      try {
        content = json.decode(content);
      } catch (_) {
        content = const {'nodes': []};
      }
    }
    if (content is! Map) {
      content = const {'nodes': []};
    }
    final nodes = (content['nodes'] as List?) ?? const [];
    final rebuilt = <DocumentNode>[];
    for (final raw in nodes) {
      final m = (raw as Map).cast<String, dynamic>();
      final id = (m['id'] ?? '').toString();
      final type = (m['type'] ?? '').toString();
      switch (type) {
        case 'paragraph':
          final text = (m['text'] ?? '').toString();
          final align = (m['align'] ?? 'center').toString();
          final isTitle = m['isTitle'] == true;
          // 제목 문단은 화면 상단 이미지 오버레이로 별도 표시되므로 본문에서는 제외
          if (isTitle) break;
          final spans = (m['spans'] as List?) ?? const [];
          final attributed = _buildAttributedText(text, spans);
          final meta = <String, dynamic>{'textAlign': align};
          rebuilt.add(ParagraphNode(id: id, text: attributed, metadata: meta));
          break;
        case 'image':
          rebuilt.add(
            ImageNode(
              id: id,
              imageUrl: (m['url'] ?? '').toString(),
              altText: (m['altText'] ?? '').toString(),
            ),
          );
          break;
        case 'imageRow':
          rebuilt.add(
            ImageRowNode(
              id: id,
              imageUrls:
                  ((m['urls'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList(),
              spacing: (m['spacing'] as num?)?.toDouble() ?? 4.0,
            ),
          );
          break;
        case 'link':
          rebuilt.add(
            LinkNode(
              id: id,
              url: (m['url'] ?? '').toString(),
              title: (m['title'] ?? '').toString(),
              description: (m['description'] ?? '').toString(),
              thumbnailUrl: (m['thumbnailUrl'] ?? '').toString(),
            ),
          );
          break;

        case 'mention':
          rebuilt.add(
            MentionNode(
              id: id,
              usernames:
                  ((m['usernames'] as List?) ?? const [])
                      .map((e) => e.toString())
                      .toList(),
            ),
          );
          break;
        default:
          // 알 수 없는 노드는 문단으로 폴백
          rebuilt.add(ParagraphNode(id: id, text: AttributedText('[${type}]')));
      }
    }
    return MutableDocument(nodes: rebuilt);
  }

  AttributedText _buildAttributedText(String text, List spans) {
    final attributed = AttributedText(text);
    for (final s in spans) {
      final m = (s as Map).cast<String, dynamic>();
      final start = (m['start'] as num?)?.toInt() ?? 0;
      final end = (m['end'] as num?)?.toInt() ?? start;
      final ann = (m['attrs'] as Map?)?.cast<String, dynamic>() ?? {};
      final atts = <Attribution>{};
      if (ann['bold'] == true) atts.add(boldAttribution);
      if (ann['italic'] == true) atts.add(italicsAttribution);
      if (ann['underline'] == true) atts.add(underlineAttribution);
      if (ann['strikethrough'] == true) atts.add(strikethroughAttribution);
      final fs = (ann['font_size'] as num?)?.toDouble();
      if (fs != null) atts.add(FontSizeAttribution(fs));
      final colorHex = ann['color'] as String?;
      if (colorHex != null && colorHex.isNotEmpty) {
        atts.add(ColorAttribution(_parseHexColor(colorHex)));
      }
      // 🎨 형광펜 속성 디코딩
      final highlightHex = ann['highlight'] as String?;
      if (highlightHex != null && highlightHex.isNotEmpty) {
        print('DEBUG: 형광펜 디코딩 - HEX: $highlightHex');
        final highlightColor = _parseHexColor(highlightHex);
        print('DEBUG: 형광펜 디코딩 - 색상: $highlightColor');
        atts.add(HighlightAttribution(highlightColor));
      }
      // 🎨 폰트 패밀리 속성 디코딩
      final fontFamily = ann['fontFamily'] as String?;
      if (fontFamily != null && fontFamily.isNotEmpty) {
        atts.add(FontFamilyAttribution(fontFamily));
      }
      for (final a in atts) {
        attributed.addAttribution(a, SpanRange(start, end - 1));
      }
    }
    return attributed;
  }

  ui.Color _parseHexColor(String hex) {
    var v = hex.replaceAll('#', '');
    if (v.length == 6) v = 'FF$v';
    return ui.Color(int.parse(v, radix: 16));
  }
}

class _ReadOnlyStickers extends StatelessWidget {
  const _ReadOnlyStickers({
    required this.stickers,
    required this.layoutKey,
    required this.stackKey,
    required this.scrollController,
  });
  final List stickers;
  final GlobalKey layoutKey;
  final GlobalKey stackKey;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final children = <Widget>[];
        final double scrollY =
            scrollController.hasClients ? scrollController.offset : 0.0;
        for (final s in stickers) {
          final m = (s as Map).cast<String, dynamic>();
          final type = (m['type'] ?? '').toString();
          final z = (m['zIndex'] as num?)?.toInt() ?? 0;
          final rot = (m['rotation'] as num?)?.toDouble() ?? 0.0;
          final scale = (m['scale'] as num?)?.toDouble() ?? 1.0;
          final anchor = (m['anchor'] as Map?)?.cast<String, dynamic>();
          late final Offset absPos;
          late final bool needsScrollCompensation;
          if (anchor != null) {
            absPos = _resolveAnchor(anchor);
            // anchor는 DocumentLayout 기준으로 이미 스크롤을 포함한 스택 로컬 좌표이므로 보정 불필요
            needsScrollCompensation = false;
          } else {
            final pf =
                (m['positionFallback'] as Map?)?.cast<String, dynamic>() ?? {};
            absPos = Offset(
              (pf['xPx'] as num?)?.toDouble() ?? 0.0,
              (pf['yPx'] as num?)?.toDouble() ?? 0.0,
            );
            // 절대좌표 fallback은 문서 좌표(스크롤 포함)로 저장되었으므로 화면 배치 시 스크롤 보정 필요
            needsScrollCompensation = true;
          }

          Widget body;
          if (type == 'text') {
            final content =
                (m['content'] as Map?)?.cast<String, dynamic>() ?? {};
            final text = (content['text'] ?? '').toString();
            final style =
                (content['style'] as Map?)?.cast<String, dynamic>() ?? {};
            body = Text(
              text,
              style: TextStyle(
                color: _toColor(style['color']) ?? Colors.white,
                fontSize: (style['fontSize'] as num?)?.toDouble() ?? 32,
                fontWeight:
                    (style['bold'] == true) ? FontWeight.w800 : FontWeight.w500,
                fontStyle:
                    (style['italic'] == true)
                        ? FontStyle.italic
                        : FontStyle.normal,
                decoration:
                    (style['underline'] == true)
                        ? TextDecoration.underline
                        : TextDecoration.none,
                letterSpacing:
                    (style['letterSpacing'] as num?)?.toDouble() ?? 0,
              ),
            );
          } else if (type == 'emoji') {
            final content = (m['content'] ?? '').toString();
            body = Text(content, style: const TextStyle(fontSize: 40));
          } else if (type == 'image') {
            final content =
                (m['content'] as Map?)?.cast<String, dynamic>() ?? {};
            final dynamic raw = content['bytes'];
            if (raw != null) {
              try {
                final bytes =
                    raw is String ? base64Decode(raw) : raw as Uint8List;
                body = ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 200,
                      maxHeight: 200,
                    ),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                );
              } catch (_) {
                body = Container(
                  width: 140,
                  height: 140,
                  color: Colors.grey[700],
                );
              }
            } else if ((content['url'] ?? '').toString().isNotEmpty) {
              final url = (content['url'] ?? '').toString();
              body = ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 200,
                    maxHeight: 200,
                  ),
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    cacheWidth: 300,
                    cacheHeight: 300,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              );
            } else {
              body = Container(
                width: 140,
                height: 140,
                color: Colors.grey[700],
              );
            }
          } else {
            body = const SizedBox.shrink();
          }

          final double topPos =
              needsScrollCompensation ? (absPos.dy - scrollY) : absPos.dy;

          final w = Positioned(
            left: absPos.dx,
            top: topPos,
            child: Transform(
              alignment: Alignment.center,
              transform:
                  Matrix4.identity()
                    ..rotateZ(rot)
                    ..scale(scale),
              child: body,
            ),
          );
          children.add(Stack(key: ValueKey('z_$z'), children: [w]));
        }
        return Stack(children: children);
      },
    );
  }

  Offset _resolveAnchor(Map<String, dynamic> anchor) {
    final nodeId = (anchor['nodeId'] ?? '').toString();
    final relX = (anchor['relX'] as num?)?.toDouble() ?? 0.5;
    final relY = (anchor['relY'] as num?)?.toDouble() ?? 0.0;

    final layout = layoutKey.currentState as DocumentLayout?;
    final stackBox = stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (layout == null || stackBox == null) return const Offset(0, 0);
    try {
      final rect = layout.getRectForSelection(
        DocumentPosition(
          nodeId: nodeId,
          nodePosition: const UpstreamDownstreamNodePosition.upstream(),
        ),
        DocumentPosition(
          nodeId: nodeId,
          nodePosition: const UpstreamDownstreamNodePosition.downstream(),
        ),
      );
      if (rect == null) return const Offset(0, 0);
      final topLeftInStack = stackBox.globalToLocal(rect.topLeft);
      final x = topLeftInStack.dx + relX * rect.width;
      final y = topLeftInStack.dy + relY * rect.height;
      return Offset(x, y);
    } catch (_) {
      return const Offset(0, 0);
    }
  }

  Color? _toColor(dynamic v) {
    if (v is String && v.startsWith('#')) {
      var hex = v.substring(1);
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    }
    return null;
  }
}
