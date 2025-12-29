import 'dart:ui' as ui;
import 'dart:async';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/single_image_component.dart';
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
import 'package:doppy/editor/postwrite_screen.dart';
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
import 'package:doppy/utils/dialog_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';

// 읽기 전용에서는 에디터 전용 컴포넌트를 사용하지 않음
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/component/paragraph_component.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show
        ClipNode,
        videoPlayerControllers,
        ClipComponentBuilder,
        readerVideoControllers;
import 'package:video_player/video_player.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/post_reader_service.dart';
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
  final BlogService _blogService = BlogService();
  final PostReaderService _postReaderService = PostReaderService();
  Future<Map<String, dynamic>>? _contentFuture;
  Map<String, dynamic>? _currentExportedData; // 최신 컨텐츠를 저장
  bool _showLoadingLogo = false; // 로딩 로고 표시 여부
  bool _isRenderReady = false; // 스포일러 마스크 렌더링 완료 여부
  bool _accessLevelChanged = false; // 🎯 공개 범위 변경 여부
  bool _documentInitialized = false; // 🎯 문서 초기화 완료 플래그 (재생성 방지)
  bool _topMediaPreloaded = false; // 🎯 상위 3개 노드 미디어 프리로드 완료 여부
  DateTime? _preloadStartTime; // 🎯 프리로드 시작 시간 (최소 로딩 시간 보장용)

  // 스크롤 애니메이션을 위한 변수들
  static const double _appBarHeight = 52.0; // AppBar 높이
  double _lastScrollOffset = 0.0;
  DateTime? _lastScrollUpdate; // 🎯 스크롤 업데이트 throttling용

  // 앱바 표시/숨김을 위한 변수들
  bool _showAppBar = true; // 상단 이미지 제거 → 기본 표시
  int _bottomBarAnimationDuration = 300; // 하단 바 애니메이션 속도 (ms)
  bool _previousAppBarState = true; // 🎯 풀스크린/오버레이 진입 전 앱바 상태 저장
  double _currentScrollOffset = 0.0; // 🎯 현재 스크롤 위치 (타이틀 표시용)
  bool _showLoadingBackButton = true; // 🎯 로딩 화면 뒤로가기 버튼 표시 여부
  bool _showErrorBackButton = true; // 🎯 에러 화면 뒤로가기 버튼 표시 여부

  // 순차 애니메이션 제거

  // 댓글 화면은 Route(push)로 분리하여 표시 (오버레이 제거)

  // 좋아요 사용자 목록 오버레이 상태/애니메이션
  bool _showLikedUsersOverlay = false;
  late final AnimationController _likedUsersOverlayCtrl;
  late final Animation<double> _likedUsersFade;

  // 본 사람 목록 오버레이 상태/애니메이션
  bool _showViewersOverlay = false;
  late final AnimationController _viewersOverlayCtrl;
  late final Animation<double> _viewersFade;

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
        // 🎯 ClipComponent에서 생성한 컨트롤러를 가져와서 FullscreenMediaViewer에 전달
        final controller = readerVideoControllers[clipNode.url];
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
    } else if (node is ParagraphNode) {
      final paragraphNode = node;

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
    }
    // default: 알 수 없는 노드 타입 (처리 안 함)
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
    if (_showLikedUsersOverlay) {
      _closeLikedUsersOverlay();
      return;
    }

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
                      title: widget.exported['title'] ?? '',
                      commentService: _commentService,
                      postThumbnailUrl:
                          widget.exported['thumbnailImageUrl']?.toString(),
                      postSummary: widget.exported['summary']?.toString(),
                      scrollToCommentId: widget.scrollToCommentId,
                      postAuthorUsername:
                          widget.exported['author']
                              ?.toString(), // 🎯 블로그 작성자 username
                    ),
              )
              : MaterialPageRoute(
                builder:
                    (_) => CommentBottomSheet(
                      title: widget.exported['title'] ?? '',
                      commentService: _commentService,
                      postThumbnailUrl:
                          widget.exported['thumbnailImageUrl']?.toString(),
                      postSummary: widget.exported['summary']?.toString(),
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

  // 🎯 좋아요 사용자 목록 오버레이 표시
  void _openLikedUsersOverlay() {
    setState(() {
      _previousAppBarState = _showAppBar; // 🎯 현재 상태 저장
      _showLikedUsersOverlay = true;
      _showAppBar = false; // 하단 바 숨김
      _bottomBarAnimationDuration = 50; // 빠르게 숨김
    });

    // 🎯 애니메이션 컨트롤러 리셋 후 forward
    _likedUsersOverlayCtrl.reset();
    _likedUsersOverlayCtrl.forward(from: 0.0);
  }

  // 🎯 좋아요 사용자 목록 오버레이 닫기
  void _closeLikedUsersOverlay() {
    _likedUsersOverlayCtrl.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() {
        _showLikedUsersOverlay = false;
        _showAppBar = _previousAppBarState; // 🎯 이전 상태로 복원
        _bottomBarAnimationDuration =
            _previousAppBarState ? 0 : 300; // 🎯 열려있었으면 즉시(0), 닫혀있었으면 일반 속도
      });
    });
  }

  // 🎯 본 사람 목록 오버레이 표시
  void _openViewersOverlay() {
    setState(() {
      _previousAppBarState = _showAppBar; // 🎯 현재 상태 저장
      _showViewersOverlay = true;
      _showAppBar = false; // 하단 바 숨김
      _bottomBarAnimationDuration = 50; // 빠르게 숨김
    });

    // 🎯 애니메이션 컨트롤러 리셋 후 forward
    _viewersOverlayCtrl.reset();
    _viewersOverlayCtrl.forward(from: 0.0);
  }

  // 🎯 본 사람 목록 오버레이 닫기
  void _closeViewersOverlay() {
    _viewersOverlayCtrl.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() {
        _showViewersOverlay = false;
        _showAppBar = _previousAppBarState; // 🎯 이전 상태로 복원
        _bottomBarAnimationDuration =
            _previousAppBarState ? 0 : 300; // 🎯 열려있었으면 즉시(0), 닫혀있었으면 일반 속도
      });
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

      // 🎯 모든 비디오 + 상위 3개 이미지 동기 프리로드 (shimmer 방지)
      if (content.isNotEmpty && content['nodes'] != null && mounted) {
        debugPrint('[PostReaderScreen] 🚀 서버 응답 후 미디어 프리로드 시작');
        _preloadStartTime = DateTime.now();

        try {
          // 🎯 첫 텍스트 제외 후, 첫 3개 미디어 노드 프리로드 (이미지 + 비디오)
          await _postReaderService.preloadTopMedia(
            context,
            content,
            mediaNodeCount: 3,
          );

          // 🎯 나머지 비디오 프리로드 (첫 3개 미디어 노드 이후)
          final allClipUrls = _postReaderService.extractClipUrls(content);
          final topClipUrls = _postReaderService.extractTopClipUrls(
            content,
            mediaNodeCount: 3,
          );
          final remainingClips =
              allClipUrls.where((url) => !topClipUrls.contains(url)).toList();

          if (remainingClips.isNotEmpty) {
            debugPrint(
              '[PostReaderScreen] 🎬 나머지 비디오 프리로드 시작 (${remainingClips.length}개)',
            );
            final videoFutures = <Future>[];
            for (final url in remainingClips) {
              videoFutures.add(
                PostReaderService.preloadVideoForReader(url).catchError((e) {
                  debugPrint('[PostReaderScreen] 비디오 프리로드 실패: $url');
                }),
              );
            }
            await Future.wait(videoFutures, eagerError: false);
          }

          final elapsed = DateTime.now().difference(_preloadStartTime!);
          debugPrint(
            '[PostReaderScreen] ✅ 서버 응답 후 상위 미디어 프리로드 완료 (${elapsed.inMilliseconds}ms)',
          );

          // 🎯 최소 로딩 시간 보장 (600ms) - 프리로드 완료 체감
          const minLoadingDuration = Duration(milliseconds: 600);
          if (elapsed < minLoadingDuration) {
            final remaining = minLoadingDuration - elapsed;
            debugPrint(
              '[PostReaderScreen] ⏳ 최소 로딩 대기: ${remaining.inMilliseconds}ms',
            );
            await Future.delayed(remaining);
          }

          if (mounted) {
            setState(() {
              _topMediaPreloaded = true;
            });
          }
        } catch (e) {
          debugPrint('[PostReaderScreen] ❌ 서버 응답 후 상위 미디어 프리로드 실패: $e');
          // 실패해도 로딩 해제
          if (mounted) {
            setState(() {
              _topMediaPreloaded = true;
            });
          }
        }
      } else {
        // content가 없으면 바로 완료 처리
        if (mounted) {
          setState(() {
            _topMediaPreloaded = true;
          });
        }
      }

      // 🎯 나머지 이미지 백그라운드 프리로드 (비디오는 이미 완료)
      if (content.isNotEmpty && mounted) {
        final imageUrls = _postReaderService.extractImageUrls(content);
        if (imageUrls.isNotEmpty) {
          // 첫 3개 미디어 노드 내 이미지는 이미 프리로드했으므로 나머지만
          final topImageUrls = _postReaderService.extractTopImageUrls(
            content,
            mediaNodeCount: 3,
          );
          final remainingImages =
              imageUrls.where((url) => !topImageUrls.contains(url)).toList();

          if (remainingImages.isNotEmpty) {
            Future.microtask(() async {
              if (mounted) {
                await _postReaderService.preloadImages(
                  context,
                  remainingImages,
                  maxCount: remainingImages.length,
                );
                debugPrint(
                  '[PostReaderScreen] ✅ 나머지 이미지 프리로드 완료 (${remainingImages.length}개)',
                );
              }
            });
          }
        }
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

    // 🎯 상위 3개 노드 미디어 프리로드 (로딩 로고 표시 중)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // widget.exported['content'] 또는 widget.preloadedContent 사용
      final content =
          widget.preloadedContent ??
          (widget.exported['content'] as Map<String, dynamic>?);

      if (content != null && content['nodes'] != null) {
        debugPrint('[PostReaderScreen] 🚀 미디어 프리로드 시작 (initState)');
        _preloadStartTime = DateTime.now();

        // 🎯 모든 비디오 + 첫 3개 미디어 노드 이미지 프리로드
        Future(() async {
          // 🎯 첫 텍스트 제외 후, 첫 3개 미디어 노드 프리로드 (이미지 + 비디오)
          await _postReaderService.preloadTopMedia(
            context,
            content,
            mediaNodeCount: 3,
          );

          // 🎯 나머지 비디오 프리로드 (첫 3개 미디어 노드 이후)
          final allClipUrls = _postReaderService.extractClipUrls(content);
          final topClipUrls = _postReaderService.extractTopClipUrls(
            content,
            mediaNodeCount: 3,
          );
          final remainingClips =
              allClipUrls.where((url) => !topClipUrls.contains(url)).toList();

          if (remainingClips.isNotEmpty) {
            debugPrint(
              '[PostReaderScreen] 🎬 나머지 비디오 프리로드 시작 (${remainingClips.length}개)',
            );
            final videoFutures = <Future>[];
            for (final url in remainingClips) {
              videoFutures.add(
                PostReaderService.preloadVideoForReader(url).catchError((e) {
                  debugPrint('[PostReaderScreen] 비디오 프리로드 실패: $url');
                }),
              );
            }
            await Future.wait(videoFutures, eagerError: false);
          }

          final elapsed = DateTime.now().difference(_preloadStartTime!);
          debugPrint(
            '[PostReaderScreen] ✅ 미디어 프리로드 완료 (initState, ${elapsed.inMilliseconds}ms)',
          );

          // 최소 로딩 시간 보장
          const minLoadingDuration = Duration(milliseconds: 600);
          if (elapsed < minLoadingDuration) {
            await Future.delayed(minLoadingDuration - elapsed);
          }

          if (mounted) {
            setState(() => _topMediaPreloaded = true);
          }
        }).catchError((e) {
          debugPrint('[PostReaderScreen] ❌ 미디어 프리로드 실패 (initState): $e');
          if (mounted) {
            setState(() => _topMediaPreloaded = true);
          }
        });
      } else {
        debugPrint(
          '[PostReaderScreen] ⚠️ initState에서 content 없음 - 서버 응답 후 프리로드',
        );
      }
    });

    // PostReaderScreen은 StickerService를 사용하지 않고
    // widget.exported에서 stickers를 직접 읽어 PostReaderStickers에 전달

    // 🎯 좋아요 사용자 목록 오버레이 애니메이션 초기화
    _likedUsersOverlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _likedUsersFade = CurvedAnimation(
      parent: _likedUsersOverlayCtrl,
      curve: Curves.easeOutCubic,
    );

    // 🎯 조회자 목록 오버레이 애니메이션 초기화
    _viewersOverlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _viewersFade = CurvedAnimation(
      parent: _viewersOverlayCtrl,
      curve: Curves.easeOutCubic,
    );

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

        // 이미 로드된 content를 Future로 감싸서 반환
        _contentFuture = Future.value(widget.preloadedContent);

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

        // 🎯 첫 10개 이미지 빠르게 병렬 프리로드 (딥링크 진입 시)
        if (mounted && widget.preloadedContent != null) {
          final imageUrls = _postReaderService.extractImageUrls(
            widget.preloadedContent!,
          );
          if (imageUrls.isNotEmpty) {
            // 첫 10개 이미지를 빠르게 병렬 프리로드
            final first10Images = imageUrls.take(10).toList();
            Future.microtask(() async {
              if (mounted) {
                await _postReaderService.preloadImages(
                  context,
                  first10Images,
                  maxCount: 10,
                );
                debugPrint('[PostReaderScreen] ✅ 첫 10개 이미지 프리로드 완료 (딥링크)');
              }
            });

            // 나머지 이미지도 백그라운드에서 계속 로드
            if (imageUrls.length > 10) {
              final remainingImages = imageUrls.skip(10).toList();
              Future.microtask(() async {
                if (mounted) {
                  await _postReaderService.preloadImages(
                    context,
                    remainingImages,
                    maxCount: remainingImages.length,
                  );
                  debugPrint('[PostReaderScreen] ✅ 나머지 이미지 프리로드 완료 (딥링크)');
                }
              });
            }
          }
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
        if (mounted) {
          setState(() {
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
                  debugPrint('[PostReaderScreen] 🎯 좋아요 시트 즉시 열기');
                  _openLikedUsersOverlay();
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
                    _openLikedUsersOverlay();
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

  @override
  void dispose() {
    _commentService.removeListener(_onCommentServiceChanged);
    _likeService.removeListener(_onLikeServiceChanged);

    // WebSocket 연결 해제
    _commentService.disconnectWebSocket();

    _readOnlyFocus.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _likedUsersOverlayCtrl.dispose();
    _imageViewerCtrl.dispose();

    // 프리로드된 비디오 컨트롤러 정리 (구버전 호환)
    PostReaderService.disposeAllPreloaded();
    debugPrint('[PostReaderScreen] 프리로드 컨트롤러 모두 정리');

    // 🎯 reader 모드에서 생성한 모든 비디오 컨트롤러 정지 및 dispose
    // 먼저 목록을 복사 (dispose 중에 맵이 변경될 수 있음)
    final controllersToDispose = <VideoPlayerController>[];
    final urlsToRemove = <String>[];

    for (final entry in readerVideoControllers.entries) {
      controllersToDispose.add(entry.value);
      urlsToRemove.add(entry.key);
    }

    // 모든 컨트롤러 정지 및 dispose
    for (int i = 0; i < controllersToDispose.length; i++) {
      final controller = controllersToDispose[i];
      final url = urlsToRemove[i];
      try {
        if (controller.value.isInitialized) {
          // 일시정지
          if (controller.value.isPlaying) {
            controller.pause();
            debugPrint('[PostReaderScreen] 컨트롤러 일시정지: $url');
          }
          // 리스너 제거 시도
          try {
            controller.removeListener(() {});
          } catch (_) {}
          // dispose
          controller.dispose();
          debugPrint('[PostReaderScreen] 컨트롤러 dispose: $url');
        }
      } catch (e) {
        debugPrint('[PostReaderScreen] 컨트롤러 정리 오류 ($url): $e');
      }
    }

    // 맵 clear
    readerVideoControllers.clear();
    debugPrint(
      '[PostReaderScreen] reader 비디오 컨트롤러 모두 정리 완료 (${controllersToDispose.length}개)',
    );

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
    final bool interceptPop = _showLikedUsersOverlay || _accessLevelChanged;

    return PopScope(
      canPop: !interceptPop,
      onPopInvoked: (didPop) {
        if (didPop) return;

        // 1) 오버레이가 열려 있으면 먼저 닫기
        if (_showLikedUsersOverlay) {
          _closeLikedUsersOverlay();
          return;
        }

        // 2) 공개 범위 변경이 있으면 결과를 포함해서 pop
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
            // 🎯 로딩 상태: content 로딩 중이거나 상위 미디어 프리로드 중
            final isLoading =
                snap.connectionState == ConnectionState.waiting ||
                (snap.hasData && !_topMediaPreloaded);

            if (isLoading) {
              return DoppyLoadingLogo(
                opacity: _showLoadingLogo ? 1.0 : 0.0,
                showBackButton: _showLoadingBackButton,
                onBack: _closeLoadingScreen,
              );
            }

            // ✅ 데이터/미디어 선행 준비 후 약간 더 대기하여 첫 프레임 안정화
            if (snap.hasData && !_isRenderReady && _topMediaPreloaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  debugPrint('[PostReaderScreen] 🎨 렌더링 준비 완료');
                  setState(() => _isRenderReady = true);
                }
              });
              return DoppyLoadingLogo(
                opacity: _showLoadingLogo ? 1.0 : 0.0,
                showBackButton: _showLoadingBackButton,
                onBack: _closeLoadingScreen,
              );
            }
            if (snap.hasError) {
              return Scaffold(
                // ✅ 에러 화면에서도 키보드(viewInsets)로 인한 불필요 레이아웃 변경 차단
                resizeToAvoidBottomInset: false,
                backgroundColor: Theme.of(context).colorScheme.background,
                appBar:
                    _showErrorBackButton
                        ? AppBar(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          leading: Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: IconButton(
                              icon: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 24,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.75),
                              ),
                              onPressed: _closeErrorScreen,
                            ),
                          ),
                        )
                        : AppBar(
                          automaticallyImplyLeading: false,
                          backgroundColor: Colors.transparent,
                          elevation: 0,
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
                        const SizedBox(height: 15),
                      ],
                    ),
                  ),
                ),
              );
            }

            // 🎯 본문 로드 실패 시에도 화면 표시 (댓글은 비동기로 로드되므로)
            if (snap.hasData) {
              final merged = Map<String, dynamic>.from(widget.exported);
              merged['content'] = snap.data!;

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
                    : ((widget.exported['content'] as Map<String, dynamic>?) ??
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
                  child: Stack(
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
                                            widget.exported['authorId'] != null,
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
                                            showModalBottomSheet(
                                              context: context,
                                              backgroundColor:
                                                  Colors.transparent,
                                              builder: (_) {
                                                return Container(
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.surface,
                                                    borderRadius:
                                                        const BorderRadius.vertical(
                                                          top: Radius.circular(
                                                            16,
                                                          ),
                                                        ),
                                                  ),
                                                  child: SafeArea(
                                                    top: false,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Container(
                                                          width: 40,
                                                          height: 4,
                                                          decoration: BoxDecoration(
                                                            color: Theme.of(
                                                                  context,
                                                                )
                                                                .colorScheme
                                                                .onSurface
                                                                .withOpacity(
                                                                  0.2,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  2,
                                                                ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        ...names.map(
                                                          (u) => ListTile(
                                                            title: Text(
                                                              '@$u',
                                                              style: TextStyle(
                                                                color:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .onSurface,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            onTap: () {
                                                              Navigator.of(
                                                                context,
                                                              ).pop();
                                                              _openUserProfile(
                                                                u,
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
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
                                    );
                                  },
                                ),
                                SliverToBoxAdapter(
                                  child: SizedBox(height: 100),
                                ),

                                // 댓글 미리보기 (추출된 위젯)
                                SliverToBoxAdapter(
                                  child: CommentPreviewSection(
                                    commentService: _commentService,
                                    likeService: _likeService,
                                    postId:
                                        widget.exported['id']?.toString() ?? '',
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

                            topInset: (_appBarHeight + gapHeight),
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
                              _appBarHeight + MediaQuery.paddingOf(context).top;
                          return PostReaderAppBar(
                            showAppBar: _showAppBar,
                            barHeight: computedBarHeight,
                            isMyPost: isMyPost,
                            onBack: _closeScreen,
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
                                        (
                                          context,
                                          animation,
                                          secondaryAnimation,
                                        ) => PostwriteScreen(
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
                                debugPrint('[PostReaderScreen] postId가 없습니다');
                              }
                            },
                            onDelete: _deletePost,
                            onShowComments: _showCommentBottomSheet,
                            title: widget.exported['title'] ?? '',
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
                                          widget.exported['title']
                                              ?.toString() ??
                                          '';
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
                                            _openLikedUsersOverlay,
                                      );
                                    }
                                    : null,
                          );
                        },
                      ),
                      // (댓글 오버레이는 viewInsets를 받아야 하므로 바깥 Stack에서 렌더링)
                      // 좋아요 사용자 목록 오버레이
                      if (_showLikedUsersOverlay)
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _likedUsersFade,
                            builder: (context, _) {
                              return Opacity(
                                opacity: _likedUsersFade.value,
                                child: LikedUsersBottomSheet(
                                  postId:
                                      widget.exported['id']?.toString() ?? '',
                                  likeCount: _likeService.getPostLikeCount(
                                    widget.exported['id']?.toString() ?? '',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      // 조회자 목록 오버레이
                      if (_showViewersOverlay)
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _viewersFade,
                            builder: (context, _) {
                              return Opacity(
                                opacity: _viewersFade.value,
                                child: ViewersBottomSheet(
                                  postId:
                                      widget.exported['id']?.toString() ?? '',
                                  viewerCount: int.parse(
                                    (_currentExportedData?['viewCount'] ??
                                            widget.exported['viewCount'])
                                        .toString(),
                                  ),
                                  onClose: _closeViewersOverlay,
                                ),
                              );
                            },
                          ),
                        ),
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
                                      ? _allImageUrls.indexOf(_currentImageUrl!)
                                      : 0,
                              isVideo: _isVideoViewer,
                              preloadedController:
                                  _isVideoViewer && _currentImageUrl != null
                                      ? readerVideoControllers[_currentImageUrl!]
                                      : null, // 🎯 ClipComponent에서 생성한 컨트롤러 공유
                              imageProvider:
                                  !_isVideoViewer && _currentImageUrl != null
                                      ? NetworkImage(_currentImageUrl!)
                                      : null, // 🎯 NetworkImage 인스턴스 직접 생성
                              onClose: _closeImageViewer,
                              postTitle: () {
                                final title =
                                    widget.exported['title'] as String?;
                                debugPrint('[PostReader] postTitle: $title');
                                return title;
                              }(),
                              postAuthor: () {
                                final author =
                                    widget.exported['author'] as String?;
                                debugPrint('[PostReader] postAuthor: $author');
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
                                debugPrint('[PostReader] commentCount: $count');
                                debugPrint(
                                  '[PostReader] exported keys: ${widget.exported.keys.toList()}',
                                );
                                return count;
                              }(),
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
                                color: Theme.of(context).colorScheme.background,

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
                                          child: _buildAccessLevelIcon(context),
                                        ),
                                      ),

                                      // 내 포스트이고 나만보기가 아닌 경우 lock_open.svg 추가
                                      if (isMyPost) ...[
                                        Consumer<GroupProvider>(
                                          builder: (context, groupProvider, _) {
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
                                                if (_sharedGroupNames!.length ==
                                                    1) {
                                                  groupName =
                                                      _sharedGroupNames!.first;
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
                                                  _sharedGroupIds!.isNotEmpty) {
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

                                                if (matchingGroups.isNotEmpty) {
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
                                          onLongPress: _openLikedUsersOverlay,
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
                                                              .withOpacity(0.8),
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
        builder: (_) => UserProfileScreen(otherUser: User(username: username)),
      ),
    );
  }
}
