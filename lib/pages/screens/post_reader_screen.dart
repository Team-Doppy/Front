import 'dart:ui' as ui;
import 'dart:async';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/single_image_component.dart';
import 'package:doppy/editor/nodes/mention_node.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/post_reader_header.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/utils/access_level_parser.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/format_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
// google_fonts 사용은 헤더 컴포넌트 내부로 이동
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/style/style_sheet.dart';
import 'package:doppy/editor/component/row_image_component.dart'
    show RowImageComponentBuilder, ImageRowNode;
import 'package:doppy/editor/component/pageview_image_component.dart'
    show PageViewImageComponentBuilder, PageViewImageNode;
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/components/access_level_sheet.dart';
import 'package:doppy/pages/components/comment_bottom_sheet.dart';
import 'package:doppy/pages/screens/manage_group_screen.dart';
import 'package:doppy/pages/components/comment_preview_section.dart';
import 'package:doppy/pages/components/share_post_overlay.dart';
import 'package:doppy/pages/components/doppy_loading_logo.dart';
import 'package:doppy/pages/components/fullscreen_media_viewer.dart';
import 'package:doppy/pages/components/liked_users_bottom_sheet.dart';
import 'package:doppy/pages/components/viewers_bottom_sheet.dart';
import 'package:doppy/pages/components/post_action_bottom_sheet.dart';
import 'package:doppy/pages/components/mention_bottom_sheet.dart';
import 'package:doppy/pages/components/post_reader_mention_bottom_sheet.dart';
import 'package:doppy/pages/components/post_reader_error_screen.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';

// 읽기 전용에서는 에디터 전용 컴포넌트를 사용하지 않음
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/component/paragraph_component.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show
        ClipNode,
        videoPlayerControllers,
        videoPlayerProxyKey,
        ClipComponentBuilder;
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:video_player/video_player.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/post_reader_service.dart';
import 'package:doppy/editor/service/post_reader_scroll_preload_service.dart';
import 'package:doppy/editor/post_reader_stickers.dart';
import 'package:doppy/editor/service/node_component_service.dart';

/// 읽기 전용: 작성 화면에서 Export된 Map을 받아 그대로 복원하여 보여준다.
class PostReaderScreen extends StatefulWidget {
  const PostReaderScreen({
    super.key,
    required this.exported,
    this.heroTag,
    this.fromProfile = false, // 프로필에서 들어왔는지 여부
    this.initialAction, // 🎯 초기 액션 (댓글/좋아요 탭 자동 열기)
    this.scrollToCommentId, // 🎯 특정 댓글로 스크롤할 댓글 ID
    this.preloadedContent, // 🎯 딥링크로 들어올 때 이미 로드된 content (중복 로딩 방지)
  });
  final Map<String, dynamic> exported;
  final String? heroTag; // 홈 썸네일과 자연스러운 연결(Hero)
  final bool fromProfile; // 프로필에서 들어왔는지 여부
  final PostReaderInitialAction? initialAction; // 🎯 초기 액션
  final String? scrollToCommentId; // 🎯 특정 댓글로 스크롤할 댓글 ID
  final Map<String, dynamic>? preloadedContent; // 🎯 이미 로드된 content (딥링크용)

  @override
  State<PostReaderScreen> createState() => _PostReaderScreenState();
}

/// 🎯 PostReaderScreen 초기 액션 타입
enum PostReaderInitialAction {
  showComments, // 댓글 탭 열기
  showLikes, // 좋아요 탭 열기
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
  final GlobalKey _documentStartMarkerKey = GlobalKey(); // 🎯 문서 시작점 측정용
  final BlogService _blogService = BlogService();
  final PostReaderService _postReaderService = PostReaderService();
  final PostReaderScrollPreloadService _scrollPreloadService =
      PostReaderScrollPreloadService();
  Future<Map<String, dynamic>>? _contentFuture;
  Map<String, dynamic>? _currentExportedData; // 최신 컨텐츠를 저장
  bool _showLoadingLogo = false; // 로딩 로고 표시 여부
  bool _keepLoadingOverlay = false; // ✅ content 로드 완료 후에도 페이드아웃 동안 오버레이 유지
  bool _isLoadingContent = true; // ✅ 0.5s 로고 show 타이머가 "완료 후 깜빡임"을 내지 않게 가드
  bool _didScheduleLoadingHide = false; // ✅ hide 스케줄 1회 보장
  static const Duration _loadingFadeDuration = Duration(milliseconds: 200);
  bool _accessLevelChanged = false; // 🎯 공개 범위 변경 여부
  bool _documentInitialized = false; // 🎯 문서 초기화 완료 플래그 (재생성 방지
  bool _didStartRemainingMediaPreload =
      false; // ✅ 상위 3개 제외 나머지 미디어 백그라운드 프리로드 1회 보장 (레거시)
  // 🎯 프리로드 임계값: 뷰포트 기반 (서버가 느려서 더 일찍 프리로드)
  // 화면 높이의 2배 전에 프리로드 = 사용자가 보는 화면 아래 1화면 전에 미리 준비
  static const double _preloadViewportMultiplier = 1.0; // 화면 높이의 1배
  static const double _preloadBottomThresholdFallback =
      800.0; // 🎯 뷰포트 계산 불가 시 fallback (하단 800px)
  double? _cachedScreenHeight; // 🎯 성능 최적화: 화면 높이 캐싱

  // 스크롤 애니메이션을 위한 변수들
  static const double _appBarHeight = 56.0; // AppBar 높이 (kToolbarHeight와 동일)
  double _lastScrollOffset = 0.0;
  DateTime? _lastScrollUpdate; // 🎯 스크롤 업데이트 throttling용

  // 앱바 표시/숨김을 위한 변수들
  bool _showAppBar = true; // 상단 이미지 제거 → 기본 표시
  int _bottomBarAnimationDuration = 300; // 하단 바 애니메이션 속도 (ms)
  bool _previousAppBarState = true; // 🎯 풀스크린/오버레이 진입 전 앱바 상태 저장
  double _currentScrollOffset = 0.0; // 🎯 현재 스크롤 위치 (타이틀 표시용)
  final bool _showLoadingBackButton = true; // 🎯 로딩 화면 뒤로가기 버튼 표시 여부
  final bool _showErrorBackButton = true; // 🎯 에러 화면 뒤로가기 버튼 표시 여부

  // 순차 애니메이션 제거

  // 댓글 화면은 Route(push)로 분리하여 표시 (오버레이 제거)

  // 전체화면 이미지 뷰어 상태/애니메이션
  bool _showImageViewer = false;
  bool _isVideoViewer = false;
  String? _currentImageUrl;
  List<String> _allImageUrls = [];
  late final AnimationController _imageViewerCtrl;
  late final Animation<double> _imageViewerFade;

  // 좋아요/댓글 데이터
  final CommentService _commentService = CommentService();

  // 🎯 content에서 받아온 공개범위 데이터
  String? _accessLevel; // 'PUBLIC', 'PRIVATE', 'FRIENDS', 'GROUPS'
  List<int>? _sharedGroupIds;
  List<String>? _sharedGroupNames; // 🎯 서버에서 제공하는 그룹 이름 목록
  final LikeService _likeService = LikeService();

  // 마지막 탭 위치 저장
  Offset? _lastTapPosition;

  // 제목 정렬/폰트 파싱은 헤더 컴포넌트 내부에서 처리

  void _handleTap() async {
    if (_lastTapPosition == null) return;

    final node = _editorService.findNodeAtPosition(_lastTapPosition!);
    debugPrint(
      '[PostReaderScreen] 🔍 찾은 노드: ${node?.runtimeType} (ID: ${node?.id})',
    );

    if (node == null) {
      debugPrint('[PostReaderScreen] ⚠️ 노드를 찾을 수 없음');
      return;
    }

    // 노드 타입에 따른 분기 처리
    debugPrint('[PostReaderScreen] 🎯 노드 타입 분기: ${node.runtimeType}');

    // 🎯 switch 대신 if-else 사용 (AppImageNode는 ImageNode 상속이지만 runtimeType이 다름)
    if (node is ClipNode) {
      final clipNode = node;
      debugPrint('  - Clip: ${clipNode.url}');

      // 1) 읽기모드: 빈 영역 탭이면 fullscreen, 특정 영역(중앙/모서리) 탭이면 액션
      final action = _dragService.handleClipNodeTap(
        clipNode.id,
        _lastTapPosition!,
      );
      if (action != null) {
        _triggerClipNodeAction(clipNode.id, action);
        return;
      }

      // 2) 액션이 없으면 전체화면으로 열기 (프리로드 보장)
      if (clipNode.url.isNotEmpty) {
        // 🎯 VideoCacheService에서 컨트롤러 가져오기
        final videoCache = VideoCacheService();
        VideoPlayerController? controller;
        if (videoCache.hasController(clipNode.url, namespace: 'reader')) {
          controller = videoCache.getOrCreateController(
            clipNode.url,
            namespace: 'reader',
          );
        }
        debugPrint(
          '[PostReaderScreen] ✅ 풀스크린 뷰어 열기: ${clipNode.url} (컨트롤러: ${controller != null ? "있음" : "없음"})',
        );

        setState(() {
          _previousAppBarState = _showAppBar; // 🎯 현재 상태 저장
          _currentImageUrl = clipNode.url;
          _allImageUrls = [clipNode.url];
          _isVideoViewer = true;
          _showImageViewer = true;
          _showAppBar = false; // 하단 바 숨김
          _bottomBarAnimationDuration = 50; // 빠르게 숨김
        });
        _imageViewerCtrl.forward(from: 0.0);
      }
    } else if (node is LinkNode) {
      final linkNode = node;
      debugPrint('  - Link: ${linkNode.url}');
      final raw = linkNode.url.trim();
      if (raw.isEmpty) return;
      final String normalized =
          raw.startsWith('http://') || raw.startsWith('https://')
              ? raw
              : 'https://$raw';
      final uri = Uri.tryParse(normalized);
      if (uri == null) {
        if (mounted)
          ErrorHandler.showError(context, context.tr('invalid_link'));
        return;
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
        if (mounted)
          ErrorHandler.showError(context, context.tr('cannot_open_link'));
      }
    } else if (node is AppImageNode) {
      final imageNode = node;
      debugPrint('  - Image: ${imageNode.imageUrl}');

      // 스포일러 상태 확인
      final nodeService = NodeComponentService();
      bool hasSpoiler = false;
      try {
        // ✅ NodeComponentService에서 먼저 확인 (해제된 상태가 저장되어 있음)
        final isDisabled = nodeService.isSpoilerDisabled(imageNode.id);

        if (!isDisabled) {
          // NodeComponentService에서 해제 안 했으면 실제 스포일러 상태 확인
          hasSpoiler = nodeService.isSpoiler(imageNode.id);

          // metadata에서도 확인 (초기 상태)
          if (!hasSpoiler) {
            final meta =
                (imageNode as dynamic).metadata as Map<String, dynamic>?;
            hasSpoiler = meta != null && (meta['spoiler'] == true);
          }
        }
        // isDisabled가 true면 hasSpoiler는 false 유지
      } catch (_) {}

      // 스포일러가 있으면 해제
      if (hasSpoiler) {
        nodeService.setSpoiler(imageNode.id, false);
        setState(() {}); // UI 즉시 업데이트
        debugPrint('[PostReaderScreen] 이미지 스포일러 해제: ${imageNode.id}');
        return; // 스포일러 해제만 하고 종료
      }

      // 스포일러가 없으면 full viewer 열기
      setState(() {
        _previousAppBarState = _showAppBar; // 🎯 현재 상태 저장
        _currentImageUrl = imageNode.imageUrl;
        _allImageUrls = [_currentImageUrl!];
        _isVideoViewer = false;
        _showImageViewer = true;
        _showAppBar = false; // 하단 바 숨김
        _bottomBarAnimationDuration = 50; // 빠르게 숨김
      });
      _imageViewerCtrl.forward(from: 0.0);
    } else if (node is ImageRowNode) {
      final imageRowNode = node;

      // 스포일러 상태 확인
      final nodeService = NodeComponentService();
      bool hasSpoiler = false;
      try {
        // ✅ NodeComponentService에서 먼저 확인 (해제된 상태가 저장되어 있음)
        final isDisabled = nodeService.isSpoilerDisabled(imageRowNode.id);

        if (!isDisabled) {
          // NodeComponentService에서 해제 안 했으면 실제 스포일러 상태 확인
          hasSpoiler = nodeService.isSpoiler(imageRowNode.id);

          // metadata에서도 확인 (초기 상태)
          if (!hasSpoiler) {
            final meta = imageRowNode.metadata;
            hasSpoiler = meta['spoiler'] == true;
          }
        }
        // isDisabled가 true면 hasSpoiler는 false 유지
      } catch (_) {}

      // 스포일러가 있으면 해제
      if (hasSpoiler) {
        nodeService.setSpoiler(imageRowNode.id, false);
        setState(() {}); // UI 즉시 업데이트
        debugPrint('[PostReaderScreen] 이미지 행 스포일러 해제: ${imageRowNode.id}');
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
          _previousAppBarState = _showAppBar; // 🎯 현재 상태 저장
          _allImageUrls = imageRowNode.imageUrls;
          _currentImageUrl = imageRowNode.imageUrls[clickedIndex];
          _isVideoViewer = false;
          _showImageViewer = true;
          _showAppBar = false; // 하단 바 숨김
          _bottomBarAnimationDuration = 50; // 빠르게 숨김
        });
        _imageViewerCtrl.forward(from: 0.0);
      }
    } else if (node is PageViewImageNode) {
      final pageViewNode = node;

      // 스포일러 상태 확인
      final nodeService = NodeComponentService();
      bool hasSpoiler = false;
      try {
        final isDisabled = nodeService.isSpoilerDisabled(pageViewNode.id);

        if (!isDisabled) {
          hasSpoiler = nodeService.isSpoiler(pageViewNode.id);

          if (!hasSpoiler) {
            final meta = pageViewNode.metadata;
            hasSpoiler = meta['spoiler'] == true;
          }
        }
      } catch (_) {}

      // 스포일러가 있으면 해제
      if (hasSpoiler) {
        nodeService.setSpoiler(pageViewNode.id, false);
        setState(() {});
        debugPrint('[PostReaderScreen] 페이지뷰 이미지 스포일러 해제: ${pageViewNode.id}');
        return;
      }

      // 스포일러가 없으면 full viewer 열기
      setState(() {
        _previousAppBarState = _showAppBar;
        _currentImageUrl =
            pageViewNode.imageUrls.isNotEmpty
                ? pageViewNode.imageUrls.first
                : null;
        _allImageUrls = List<String>.from(pageViewNode.imageUrls);
        _isVideoViewer = false;
        _showImageViewer = true;
        _showAppBar = false;
        _bottomBarAnimationDuration = 50;
      });
      _imageViewerCtrl.forward(from: 0.0);
    } else if (node is DividerNode) {
      debugPrint('  - Divider');
    } else if (node is MentionNode) {
      // 멘션 노드 처리: 탭 시 프로필로 이동
      final usernames = node.usernames;
      if (usernames.isEmpty) return;
      if (usernames.length == 1) {
        _openUserProfile(usernames.first);
        return;
      }

      if (!mounted) return;
      // 여러 명이면 선택 바텀시트
      MentionBottomSheet.show(
        context,
        usernames: usernames,
        onUsernameTap: _openUserProfile,
      );
      return;
    } else if (node is ParagraphNode) {
      // 스포일러 확인: 텍스트에 spoiler attribution이 있는지 확인
      final text = node.text;
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
        nodeService.setSpoiler(node.id, false);
        // setState를 호출하여 UI 업데이트 (NodeComponentService 변경 감지)
        setState(() {});
      }
    }
    // default: 알 수 없는 노드 타입 (처리 안 함)
  }

  /// 🎯 레거시: 한 번만 실행되는 프리로드 (하위 호환성)
  void _startRemainingMediaPreloadOnce(Map<String, dynamic> content) {
    if (_didStartRemainingMediaPreload) return;
    _didStartRemainingMediaPreload = true;
    // 🎯 스크롤 기반 프리로드로 대체되므로, 초기에는 다음 배치를 한 번만 트리거
    _scrollPreloadService.preloadNextBatch(
      content: content,
      context: context,
      mounted: () => mounted,
    );
  }

  void _triggerClipNodeAction(String nodeId, String action) {
    debugPrint('[ClipNode] Action triggered: $action for node: $nodeId');

    // 문서에서 ClipNode 찾기
    final node = _document.getNodeById(nodeId);
    if (node is! ClipNode || node.url.isEmpty) {
      debugPrint('[ClipNode] ClipNode를 찾을 수 없거나 URL이 비어있습니다');
      return;
    }

    // 컨트롤러 찾기
    final key = videoPlayerProxyKey(
      namespace: 'reader',
      url: node.url,
      localPath: node.localPath,
    );
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

  void _closeImageViewer() async {
    await _imageViewerCtrl.reverse();
    if (mounted) {
      setState(() {
        _showImageViewer = false;
        _currentImageUrl = null;
        _showAppBar = _previousAppBarState; // 🎯 이전 상태로 복원
        _bottomBarAnimationDuration =
            _previousAppBarState ? 0 : 300; // 🎯 열려있었으면 즉시(0), 닫혀있었으면 일반 속도
      });
    }
  }

  void _closeScreen() {
    if (_accessLevelChanged) {
      Navigator.of(context).pop({
        'accessLevelChanged': true,
        'postId': widget.exported['id']?.toString(),
        'accessLevel': _accessLevel,
        'sharedGroupIds': _sharedGroupIds,
      });
      return;
    }

    Navigator.of(context).pop();
  }

  void _closeLoadingScreen() {
    Navigator.of(context).pop();
  }

  void _closeErrorScreen() {
    Navigator.of(context).pop();
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
      debugPrint('[PostReaderScreen] 좋아요 처리 중 오류가 발생했습니다: $e');
    }
  }

  void _deletePost() async {
    final postId = widget.exported['id']?.toString();
    if (postId == null || postId.isEmpty) {
      debugPrint('[PostReaderScreen] 유효하지 않은 포스트 ID: $postId');
      return;
    }

    // 삭제 확인 다이얼로그 (공통 다이얼로그 사용)
    final bool? shouldDelete = await DialogUtils.showConfirmDialog(
      context,
      title: context.tr('delete_post_confirm_title'),
      message: context.tr('delete_post_confirm_message'),
      confirmText: context.tr('delete'),
      cancelText: context.tr('cancel'),
      isDestructive: true,
    );

    if (shouldDelete != true) return;

    try {
      // 🎯 삭제 전에 공개범위 정보 저장 (삭제 후에는 접근 불가)
      final accessLevel = _accessLevel ?? 'PUBLIC';
      final sharedGroupIds = _sharedGroupIds;

      await _blogService.deletePost(postId);

      // 🎯 포스트 삭제 후 관련 그룹의 postCount 및 포스트 캐시 동기화
      try {
        final groupProvider = context.read<GroupProvider>();

        // GROUPS 공개범위인 경우: 관련 그룹의 postCount 업데이트 및 포스트 캐시 무효화
        if (accessLevel == 'GROUPS' &&
            sharedGroupIds != null &&
            sharedGroupIds.isNotEmpty) {
          final groupIdToDelta = <int, int>{};
          for (final groupId in sharedGroupIds) {
            groupIdToDelta[groupId] = -1; // 포스트 삭제로 -1
          }
          groupProvider.updateMultipleGroupsPostCount(groupIdToDelta);

          // 🎯 그룹 포스트 캐시 무효화 (동기화)
          ManageGroupScreen.invalidateMultipleGroupsPostsCache(sharedGroupIds);

          debugPrint(
            '[PostReaderScreen] 관련 그룹 postCount 및 포스트 캐시 동기화 완료: ${sharedGroupIds.length}개 그룹',
          );
        }
        // FRIENDS 공개범위인 경우: allFriends 그룹 포스트 캐시 무효화
        else if (accessLevel == 'FRIENDS') {
          // 🎯 allFriends 그룹 포스트 캐시 무효화 (동기화)
          ManageGroupScreen.invalidateGroupPostsCache(-1);
          debugPrint('[PostReaderScreen] allFriends 그룹 포스트 캐시 무효화 완료');
        }
        // PUBLIC/PRIVATE는 그룹 postCount에 영향 없음
      } catch (e) {
        debugPrint('[PostReaderScreen] 그룹 postCount 및 포스트 캐시 동기화 실패: $e');
      }

      if (mounted) {
        // 뒤로가기 전에 결과 전달하여 프로필 화면이 다시 빌드되도록 함
        Navigator.of(context).pop({'deleted': true});
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, context.tr('post_delete_failed'));
      }
    }
  }

  /// 🎯 widget.exported에서 공개범위 데이터 초기화 (임시 값, _loadContentWithPreloadedMedia에서 최신 값으로 업데이트됨)
  void _initializeAccessLevelFromExported() {
    // widget.exported에 이미 데이터가 있으면 먼저 사용 (초기 표시용)
    final parsed = AccessLevelParser.parseAccessLevelMetadata(widget.exported);
    setState(() {
      _accessLevel = parsed['accessLevel'] as String? ?? 'PUBLIC';
      _sharedGroupIds = parsed['sharedGroupIds'] as List<int>?;
      _sharedGroupNames = parsed['sharedGroupNames'] as List<String>?;
    });

    // 🎯 최신 공개범위는 _loadContentWithPreloadedMedia에서 함께 받아옴 (별도 호출 불필요)
  }

  /// 공개범위에 따라 아이콘 빌드 (PRIVATE이면 자물쇠, 그 외에는 공유 아이콘)
  Widget _buildAccessLevelIcon(BuildContext context) {
    final accessLevelStr = _accessLevel ?? 'PUBLIC';
    final isPrivate = accessLevelStr == 'PRIVATE';
    final iconColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.7);

    if (isPrivate) {
      // PRIVATE이면 자물쇠 아이콘
      return SvgPicture.asset(
        'assets/icons/lock.svg',
        width: 24,
        height: 24,
        color: iconColor,
      );
    } else {
      // 그 외에는 공유 아이콘
      return Icon(Icons.share, size: 24, color: iconColor);
    }
  }

  /// 공개범위에 따라 공유 오버레이 또는 공개범위 변경 바텀시트 표시
  void _handleAccessLevelOrShare() {
    final accessLevelStr = _accessLevel ?? 'PUBLIC';
    final isPrivate = accessLevelStr == 'PRIVATE';

    if (isPrivate) {
      // PRIVATE이면 공개범위 변경 바텀시트
      _showAccessLevelBottomSheet();
    } else {
      // 그 외에는 공유 오버레이
      _showShareOverlay();
    }
  }

  /// 공유 오버레이 표시
  void _showShareOverlay() {
    final postId = widget.exported['id']?.toString() ?? '';
    final title = widget.exported['title']?.toString() ?? '';
    final summary = widget.exported['summary']?.toString() ?? '';
    final authorUsername = widget.exported['author']?.toString() ?? '';
    final authorProfileImageUrl =
        widget.exported['authorProfileImageUrl']?.toString();
    final thumbnailUrl = widget.exported['thumbnailImageUrl']?.toString();
    final readTime = (widget.exported['readTime'] as int?) ?? 1;

    SharePostOverlay.show(
      context,
      postId: postId,
      title: title,
      summary: summary,
      authorUsername: authorUsername,
      authorProfileImageUrl: authorProfileImageUrl,
      thumbnailUrl: thumbnailUrl, // 🎯 썸네일 URL 전달
      readTime: readTime,
      isNewPost: false,
      useReplacement: false,
    );
  }

  void _showAccessLevelBottomSheet() async {
    final postId = widget.exported['id']?.toString();
    if (postId == null || postId.isEmpty) {
      return;
    }

    // 🎯 content에서 받아온 공개범위 정보 사용 (메타데이터 조회 안 함)
    final currentAccessLevelStr = _accessLevel ?? 'PUBLIC';
    final currentSharedGroupIds = _sharedGroupIds;
    final currentSharedGroupNames = _sharedGroupNames;

    AccessLevelSheet.show(
      context,
      postId: postId,
      currentAccessLevel: currentAccessLevelStr,
      currentSharedGroupIds: currentSharedGroupIds,
      currentSharedGroupNames: currentSharedGroupNames, // 🎯 그룹 이름 목록 전달
      onChanged: (String accessLevel, List<int>? sharedGroupIds) async {
        // 🎯 공개범위 변경 후 상태 업데이트 (낙관적 업데이트)
        if (mounted) {
          setState(() {
            _accessLevel = accessLevel;
            _sharedGroupIds = sharedGroupIds;
            // sharedGroupNames는 서버에서 갱신되므로 다음 content 로드 시 업데이트됨

            // 🎯 _currentExportedData도 함께 업데이트
            if (_currentExportedData != null) {
              _currentExportedData!['accessLevel'] = accessLevel;
              if (sharedGroupIds != null) {
                _currentExportedData!['sharedGroupIds'] = sharedGroupIds;
              } else {
                _currentExportedData!.remove('sharedGroupIds');
              }
            }
          });
        }

        // 🎯 공개 범위 변경 플래그 설정
        _accessLevelChanged = true;

        // 🎯 프로필에서 들어왔다면 피드 선택적 업데이트 (전체 새로고침 생략)
        if (widget.fromProfile) {
          try {
            final feed = MyProfileFeedProvider(); // 싱글톤 직접 접근
            final postId = widget.exported['id']?.toString();
            if (postId != null) {
              feed.updatePostMetadata(
                postId,
                accessLevel: accessLevel,
                sharedGroupIds: sharedGroupIds,
              );
              debugPrint('[PostReaderScreen] 프로필 피드 선택적 업데이트 완료 (공개범위 변경)');
            }
          } catch (e) {
            debugPrint('[PostReaderScreen] 프로필 피드 선택적 업데이트 실패: $e');
          }
        }
      },
    );
  }

  Future<void> _showCommentBottomSheet() async {
    final id = widget.exported['id']?.toString() ?? '';
    final postAuthorUsername = widget.exported['author']?.toString();

    _commentService.setPostId(id);
    // 🎯 포스트 작성자 정보를 먼저 설정 (loadComments 전에)
    if (postAuthorUsername != null) {
      _commentService.setPostAuthorUsername(postAuthorUsername);
    }
    // WebSocket 연결 + 초기 로드(비동기)
    _initCommentsAsync();

    try {
      final route =
          Theme.of(context).platform == TargetPlatform.iOS
              ? CupertinoPageRoute(
                builder:
                    (_) => CommentBottomSheet(
                      title:
                          (_currentExportedData?['title'] ??
                                  widget.exported['title'] ??
                                  '')
                              .toString(),
                      commentService: _commentService,
                      postThumbnailUrl:
                          (_currentExportedData?['thumbnailImageUrl'] ??
                                  widget.exported['thumbnailImageUrl'])
                              ?.toString(),
                      postSummary:
                          (_currentExportedData?['summary'] ??
                                  widget.exported['summary'])
                              ?.toString(),
                      scrollToCommentId: widget.scrollToCommentId,
                      postAuthorUsername:
                          widget.exported['author']
                              ?.toString(), // 🎯 블로그 작성자 username
                    ),
              )
              : MaterialPageRoute(
                builder:
                    (_) => CommentBottomSheet(
                      title:
                          (_currentExportedData?['title'] ??
                                  widget.exported['title'] ??
                                  '')
                              .toString(),
                      commentService: _commentService,
                      postThumbnailUrl:
                          (_currentExportedData?['thumbnailImageUrl'] ??
                                  widget.exported['thumbnailImageUrl'])
                              ?.toString(),
                      postSummary:
                          (_currentExportedData?['summary'] ??
                                  widget.exported['summary'])
                              ?.toString(),
                      scrollToCommentId: widget.scrollToCommentId,
                      postAuthorUsername:
                          widget.exported['author']
                              ?.toString(), // 🎯 블로그 작성자 username
                    ),
              );

      await Navigator.of(context).push(route);
    } finally {
      // Route가 닫히면 WebSocket 연결 해제
      _commentService.disconnectWebSocket();
      debugPrint('[PostReaderScreen] 댓글 화면 닫기 - WebSocket 연결 해제');
    }
  }

  // 댓글 데이터 초기화 (비동기)
  Future<void> _initCommentsAsync() async {
    // WebSocket 연결 (백그라운드, 실패해도 무시)
    _commentService.connectWebSocketForCurrentPost().catchError((e) {});

    // 🎯 댓글이 아직 로드되지 않았으면 비동기로 로드
    final comments = _commentService.getAllComments();
    if (comments.isEmpty && !_commentService.isLoading) {
      await _commentService.loadComments(); // 🎯 기본 크기(100개)로 로드
    } else if (comments.isNotEmpty) {
      // 🎯 기존 캐시가 있으면 새 댓글만 확인 (기존 캐시 유지)
      await _commentService.checkForNewComments();
    }
  }

  // NOTE: 댓글 오버레이(close) 로직은 Route(push) 방식으로 전환하면서 제거됨.

  // 🎯 좋아요한 사람 목록 기능은 FullscreenMediaViewer로 이동됨

  /// ✅ 본 사람(조회자) 목록: 표준 Navigator.push 방식으로 이동
  Future<void> _openViewersOverlay() async {
    final postId = widget.exported['id']?.toString() ?? '';
    if (postId.isEmpty) return;

    final viewerCount = int.parse(
      (_currentExportedData?['viewCount'] ?? widget.exported['viewCount'])
          .toString(),
    );

    final likeCount = _likeService.getPostLikeCount(postId);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ViewersBottomSheet(
              postId: postId,
              viewerCount: viewerCount,
              likeCount: likeCount > 0 ? likeCount : null,
            ),
      ),
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

  // 본문 로드 + 상위 6개 이미지 + 모든 클립 미리 디코딩
  Future<Map<String, dynamic>> _loadContentWithPreloadedMedia(
    String postId,
  ) async {
    try {
      final response = await _blogService.getPostContent(postId);

      // 🎯 서버 응답 구조: { isLiked, likeCount, commentCount, viewCount, postId, content: {...}, accessLevel, sharedGroupIds, sharedGroupNames }
      final actualLikeCount = response['likeCount'] as int? ?? 0;
      final actualIsLiked = response['isLiked'] == true;
      final actualCommentCount = response['commentCount'] as int? ?? 0;
      final actualViewCount =
          response['viewCount'] != null
              ? (response['viewCount'] is int
                  ? response['viewCount'] as int
                  : int.tryParse(response['viewCount'].toString()) ?? 0)
              : null;

      // 🎯 성능 최적화: 좋아요/댓글 데이터는 비동기로 백그라운드 처리
      Future.microtask(() {
        _likeService.setInitialLikeData(postId, actualIsLiked, actualLikeCount);
        _commentService.setInitialCommentCount(actualCommentCount);
      });

      debugPrint(
        '[PostReaderScreen] 실제 데이터 - 좋아요: $actualLikeCount, 좋아요 상태: $actualIsLiked, 댓글: $actualCommentCount',
      );

      // 🎯 공개범위 정보 업데이트 (content.accessLevelInfo에서 추출)
      final parsed = AccessLevelParser.parseAccessLevelFromContent(response);
      if (mounted) {
        setState(() {
          _accessLevel = parsed['accessLevel'] as String? ?? 'PUBLIC';
          _sharedGroupIds = parsed['sharedGroupIds'] as List<int>?;
          _sharedGroupNames = parsed['sharedGroupNames'] as List<String>?;
        });
      }

      // content 객체 추출
      final content = response['content'] as Map<String, dynamic>? ?? {};

      // ✅ 상위 3개 미디어 노드는 "화면이 뜨기 전에" 프리로드를 끝내야 캐시 hit(=sync decode)로 쉬머가 안 뜬다.
      // (프리로드가 끝나기 전에 위젯이 먼저 빌드되면, 첫 프레임에서 이미 async로 로드가 시작되어 hit로 전환되지 않음)
      if (content.isNotEmpty && content['nodes'] != null && mounted) {
        try {
          await _postReaderService.preloadTopMedia(
            context,
            content,
            mediaNodeCount: 3,
          );
        } catch (_) {}
      }

      // 🎯 서버에서 받은 content 데이터 로그
      debugPrint('[PostReaderScreen] 🔍 서버 응답 content 키: ${content.keys}');
      if (content.containsKey('nodes')) {
        final nodes = content['nodes'] as List?;
        debugPrint('[PostReaderScreen] 🔍 nodes 개수: ${nodes?.length}');
        // video 노드 찾기
        if (nodes != null) {
          for (final node in nodes) {
            if (node is Map && node['type'] == 'video') {
              debugPrint('[PostReaderScreen] 🎬 서버 응답 video 노드: $node');
              final data = node['data'] as Map?;
              debugPrint('[PostReaderScreen] 🎬 video data: $data');
            }
          }
        }
      }

      // 메타데이터를 content에 병합 (UI에서 사용)
      content['likeCount'] = actualLikeCount;
      content['isLiked'] = actualIsLiked;
      content['commentCount'] = actualCommentCount;
      // 🎯 viewCount도 content에 추가 (서버 응답에서 최신 조회수 제공)
      if (actualViewCount != null) {
        content['viewCount'] = actualViewCount;
      }

      // 🎯 성능 최적화: 이미지 프리로드 제거 (즉시 반환)

      return content;
    } catch (e) {
      // 🎯 본문 로드 실패 시에도 빈 content 반환 (댓글은 비동기로 로드되므로 화면 표시 가능)
      debugPrint('[PostReaderScreen] 본문 로드 실패: $e');
      // 빈 content 반환하여 에러 화면 대신 기본 화면 표시
      return <String, dynamic>{
        'likeCount': widget.exported['likeCount'] as int? ?? 0,
        'isLiked': widget.exported['isLiked'] as bool? ?? false,
        'commentCount': widget.exported['commentCount'] as int? ?? 0,
      };
    }
  }

  @override
  void initState() {
    super.initState();
    // 새 글 진입 시 이전 화면에서 해제한 스포일러 상태를 초기화하여
    // 항상 기본(가려진) 상태로 시작
    try {
      NodeComponentService().clearSpoilers();
    } catch (_) {}

    // 🎯 딥링크로 들어온 경우: preloadedContent를 사용하여 문서 생성
    // 일반 진입: widget.exported 사용 (피드 데이터에 mediaId 포함 가능)
    if (widget.preloadedContent != null) {
      final merged = Map<String, dynamic>.from(widget.exported);
      merged['content'] = widget.preloadedContent;
      _document = _postReaderService.rebuildDocumentForRead(merged);
    } else {
      _document = _postReaderService.rebuildDocumentForRead(widget.exported);
    }

    // 🎯 공개범위 데이터 초기화: widget.exported에서 먼저 읽고, 필요시 서버 조회
    _initializeAccessLevelFromExported();
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _composer,
    );
    _editorService = EditorService(
      editor: _editor,
      document: _document,
      enableInitialStateSave: false, // 🚀 포스트 리더에서는 초기저장 불필요
    );
    _editorService.setDocumentLayoutKey(_layoutKey);
    _dragService = DragService(editorService: _editorService);
    _readOnlyFocus = FocusNode(canRequestFocus: false);
    _scrollCtrl.addListener(_onScroll);

    // PostReaderScreen은 StickerService를 사용하지 않고
    // widget.exported에서 stickers를 직접 읽어 PostReaderStickers에 전달

    // 🎯 이미지 뷰어 애니메이션 초기화
    _imageViewerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _imageViewerFade = CurvedAnimation(
      parent: _imageViewerCtrl,
      curve: Curves.easeOut,
    );

    // 포스트 ID 설정 및 서비스 초기화

    final postId = widget.exported['id']?.toString();
    if (postId != null && postId.isNotEmpty) {
      // 🎯 딥링크로 들어온 경우: 이미 로드된 데이터 사용 (중복 로딩 방지)
      if (widget.preloadedContent != null) {
        debugPrint('[PostReaderScreen] 딥링크로 들어옴 - 이미 로드된 데이터 사용');

        // ✅ 딥링크 진입에서도 상위 3개는 "화면 뜨기 전에" 프리로드를 끝낸다 (캐시 hit 보장)
        _contentFuture = Future(() async {
          final content = widget.preloadedContent;
          if (content != null && content['nodes'] != null && mounted) {
            try {
              await _postReaderService.preloadTopMedia(
                context,
                content,
                mediaNodeCount: 3,
              );
            } catch (_) {}
          }
          return content ?? <String, dynamic>{};
        });

        // 좋아요/댓글 데이터는 이미 딥링크 핸들러에서 초기화됨
        // 공개범위 정보만 업데이트
        final parsed = AccessLevelParser.parseAccessLevelFromContent({
          'content': widget.preloadedContent,
          'accessLevel': widget.exported['accessLevel'],
          'sharedGroupIds': widget.exported['sharedGroupIds'],
          'sharedGroupNames': widget.exported['sharedGroupNames'],
        });
        if (mounted) {
          setState(() {
            _accessLevel = parsed['accessLevel'] as String? ?? 'PUBLIC';
            _sharedGroupIds = parsed['sharedGroupIds'] as List<int>?;
            _sharedGroupNames = parsed['sharedGroupNames'] as List<String>?;
          });
        }
      } else {
        // 일반 진입: 서버에서 데이터 로드
        _commentService.setPostId(postId);

        // 🎯 widget.exported에서 초기 댓글 수 설정 (포스트 목록에서 가져온 값)
        final initialCommentCount =
            widget.exported['commentCount'] as int? ?? 0;
        _commentService.setInitialCommentCount(initialCommentCount);

        // 🎯 성능 최적화: 댓글/좋아요 로드는 비동기로 백그라운드 처리
        Future.microtask(() {
          // 초기 댓글 로드 (비동기, 테스트: 20개)
          _commentService.loadComments(); // 🎯 기본 크기(100개)로 로드

          // 좋아요 사용자 목록 미리 로드 (비동기)
          LikedUsersBottomSheet.preloadLikedUsers(postId).catchError((e) {
            debugPrint('[PostReaderScreen] 좋아요 사용자 목록 미리 로드 실패: $e');
          });
        });

        // 본문 로드만 즉시 처리 (이미지 프리로드 제거)
        _contentFuture = _loadContentWithPreloadedMedia(postId);
      }

      // 0.5초 후 로딩 로고 표시
      Future.delayed(const Duration(milliseconds: 500), () {
        // ✅ 이미 로드가 끝났으면(혹은 곧 오버레이를 내릴 예정이면) 깜빡임 방지
        if (!_isLoadingContent) return;
        if (mounted) {
          setState(() {
            _keepLoadingOverlay = true;
            _showLoadingLogo = true;
          });
        }
      });

      // 🎯 초기 액션 처리 (댓글/좋아요 탭 자동 열기)
      if (widget.initialAction != null) {
        // 🎯 딥링크로 들어온 경우 (preloadedContent 있음): 바로 실행
        // 일반 진입의 경우: _contentFuture 완료 후 실행
        if (widget.preloadedContent != null) {
          // 딥링크: 데이터가 이미 로드되어 있으므로 화면 빌드 완료 후 즉시 실행
          // 애니메이션 컨트롤러가 초기화되도록 두 프레임 대기
          WidgetsBinding.instance.addPostFrameCallback((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                debugPrint('[PostReaderScreen] 🎯 딥링크 - initialAction 즉시 실행');
                if (widget.initialAction ==
                    PostReaderInitialAction.showComments) {
                  _showCommentBottomSheet();
                } else if (widget.initialAction ==
                    PostReaderInitialAction.showLikes) {
                  debugPrint('[PostReaderScreen] 🎯 좋아요 시트는 뷰어에서 처리됨');
                  // 🎯 좋아요 기능은 FullscreenMediaViewer로 이동됨
                }
              }
            });
          });
        } else {
          // 일반 진입: 본문 로드 완료 후 즉시 처리 (최소 딜레이)
          _contentFuture?.then((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // 화면 안정화를 위한 최소 딜레이 (100ms)
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) {
                  if (widget.initialAction ==
                      PostReaderInitialAction.showComments) {
                    _showCommentBottomSheet();
                  } else if (widget.initialAction ==
                      PostReaderInitialAction.showLikes) {
                    // 🎯 좋아요 기능은 FullscreenMediaViewer로 이동됨
                  }
                }
              });
            });
          });
        }
      }
    }

    // 서비스 변경사항 감지
    _commentService.addListener(_onCommentServiceChanged);
    _likeService.addListener(_onLikeServiceChanged);

    try {
      _composer.clearSelection();
    } catch (_) {}
  }

  void _scheduleHideLoadingOverlayAfterEditorLayoutReady() {
    if (_didScheduleLoadingHide) return;
    _didScheduleLoadingHide = true;

    // ✅ 더 이상 "로딩 중"이 아님 (0.5s 타이머가 로고를 띄우지 못하게)
    _isLoadingContent = false;

    // 로고가 아예 안 떴으면(빠른 로드) 스킵
    if (!_keepLoadingOverlay) return;

    int tries = 0;
    const int maxTries = 30; // 약 0.5초@60fps (best-effort)

    void check() {
      if (!mounted) return;

      final ctx = _layoutKey.currentContext;
      final ro = ctx?.findRenderObject();
      final box = ro is RenderBox ? ro : null;

      final bool layoutReady =
          box != null &&
          box.hasSize &&
          box.size.height > 0 &&
          box.size.width > 0;

      if (layoutReady || tries >= maxTries) {
        // ✅ 레이아웃이 잡힌 "다음 프레임"에서 페이드아웃 시작
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _showLoadingLogo = false;
          });
        });

        // ✅ 페이드아웃이 끝난 뒤에만 트리에서 제거
        Future.delayed(_loadingFadeDuration, () {
          if (!mounted) return;
          setState(() {
            _keepLoadingOverlay = false;
          });
        });
        return;
      }

      tries += 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => check());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => check());
  }

  Widget _buildLoadingOverlay({
    required double opacity,
    required bool showBackButton,
    required VoidCallback onBack,
  }) {
    // ✅ "로딩 화면 전체(배경+로고)"를 같이 페이드 아웃
    return AnimatedOpacity(
      opacity: opacity,
      duration: _loadingFadeDuration,
      curve: Curves.easeOut,
      child: Container(
        color: Theme.of(context).colorScheme.background,
        child: DoppyLoadingLogo(
          // 부모 AnimatedOpacity가 페이드를 담당하므로 내부 애니메이션은 끔(중복 페이드 방지)
          opacity: 1.0,
          opacityDuration: Duration.zero,
          showBackButton: showBackButton,
          onBack: onBack,
        ),
      ),
    );
  }

  @override
  void dispose() {
    // 🎯 dispose 순서 중요: 프리로드 중단 → 스크롤 리스너 제거 → 리소스 정리
    _scrollPreloadService.dispose(); // ✅ 남아있는 프리로드 작업 중단
    _scrollCtrl.removeListener(_onScroll); // 🎯 스크롤 리스너 제거 (프리로드 트리거 방지)
    _commentService.removeListener(_onCommentServiceChanged);
    _likeService.removeListener(_onLikeServiceChanged);

    // WebSocket 연결 해제
    _commentService.disconnectWebSocket();

    // 🎯 EditorService dispose (무한 루프 방지)
    _editorService.dispose();
    _readOnlyFocus.dispose();
    _imageViewerCtrl.dispose();

    // ✅ 주의: PostReaderService의 프리로드 캐시는 앱 전역(shared) 캐시다.
    // 여기서 전부 dispose/clear 하면, 홈으로 돌아갔을 때 비디오/썸네일이 다시 로드되며
    // "캐시가 날아간 느낌" + pop 타이밍 레이스로 에러가 터질 수 있다.
    // 따라서 화면 종료 시점에는 reader 전용 컨트롤러만 정리한다.

    // 🎯 reader 모드에서 생성한 모든 비디오 컨트롤러 정지 및 dispose
    // 🎯 VideoCacheService를 통해 reader 네임스페이스의 모든 컨트롤러 일시정지
    try {
      VideoCacheService().pauseAllInNamespace('reader');
      debugPrint(
        '[PostReaderScreen] VideoCacheService를 통한 reader 컨트롤러 일시정지 완료',
      );
    } catch (e) {
      debugPrint('[PostReaderScreen] VideoCacheService 일시정지 오류: $e');
    }

    // 화면 종료 시 스포일러 세션 상태 초기화 (프레임 잠금 중 알림 방지)
    try {
      NodeComponentService().clearSpoilers(notify: false);
    } catch (_) {}

    // ⚠️ ImageCache 사이즈 복원: 읽기 화면 이탈 시 원래 값으로 복원
    // - 다른 화면에서 메모리 압박 방지
    try {
      PostReaderService.restoreImageCacheSize();
    } catch (e) {
      debugPrint('[PostReaderScreen] ImageCache 사이즈 복원 실패: $e');
    }

    super.dispose();
  }

  void _onScroll() {
    final double nextOffset = _scrollCtrl.offset;
    final double delta = nextOffset - _lastScrollOffset;
    const double threshold = 4.0; // 미세 스크롤 무시

    // 🎯 성능 최적화: 스크롤 업데이트 throttling (16ms = 60fps)
    final now = DateTime.now();
    if (_lastScrollUpdate != null &&
        now.difference(_lastScrollUpdate!).inMilliseconds < 16) {
      _lastScrollOffset = nextOffset;
      return; // 너무 자주 업데이트하지 않음
    }
    _lastScrollUpdate = now;

    bool nextShow = _showAppBar;

    if (delta < -threshold) {
      // 위로 스크롤 → 앱바 표시
      nextShow = true;
    } else if (delta > threshold) {
      // 아래로 스크롤 → 앱바 숨김
      nextShow = false;
    }

    // 🎯 스크롤 위치 변경 시 항상 업데이트 (타이틀 표시/숨김을 위해)
    final bool shouldUpdate =
        nextShow != _showAppBar || nextOffset != _currentScrollOffset;

    if (shouldUpdate) {
      // 🎯 성능 최적화: setState를 다음 프레임으로 지연
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _showAppBar = nextShow;
            _currentScrollOffset = nextOffset; // 🎯 현재 스크롤 위치 업데이트
            _previousAppBarState = nextShow; // 🎯 스크롤로 변경된 상태도 저장
            _bottomBarAnimationDuration = 300; // 일반 속도
          });
        }
      });
    }

    // 🎯 뷰포트 기반 프리로드 (서버가 느려서 더 일찍 프리로드)
    if (delta > threshold && // 아래로 스크롤
        _currentExportedData != null &&
        !_scrollPreloadService.isPreloading) {
      // 🎯 스크롤 컨트롤러에서 최대 스크롤 위치 가져오기
      if (_scrollCtrl.hasClients && context.mounted) {
        final maxScroll = _scrollCtrl.position.maxScrollExtent;
        final currentScroll = _scrollCtrl.position.pixels;
        final distanceToBottom = maxScroll - currentScroll;

        // 🎯 뷰포트 기반 임계값 계산 (화면 높이의 배수) - 캐싱으로 성능 최적화
        _cachedScreenHeight ??= MediaQuery.sizeOf(context).height;
        final viewportThreshold =
            _cachedScreenHeight! * _preloadViewportMultiplier;

        // 🎯 뷰포트 기반 또는 하단 거리 기반 중 더 큰 값 사용
        final preloadThreshold =
            viewportThreshold > _preloadBottomThresholdFallback
                ? viewportThreshold
                : _preloadBottomThresholdFallback;

        // 🎯 실제로 스크롤 가능한 컨텐츠가 없으면 프리로드 불필요
        // 🎯 문서 전체 길이가 threshold보다 짧으면 프리로드 안 함 (이미 모든 미디어가 보임)
        if (maxScroll > preloadThreshold &&
            distanceToBottom < preloadThreshold) {
          _scrollPreloadService.preloadNextBatch(
            content: _currentExportedData!,
            context: context,
            mounted: () => mounted,
          );
        }
      }
    }

    _lastScrollOffset = nextOffset;
  }

  // 상단 이미지 제거됨: 배경 이미지 빌더 삭제

  @override
  Widget build(BuildContext context) {
    // 스티커는 아래 FutureBuilder에서 최신 content 기준으로 추출

    final currentUser = context.read<UserProvider>().currentUser;
    final String postAuthor = (widget.exported['author'] ?? '').toString();
    final bool isMyPost =
        currentUser != null && currentUser.username == postAuthor;

    // 🎯 성능 최적화: ThemeProvider를 한 번만 읽어서 변수로 저장
    final isDarkMode =
        context.watch<ThemeProvider>().themeMode == ThemeMode.dark;

    // ✅ iOS "스와이프 백(오른쪽으로 밀어서 뒤로가기)"는 WillPopScope가 있으면 막히는 경우가 많아서,
    // PopScope로 전환하고 필요한 경우에만 pop을 가로챈다.
    final bool interceptPop = _accessLevelChanged;

    // ✅ 중요한 포인트:
    // 키보드가 올라오면(댓글 화면) 앱 루트의 metrics/viewInsets가 변하면서,
    // 뒤에 깔린 Route(PostReader)도 InheritedWidget 변화로 rebuild될 수 있다.
    // PostReader는 키보드와 무관해야 하므로 viewInsets를 0으로 "고정"해서
    // 불필요한 레이아웃/빌드(특히 이미지 LayoutBuilder 로그)를 차단한다.
    final view = View.of(context);
    final frozenMq = MediaQueryData.fromView(
      view,
    ).copyWith(viewInsets: EdgeInsets.zero);

    return MediaQuery(
      data: frozenMq,
      child: PopScope(
        canPop: !interceptPop,
        onPopInvoked: (didPop) {
          if (didPop) return;

          // 1) 공개 범위 변경이 있으면 결과를 포함해서 pop
          if (_accessLevelChanged) {
            Navigator.of(context).pop({
              'accessLevelChanged': true,
              'postId': widget.exported['id']?.toString(),
              'accessLevel': _accessLevel,
              'sharedGroupIds': _sharedGroupIds,
            });
            return;
          }

          // fallback (원칙상 여기로 오면 안 오지만, 안전하게)
          Navigator.of(context).pop();
        },
        child: Scaffold(
          // ✅ 댓글 오버레이에서 키보드를 사용해도, 본문(PostReader) 레이아웃이
          // 키보드(viewInsets)로 인해 다시 레이아웃/리빌드되지 않도록 차단
          resizeToAvoidBottomInset: false,
          backgroundColor: Theme.of(context).colorScheme.background,
          body: FutureBuilder<Map<String, dynamic>>(
            future: _contentFuture,
            builder: (context, snap) {
              // ✅ 로딩 상태: content 로딩 중에만 로딩 로고 표시 (프리로드로 UI를 막지 않음)
              if (snap.connectionState == ConnectionState.waiting) {
                return _buildLoadingOverlay(
                  opacity: _showLoadingLogo ? 1.0 : 0.0,
                  showBackButton: _showLoadingBackButton,
                  onBack: _closeLoadingScreen,
                );
              }

              // ✅ content 로딩 완료: "UI가 안정화된 뒤" 로딩 오버레이를 내리도록 스케줄
              // (동기 프리로드 로직은 그대로 유지)
              _isLoadingContent = false;
              if (_keepLoadingOverlay) {
                _scheduleHideLoadingOverlayAfterEditorLayoutReady();
              }

              if (snap.hasError) {
                return PostReaderErrorScreen(
                  showBackButton: _showErrorBackButton,
                  onBack: _closeErrorScreen,
                );
              }

              // 🎯 본문 로드 실패 시에도 화면 표시 (댓글은 비동기로 로드되므로)
              if (snap.hasData) {
                final contentData = snap.data!;

                // 🎯 빈 content인지 확인 (본문 로드 실패 시 빈 Map 반환됨)
                // content에 'nodes' 키가 없거나 빈 배열이면 본문이 없는 것으로 간주
                final hasValidContent =
                    contentData.containsKey('nodes') &&
                    contentData['nodes'] is List &&
                    (contentData['nodes'] as List).isNotEmpty;

                // 🎯 빈 content이면 에러 화면 표시
                if (!hasValidContent && contentData.length <= 3) {
                  // content가 메타데이터(likeCount, isLiked, commentCount)만 있는 경우
                  return PostReaderErrorScreen(
                    showBackButton: _showErrorBackButton,
                    onBack: _closeErrorScreen,
                  );
                }

                // ✅ 편집 후 _currentExportedData(메타데이터)가 갱신된 상태에서
                // FutureBuilder가 widget.exported(초기값)로 다시 덮어써서 title 등이 되돌아가는 문제 방지.
                // 항상 "현재 메모리 상태"를 우선 베이스로 삼는다.
                final merged = Map<String, dynamic>.from(
                  _currentExportedData ?? widget.exported,
                );
                merged['content'] = contentData;

                // ✅ 상위 3개는 이미 await preloadTopMedia로 끝난 상태.
                // 나머지는 딱 1번만 백그라운드로 프리로드한다(중복/재빌드 방지).
                if (contentData.isNotEmpty &&
                    contentData.containsKey('nodes')) {
                  _startRemainingMediaPreloadOnce(contentData);
                }

                // 🎯 공개범위 정보도 최신 상태로 업데이트 (_loadContentWithPreloadedMedia에서 이미 업데이트됨)
                if (_accessLevel != null) {
                  merged['accessLevel'] = _accessLevel;
                }
                if (_sharedGroupIds != null) {
                  merged['sharedGroupIds'] = _sharedGroupIds;
                }
                if (_sharedGroupNames != null) {
                  merged['sharedGroupNames'] = _sharedGroupNames;
                }

                // 🎯 서버 응답에서 viewCount 업데이트 (서버에서 최신 조회수 제공)
                // snap.data는 content 객체이므로, viewCount가 포함되어 있을 수 있음
                if (snap.data is Map<String, dynamic>) {
                  final contentData = snap.data as Map<String, dynamic>;
                  if (contentData.containsKey('viewCount')) {
                    merged['viewCount'] = contentData['viewCount'];
                  }
                }

                // 최신 데이터 저장 (수정하기에서 사용)
                _currentExportedData = merged;

                // 🎯 딥링크로 들어온 경우: 이미 initState에서 preloadedContent로 문서 생성했으므로 재생성 불필요
                // 일반 진입: 최신 본문으로 문서 재구성 (최초 1회만)
                if (!_documentInitialized && widget.preloadedContent == null) {
                  _document = _postReaderService.rebuildDocumentForRead(merged);
                  _editor = createDefaultDocumentEditor(
                    document: _document,
                    composer: _composer,
                  );
                  _editorService = EditorService(
                    editor: _editor,
                    document: _document,
                    enableInitialStateSave: false, // 🚀 포스트 리더에서는 초기저장 불필요
                  );
                  _editorService.setDocumentLayoutKey(_layoutKey);
                  _dragService = DragService(editorService: _editorService);
                  _documentInitialized = true;
                } else if (widget.preloadedContent != null) {
                  // 딥링크: 이미 initState에서 문서 생성했으므로 플래그만 설정
                  _documentInitialized = true;
                }
              }

              // 스티커 추출: 서버에서 최신 본문(snap.data)이 있으면 그쪽에서,
              // 아니면 최초 exported의 content에서 읽는다
              final Map<String, dynamic> stickersContent =
                  (snap.hasData && (snap.data?.isNotEmpty ?? false))
                      ? (snap.data as Map<String, dynamic>)
                      : ((widget.exported['content']
                              as Map<String, dynamic>?) ??
                          {});
              final List stickers =
                  (stickersContent['stickers'] as List?) ?? const [];

              const double gapHeight = 50;

              return Stack(
                children: [
                  // ✅ 키보드(viewInsets) 변화가 본문(PostReader) 트리까지 전파되면
                  // 이미지/클립 같은 무거운 컴포넌트가 레이아웃/리빌드될 수 있음.
                  // 그래서 본문 트리는 viewInsets를 제거한 MediaQuery로 감싸고,
                  // 댓글 오버레이는 아래에서 별도로 렌더링하여 키보드에만 반응하게 한다.
                  MediaQuery.removeViewInsets(
                    context: context,
                    removeBottom: true,
                    // ✅ PostReaderStickers가 topInset을 계산할 때 기준이 되는 Stack.
                    // stackKey가 실제 트리에 붙어있지 않으면 stackContext가 null이 되어
                    // topInset 측정이 영원히 실패한다.
                    child: Stack(
                      key: _stackKey,
                      children: [
                        // 전체 스크롤
                        NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            return false;
                          },
                          child: GestureDetector(
                            behavior:
                                HitTestBehavior
                                    .translucent, // 🎯 자식이 터치를 소비해도 부모도 받음
                            onTapUp: (details) {
                              _lastTapPosition = details.globalPosition;
                              debugPrint(
                                '[PostReaderScreen] 🖱️ 탭 감지: ${details.globalPosition}',
                              );
                              _handleTap();
                            },
                            child: RawScrollbar(
                              controller: _scrollCtrl,
                              thumbColor: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.3),
                              thickness: 4,
                              radius: const Radius.circular(12),
                              child: CustomScrollView(
                                controller: _scrollCtrl,
                                physics: const ClampingScrollPhysics(),
                                // 🎯 성능 최적화: cacheExtent 설정 (스크롤 성능 향상)
                                cacheExtent: 1000,
                                slivers: [
                                  SliverSafeArea(
                                    top: true,
                                    bottom: false,
                                    sliver: SliverToBoxAdapter(
                                      child: GestureDetector(
                                        onTap: () {
                                          debugPrint('postAuthor: $postAuthor');

                                          if (postAuthor.isEmpty ||
                                              postAuthor ==
                                                  AuthService()
                                                      .currentUsernameSync) {
                                            return;
                                          }

                                          final authorProfileImageUrl =
                                              widget.exported['authorProfileImageUrl']
                                                  as String?;
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder:
                                                  (_) => UserProfileScreen(
                                                    otherUser: User(
                                                      username: postAuthor,
                                                      profileImageUrl:
                                                          authorProfileImageUrl,
                                                    ),
                                                  ),
                                            ),
                                          );
                                        },
                                        child: PostReaderHeader(
                                          exportedRoot: widget.exported,

                                          currentExportedData:
                                              _currentExportedData,
                                          postAuthor: postAuthor,
                                          authorProfileImageUrl:
                                              widget.exported['authorProfileImageUrl']
                                                  as String?,
                                          enableAuthorTap:
                                              !isMyPost &&
                                              widget.exported['authorId'] !=
                                                  null,
                                          onAuthorTap: () {},
                                          horizontalPadding: 20,
                                          topSpacing: 90,
                                          gapHeight: gapHeight,
                                          isMyPost: isMyPost,
                                          likeCount: _likeService
                                              .getPostLikeCount(
                                                widget.exported['id']
                                                        ?.toString() ??
                                                    '',
                                              ),
                                          commentCount:
                                              _commentService
                                                  .getTotalCommentCount(),
                                          onLikeTap: _toggleLike,
                                          onCommentTap: _showCommentBottomSheet,
                                          isLiked: _likeService.isPostLiked(
                                            widget.exported['id']?.toString() ??
                                                '',
                                          ), // ← 추가
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 🎯 문서 시작점 마커 (SuperEditor 바로 앞)
                                  SliverToBoxAdapter(
                                    child: SizedBox(
                                      key: _documentStartMarkerKey,
                                      height: 0,
                                    ),
                                  ),
                                  // SuperEditor 슬리버
                                  Builder(
                                    builder: (context) {
                                      // ✅ 키보드(viewInsets) 변화로 인한 불필요 리빌드를 막기 위해
                                      // MediaQuery.of 대신 aspect 구독(sizeOf) 사용
                                      final screenWidth =
                                          MediaQuery.sizeOf(
                                            context,
                                          ).width; // 🚀 최고 효율: 한 번만 계산
                                      return SuperEditor(
                                        editor: _editor,
                                        stylesheet: buildCustomStylesheet(
                                          context,
                                          isReadOnly:
                                              true, // 🎯 읽기 모드: 전역 폰트 사용 안 함, 블록 metadata만 사용
                                        ),
                                        selectionStyle: SelectionStyles(
                                          selectionColor: Colors.transparent,
                                          highlightEmptyTextBlocks: false,
                                        ),
                                        componentBuilders: [
                                          SingleImageComponentBuilder(
                                            screenWidth:
                                                screenWidth, // 🚀 최고 효율: 전달
                                            dragService: _dragService,
                                            isEditing: false, // 읽기 모드
                                            isDarkMode:
                                                isDarkMode, // 🎯 성능 최적화: 변수 사용
                                          ),
                                          RowImageComponentBuilder(
                                            screenWidth:
                                                screenWidth, // 🚀 최고 효율: 전달
                                            dragService: _dragService,
                                            isEditing: false, // 읽기 모드
                                            isDarkMode:
                                                isDarkMode, // 🎯 성능 최적화: 변수 사용
                                          ),
                                          PageViewImageComponentBuilder(
                                            screenWidth:
                                                screenWidth, // 🚀 최고 효율: 전달
                                            dragService: _dragService,
                                            isEditing: false, // 읽기 모드
                                            isDarkMode: isDarkMode,
                                          ),
                                          LinkComponentBuilder(
                                            isEditing: false,
                                            isDarkMode:
                                                isDarkMode, // 🎯 성능 최적화: 변수 사용
                                          ),
                                          DividerComponentBuilder(),
                                          MentionComponentBuilder(
                                            onMentionTap: (names) {
                                              if (names.isEmpty) return;
                                              if (names.length == 1) {
                                                _openUserProfile(names.first);
                                                return;
                                              }

                                              if (!mounted) return;
                                              // 여러 명이면 선택 바텀시트
                                              MentionBottomSheet.show(
                                                context,
                                                usernames: names,
                                                onUsernameTap: _openUserProfile,
                                              );
                                            },
                                            isDarkMode: isDarkMode,
                                          ),
                                          ClipComponentBuilder(
                                            screenWidth: screenWidth, // 🚀 전달
                                            dragService: _dragService,
                                            isDarkMode: isDarkMode,
                                          ),
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
                                              PostReaderMentionBottomSheet.show(
                                                context,
                                                names: names,
                                                onUsernameTap: _openUserProfile,
                                              );
                                            },
                                          ),
                                          ...defaultComponentBuilders,
                                        ],
                                        documentLayoutKey: _layoutKey,
                                        focusNode: _readOnlyFocus,
                                        gestureMode: DocumentGestureMode.mouse,
                                      );
                                    },
                                  ),
                                  SliverToBoxAdapter(
                                    child: SizedBox(height: 30),
                                  ),

                                  // 댓글 미리보기 (추출된 위젯)
                                  SliverToBoxAdapter(
                                    child: CommentPreviewSection(
                                      commentService: _commentService,
                                      likeService: _likeService,
                                      postId:
                                          widget.exported['id']?.toString() ??
                                          '',
                                      onToggleLike: _toggleLike,
                                      onShowComments: _showCommentBottomSheet,
                                    ),
                                  ),
                                ],
                              ),
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
                              // 🎯 리더에서 스티커가 약간 아래로 치우치는 현상 보정
                              // - 값은 디바이스/레이아웃 변화에 따라 조정 가능
                              positionCorrection: const Offset(0, -26),

                              documentStartMarkerKey:
                                  _documentStartMarkerKey, // 🎯 문서 시작점 자동 측정
                            ),
                          ),
                        ),

                        // 🎯 성능 최적화: BackdropFilter 제거 (스크롤 성능 향상)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 35,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.background.withOpacity(0.95),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                              ),
                            ),
                          ),
                        ),

                        // 동적 AppBar 컴포넌트로 분리
                        Builder(
                          builder: (context) {
                            final double computedBarHeight =
                                // ✅ 키보드(viewInsets) 변화로 인한 불필요 리빌드를 막기 위해
                                // MediaQuery.of 대신 aspect 구독(paddingOf) 사용
                                _appBarHeight +
                                MediaQuery.paddingOf(context).top;
                            return PostReaderAppBar(
                              showAppBar: _showAppBar,
                              barHeight: computedBarHeight,
                              isMyPost: isMyPost,
                              onBack: _closeScreen,
                              onEdit: () async {
                                final dataToEdit =
                                    _currentExportedData ?? widget.exported;
                                final postId =
                                    dataToEdit['id']?.toString() ??
                                    widget.exported['id']?.toString();

                                if (postId == null || postId.isEmpty) {
                                  debugPrint('[PostReaderScreen] postId가 없습니다');
                                  return;
                                }

                                // 편집 화면 열기
                                debugPrint('[PostReaderScreen] 편집 화면 진입');
                                debugPrint(
                                  '  - dataToEdit의 content.nodes: ${((dataToEdit['content'] as Map?)?['nodes'] as List?)?.length ?? 0}개',
                                );

                                // 편집 화면 열기 (저장 성공 여부를 pop result로 받음)
                                final result =
                                    await PostReaderService.openEditScreen(
                                      context,
                                      exportedData: dataToEdit,
                                      postId: postId,
                                    );

                                if (!mounted) return;

                                final resultKeys =
                                    result is Map ? result.keys.toList() : null;
                                debugPrint(
                                  '[PostReaderScreen][EDIT_RESULT] resultType=${result.runtimeType} keys=$resultKeys',
                                );

                                if (result is! Map) return;
                                final bool didEdit =
                                    (result['didEdit'] == true);

                                // 저장/적용이 실제로 일어난 경우에만 최신 문서로 갱신
                                if (!didEdit) return;

                                try {
                                  // ✅ Postwrite에서 로컬 export/content를 pop으로 넘긴 경우
                                  // 추가 서버 호출 없이 pop 결과로 즉시 반영한다.
                                  Map<String, dynamic>? poppedExported;
                                  try {
                                    final raw = result['exported'];
                                    if (raw is Map) {
                                      poppedExported =
                                          raw.cast<String, dynamic>();
                                    }
                                  } catch (_) {
                                    poppedExported = null;
                                  }

                                  Map<String, dynamic>? poppedContent;
                                  try {
                                    final raw = result['content'];
                                    if (raw is Map) {
                                      poppedContent =
                                          raw.cast<String, dynamic>();
                                    }
                                  } catch (_) {
                                    poppedContent = null;
                                  }

                                  late final MutableDocument refreshedDoc;
                                  late final Map<String, dynamic> merged;

                                  debugPrint(
                                    '[PostReaderScreen][EDIT_RESULT] didEdit=$didEdit poppedExported=${poppedExported != null} poppedContent=${poppedContent != null}',
                                  );
                                  if (poppedExported != null) {
                                    debugPrint(
                                      '[PostReaderScreen][EDIT_RESULT] exported.title=${poppedExported['title']} exported.summary=${poppedExported['summary']} exported.thumbnail=${poppedExported['thumbnailImageUrl']} exported.accessLevel=${poppedExported['accessLevel']}',
                                    );
                                  }

                                  if (poppedContent != null ||
                                      poppedExported != null) {
                                    merged = Map<String, dynamic>.from(
                                      dataToEdit,
                                    );
                                    if (poppedExported != null) {
                                      merged.addAll(poppedExported);
                                    }
                                    if (poppedContent != null) {
                                      merged['content'] = poppedContent;
                                    }

                                    refreshedDoc = _postReaderService
                                        .rebuildDocumentForRead(merged);
                                  } else {
                                    // fallback: 서버에서 최신 content 재조회
                                    final (
                                      d,
                                      m,
                                    ) = await PostReaderService.refreshDocumentAfterEdit(
                                      context,
                                      postId,
                                      currentExportedData: dataToEdit,
                                    );
                                    refreshedDoc = d;
                                    merged = m;
                                  }

                                  if (!mounted) return;

                                  final mergedContent =
                                      (merged['content'] as Map?)
                                          ?.cast<String, dynamic>() ??
                                      <String, dynamic>{};

                                  debugPrint(
                                    '[PostReaderScreen][EDIT_APPLY] beforeTitle=${(_currentExportedData?['title'] ?? widget.exported['title'])} afterTitle=${merged['title']}',
                                  );

                                  setState(() {
                                    _currentExportedData = merged;

                                    // 공개범위도 최신으로 동기화
                                    _accessLevel =
                                        (merged['accessLevel'] as String?) ??
                                        _accessLevel;
                                    _sharedGroupIds =
                                        (merged['sharedGroupIds'] as List?)
                                            ?.map((e) => (e as num).toInt())
                                            .toList() ??
                                        _sharedGroupIds;
                                    _sharedGroupNames =
                                        (merged['sharedGroupNames'] as List?)
                                            ?.map((e) => e.toString())
                                            .toList() ??
                                        _sharedGroupNames;

                                    // FutureBuilder도 최신 content를 사용하게 교체
                                    _contentFuture =
                                        Future<Map<String, dynamic>>.value(
                                          mergedContent,
                                        );

                                    // 문서/에디터를 최신 content로 교체
                                    _document = refreshedDoc;
                                    _editor = createDefaultDocumentEditor(
                                      document: _document,
                                      composer: _composer,
                                    );
                                    try {
                                      _editorService.dispose();
                                    } catch (_) {}
                                    _editorService = EditorService(
                                      editor: _editor,
                                      document: _document,
                                      enableInitialStateSave: false,
                                    );
                                    _editorService.setDocumentLayoutKey(
                                      _layoutKey,
                                    );
                                    _dragService = DragService(
                                      editorService: _editorService,
                                    );
                                    _documentInitialized = true;
                                  });
                                } catch (e) {
                                  debugPrint(
                                    '[PostReaderScreen] 수정 후 문서 갱신 실패(무시): $e',
                                  );
                                }
                              },
                              onDelete: _deletePost,
                              onShowComments: _showCommentBottomSheet,
                              title:
                                  (_currentExportedData?['title'] ??
                                          widget.exported['title'] ??
                                          '')
                                      .toString(),
                              likeCount: _likeService.getPostLikeCount(
                                widget.exported['id']?.toString() ?? '',
                              ),
                              commentCount:
                                  _commentService.getTotalCommentCount(),
                              onLikeTap: _toggleLike,
                              onCommentTap: _showCommentBottomSheet,
                              isLiked: _likeService.isPostLiked(
                                widget.exported['id']?.toString() ?? '',
                              ),
                              animationDuration:
                                  _bottomBarAnimationDuration, // 🎯 바텀바와 동일한 속도
                              scrollOffset:
                                  _currentScrollOffset, // 🎯 현재 스크롤 위치 전달
                              viewCount:
                                  int.tryParse(
                                    (_currentExportedData?['viewCount'] ??
                                            widget.exported['viewCount'])
                                        .toString(),
                                  ) ??
                                  0,
                              onViewCountTap: () {
                                // 🎯 나만보기 포스트는 제외
                                final accessLevelStr = _accessLevel ?? 'PUBLIC';
                                if (accessLevelStr != 'PRIVATE') {
                                  _openViewersOverlay();
                                }
                              },
                              isPrivate:
                                  (_accessLevel ?? 'PUBLIC') ==
                                  'PRIVATE', // 🎯 나만보기 포스트 여부
                              onMoreTap:
                                  !isMyPost
                                      ? () {
                                        final postId =
                                            widget.exported['id']?.toString() ??
                                            '';
                                        final postTitle =
                                            (_currentExportedData?['title'] ??
                                                    widget.exported['title'] ??
                                                    '')
                                                .toString();
                                        final authorUsername = postAuthor;
                                        final authorProfileImageUrl =
                                            widget
                                                .exported['authorProfileImageUrl']
                                                ?.toString();
                                        final authorAlias =
                                            widget.exported['authorAlias']
                                                ?.toString();
                                        final thumbnailImageUrl =
                                            widget.exported['thumbnailImageUrl']
                                                ?.toString();
                                        final likeCount = _likeService
                                            .getPostLikeCount(postId);

                                        PostActionBottomSheet.show(
                                          context,
                                          postId: postId,
                                          postTitle: postTitle,
                                          authorUsername: authorUsername,
                                          authorAlias: authorAlias,
                                          authorProfileImageUrl:
                                              authorProfileImageUrl,
                                          thumbnailImageUrl: thumbnailImageUrl,
                                          likeCount: likeCount,
                                          onShowLikedUsers:
                                              null, // 🎯 좋아요 기능은 뷰어로 이동됨
                                        );
                                      }
                                      : null,
                            );
                          },
                        ),
                        // (좋아요/조회자 목록은 Navigator.push로 분리됨)
                        // 전체화면 이미지/영상 뷰어 (페이드 애니메이션)
                        if (_showImageViewer && _currentImageUrl != null)
                          Positioned.fill(
                            child: FadeTransition(
                              opacity: _imageViewerFade,
                              child: FullscreenMediaViewer(
                                imageUrl: _currentImageUrl!,
                                allImageUrls: _allImageUrls,

                                initialIndex:
                                    _currentImageUrl != null &&
                                            _allImageUrls.isNotEmpty
                                        ? _allImageUrls.indexOf(
                                          _currentImageUrl!,
                                        )
                                        : 0,
                                isVideo: _isVideoViewer,
                                preloadedController:
                                    _isVideoViewer && _currentImageUrl != null
                                        ? (VideoCacheService().hasController(
                                              _currentImageUrl!,
                                              namespace: 'reader',
                                            )
                                            ? VideoCacheService()
                                                .getOrCreateController(
                                                  _currentImageUrl!,
                                                  namespace: 'reader',
                                                )
                                            : null)
                                        : null, // 🎯 VideoCacheService에서 컨트롤러 가져오기
                                // ✅ imageProvider 제거: FullscreenMediaViewer 내부에서 EditorImageProvider 사용
                                imageProvider: null,
                                onClose: _closeImageViewer,
                                postTitle: () {
                                  final title =
                                      (_currentExportedData?['title'] ??
                                              widget.exported['title'])
                                          ?.toString();
                                  debugPrint('[PostReader] postTitle: $title');
                                  return title;
                                }(),
                                postAuthor: () {
                                  final author =
                                      widget.exported['author'] as String?;
                                  debugPrint(
                                    '[PostReader] postAuthor: $author',
                                  );
                                  return author;
                                }(),
                                postAuthorProfileUrl: () {
                                  final url =
                                      widget.exported['authorProfileImageUrl']
                                          as String?;
                                  debugPrint(
                                    '[PostReader] postAuthorProfileUrl: $url',
                                  );
                                  return url;
                                }(),
                                commentCount: () {
                                  final count =
                                      widget.exported['commentCount'] as int?;
                                  debugPrint(
                                    '[PostReader] commentCount: $count',
                                  );
                                  debugPrint(
                                    '[PostReader] exported keys: ${widget.exported.keys.toList()}',
                                  );
                                  return count;
                                }(),
                                // 🎯 좋아요 기능 추가
                                postId: widget.exported['id']?.toString(),
                                likeService: _likeService,
                              ),
                            ),
                          ),

                        // 하단 바 (Medium 스타일)
                        AnimatedPositioned(
                          duration: Duration(
                            milliseconds: _bottomBarAnimationDuration,
                          ),
                          curve: Curves.easeInOut,
                          bottom: _showAppBar ? 0 : -100,
                          left: 0,
                          right: 0,
                          child: AnimatedBuilder(
                            animation: Listenable.merge([
                              _likeService,
                              _commentService,
                            ]), // 🎯 두 서비스 모두 감지
                            builder: (context, child) {
                              final postId =
                                  widget.exported['id']?.toString() ?? '';
                              final isLiked = _likeService.isPostLiked(postId);
                              final likeCount = _likeService.getPostLikeCount(
                                postId,
                              );
                              final commentCount =
                                  _commentService.getTotalCommentCount();

                              // isMyPost 확인
                              final currentUser =
                                  context.read<UserProvider>().currentUser;
                              final String postAuthor =
                                  (widget.exported['author'] ?? '').toString();
                              final bool isMyPost =
                                  currentUser != null &&
                                  currentUser.username == postAuthor;

                              // 🎯 나만보기 포스트 확인
                              final accessLevelStr =
                                  _accessLevel ?? AccessLevel.public;
                              final isPrivate =
                                  accessLevelStr == AccessLevel.private;

                              return Container(
                                height: 74,
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).colorScheme.background,

                                  border: Border(
                                    top: BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.1),
                                      width: 1,
                                    ),
                                  ),
                                ),

                                child: SafeArea(
                                  top: false,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: 20,
                                      right: 20,
                                      top: 15,
                                    ),
                                    child: Row(
                                      children: [
                                        // 공유 아이콘 또는 자물쇠 아이콘
                                        GestureDetector(
                                          onTap:
                                              isMyPost
                                                  ? _handleAccessLevelOrShare
                                                  : _showShareOverlay,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8.0,
                                              top: 1,
                                            ),
                                            child: _buildAccessLevelIcon(
                                              context,
                                            ),
                                          ),
                                        ),

                                        // 내 포스트이고 나만보기가 아닌 경우 lock_open.svg 추가
                                        if (isMyPost) ...[
                                          Consumer<GroupProvider>(
                                            builder: (
                                              context,
                                              groupProvider,
                                              _,
                                            ) {
                                              // 🎯 서버에서 조회한 공개범위 데이터 사용
                                              final accessLevelStr =
                                                  _accessLevel ?? 'PUBLIC';
                                              final isPrivate =
                                                  accessLevelStr == 'PRIVATE';

                                              // 🎯 GROUPS인 경우 실제 그룹 이름 가져오기
                                              // 🎯 서버에서 제공하는 sharedGroupNames 우선 사용
                                              String? groupName;
                                              if (accessLevelStr == 'GROUPS') {
                                                if (_sharedGroupNames != null &&
                                                    _sharedGroupNames!
                                                        .isNotEmpty) {
                                                  // 🎯 서버에서 받은 그룹 이름 직접 사용
                                                  if (_sharedGroupNames!
                                                          .length ==
                                                      1) {
                                                    groupName =
                                                        _sharedGroupNames!
                                                            .first;
                                                  } else {
                                                    groupName = context
                                                        .tr('groups_count')
                                                        .replaceAll(
                                                          '{count}',
                                                          '${_sharedGroupNames!.length}',
                                                        );
                                                  }
                                                } else if (_sharedGroupIds !=
                                                        null &&
                                                    _sharedGroupIds!
                                                        .isNotEmpty) {
                                                  // 🎯 sharedGroupNames가 없으면 GroupProvider에서 찾기 (fallback)
                                                  final groups =
                                                      groupProvider.myGroups;
                                                  final matchingGroups =
                                                      groups
                                                          .where(
                                                            (g) =>
                                                                _sharedGroupIds!
                                                                    .contains(
                                                                      g.id,
                                                                    ),
                                                          )
                                                          .toList();

                                                  if (matchingGroups
                                                      .isNotEmpty) {
                                                    if (matchingGroups.length ==
                                                        1) {
                                                      final group =
                                                          matchingGroups.first;
                                                      if (group.isSystem ==
                                                          true) {
                                                        groupName = context.tr(
                                                          'all_friends',
                                                        );
                                                      } else {
                                                        groupName = group.name;
                                                      }
                                                    } else {
                                                      groupName = context
                                                          .tr('groups_count')
                                                          .replaceAll(
                                                            '{count}',
                                                            '${matchingGroups.length}',
                                                          );
                                                    }
                                                  }
                                                }
                                              }

                                              // 나만보기가 아닌 경우에만 lock_open.svg 표시
                                              if (!isPrivate) {
                                                return GestureDetector(
                                                  onTap:
                                                      _showAccessLevelBottomSheet,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: 20.0,
                                                          top: 1,
                                                        ),
                                                    child:
                                                        groupName != null
                                                            ? Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                SvgPicture.asset(
                                                                  'assets/icons/lock_open.svg',
                                                                  width: 23,
                                                                  height: 23,
                                                                  color: Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onSurface
                                                                      .withOpacity(
                                                                        0.7,
                                                                      ),
                                                                ),
                                                              ],
                                                            )
                                                            : SvgPicture.asset(
                                                              'assets/icons/lock_open.svg',
                                                              width: 23,
                                                              height: 23,
                                                              color: Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .onSurface
                                                                  .withOpacity(
                                                                    0.7,
                                                                  ),
                                                            ),
                                                  ),
                                                );
                                              }
                                              return const SizedBox.shrink();
                                            },
                                          ),
                                        ],

                                        const Spacer(),
                                        // 우측: 좋아요 + 댓글 (나만보기 포스트 제외)
                                        if (!isPrivate) ...[
                                          GestureDetector(
                                            onTap: _toggleLike,
                                            // 🎯 좋아요한 사람 목록은 뷰어에서 처리됨
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SvgPicture.asset(
                                                  'assets/icons/heart.svg',
                                                  width: 22,
                                                  height: 22,
                                                  color:
                                                      isLiked
                                                          ? const ui.Color.fromARGB(
                                                            255,
                                                            255,
                                                            89,
                                                            89,
                                                          )
                                                          : Theme.of(context)
                                                              .colorScheme
                                                              .onSurface
                                                              .withOpacity(0.8),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  formatCount(likeCount),
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color:
                                                        isLiked
                                                            ? const ui.Color.fromARGB(
                                                              255,
                                                              255,
                                                              89,
                                                              89,
                                                            )
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .onSurface
                                                                .withOpacity(
                                                                  0.8,
                                                                ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 20),
                                        ],
                                        GestureDetector(
                                          onTap: _showCommentBottomSheet,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 0.8,
                                                ),
                                                child: SvgPicture.asset(
                                                  'assets/icons/comment.svg',
                                                  width: 24,
                                                  height: 24,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withOpacity(0.8),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                formatCount(commentCount),
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withOpacity(0.8),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ✅ 댓글 Glass 카드 오버레이: 키보드(viewInsets)에 반응해야 하므로
                  // removeViewInsets 래퍼 밖에서 렌더링한다.
                  // 댓글 화면은 Route(push)로 분리되어 오버레이로 렌더링하지 않음

                  // 🎯 로딩 로고 오버레이: content는 이미 준비됐지만, 에디터 레이아웃 안정화까지 유지
                  if (_keepLoadingOverlay)
                    Positioned.fill(
                      child: IgnorePointer(
                        // 투명해지면 터치 통과
                        ignoring: !_showLoadingLogo,
                        child: _buildLoadingOverlay(
                          opacity: _showLoadingLogo ? 1.0 : 0.0,
                          showBackButton: _showLoadingBackButton,
                          onBack: _closeLoadingScreen,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _openUserProfile(String username) {
    if (username.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(otherUser: User(username: username)),
      ),
    );
  }
}
