import 'dart:ui' as ui;
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
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
import 'package:doppy/pages/components/post_action_bottom_sheet.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';

// 읽기 전용에서는 에디터 전용 컴포넌트를 사용하지 않음
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/component/paragraph_component.dart';
import 'package:doppy/editor/component/clip_component.dart'
    show ClipNode, videoPlayerControllers, ClipComponentBuilder;
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
  });
  final Map<String, dynamic> exported;
  final String? heroTag; // 홈 썸네일과 자연스러운 연결(Hero)
  final bool fromProfile; // 프로필에서 들어왔는지 여부

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
  bool _accessLevelChanged = false; // 🎯 공개 범위 변경 여부
  bool _documentInitialized = false; // 🎯 문서 초기화 완료 플래그 (재생성 방지)

  // 스크롤 애니메이션을 위한 변수들
  static const double _appBarHeight = 52.0; // AppBar 높이
  double _lastScrollOffset = 0.0;
  double _pullAccum = 0.0; // 상단에서 아래로 당겨 닫기 누적 거리
  double _horizontalDragDistance = 0.0; // 오른쪽으로 밀어 닫기 누적 거리

  // 앱바 표시/숨김을 위한 변수들
  bool _showAppBar = true; // 상단 이미지 제거 → 기본 표시
  int _bottomBarAnimationDuration = 300; // 하단 바 애니메이션 속도 (ms)
  bool _previousAppBarState = true; // 🎯 풀스크린/댓글 진입 전 앱바 상태 저장
  double _currentScrollOffset = 0.0; // 🎯 현재 스크롤 위치 (타이틀 표시용)
  bool _showLoadingBackButton = true; // 🎯 로딩 화면 뒤로가기 버튼 표시 여부
  bool _showErrorBackButton = true; // 🎯 에러 화면 뒤로가기 버튼 표시 여부

  // 순차 애니메이션 제거

  // 댓글 오버레이 상태/애니메이션
  bool _showCommentsOverlay = false;
  late final AnimationController _commentOverlayCtrl;
  late final Animation<double> _commentFade;

  // 좋아요 사용자 목록 오버레이 상태/애니메이션
  bool _showLikedUsersOverlay = false;
  late final AnimationController _likedUsersOverlayCtrl;
  late final Animation<double> _likedUsersFade;

  // 전체화면 이미지 뷰어 상태/애니메이션
  bool _showImageViewer = false;
  bool _isVideoViewer = false;
  String? _currentImageUrl;
  List<String> _allImageUrls = [];
  String? _currentMediaId;
  List<String> _allMediaIds = [];
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
    print(
      '[PostReaderScreen] 🔍 찾은 노드: ${node?.runtimeType} (ID: ${node?.id})',
    );

    if (node == null) {
      print('[PostReaderScreen] ⚠️ 노드를 찾을 수 없음');
      return;
    }

    // 노드 타입에 따른 분기 처리
    print('[PostReaderScreen] 🎯 노드 타입 분기: ${node.runtimeType}');

    // 🎯 switch 대신 if-else 사용 (AppImageNode는 ImageNode 상속이지만 runtimeType이 다름)
    if (node is ClipNode) {
      final clipNode = node;
      print('  - Clip: ${clipNode.url}');

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
        // 프리로드 컨트롤러 확인
        final controller = PostReaderService.getPreloadedController(
          clipNode.url,
        );

        if (controller == null) {
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

        // 🎯 ClipNode의 metadata에서 mediaId 추출
        String? mediaId;
        try {
          final meta = clipNode.metadata;
          mediaId = meta['mediaId']?.toString();
          print('[PostReaderScreen] 🎬 ClipNode mediaId: $mediaId');
        } catch (e) {
          print('[PostReaderScreen] ❌ ClipNode mediaId 추출 실패: $e');
        }

        setState(() {
          _previousAppBarState = _showAppBar; // 🎯 현재 상태 저장
          _currentImageUrl = clipNode.url;
          _allImageUrls = [clipNode.url];
          _isVideoViewer = true;
          _showImageViewer = true;
          _currentMediaId = mediaId; // 🎯 mediaId 설정
          _allMediaIds = mediaId != null ? [mediaId] : []; // 🎯 mediaIds 배열 설정
          _showAppBar = false; // 하단 바 숨김
          _bottomBarAnimationDuration = 50; // 빠르게 숨김
        });
        _imageViewerCtrl.forward(from: 0.0);
      }
    } else if (node is LinkNode) {
      final linkNode = node;
      print('  - Link: ${linkNode.url}');
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
      print('  - Image: ${imageNode.imageUrl}');

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
        print('[PostReaderScreen] 이미지 스포일러 해제: ${imageNode.id}');
        return; // 스포일러 해제만 하고 종료
      }

      // 스포일러가 없으면 full viewer 열기
      // mediaId 메타 추출
      String? mediaId;
      try {
        final meta = (imageNode as dynamic).metadata as Map<String, dynamic>?;
        print('[PostReaderScreen] 🔍 ImageNode metadata: $meta');

        // 🎯 서버 응답: data.mediaId 구조 확인
        if (meta != null) {
          // data 안에 mediaId가 있는 경우
          if (meta.containsKey('mediaId')) {
            mediaId = meta['mediaId']?.toString();
            print('[PostReaderScreen] ✅ mediaId from meta[mediaId]: $mediaId');
          }
          // 또는 data 객체가 있는 경우
          else if (meta.containsKey('data')) {
            final data = meta['data'] as Map<String, dynamic>?;
            mediaId = data?['mediaId']?.toString();
          }
        }
      } catch (e) {}

      setState(() {
        _previousAppBarState = _showAppBar; // 🎯 현재 상태 저장
        _currentImageUrl = imageNode.imageUrl;
        _allImageUrls = [_currentImageUrl!];
        _isVideoViewer = false;
        _showImageViewer = true;
        _currentMediaId = mediaId;
        _allMediaIds = mediaId != null ? [mediaId] : [];
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

        // 🎯 ImageRowNode의 메타데이터에서 각 이미지의 mediaId 추출
        List<String> mediaIds = [];
        try {
          final meta = imageRowNode.metadata;
          print('[PostReaderScreen] 🔍 ImageRowNode metadata: $meta');
          print(
            '[PostReaderScreen] 🔍 ImageRowNode metadata keys: ${meta.keys}',
          );

          final mediaIdList = meta['mediaIds'] as List?;
          print(
            '[PostReaderScreen] 🔍 mediaIdList from meta[mediaIds]: $mediaIdList',
          );

          if (mediaIdList != null) {
            mediaIds = mediaIdList.map((e) => e?.toString() ?? '').toList();
            print('[PostReaderScreen] ✅ ImageRow mediaIds 추출 성공: $mediaIds');
          } else {
            print('[PostReaderScreen] ⚠️ meta[mediaIds]가 null');
          }
        } catch (e) {
          print('[PostReaderScreen] ❌ ImageRow mediaId 추출 실패: $e');
        }

        print(
          '[PostReaderScreen] clickedIndex: $clickedIndex, mediaIds: $mediaIds',
        );

        setState(() {
          _previousAppBarState = _showAppBar; // 🎯 현재 상태 저장
          _allImageUrls = imageRowNode.imageUrls;
          _currentImageUrl = imageRowNode.imageUrls[clickedIndex];
          _isVideoViewer = false;
          _showImageViewer = true;
          _currentMediaId = mediaIds.isNotEmpty ? mediaIds[clickedIndex] : null;
          _allMediaIds = mediaIds;
          _showAppBar = false; // 하단 바 숨김
          _bottomBarAnimationDuration = 50; // 빠르게 숨김
        });
        _imageViewerCtrl.forward(from: 0.0);
      }
    } else if (node is DividerNode) {
      print('  - Divider');
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

  // 🎯 앱바를 먼저 숨기고 화면 닫기
  void _closeScreen() {
    // 앱바가 보이는 상태면 먼저 숨기기
    if (_showAppBar) {
      setState(() {
        _showAppBar = false;
        _bottomBarAnimationDuration = 200; // 빠른 애니메이션
      });
      // 앱바 숨김 애니메이션 후 화면 닫기
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    } else {
      // 앱바가 이미 숨겨져 있으면 바로 닫기
      Navigator.of(context).pop();
    }
  }

  // 🎯 로딩 화면 닫기 (뒤로가기 버튼 먼저 숨기고 닫기)
  void _closeLoadingScreen() {
    if (_showLoadingBackButton) {
      setState(() {
        _showLoadingBackButton = false;
      });
      // 뒤로가기 버튼 숨김 애니메이션 후 화면 닫기
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    } else {
      // 이미 숨겨져 있으면 바로 닫기
      Navigator.of(context).pop();
    }
  }

  // 🎯 에러 화면 닫기 (뒤로가기 버튼 먼저 숨기고 닫기)
  void _closeErrorScreen() {
    if (_showErrorBackButton) {
      setState(() {
        _showErrorBackButton = false;
      });
      // 뒤로가기 버튼 숨김 애니메이션 후 화면 닫기
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    } else {
      // 이미 숨겨져 있으면 바로 닫기
      Navigator.of(context).pop();
    }
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
      print('[PostReaderScreen] 좋아요 처리 중 오류가 발생했습니다: $e');
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

          print(
            '[PostReaderScreen] 관련 그룹 postCount 및 포스트 캐시 동기화 완료: ${sharedGroupIds.length}개 그룹',
          );
        }
        // FRIENDS 공개범위인 경우: allFriends 그룹 포스트 캐시 무효화
        else if (accessLevel == 'FRIENDS') {
          // 🎯 allFriends 그룹 포스트 캐시 무효화 (동기화)
          ManageGroupScreen.invalidateGroupPostsCache(-1);
          print('[PostReaderScreen] allFriends 그룹 포스트 캐시 무효화 완료');
        }
        // PUBLIC/PRIVATE는 그룹 postCount에 영향 없음
      } catch (e) {
        print('[PostReaderScreen] 그룹 postCount 및 포스트 캐시 동기화 실패: $e');
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
      thumbnailUrl: thumbnailUrl,
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
              print('[PostReaderScreen] 프로필 피드 선택적 업데이트 완료 (공개범위 변경)');
            }
          } catch (e) {
            print('[PostReaderScreen] 프로필 피드 선택적 업데이트 실패: $e');
          }
        }
      },
    );
  }

  void _showCommentBottomSheet() {
    // 오버레이 즉시 표시
    final id = widget.exported['id']?.toString() ?? '';
    _commentService.setPostId(id);

    setState(() {
      _previousAppBarState = _showAppBar; // 🎯 현재 상태 저장
      _showCommentsOverlay = true;
      _showAppBar = false; // 하단 바 숨김
      _bottomBarAnimationDuration = 50; // 빠르게 숨김
    });
    _commentOverlayCtrl.forward(from: 0.0);

    // WebSocket 연결 (백그라운드, 비동기)
    _initCommentsAsync();
  }

  // 댓글 데이터 초기화 (비동기)
  Future<void> _initCommentsAsync() async {
    // WebSocket 연결 (백그라운드, 실패해도 무시)
    _commentService.connectWebSocketForCurrentPost().catchError((e) {});

    // 🎯 댓글이 이미 로드되어 있으면 로딩 스킵 (initState에서 이미 로드됨)
    // 댓글창은 이미 로드된 데이터를 즉시 표시
  }

  void _closeCommentsOverlay() {
    _commentOverlayCtrl.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() {
        _showCommentsOverlay = false;
        _showAppBar = _previousAppBarState; // 🎯 이전 상태로 복원
        _bottomBarAnimationDuration =
            _previousAppBarState ? 0 : 300; // 🎯 열려있었으면 즉시(0), 닫혀있었으면 일반 속도
      });
      // WebSocket 연결 해제
      _commentService.disconnectWebSocket();
      print('[PostReaderScreen] 댓글창 닫기 - WebSocket 연결 해제');
    });
  }

  // 🎯 좋아요 사용자 목록 오버레이 표시
  void _openLikedUsersOverlay() {
    setState(() {
      _previousAppBarState = _showAppBar; // 🎯 현재 상태 저장
      _showLikedUsersOverlay = true;
      _showAppBar = false; // 하단 바 숨김
      _bottomBarAnimationDuration = 50; // 빠르게 숨김
    });
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
    final response = await _blogService.getPostContent(postId);

    // 🎯 서버 응답 구조: { isLiked, likeCount, commentCount, postId, content: {...}, accessLevel, sharedGroupIds, sharedGroupNames }
    final actualLikeCount = response['likeCount'] as int? ?? 0;
    final actualIsLiked = response['isLiked'] == true;
    final actualCommentCount = response['commentCount'] as int? ?? 0;

    _likeService.setInitialLikeData(postId, actualIsLiked, actualLikeCount);
    _commentService.setInitialCommentCount(actualCommentCount); // 🎯 초기 댓글 수 설정

    print(
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

    // 🎯 서버에서 받은 content 데이터 로그
    print('[PostReaderScreen] 🔍 서버 응답 content 키: ${content.keys}');
    if (content.containsKey('nodes')) {
      final nodes = content['nodes'] as List?;
      print('[PostReaderScreen] 🔍 nodes 개수: ${nodes?.length}');
      // video 노드 찾기
      if (nodes != null) {
        for (final node in nodes) {
          if (node is Map && node['type'] == 'video') {
            print('[PostReaderScreen] 🎬 서버 응답 video 노드: $node');
            final data = node['data'] as Map?;
            print('[PostReaderScreen] 🎬 video data: $data');
            print('[PostReaderScreen] 🎬 video mediaId: ${data?['mediaId']}');
          }
        }
      }
    }

    // 메타데이터를 content에 병합 (UI에서 사용)
    content['likeCount'] = actualLikeCount;
    content['isLiked'] = actualIsLiked;
    content['commentCount'] = actualCommentCount;

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

    // 🎯 공개범위 데이터 초기화: widget.exported에서 먼저 읽고, 필요시 서버 조회
    _initializeAccessLevelFromExported();
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

    // PostReaderScreen은 StickerService를 사용하지 않고
    // widget.exported에서 stickers를 직접 읽어 PostReaderStickers에 전달

    _commentOverlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _commentFade = CurvedAnimation(
      parent: _commentOverlayCtrl,
      curve: Curves.easeOutCubic,
    );

    // 🎯 좋아요 사용자 목록 오버레이 애니메이션 초기화
    _likedUsersOverlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _likedUsersFade = CurvedAnimation(
      parent: _likedUsersOverlayCtrl,
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
      _commentService.setPostId(postId);

      // 🎯 widget.exported에서 초기 댓글 수 설정 (포스트 목록에서 가져온 값)
      final initialCommentCount = widget.exported['commentCount'] as int? ?? 0;
      _commentService.setInitialCommentCount(initialCommentCount);

      // 🎯 초기 댓글 로드 (타이밍 시어 없이 즉시 로드)
      _commentService.loadComments(size: 20);

      // 🎯 좋아요 사용자 목록 미리 로드 (비동기, 백그라운드)
      LikedUsersBottomSheet.preloadLikedUsers(postId).catchError((e) {
        print('[PostReaderScreen] 좋아요 사용자 목록 미리 로드 실패: $e');
      });

      // 본문 로드 시 실제 데이터로 좋아요/댓글 초기화 (_loadContentWithPreloadedMedia에서 처리)
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
    _commentOverlayCtrl.dispose();
    _likedUsersOverlayCtrl.dispose();
    _imageViewerCtrl.dispose();

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

    // 🎯 스크롤 위치 변경 시 항상 업데이트 (타이틀 표시/숨김을 위해)
    final bool shouldUpdate =
        nextShow != _showAppBar || nextOffset != _currentScrollOffset;

    if (shouldUpdate) {
      setState(() {
        _showAppBar = nextShow;
        _currentScrollOffset = nextOffset; // 🎯 현재 스크롤 위치 업데이트
        _previousAppBarState = nextShow; // 🎯 스크롤로 변경된 상태도 저장
        _bottomBarAnimationDuration = 300; // 일반 속도
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

    return WillPopScope(
      onWillPop: () async {
        if (_showCommentsOverlay) {
          _closeCommentsOverlay();
          return false;
        }

        if (_showLikedUsersOverlay) {
          _closeLikedUsersOverlay();
          return false;
        }

        // 🎯 공개 범위가 변경되었으면 결과 반환 (피드 선택적 업데이트를 위해)
        if (_accessLevelChanged) {
          // 앱바를 먼저 숨기고 닫기
          if (_showAppBar) {
            setState(() {
              _showAppBar = false;
              _bottomBarAnimationDuration = 200;
            });
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted) {
                Navigator.of(context).pop({
                  'accessLevelChanged': true,
                  'postId': widget.exported['id']?.toString(),
                  'accessLevel': _accessLevel,
                  'sharedGroupIds': _sharedGroupIds,
                });
              }
            });
          } else {
            Navigator.of(context).pop({
              'accessLevelChanged': true,
              'postId': widget.exported['id']?.toString(),
              'accessLevel': _accessLevel,
              'sharedGroupIds': _sharedGroupIds,
            });
          }
          return false; // Navigator.pop을 호출했으므로 false 반환
        }

        // 🎯 앱바를 먼저 숨기고 닫기
        if (_showAppBar) {
          setState(() {
            _showAppBar = false;
            _bottomBarAnimationDuration = 200;
          });
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
          return false; // Navigator.pop을 호출했으므로 false 반환
        }

        return true;
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        body: FutureBuilder<Map<String, dynamic>>(
          future: _contentFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return GestureDetector(
                onHorizontalDragEnd: (details) {
                  // 오른쪽으로 스와이프 (velocity.dx > 0)
                  if (details.primaryVelocity != null &&
                      details.primaryVelocity! > 300) {
                    _closeLoadingScreen();
                  }
                },
                child: DoppyLoadingLogo(
                  opacity: _showLoadingLogo ? 1.0 : 0.0,
                  showBackButton: _showLoadingBackButton,
                  onBack: _closeLoadingScreen,
                ),
              );
            }

            // ✅ 데이터/미디어 선행 준비 후 약간 더 대기하여 첫 프레임 안정화
            if (snap.hasData && !_isRenderReady) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) {
                  setState(() => _isRenderReady = true);
                }
              });
              return GestureDetector(
                onHorizontalDragEnd: (details) {
                  // 오른쪽으로 스와이프 (velocity.dx > 0)
                  if (details.primaryVelocity != null &&
                      details.primaryVelocity! > 300) {
                    _closeLoadingScreen();
                  }
                },
                child: DoppyLoadingLogo(
                  opacity: _showLoadingLogo ? 1.0 : 0.0,
                  showBackButton: _showLoadingBackButton,
                  onBack: _closeLoadingScreen,
                ),
              );
            }
            if (snap.hasError) {
              return GestureDetector(
                // 🎯 스와이프로 닫기 기능
                onHorizontalDragStart: (details) {
                  _horizontalDragDistance = 0.0;
                },
                onHorizontalDragUpdate: (details) {
                  // 오른쪽으로 스와이프만 감지 (닫기)
                  if (details.delta.dx > 0) {
                    setState(() {
                      _horizontalDragDistance += details.delta.dx;
                    });
                  }
                },
                onHorizontalDragEnd: (details) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  final dragDistance = _horizontalDragDistance;
                  final velocity = details.primaryVelocity ?? 0;

                  // 🎯 스와이프 거리가 화면의 30% 이상이거나 빠른 속도로 스와이프하면 닫기
                  if (dragDistance > screenWidth * 0.3 || velocity > 500) {
                    _closeErrorScreen();
                  } else {
                    // 원래 위치로 복귀
                    setState(() {
                      _horizontalDragDistance = 0.0;
                    });
                  }
                },
                child: Scaffold(
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
                ),
              );
            }

            if (snap.hasData && (snap.data?.isNotEmpty ?? false)) {
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

              // 최신 데이터 저장 (수정하기에서 사용)
              _currentExportedData = merged;

              // 🎯 문서가 이미 초기화되었고 내용이 동일하면 재생성하지 않음 (성능 최적화)
              if (!_documentInitialized) {
                // 최신 본문으로 문서 재구성 (최초 1회만)
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
                _documentInitialized = true; // 🎯 초기화 완료 표시
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
                    behavior:
                        HitTestBehavior.translucent, // 🎯 자식이 터치를 소비해도 부모도 받음
                    onTapUp: (details) {
                      _lastTapPosition = details.globalPosition;
                      print(
                        '[PostReaderScreen] 🖱️ 탭 감지: ${details.globalPosition}',
                      );
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
                        _closeScreen();
                      }
                      _horizontalDragDistance = 0.0;
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
                        slivers: [
                          SliverSafeArea(
                            top: true,
                            bottom: false,
                            sliver: SliverToBoxAdapter(
                              child: GestureDetector(
                                onTap: () {
                                  print('postAuthor: $postAuthor');

                                  if (postAuthor.isEmpty ||
                                      postAuthor ==
                                          AuthService().currentUsernameSync) {
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
                                  currentExportedData: _currentExportedData,
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
                                  likeCount: _likeService.getPostLikeCount(
                                    widget.exported['id']?.toString() ?? '',
                                  ),
                                  commentCount:
                                      _commentService.getTotalCommentCount(),
                                  onLikeTap: _toggleLike,
                                  onCommentTap: _showCommentBottomSheet,
                                  isLiked: _likeService.isPostLiked(
                                    widget.exported['id']?.toString() ?? '',
                                  ), // ← 추가
                                ),
                              ),
                            ),
                          ),
                          // SuperEditor 슬리버
                          SuperEditor(
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
                                dragService: _dragService,
                                isEditing: false, // 읽기 모드
                              ),
                              RowImageComponentBuilder(
                                dragService: _dragService,
                                isEditing: false, // 읽기 모드
                              ),
                              LinkComponentBuilder(
                                isEditing: false,
                                isDarkMode:
                                    context.watch<ThemeProvider>().themeMode ==
                                    ThemeMode.dark,
                              ),
                              DividerComponentBuilder(),
                              ClipComponentBuilder(dragService: _dragService),
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
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .onSurface,
                                                      fontWeight:
                                                          FontWeight.w600,
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
                      title: widget.exported['title'] ?? '',
                      likeCount: _likeService.getPostLikeCount(
                        widget.exported['id']?.toString() ?? '',
                      ),
                      commentCount: _commentService.getTotalCommentCount(),
                      onLikeTap: _toggleLike,
                      onCommentTap: _showCommentBottomSheet,
                      isLiked: _likeService.isPostLiked(
                        widget.exported['id']?.toString() ?? '',
                      ),
                      animationDuration:
                          _bottomBarAnimationDuration, // 🎯 바텀바와 동일한 속도
                      scrollOffset: _currentScrollOffset, // 🎯 현재 스크롤 위치 전달
                      onMoreTap:
                          !isMyPost
                              ? () {
                                // 🎯 글 액션 바텀시트 표시
                                final postId =
                                    widget.exported['id']?.toString() ?? '';
                                final postTitle =
                                    widget.exported['title']?.toString() ?? '';
                                final authorUsername = postAuthor;
                                final authorProfileImageUrl =
                                    widget.exported['authorProfileImageUrl']
                                        ?.toString();
                                final authorAlias =
                                    widget.exported['authorAlias']?.toString();
                                final thumbnailImageUrl =
                                    widget.exported['thumbnailImageUrl']
                                        ?.toString();
                                final likeCount = _likeService.getPostLikeCount(
                                  postId,
                                );

                                PostActionBottomSheet.show(
                                  context,
                                  postId: postId,
                                  postTitle: postTitle,
                                  authorUsername: authorUsername,
                                  authorAlias: authorAlias,
                                  authorProfileImageUrl: authorProfileImageUrl,
                                  thumbnailImageUrl: thumbnailImageUrl,
                                  likeCount: likeCount,
                                  onShowLikedUsers: _openLikedUsersOverlay,
                                );
                              }
                              : null,
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
                          commentService: _commentService,
                        );
                      },
                    ),
                  ),
                // 좋아요 사용자 목록 오버레이
                if (_showLikedUsersOverlay)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _likedUsersFade,
                      builder: (context, _) {
                        return LikedUsersBottomSheet(
                          postId: widget.exported['id']?.toString() ?? '',
                          likeCount: _likeService.getPostLikeCount(
                            widget.exported['id']?.toString() ?? '',
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
                        imageProvider:
                            !_isVideoViewer
                                ? CachedNetworkImageProvider(_currentImageUrl!)
                                : null,
                        onClose: _closeImageViewer,
                        postTitle: () {
                          final title = widget.exported['title'] as String?;
                          print('[PostReader] postTitle: $title');
                          return title;
                        }(),
                        postAuthor: () {
                          final author = widget.exported['author'] as String?;
                          print('[PostReader] postAuthor: $author');
                          return author;
                        }(),
                        postAuthorProfileUrl: () {
                          final url =
                              widget.exported['authorProfileImageUrl']
                                  as String?;
                          print('[PostReader] postAuthorProfileUrl: $url');
                          return url;
                        }(),
                        commentCount: () {
                          final count = widget.exported['commentCount'] as int?;
                          print('[PostReader] commentCount: $count');
                          print(
                            '[PostReader] exported keys: ${widget.exported.keys.toList()}',
                          );
                          return count;
                        }(),
                      ),
                    ),
                  ),

                // 하단 바 (Medium 스타일)
                AnimatedPositioned(
                  duration: Duration(milliseconds: _bottomBarAnimationDuration),
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
                      final postId = widget.exported['id']?.toString() ?? '';
                      final isLiked = _likeService.isPostLiked(postId);
                      final likeCount = _likeService.getPostLikeCount(postId);
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
                                            _sharedGroupNames!.isNotEmpty) {
                                          // 🎯 서버에서 받은 그룹 이름 직접 사용
                                          if (_sharedGroupNames!.length == 1) {
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
                                        } else if (_sharedGroupIds != null &&
                                            _sharedGroupIds!.isNotEmpty) {
                                          // 🎯 sharedGroupNames가 없으면 GroupProvider에서 찾기 (fallback)
                                          final groups = groupProvider.myGroups;
                                          final matchingGroups =
                                              groups
                                                  .where(
                                                    (g) => _sharedGroupIds!
                                                        .contains(g.id),
                                                  )
                                                  .toList();

                                          if (matchingGroups.isNotEmpty) {
                                            if (matchingGroups.length == 1) {
                                              final group =
                                                  matchingGroups.first;
                                              if (group.isSystem == true) {
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
                                          onTap: _showAccessLevelBottomSheet,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 20.0,
                                              top: 1,
                                            ),
                                            child:
                                                groupName != null
                                                    ? Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
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
                                                              .withOpacity(0.7),
                                                        ),
                                                      ],
                                                    )
                                                    : SvgPicture.asset(
                                                      'assets/icons/lock_open.svg',
                                                      width: 23,
                                                      height: 23,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withOpacity(0.7),
                                                    ),
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ],

                                const Spacer(),
                                // 우측: 좋아요 + 댓글
                                GestureDetector(
                                  onTap: _toggleLike,
                                  onLongPress: _openLikedUsersOverlay,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SvgPicture.asset(
                                        'assets/icons/heart.svg',
                                        width: 26,
                                        height: 26,
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
