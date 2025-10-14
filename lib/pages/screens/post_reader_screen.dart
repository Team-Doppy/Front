import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:doppy/editor/component/single_image_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart'; // HighlightAttribution import
import 'package:doppy/editor/component/row_image_component.dart'
    show ImageRowNode, RowImageComponentBuilder;
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/components/comment_bottom_sheet.dart';
import 'package:doppy/pages/components/comment_shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';

// 읽기 전용에서는 에디터 전용 컴포넌트를 사용하지 않음
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/location_component.dart';
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
    with SingleTickerProviderStateMixin {
  late final MutableDocument _document;
  late final MutableDocumentComposer _composer;
  late final Editor _editor;
  late final EditorService _editorService;
  late final DragService _dragService;
  late final FocusNode _readOnlyFocus;
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _layoutKey = GlobalKey();
  static final GlobalKey _stackKey = GlobalKey();

  // 스크롤 애니메이션을 위한 변수들
  static const double _appBarHeight = 38.0; // AppBar 높이
  double _scrollOffset = 0.0;
  // 상단 이미지
  double _imageH = 0.0; // 상단 이미지 높이(px)
  double _headerFadeEnd = 0.0; // 이미지가 완전 투명해지는 오프셋
  double _lastScrollOffset = 0.0;
  bool _didAutoSnapHeader = false;
  bool _isAutoAnimating = false;

  // 댓글 진입 시 순차 등장 애니메이션
  late final AnimationController _commentsAnimCtrl;
  bool _commentsAnimStarted = false;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('좋아요 처리 중 오류가 발생했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCommentBottomSheet() {
    // 댓글 창 열기 전에 WebSocket 연결 시도
    _commentService.setPostId(widget.exported['id']?.toString() ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CommentBottomSheet(),
    );
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

  String _formatRelativeTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return '방금';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}분 전';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}시간 전';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}일 전';
      } else {
        return '${(difference.inDays / 7).floor()}주 전';
      }
    } catch (e) {
      return '방금';
    }
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _imageH = MediaQuery.of(context).size.height * 0.60;
    _headerFadeEnd = _imageH * 0.60; // 페이드 완료 지점
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
    super.dispose();
  }

  void _onScroll() {
    final double nextOffset = _scrollCtrl.offset;

    // 타이밍 시어: 스크롤 위치 업데이트
    _commentService.updateScrollPosition(nextOffset);

    // 첫 하향 스크롤 감지 시 헤더가 투명해질 지점까지 자동 스크롤
    final double delta = nextOffset - _lastScrollOffset;
    if (delta > 0.5 &&
        !_didAutoSnapHeader &&
        !_isAutoAnimating &&
        nextOffset < _headerFadeEnd) {
      _isAutoAnimating = true;
      _scrollCtrl
          .animateTo(
            _headerFadeEnd,
            duration: const Duration(milliseconds: 800),
            curve: Curves.fastOutSlowIn,
          )
          .whenComplete(() {
            if (mounted) {
              setState(() {
                _didAutoSnapHeader = true;
                _isAutoAnimating = false;
              });
            } else {
              _didAutoSnapHeader = true;
              _isAutoAnimating = false;
            }
          });
    }

    // 상단으로 거의 복귀하면 스냅을 다시 허용
    if (nextOffset < 2.0 && _didAutoSnapHeader) {
      _didAutoSnapHeader = false;
    }

    setState(() {
      _scrollOffset = nextOffset;
    });
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

  ImageProvider _buildBackgroundImage() {
    final imageUrl =
        widget.exported['thumbnailImageUrl'] ?? 'assets/images/feed2.png';

    if (imageUrl.startsWith('http')) {
      return NetworkImage(imageUrl);
    } else {
      return AssetImage(imageUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stickers = (widget.exported['stickers'] as List?) ?? const [];

    // AppBar가 나타나야 하는 시점 계산 (상단 이미지가 상당히 사라졌을 때)
    final shouldShowAppBar = _scrollOffset >= _imageH - _appBarHeight + 0;
    final appBarOpacity = shouldShowAppBar ? 1.0 : 0.0;
    final currentUser = context.read<UserProvider>().currentUser;
    final String postAuthor = (widget.exported['author'] ?? '').toString();
    final bool isMyPost =
        currentUser != null && currentUser.username == postAuthor;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          // 전체 스크롤: 상단 이미지가 스크롤로 사라지고, 아래에 본문이 이어짐
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            child: CustomScrollView(
              controller: _scrollCtrl,
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverPersistentHeader(
                  pinned: false,
                  floating: false,
                  delegate: _ImageHeaderDelegate(
                    image: _buildBackgroundImage(),
                    maxHeight: _imageH,
                    heroTag: widget.heroTag,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 40, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.exported['title'] ?? '포스트',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
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
                              child:
                                  (widget.exported['authorProfileImageUrl']
                                              ?.toString()
                                              .isNotEmpty ??
                                          false)
                                      ? CachedNetworkImage(
                                        imageUrl:
                                            widget
                                                .exported['authorProfileImageUrl']
                                                .toString(),
                                        fit: BoxFit.cover,
                                        placeholder:
                                            (context, url) => const SizedBox(
                                              width: 30,
                                              height: 30,
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ),
                                        errorWidget:
                                            (context, url, error) => Icon(
                                              Icons.person,
                                              color:
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                            ),
                                        memCacheWidth: 60,
                                        maxWidthDiskCache: 60,
                                        fadeInDuration: Duration.zero,
                                        fadeOutDuration: Duration.zero,
                                        cacheKey:
                                            'post_author_${widget.exported['authorProfileImageUrl']}',
                                      )
                                      : Icon(
                                        Icons.person,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                (widget.exported['author'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.8),
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
                // SuperEditor 슬리버
                SuperEditor(
                  editor: _editor,
                  stylesheet: buildCustomStylesheet(context),
                  selectionStyle: SelectionStyles(
                    selectionColor: Colors.transparent,
                    highlightEmptyTextBlocks: false,
                  ),
                  componentBuilders: [
                    SingleImageComponentBuilder(dragService: _dragService),
                    RowImageComponentBuilder(dragService: _dragService),
                    LinkComponentBuilder(),
                    LocationComponentBuilder(dragService: _dragService),
                    MentionComponentBuilder(dragService: _dragService),
                    ...defaultComponentBuilders,
                  ],
                  documentLayoutKey: _layoutKey,
                  focusNode: _readOnlyFocus,
                  gestureMode: DocumentGestureMode.mouse,
                ),
                SliverToBoxAdapter(child: SizedBox(height: 100)),

                // 댓글 미리보기 (최근 5개)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                // 좋아요 버튼
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _toggleLike,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          _likeService.isPostLiked(
                                                widget.exported['id']
                                                        ?.toString() ??
                                                    '',
                                              )
                                              ? Colors.redAccent.withOpacity(
                                                0.1,
                                              )
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .surfaceVariant
                                                  .withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color:
                                            _likeService.isPostLiked(
                                                  widget.exported['id']
                                                          ?.toString() ??
                                                      '',
                                                )
                                                ? Colors.redAccent.withOpacity(
                                                  0.3,
                                                )
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .outline
                                                    .withOpacity(0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          child: Icon(
                                            _likeService.isPostLiked(
                                                  widget.exported['id']
                                                          ?.toString() ??
                                                      '',
                                                )
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                            key: ValueKey(
                                              _likeService.isPostLiked(
                                                widget.exported['id']
                                                        ?.toString() ??
                                                    '',
                                              ),
                                            ),
                                            color:
                                                _likeService.isPostLiked(
                                                      widget.exported['id']
                                                              ?.toString() ??
                                                          '',
                                                    )
                                                    ? Colors.redAccent
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurface
                                                        .withOpacity(0.7),
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${_likeService.getPostLikeCount(widget.exported['id']?.toString() ?? '')}',
                                          style: TextStyle(
                                            color:
                                                _likeService.isPostLiked(
                                                      widget.exported['id']
                                                              ?.toString() ??
                                                          '',
                                                    )
                                                    ? Colors.redAccent
                                                    : Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // 댓글 정보
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceVariant
                                        .withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline.withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _showCommentBottomSheet,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.chat_bubble_outline,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.7),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${_commentService.getAllComments().length}',
                                          style: TextStyle(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            _commentService.isLoading &&
                                    _commentService.getAllComments().isEmpty
                                ? const CommentShimmer(
                                  itemCount: 3,
                                  isPreview: true,
                                )
                                : Column(
                                  children: () {
                                    final comments =
                                        _commentService.getRecentComments();
                                    comments.sort(
                                      (a, b) =>
                                          a.createdAt.compareTo(b.createdAt),
                                    );
                                    return comments.take(5).map((comment) {
                                      final currentUser =
                                          context
                                              .read<UserProvider>()
                                              .currentUser;
                                      final isMe =
                                          currentUser != null &&
                                          comment.author ==
                                              currentUser.username;
                                      final hasReactions =
                                          comment.emotionCounts.isNotEmpty;

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              isMe
                                                  ? MainAxisAlignment.end
                                                  : MainAxisAlignment.start,
                                          children: [
                                            if (!isMe) ...[
                                              Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .surfaceVariant,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                    width: 1,
                                                  ),
                                                ),
                                                clipBehavior: Clip.antiAlias,
                                                child:
                                                    comment
                                                            .authorProfileImageUrl
                                                            .isNotEmpty
                                                        ? CachedNetworkImage(
                                                          imageUrl:
                                                              comment
                                                                  .authorProfileImageUrl,
                                                          fit: BoxFit.cover,
                                                          placeholder:
                                                              (
                                                                context,
                                                                url,
                                                              ) => const SizedBox(
                                                                width: 40,
                                                                height: 40,
                                                                child: Center(
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                                ),
                                                              ),
                                                          errorWidget:
                                                              (
                                                                context,
                                                                url,
                                                                error,
                                                              ) => Icon(
                                                                Icons.person,
                                                                size: 16,
                                                                color:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .onSurfaceVariant,
                                                              ),
                                                          memCacheWidth: 80,
                                                          maxWidthDiskCache: 80,
                                                          fadeInDuration:
                                                              Duration.zero,
                                                          fadeOutDuration:
                                                              Duration.zero,
                                                          cacheKey:
                                                              'comment_profile_${comment.authorProfileImageUrl}',
                                                        )
                                                        : Icon(
                                                          Icons.person,
                                                          size: 16,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                        ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],

                                            Flexible(
                                              child: Column(
                                                crossAxisAlignment:
                                                    isMe
                                                        ? CrossAxisAlignment.end
                                                        : CrossAxisAlignment
                                                            .start,
                                                children: [
                                                  // 답글인 경우 타겟 댓글 표시
                                                  if (comment.parentId !=
                                                          null &&
                                                      comment.parentId != '0' &&
                                                      comment.parentId != '')
                                                    ...() {
                                                      // 타겟 댓글 찾기 (간단한 버전)
                                                      final allComments =
                                                          _commentService
                                                              .getAllComments();
                                                      Comment? targetComment;
                                                      try {
                                                        targetComment = allComments
                                                            .firstWhere(
                                                              (c) =>
                                                                  c.id ==
                                                                  comment
                                                                      .parentId,
                                                            );
                                                      } catch (e) {
                                                        targetComment = null;
                                                      }

                                                      if (targetComment == null)
                                                        return <Widget>[];

                                                      return [
                                                        // 타겟 댓글 (투명한 말풍선)
                                                        GestureDetector(
                                                          onTap: () {
                                                            // 타겟 댓글로 스크롤 점프 (댓글 시트 열기)
                                                            _showCommentBottomSheet();
                                                          },
                                                          child: Container(
                                                            constraints: BoxConstraints(
                                                              maxWidth:
                                                                  MediaQuery.of(
                                                                    context,
                                                                  ).size.width *
                                                                  0.75,
                                                            ),
                                                            margin:
                                                                const EdgeInsets.only(
                                                                  bottom: 8,
                                                                ),
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 8,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .surfaceVariant
                                                                  .withOpacity(
                                                                    0.3,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    16,
                                                                  ),
                                                              border: Border.all(
                                                                color: Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .outline
                                                                    .withOpacity(
                                                                      0.2,
                                                                    ),
                                                                width: 1,
                                                              ),
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  '${targetComment.author}',
                                                                  style: TextStyle(
                                                                    color: Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .onSurface
                                                                        .withOpacity(
                                                                          0.7,
                                                                        ),
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  height: 2,
                                                                ),
                                                                Text(
                                                                  targetComment
                                                                      .content,
                                                                  style: TextStyle(
                                                                    color: Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .onSurface
                                                                        .withOpacity(
                                                                          0.6,
                                                                        ),
                                                                    fontSize:
                                                                        13,
                                                                  ),
                                                                  maxLines: 2,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ];
                                                    }(),

                                                  // 댓글 버블
                                                  Container(
                                                    constraints: BoxConstraints(
                                                      maxWidth:
                                                          MediaQuery.of(
                                                            context,
                                                          ).size.width *
                                                          0.75,
                                                    ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 8,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          isMe
                                                              ? Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .primary
                                                              : Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .surfaceVariant,
                                                      borderRadius: BorderRadius.only(
                                                        topLeft:
                                                            const Radius.circular(
                                                              16,
                                                            ),
                                                        topRight:
                                                            const Radius.circular(
                                                              16,
                                                            ),
                                                        bottomLeft:
                                                            Radius.circular(
                                                              isMe ? 16 : 4,
                                                            ),
                                                        bottomRight:
                                                            Radius.circular(
                                                              isMe ? 4 : 16,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      comment.content,
                                                      style: TextStyle(
                                                        color:
                                                            isMe
                                                                ? Colors.white
                                                                : Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurface,
                                                        fontSize: 15,
                                                        height: 1.35,
                                                      ),
                                                    ),
                                                  ),

                                                  // 반응 표시
                                                  if (hasReactions)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 4,
                                                          ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          for (final entry
                                                              in comment
                                                                  .emotionCounts
                                                                  .entries)
                                                            if (entry.value !=
                                                                '0')
                                                              Container(
                                                                margin:
                                                                    const EdgeInsets.only(
                                                                      right: 4,
                                                                    ),
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          6,
                                                                      vertical:
                                                                          2,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      Theme.of(
                                                                        context,
                                                                      ).colorScheme.surface,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        10,
                                                                      ),
                                                                  boxShadow: [
                                                                    BoxShadow(
                                                                      color: Colors
                                                                          .black
                                                                          .withOpacity(
                                                                            0.1,
                                                                          ),
                                                                      blurRadius:
                                                                          2,
                                                                    ),
                                                                  ],
                                                                ),
                                                                child: Text(
                                                                  '${entry.key} ${entry.value}',
                                                                  style:
                                                                      const TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                      ),
                                                                ),
                                                              ),
                                                        ],
                                                      ),
                                                    ),

                                                  // 시간 표시
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    child: Text(
                                                      '${comment.author} • ${_formatRelativeTime(comment.createdAt)}',
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withOpacity(0.6),
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            if (isMe) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .surfaceVariant,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                    width: 1,
                                                  ),
                                                ),
                                                clipBehavior: Clip.antiAlias,
                                                child:
                                                    comment
                                                            .authorProfileImageUrl
                                                            .isNotEmpty
                                                        ? CachedNetworkImage(
                                                          imageUrl:
                                                              comment
                                                                  .authorProfileImageUrl,
                                                          fit: BoxFit.cover,
                                                          placeholder:
                                                              (
                                                                context,
                                                                url,
                                                              ) => const SizedBox(
                                                                width: 40,
                                                                height: 40,
                                                                child: Center(
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                                ),
                                                              ),
                                                          errorWidget:
                                                              (
                                                                context,
                                                                url,
                                                                error,
                                                              ) => Icon(
                                                                Icons.person,
                                                                size: 16,
                                                                color:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .onSurfaceVariant,
                                                              ),
                                                          memCacheWidth: 80,
                                                          maxWidthDiskCache: 80,
                                                          fadeInDuration:
                                                              Duration.zero,
                                                          fadeOutDuration:
                                                              Duration.zero,
                                                          cacheKey:
                                                              'comment_profile_${comment.authorProfileImageUrl}',
                                                        )
                                                        : Icon(
                                                          Icons.person,
                                                          size: 16,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                        ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }).toList();
                                  }(),
                                ),
                          ],
                        ),

                        // 댓글 위에 겹치는 블러 그라데이션 효과 (5개 이상일 때만)
                        if (_commentService.getAllComments().length >= 5)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Theme.of(
                                      context,
                                    ).colorScheme.surface.withOpacity(0.2),
                                    Theme.of(
                                      context,
                                    ).colorScheme.surface.withOpacity(0.5),
                                    Theme.of(context).colorScheme.surface,
                                  ],
                                  stops: const [0.0, 0.4, 0.7, 1.0],
                                ),
                              ),
                              child: Column(
                                children: [
                                  Spacer(),
                                  GestureDetector(
                                    onTap: _showCommentBottomSheet,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surface.withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline
                                              .withOpacity(0.6),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.1,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.keyboard_arrow_down,
                                            size: 16,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '더 많은 댓글 보기',
                                            style: TextStyle(
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 22)),
              ],
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

          // 동적 AppBar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: appBarOpacity,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    height: _appBarHeight + MediaQuery.of(context).padding.top,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withOpacity(0.8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),

                    child: Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top,

                        bottom: 5.0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 18,
                            ),
                          ),

                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.exported['title'] ?? '포스트',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMyPost) ...[
                            GestureDetector(
                              onTap: () {
                                print('widget.exported: ${widget.exported}');
                                if (widget.exported['id'] != null) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder:
                                          (_) => PostwriteScreen(
                                            screenWidth:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width,
                                            isEditMode: true,
                                            postId:
                                                widget.exported['id']
                                                    ?.toString(),
                                            initialExported: widget.exported,
                                          ),
                                    ),
                                  );
                                }
                              },
                              child: Icon(
                                Icons.edit_outlined,
                                color: Theme.of(context).colorScheme.onSurface,
                                size: 18,
                              ),
                            ),
                          ] else ...[
                            GestureDetector(
                              onTap: _showCommentBottomSheet,
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${_commentService.getAllComments().length}',
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
          ),
        ],
      ),
    );
  }

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
        case 'location':
          rebuilt.add(
            LocationNode(
              id: id,
              lat: (m['lat'] as num?)?.toDouble() ?? 0,
              lng: (m['lng'] as num?)?.toDouble() ?? 0,
              title: (m['title'] ?? '').toString(),
              address: (m['address'] ?? '').toString(),
              description: (m['description'] ?? '').toString(),
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
        atts.add(HighlightAttribution(_parseHexColor(highlightHex)));
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

class _ImageHeaderDelegate extends SliverPersistentHeaderDelegate {
  final ImageProvider image;
  final double maxHeight;
  double _pullAccum = 0.0;
  final String? heroTag;

  _ImageHeaderDelegate({
    required this.image,
    required this.maxHeight,
    this.heroTag,
  });

  @override
  double get minExtent => 0.0;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        double slideY = 0.0; // 0 ~ 140px
        // 스크롤 진행도에 따른 페이드아웃
        final double fadeProgress = (shrinkOffset / (maxHeight * 0.6)).clamp(
          0.0,
          1.0,
        );
        final double imgOpacity = 1.0 - fadeProgress;
        bool snapping = false;
        return GestureDetector(
          onVerticalDragUpdate: (details) {
            if (details.delta.dy > 0) {
              _pullAccum = (_pullAccum + details.delta.dy).clamp(0.0, 400.0);
              final next = (slideY + details.delta.dy).clamp(0.0, 140.0);
              setLocalState(() => slideY = next);
            } else if (details.delta.dy < -4) {
              // 이미지 영역에서 위로 스크롤할 때 헤더 페이드 종료 지점까지 부드럽게 스냅
              final scrollable = Scrollable.of(context);
              final position = scrollable.position;
              final double target = maxHeight * 0.6;
              if (!snapping && position.pixels < target) {
                snapping = true;
                position
                    .animateTo(
                      target,
                      duration: const Duration(milliseconds: 550),
                      curve: Curves.fastOutSlowIn,
                    )
                    .whenComplete(() {
                      snapping = false;
                    });
              }
            }
          },
          onVerticalDragEnd: (_) {
            if (_pullAccum >= 80.0) {
              Navigator.of(context).maybePop();
            }
            _pullAccum = 0.0;
            setLocalState(() => slideY = 0.0);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSlide(
                offset: Offset(0, (slideY / (maxHeight == 0 ? 1 : maxHeight))),
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Opacity(
                  opacity: imgOpacity,
                  child: Builder(
                    builder: (context) {
                      final BorderRadius radius = BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                      );
                      Widget rounded() => ClipRRect(
                        borderRadius: radius,
                        clipBehavior: Clip.antiAlias,
                        child: Image(image: image, fit: BoxFit.cover),
                      );
                      if (heroTag == null) {
                        return rounded();
                      }
                      return Hero(
                        tag: heroTag!,
                        transitionOnUserGestures: true,
                        flightShuttleBuilder: (
                          context,
                          animation,
                          direction,
                          fromContext,
                          toContext,
                        ) {
                          return rounded();
                        },
                        child: rounded(),
                      );
                    },
                  ),
                ),
              ),
              // 상단 좌측 뒤로가기
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Container(
                          padding: const EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  bool shouldRebuild(covariant _ImageHeaderDelegate oldDelegate) {
    return oldDelegate.image != image || oldDelegate.maxHeight != maxHeight;
  }
}
