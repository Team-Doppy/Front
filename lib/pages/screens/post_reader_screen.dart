import 'dart:ui' as ui;
import 'package:doppy/editor/component/single_image_component.dart';
import 'package:doppy/pages/components/post_reader_header.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// google_fonts 사용은 헤더 컴포넌트 내부로 이동
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/component/row_image_component.dart'
    show RowImageComponentBuilder, ImageRowNode;
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/components/comment_bottom_sheet.dart';
import 'package:doppy/pages/components/comment_preview_section.dart';
import 'package:doppy/pages/components/doppy_loading_logo.dart';
import 'package:doppy/pages/components/fullscreen_image_viewer.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:url_launcher/url_launcher.dart';

// 읽기 전용에서는 에디터 전용 컴포넌트를 사용하지 않음
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/component/paragraph_component.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show ClipNode, videoPlayerControllers, PinComponentBuilder;
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/post_reader_service.dart';
import 'package:doppy/editor/service/post_reader_stickers.dart';
import 'package:doppy/editor/service/node_component_service.dart';

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
  final PostReaderService _postReaderService = PostReaderService();
  Future<Map<String, dynamic>>? _contentFuture;
  Map<String, dynamic>? _currentExportedData; // 최신 컨텐츠를 저장
  bool _showLoadingLogo = false; // 로딩 로고 표시 여부
  bool _isRenderReady = false; // 스포일러 마스크 렌더링 완료 여부

  // 스크롤 애니메이션을 위한 변수들
  static const double _appBarHeight = 52.0; // AppBar 높이
  double _lastScrollOffset = 0.0;
  double _pullAccum = 0.0; // 상단에서 아래로 당겨 닫기 누적 거리
  double _horizontalDragDistance = 0.0; // 오른쪽으로 밀어 닫기 누적 거리

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

  // 마지막 탭 위치 저장
  Offset? _lastTapPosition;

  // 전체화면 이미지 뷰어 상태
  bool _showImageViewer = false;
  bool _isVideoViewer = false;
  String? _currentImageUrl;
  List<String> _allImageUrls = [];
  String? _currentMediaId;
  List<String> _allMediaIds = [];

  // 제목 정렬/폰트 파싱은 헤더 컴포넌트 내부에서 처리

  void _handleTap() async {
    if (_lastTapPosition == null) return;

    final node = _editorService.findNodeAtPosition(_lastTapPosition!);
    if (node == null) {
      return;
    }

    // 노드 타입에 따른 분기 처리
    switch (node.runtimeType) {
      case ClipNode:
        final clipNode = node as ClipNode;
        print('  - Clip: ${clipNode.url}');

        // 1) 읽기모드: 빈 영역 탭이면 fullscreen, 특정 영역(중앙/모서리) 탭이면 액션
        final action = _dragService.handleClipNodeTap(
          clipNode.id,
          _lastTapPosition!,
        );
        if (action != null) {
          _triggerClipNodeAction(clipNode.id, action);
          break;
        }

        // 2) 액션이 없으면 전체화면으로 열기 (프리로드 보장)
        if (clipNode.url.isNotEmpty) {
          // 프리로드 컨트롤러 확인
          final controller = PostReaderService.getPreloadedController(
            clipNode.url,
          );

          if (controller == null) {
            print('[PostReaderScreen] ⚠️ 비디오가 프리로드되지 않음: ${clipNode.url}');
            print('[PostReaderScreen] 즉시 프리로드 시작...');

            try {
              // 프리로드 안 되어 있으면 즉시 프리로드
              await _postReaderService.preloadClips(context, [
                clipNode.url,
              ], maxCount: 1);
              print('[PostReaderScreen] 즉시 프리로드 완료');
            } catch (e) {
              print('[PostReaderScreen] 즉시 프리로드 실패: $e');
            }
          } else {
            print('[PostReaderScreen] ✅ 비디오가 이미 프리로드됨');
          }

          setState(() {
            _currentImageUrl = clipNode.url;
            _allImageUrls = [clipNode.url];
            _isVideoViewer = true;
            _showImageViewer = true;
          });
        }
        break;

      case LinkNode:
        final linkNode = node as LinkNode;
        print('  - Link: ${linkNode.url}');
        final raw = linkNode.url.trim();
        if (raw.isEmpty) break;
        final String normalized =
            raw.startsWith('http://') || raw.startsWith('https://')
                ? raw
                : 'https://$raw';
        final uri = Uri.tryParse(normalized);
        if (uri == null) {
          if (mounted) ErrorHandler.showError(context, '유효하지 않은 링크예요');
          break;
        }
        try {
          await launchUrl(
            uri,
            mode: LaunchMode.inAppWebView,
            webViewConfiguration: const WebViewConfiguration(
              enableJavaScript: true,
              enableDomStorage: true,
            ),
          );
        } catch (_) {
          if (mounted) ErrorHandler.showError(context, '링크를 열 수 없어요');
        }
        break;

      case ImageNode:
        final imageNode = node as ImageNode;
        print('  - Image: ${imageNode.imageUrl}');

        // 스포일러 상태 확인
        final nodeService = NodeComponentService();
        bool hasSpoiler = false;
        try {
          // NodeComponentService에서 확인
          hasSpoiler = nodeService.isSpoiler(imageNode.id);
          // metadata에서도 확인
          if (!hasSpoiler) {
            final meta =
                (imageNode as dynamic).metadata as Map<String, dynamic>?;
            hasSpoiler = meta != null && (meta['spoiler'] == true);
          }
        } catch (_) {}

        // 스포일러가 있으면 해제
        if (hasSpoiler) {
          nodeService.setSpoiler(imageNode.id, false);
          setState(() {}); // UI 즉시 업데이트
          print('[PostReaderScreen] 이미지 스포일러 해제: ${imageNode.id}');
          return; // 스포일러 해제만 하고 종료
        }

        // 스포일러가 없으면 full viewer 열기
        // mediaId 메타 추출
        String? mediaId;
        try {
          final meta = (imageNode as dynamic).metadata as Map<String, dynamic>?;
          final v = meta != null ? meta['mediaId'] : null;
          if (v != null) mediaId = v.toString();
        } catch (_) {}

        setState(() {
          _currentImageUrl = imageNode.imageUrl;
          _allImageUrls = [_currentImageUrl!];
          _isVideoViewer = false;
          _showImageViewer = true;
          _currentMediaId = mediaId;
          _allMediaIds = mediaId != null ? [mediaId] : [];
        });
        break;

      case ImageRowNode:
        final imageRowNode = node as ImageRowNode;
        print('  - ImageRow: ${imageRowNode.imageUrls}');

        // 스포일러 상태 확인
        final nodeService = NodeComponentService();
        bool hasSpoiler = false;
        try {
          // NodeComponentService에서 확인
          hasSpoiler = nodeService.isSpoiler(imageRowNode.id);
          // metadata에서도 확인
          if (!hasSpoiler) {
            final meta = imageRowNode.metadata;
            hasSpoiler = meta['spoiler'] == true;
          }
        } catch (_) {}

        // 스포일러가 있으면 해제
        if (hasSpoiler) {
          nodeService.setSpoiler(imageRowNode.id, false);
          setState(() {}); // UI 즉시 업데이트
          print('[PostReaderScreen] 이미지 행 스포일러 해제: ${imageRowNode.id}');
          return; // 스포일러 해제만 하고 종료
        }

        // 스포일러가 없으면 full viewer 열기
        // 클릭한 위치의 이미지 인덱스 계산
        final nodeRect = _dragService.getNodeGlobalRect(imageRowNode.id);
        if (nodeRect != null) {
          final localX = _lastTapPosition!.dx - nodeRect.left;
          final imageCount = imageRowNode.imageUrls.length;
          final imageWidth = nodeRect.width / imageCount;
          final clickedIndex = (localX / imageWidth).floor().clamp(
            0,
            imageCount - 1,
          );

          setState(() {
            _allImageUrls = imageRowNode.imageUrls;
            _currentImageUrl = imageRowNode.imageUrls[clickedIndex];
            _isVideoViewer = false;
            _showImageViewer = true;
            _currentMediaId = null;
            _allMediaIds = List.filled(_allImageUrls.length, '');
          });
        }
        break;

      case DividerNode:
        print('  - Divider');
        break;

      case ParagraphNode:
        final paragraphNode = node as ParagraphNode;

        // 멘션 노드 처리: 탭 시 프로필로 이동
        final isMention = (paragraphNode.metadata['mention'] == true);
        if (isMention) {
          // 우선 메타의 usernames 사용; 없으면 텍스트에서 파싱
          final List<String> names =
              ((paragraphNode.metadata['usernames'] as List?)
                  ?.map((e) => e.toString())
                  .toList()) ??
              _extractUsernamesFromText(paragraphNode.text.text);

          if (names.isEmpty) return;
          if (names.length == 1) {
            _openUserProfile(names.first);
            return;
          }

          if (!mounted) return;
          // 여러 명이면 선택 바텀시트
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (_) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...names.map(
                        (u) => ListTile(
                          title: Text(
                            '@$u',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            _openUserProfile(u);
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
            },
          );
          return;
        }

        // 스포일러 확인: 텍스트에 spoiler attribution이 있는지 확인
        final text = paragraphNode.text;
        bool hasSpoiler = false;
        try {
          // 텍스트 전체를 확인하여 spoiler attribution이 있는지 체크
          for (int i = 0; i < text.text.length; i++) {
            final attrs = text.getAllAttributionsAt(i);
            if (attrs.any((a) => a is NamedAttribution && a.id == 'spoiler')) {
              hasSpoiler = true;
              break;
            }
          }
        } catch (_) {}

        // 스포일러가 있으면 NodeComponentService를 통해 해제하고 문서에서도 제거
        if (hasSpoiler) {
          final nodeService = NodeComponentService();

          // NodeComponentService에 "스포일러 해제됨" 상태 저장
          // 문서는 수정하지 않고 UI에서만 일시적으로 해제
          nodeService.setSpoiler(paragraphNode.id, false);
          // setState를 호출하여 UI 업데이트 (NodeComponentService 변경 감지)
          setState(() {});
        }
        break;

      default:
        // 알 수 없는 노드 타입
        break;
    }
  }

  void _triggerClipNodeAction(String nodeId, String action) {
    print('[ClipNode] Action triggered: $action for node: $nodeId');

    // 문서에서 ClipNode 찾기
    final node = _document.getNodeById(nodeId);
    if (node is! ClipNode || node.url.isEmpty) {
      print('[ClipNode] ClipNode를 찾을 수 없거나 URL이 비어있습니다');
      return;
    }

    // 컨트롤러 찾기
    final key = 'video_${node.url.hashCode}';
    final controller = videoPlayerControllers[key];

    if (controller == null) {
      return;
    }

    // 액션 실행
    if (action == 'toggleMute') {
      controller.toggleMute?.call();
    } else if (action == 'restartVideo') {
      controller.restartVideo?.call();
    }
  }

  void _closeImageViewer() {
    setState(() {
      _showImageViewer = false;
      _currentImageUrl = null;
    });
  }

  void _toggleLike() async {
    final postId = widget.exported['id']?.toString();
    if (postId == null || postId.isEmpty) {
      return;
    }

    try {
      await _likeService.togglePostLike(postId);
      // setState() 제거 - LikeService 리스너가 자동으로 UI 업데이트
    } catch (e) {
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

    // 삭제 확인 다이얼로그 (공통 다이얼로그 사용)
    final bool? shouldDelete = await DialogUtils.showConfirmDialog(
      context,
      title: '게시물을 삭제하시겠습니까?',
      message: '30일 이후 자동 영구 삭제됩니다.\n삭제된 게시물의 조회수, 댓글, 좋아요 등의 데이터는 복구할 수 없습니다.',
      confirmText: '삭제',
      cancelText: '취소',
      isDestructive: true,
    );

    if (shouldDelete != true) return;

    try {
      await _blogService.deletePost(postId);

      if (mounted) {
        // 뒤로가기 전에 결과 전달하여 프로필 화면이 다시 빌드되도록 함
        Navigator.of(context).pop({'deleted': true});
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

    // 남은 댓글 로드 (페이지네이션)
    _commentService.loadComments();

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

  // 본문 로드 + 상위 6개 이미지 + 모든 클립 미리 디코딩
  Future<Map<String, dynamic>> _loadContentWithPreloadedMedia(
    String postId,
  ) async {
    final content = await _blogService.getPostContent(postId);

    // 이미지와 클립 URL 추출 및 미리 로드 (비동기, 화면 그린 뒤 시작)
    if (mounted) {
      final imageUrls = _postReaderService.extractImageUrls(content);
      print('[PostReaderScreen] 이미지 프리로드 대상: ${imageUrls.length}개');
      // 이미지는 상위 6개만 선 프리로드
      await _postReaderService.preloadImages(context, imageUrls, maxCount: 6);

      final clipUrls = _postReaderService.extractClipUrls(content);
      if (clipUrls.isNotEmpty) {
        // 첫 번째 클립은 동기 프리로드(타임아웃 가드) → 완전 무쉬머 보장
        try {
          await _postReaderService
              .preloadClips(context, [clipUrls.first], maxCount: 1)
              .timeout(const Duration(milliseconds: 1000));
          print('[PostReaderScreen] 첫 클립 동기 프리로드 완료');
        } catch (e) {
          print('[PostReaderScreen] 첫 클립 동기 프리로드 타임아웃/실패: $e');
        }

        // 나머지는 화면 그린 뒤 비동기 프리로드 전체 실행
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            final rest = clipUrls.skip(1).toList();
            if (rest.isEmpty) return;
            // ignore: discarded_futures
            _postReaderService.preloadClips(context, rest);
            print('[PostReaderScreen] 나머지 클립 비동기 프리로드 시작: ${rest.length}개');
          } catch (e) {
            print('[PostReaderScreen] 클립 프리로드(비동기) 오류: $e');
          }
        });
      }
    }

    return content;
  }

  @override
  void initState() {
    super.initState();
    // 새 글 진입 시 이전 화면에서 해제한 스포일러 상태를 초기화하여
    // 항상 기본(가려진) 상태로 시작
    try {
      NodeComponentService().clearSpoilers();
    } catch (_) {}
    _document = _postReaderService.rebuildDocumentForRead(widget.exported);
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _composer,
    );
    _editorService = EditorService(editor: _editor, document: _document);
    _editorService.setDocumentLayoutKey(_layoutKey);
    _dragService = DragService(editorService: _editorService);
    _readOnlyFocus = FocusNode(canRequestFocus: false);
    _scrollCtrl.addListener(_onScroll);

    // 전체 이미지 URL 저장 (프리캐싱은 _loadContentWithPreloadedMedia에서 처리)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _contentFuture != null) {
        _contentFuture!.then((content) {
          if (mounted) {
            final imageUrls = _postReaderService.extractImageUrls(content);
            setState(() {
              _allImageUrls = imageUrls;
            });
          }
        });
      }
    });

    // PostReaderScreen은 StickerService를 사용하지 않고
    // widget.exported에서 stickers를 직접 읽어 PostReaderStickers에 전달

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

    final postId = widget.exported['id']?.toString();
    if (postId != null && postId.isNotEmpty) {
      _commentService.setPostId(postId);

      // 초기 댓글 로드 (미리보기용으로 소량만)
      _commentService.loadComments(size: 10);

      // 초기 좋아요 상태와 수 설정
      final initialLikeCount = widget.exported['likeCount'] ?? 0;
      final initialIsLiked = widget.exported['isLiked'] == true;
      _likeService.setInitialLikeData(postId, initialIsLiked, initialLikeCount);

      print(
        '[PostReaderScreen] 초기 좋아요 상태: $initialIsLiked, 카운트: $initialLikeCount',
      );
      // 본문 로드 + 상위 6개 이미지 미리 디코딩
      _contentFuture = _loadContentWithPreloadedMedia(postId);

      // 0.5초 후 로딩 로고 표시
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _showLoadingLogo = true;
          });
        }
      });
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

    // 프리로드된 비디오 컨트롤러 정리
    PostReaderService.disposeAllPreloaded();
    print('[PostReaderScreen] 프리로드 컨트롤러 모두 정리');

    // 화면 종료 시 스포일러 세션 상태 초기화 (프레임 잠금 중 알림 방지)
    try {
      NodeComponentService().clearSpoilers(notify: false);
    } catch (_) {}
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
    // 스티커는 아래 FutureBuilder에서 최신 content 기준으로 추출

    final currentUser = context.read<UserProvider>().currentUser;
    final String postAuthor = (widget.exported['author'] ?? '').toString();
    final bool isMyPost =
        currentUser != null && currentUser.username == postAuthor;

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
              return DoppyLoadingLogo(
                opacity: _showLoadingLogo ? 1.0 : 0.0,
                showBackButton: true,
                onBack: () => Navigator.of(context).pop(),
              );
            }

            // ✅ 데이터/미디어 선행 준비 후 약간 더 대기하여 첫 프레임 안정화
            if (snap.hasData && !_isRenderReady) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) {
                  setState(() => _isRenderReady = true);
                }
              });
              return DoppyLoadingLogo(
                opacity: _showLoadingLogo ? 1.0 : 0.0,
                showBackButton: true,
                onBack: () => Navigator.of(context).pop(),
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
              _document = _postReaderService.rebuildDocumentForRead(merged);
              _editor = createDefaultDocumentEditor(
                document: _document,
                composer: _composer,
              );
              _editorService = EditorService(
                editor: _editor,
                document: _document,
              );
              _editorService.setDocumentLayoutKey(_layoutKey);
              _dragService = DragService(editorService: _editorService);
            }

            // 스티커 추출: 서버에서 최신 본문(snap.data)이 있으면 그쪽에서,
            // 아니면 최초 exported의 content에서 읽는다
            final Map<String, dynamic> stickersContent =
                (snap.hasData && (snap.data?.isNotEmpty ?? false))
                    ? (snap.data as Map<String, dynamic>)
                    : ((widget.exported['content'] as Map<String, dynamic>?) ??
                        {});
            final List stickers =
                (stickersContent['stickers'] as List?) ?? const [];

            const double gapHeight = 50;

            return Stack(
              children: [
                // 전체 스크롤
                NotificationListener<ScrollNotification>(
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
                      if (_pullAccum >= 100.0) {
                        Navigator.of(context).maybePop();
                      }
                      _pullAccum = 0.0;
                    }
                    return false;
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: (details) {
                      _lastTapPosition = details.globalPosition;
                      _handleTap();
                    },
                    onHorizontalDragUpdate: (details) {
                      // 오른쪽으로 스와이프 (positive delta)
                      if (details.primaryDelta! > 0) {
                        _horizontalDragDistance += details.primaryDelta!;
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      if (_horizontalDragDistance > 100) {
                        Navigator.of(context).pop();
                      }
                      _horizontalDragDistance = 0.0;
                    },
                    child: CustomScrollView(
                      controller: _scrollCtrl,
                      physics: const ClampingScrollPhysics(),
                      slivers: [
                        SliverSafeArea(
                          top: true,
                          bottom: false,
                          sliver: SliverToBoxAdapter(
                            child: PostReaderHeader(
                              exportedRoot: widget.exported,
                              currentExportedData: _currentExportedData,
                              postAuthor: postAuthor,
                              authorProfileImageUrl:
                                  widget.exported['authorProfileImageUrl']
                                      as String?,
                              enableAuthorTap:
                                  !isMyPost &&
                                  widget.exported['authorId'] != null,
                              onAuthorTap: () {
                                if (isMyPost ||
                                    widget.exported['authorId'] == null) {
                                  return;
                                }
                                final authorId = widget.exported['authorId'];
                                final authorProfileImageUrl =
                                    widget.exported['authorProfileImageUrl']
                                        as String?;
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder:
                                        (_) => UserProfileScreen(
                                          otherUser: User(
                                            id: authorId,
                                            username: postAuthor,
                                            profileImageUrl:
                                                authorProfileImageUrl,
                                          ),
                                        ),
                                  ),
                                );
                              },
                              horizontalPadding: 20,
                              topSpacing: 90,
                              gapHeight: gapHeight,
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
                              isEditing: false, // 읽기 모드
                            ),
                            RowImageComponentBuilder(
                              dragService: _dragService,
                              isEditing: false, // 읽기 모드
                            ),
                            LinkComponentBuilder(isEditing: false),
                            DividerComponentBuilder(),
                            PinComponentBuilder(dragService: _dragService),
                            CustomParagraphComponentBuilder(
                              dragService: _dragService,
                              editorService: _editorService,
                              isEditing: false, // 읽기 모드
                              onMentionTap: (names) {
                                if (names.isEmpty) return;
                                if (names.length == 1) {
                                  _openUserProfile(names.first);
                                  return;
                                }
                                showModalBottomSheet(
                                  context: context,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(16),
                                            ),
                                      ),
                                      child: SafeArea(
                                        top: false,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const SizedBox(height: 8),
                                            Container(
                                              width: 40,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ...names.map(
                                              (u) => ListTile(
                                                title: Text(
                                                  '@$u',
                                                  style: TextStyle(
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.onSurface,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                onTap: () {
                                                  Navigator.of(context).pop();
                                                  _openUserProfile(u);
                                                },
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
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
                    child: PostReaderStickers(
                      stickers: stickers,
                      layoutKey: _layoutKey,
                      stackKey: _stackKey,
                      scrollController: _scrollCtrl,

                      topInset: (_appBarHeight + gapHeight),
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

                // 동적 AppBar 컴포넌트로 분리
                Builder(
                  builder: (context) {
                    final double computedBarHeight =
                        _appBarHeight + MediaQuery.of(context).padding.top;
                    return PostReaderAppBar(
                      showAppBar: _showAppBar,
                      barHeight: computedBarHeight,
                      isMyPost: isMyPost,
                      onBack: () => Navigator.of(context).pop(),
                      onEdit: () {
                        final dataToEdit =
                            _currentExportedData ?? widget.exported;
                        final postId =
                            dataToEdit['id']?.toString() ??
                            widget.exported['id']?.toString();

                        if (postId != null && postId.isNotEmpty) {
                          Navigator.of(context).pushReplacement(
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      PostwriteScreen(
                                        isEditingMode: true,
                                        exportedDataForEdit: dataToEdit,
                                        postId: postId,
                                      ),
                              transitionDuration: const Duration(
                                milliseconds: 200,
                              ),
                              reverseTransitionDuration: const Duration(
                                milliseconds: 200,
                              ),
                              transitionsBuilder: (
                                context,
                                animation,
                                secondaryAnimation,
                                child,
                              ) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                            ),
                          );
                        } else {
                          print('[PostReaderScreen] postId가 없습니다');
                        }
                      },
                      onDelete: _deletePost,
                      onShowComments: _showCommentBottomSheet,
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
                // 전체화면 이미지/영상 뷰어
                if (_showImageViewer && _currentImageUrl != null)
                  Positioned.fill(
                    child: FullscreenImageViewer(
                      imageUrl: _currentImageUrl!,
                      allImageUrls: _allImageUrls,
                      mediaId: _currentMediaId,
                      allMediaIds: _allMediaIds,

                      initialIndex:
                          _currentImageUrl != null && _allImageUrls.isNotEmpty
                              ? _allImageUrls.indexOf(_currentImageUrl!)
                              : 0,
                      isVideo: _isVideoViewer,
                      preloadedController:
                          _isVideoViewer
                              ? PostReaderService.getPreloadedController(
                                _currentImageUrl!,
                              )
                              : null,
                      onClose: _closeImageViewer,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<String> _extractUsernamesFromText(String text) {
    if (text.isEmpty) return const [];
    return text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.startsWith('@') && e.length > 1)
        .map((e) => e.substring(1))
        .toList();
  }

  void _openUserProfile(String username) {
    if (username.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) =>
                UserProfileScreen(otherUser: User(id: 0, username: username)),
      ),
    );
  }
}
