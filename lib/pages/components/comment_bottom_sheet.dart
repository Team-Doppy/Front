import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/comment_item.dart';
import 'package:doppy/pages/components/comment_mention_overlay.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/image/media_picker_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

class CommentBottomSheet extends StatefulWidget {
  const CommentBottomSheet({
    super.key,
    required this.title,
    required this.commentService,
    this.postThumbnailUrl,
    this.postSummary,
    this.scrollToCommentId, // 🎯 특정 댓글로 스크롤할 댓글 ID
    this.postAuthorUsername, // 🎯 블로그 작성자 username (비밀 메시지용)
  });
  final String title;
  final CommentService commentService;
  final String? postThumbnailUrl; // 🎯 댓글 0개일 때 보여줄 포스트 썸네일
  final String? postSummary; // 🎯 댓글 0개일 때 보여줄 포스트 요약(한 줄)
  final String? scrollToCommentId; // 🎯 특정 댓글로 스크롤할 댓글 ID
  final String? postAuthorUsername; // 🎯 블로그 작성자 username (비밀 메시지용)

  @override
  State<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends State<CommentBottomSheet>
    with TickerProviderStateMixin {
  late final CommentService _commentService;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final Map<String, GlobalKey> _commentKeys = {}; // 높이 측정용 GlobalKey

  Comment? _replyTarget;
  Comment? _editingComment;
  String? _secretMessageTarget; // 🎯 비밀 메시지 대상 사용자 (블로그 작성자)
  String? _selectedImageUrl; // 🎯 선택된 이미지 URL (임시 또는 실제 URL)
  File? _selectedImageFile; // 🎯 선택된 이미지 파일 (로컬)
  final Map<String, File> _localImageFiles = {}; // 🎯 댓글 ID -> 로컬 파일 매핑
  final Set<String> _failedUploads = {}; // 🎯 업로드 실패한 댓글 ID 추적

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  String? _bouncingCommentId;

  // 🎯 로드 모어 스피너 애니메이션
  late AnimationController _loadMoreSpinnerController;
  late Animation<double> _loadMoreSpinnerRotation;

  bool _showScrollToBottomButton = false; // 맨 아래로 버튼 표시 여부
  bool _showNewMessageBadge = false; // 새 메시지 알림 표시 여부
  int _lastCommentCount = 0; // 마지막 댓글 수
  bool _isKeyboardActive = false; // 키보드 활성화 상태
  // NOTE: PostReader에서 댓글 화면 전환이 이미 Fade라,
  // 댓글 아이템 개별 페이드(_isInitialLoad)로 인한 "2번 깜빡임"을 막기 위해 제거.
  bool _isLoadingTargetComment = false; // 타겟 댓글 로딩 중 표시 여부
  double _inputSectionHeight = 80.0; // 🎯 입력창 높이 (기본값, 실제 높이로 업데이트)
  bool _isLoadingMore = false; // 🎯 로드 모어 로딩 중 표시 여부

  // 🎯 성능 최적화: 타겟 댓글 캐싱
  final Map<String, Comment?> _targetCommentCache = {};

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      setState(fn);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(fn);
      });
    }
  }

  // ✅ 기존 pin/auto-position/scroll scheduling 로직 제거:
  // 새 구조는 ScrollController + ListView(reverse:true)로 단순화하고,
  // "맨 아래" 이동은 animateTo(0)으로 처리한다.

  /// 🎯 타겟 댓글이 로컬에 없을 때, 서버 locate API로 "정확한 페이지"만 로드해서 가져오기
  /// - 기존 _loadTargetPage는 스캔/반복 로드라 불안정/비효율일 수 있음
  Future<bool> _loadTargetPageByLocate(String commentId) async {
    final postId = _commentService.currentPostId;
    if (postId == null || postId.isEmpty) return false;

    try {
      // 로딩 인디케이터 즉시 표시
      if (mounted) {
        _safeSetState(() {
          _isLoadingTargetComment = true;
        });
      }

      final locate = await _commentService.locateCommentInPost(
        postId: postId,
        commentId: commentId,
        size: CommentService.defaultPageSize,
      );

      // locate가 준 page만 로드
      await _commentService.loadComments(
        targetPage: locate.page,
        size: locate.size,
      );

      return _commentService.comments.any((c) => c.id == commentId) ||
          _commentService.comments.any(
            (c) => c.id == locate.anchorParentCommentId,
          );
    } catch (e) {
      debugPrint('[CommentBottomSheet] ⚠️ locate 기반 로드 실패: $e');
      return false;
    } finally {
      // 로딩 인디케이터 숨김
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _safeSetState(() {
              _isLoadingTargetComment = false;
            });
          }
        });
      }
    }
  }

  // 🎯 드래그 상태 관리 (부모에서 관리)
  final Map<String, double> _dragOffsets = {};
  // 🎯 성능: 드래그 중에는 해당 아이템만 리빌드되게 ValueNotifier 사용
  final Map<String, ValueNotifier<double>> _dragOffsetNotifiers = {};

  @override
  void initState() {
    super.initState();
    _commentService = widget.commentService;
    // 🎯 포스트 작성자 정보를 CommentService에 설정
    if (widget.postAuthorUsername != null) {
      _commentService.setPostAuthorUsername(widget.postAuthorUsername);
    }
    _commentService.addListener(_onCommentsChanged);
    _itemPositionsListener.itemPositions.addListener(_onScroll);

    // 🎯 초기 댓글 수 확인 (프레임 렌더링 후 정확한 개수로 판단)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _lastCommentCount = _commentService.comments.length;

        // 🎯 딥링크로 특정 댓글로 스크롤 (초기 로드 완료 후)
        if (widget.scrollToCommentId != null &&
            widget.scrollToCommentId!.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _scrollToTargetComment(widget.scrollToCommentId!);
            }
          });
        }
      }
    });

    // 키보드 상태 감지
    _focusNode.addListener(_onFocusChanged);

    // 바운싱 애니메이션 초기화 (2번 바운스)
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    // 🎯 로드 모어 스피너 애니메이션 초기화
    _loadMoreSpinnerController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _loadMoreSpinnerRotation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_loadMoreSpinnerController);
  }

  void _onFocusChanged() {
    if (mounted) {
      // 🎯 키보드 상태 변경을 다음 프레임에 처리하여 블로킹 방지
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _safeSetState(() {
          _isKeyboardActive = _focusNode.hasFocus;
          // 🎯 키보드가 내려가면 답글/수정 모드 취소
          if (!_focusNode.hasFocus) {
            _replyTarget = null;
            _editingComment = null;
          }
        });
      });
    }
  }

  void _onScroll() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final minIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a < b ? a : b);
    final maxIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a > b ? a : b);

    // reverse:true: builder index=0이 최신(맨 아래)
    final isAtBottom = minIndex <= 0;
    if (_showScrollToBottomButton != !isAtBottom) {
      _safeSetState(() => _showScrollToBottomButton = !isAtBottom);
    }

    // reverse:true: 과거(맨 위)로 갈수록 index가 커짐
    final itemCount = _getSortedComments().length;
    final nearTop = itemCount > 0 && maxIndex >= itemCount - 5;
    if (nearTop &&
        !_commentService.isLoading &&
        _commentService.hasMoreComments &&
        !_isLoadingMore) {
      _safeSetState(() => _isLoadingMore = true);
      _loadMoreSpinnerController.repeat();
      _commentService
          .loadComments()
          .catchError((e) {
            debugPrint('[CommentBottomSheet] ⚠️ 로드 모어 실패: $e');
          })
          .whenComplete(() {
            if (!mounted) return;
            _loadMoreSpinnerController.stop();
            _safeSetState(() => _isLoadingMore = false);
          });
    }
  }

  @override
  void dispose() {
    _commentService.removeListener(_onCommentsChanged);
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    _bounceController.dispose();
    // 🎯 로드 모어 스피너 컨트롤러가 초기화되었는지 확인 후 dispose
    try {
      _loadMoreSpinnerController.dispose();
    } catch (e) {
      // 초기화되지 않은 경우 무시
    }
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCommentsChanged() {
    if (!mounted) return;

    // 🎯 성능 최적화: 댓글 수만 먼저 확인 (정렬 없이)
    final currentCount = _commentService.comments.length;

    // 삭제된 댓글의 GlobalKey 정리 (ID만 사용, 정렬 없이)
    final currentCommentIds = _commentService.comments.map((c) => c.id).toSet();
    _commentKeys.removeWhere((id, key) => !currentCommentIds.contains(id));
    // 삭제된 댓글의 드래그 오프셋 정리
    _dragOffsets.removeWhere((id, offset) => !currentCommentIds.contains(id));
    // 삭제된 댓글의 notifier 정리
    _dragOffsetNotifiers.removeWhere((id, notifier) {
      final shouldRemove = !currentCommentIds.contains(id);
      if (shouldRemove) {
        notifier.dispose();
      }
      return shouldRemove;
    });

    // 새 댓글이 추가되었는지 확인
    if (currentCount > _lastCommentCount && !_commentService.isLoading) {
      if (currentCount > 0) {
        // 🎯 새 댓글 확인은 다음 프레임에 처리하여 블로킹 방지
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final sortedComments = _getSortedComments();
          if (sortedComments.isEmpty) return;

          final currentUser = context.read<UserProvider>().currentUser;
          // 🎯 최신 댓글 확인 (이미 정렬된 리스트 사용)
          final latestComment = sortedComments.last;
          final commentAge = DateTime.now().difference(
            TimeUtils.toLocalTime(latestComment.createdAt),
          );

          if (commentAge.inSeconds < 3) {
            final isMyComment = latestComment.author == currentUser?.username;
            if (isMyComment) {
              _scrollToBottom();
            } else if (_showScrollToBottomButton) {
              _safeSetState(() => _showNewMessageBadge = true);
              Future.delayed(const Duration(seconds: 5), () {
                if (mounted) _safeSetState(() => _showNewMessageBadge = false);
              });
            }
          }
        });
      }
    }

    _lastCommentCount = currentCount;

    // 🎯 notifyListeners() 호출 시 다음 프레임에 setState 호출하여 블로킹 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _safeSetState(() {});
      }
    });
  }

  void _submitComment() async {
    final text = _textController.text.trim();
    final imageFile = _selectedImageFile; // 🎯 선택된 이미지 파일 (단일)
    if (text.isEmpty && imageFile == null) return; // 🎯 텍스트와 이미지 모두 없으면 리턴

    final currentUser = context.read<UserProvider>().currentUser;
    if (currentUser == null) return;

    // 편집 모드
    if (_editingComment != null) {
      final commentId = _editingComment!.id;

      // 🎯 즉시 상태 초기화 (딜레이 없이)
      setState(() {
        _editingComment = null;
        _textController.clear();
        _selectedImageUrl = null; // 🎯 이미지 URL 초기화
        _selectedImageFile = null; // 🎯 이미지 파일 초기화
      });

      // 서버 요청은 백그라운드에서 처리 (await 제거)
      _commentService.updateComment(commentId, text);
      return;
    }

    // 새 댓글/답글 추가
    final replyTargetId = _replyTarget?.id;

    // 🎯 비밀댓글에 답장하는 경우 자동으로 PRIVATE로 설정
    String? finalVisibleToUsername = _secretMessageTarget;
    if (replyTargetId != null && _replyTarget != null) {
      final isReplyToPrivate =
          _replyTarget!.isSecret || _replyTarget!.visibility == 'PRIVATE';
      if (isReplyToPrivate) {
        // 비밀댓글에 답장: 포스트 작성자와 원래 댓글 작성자만 볼 수 있도록
        // visibleToUsername은 null로 설정하고, addComment에서 부모 댓글이 비밀댓글이면 자동으로 PRIVATE로 처리
        finalVisibleToUsername = null;
      }
    }

    // 🎯 즉시 상태 초기화 (딜레이 없이)
    setState(() {
      _textController.clear();
      _replyTarget = null;
      _selectedImageUrl = null; // 🎯 이미지 URL 초기화
      _selectedImageFile = null; // 🎯 이미지 파일 초기화
    });

    // 🎯 이미지가 있으면 서버 요청 없이 로컬 이미지로만 표시 (낙관적 업데이트)
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // 🎯 로컬 파일이 있으면 매핑 저장
    if (imageFile != null) {
      _localImageFiles[tempId] = imageFile;
    }

    // 🎯 이미지가 있으면 서버 요청 없이 로컬 이미지로만 표시
    if (imageFile != null) {
      // 낙관적 업데이트만 수행 (서버 요청 없음)
      _commentService.addCommentLocalOnly(
        username: currentUser.username,
        content: text,
        authorProfileImageUrl: currentUser.profileImageUrl,
        parentId: replyTargetId,
        localImagePath: imageFile.path, // 🎯 단일 이미지 경로
        visibleToUsername: finalVisibleToUsername,
        tempId: tempId,
      );

      // 🎯 백그라운드에서 이미지 업로드 진행
      _uploadImageInBackground(
        imageFile,
        currentUser.username,
        tempId, // 🎯 임시 ID를 전달하여 댓글 찾기
      );
    } else {
      // 🎯 텍스트만 있는 경우 기존 방식대로 서버에 전송
      _commentService.addComment(
        username: currentUser.username,
        content: text,
        authorProfileImageUrl: currentUser.profileImageUrl,
        parentId: replyTargetId,
        imageUrl: null, // 🎯 단일 이미지 파라미터 사용
        localImagePath: null, // 🎯 단일 이미지 파라미터 사용
        visibleToUsername: finalVisibleToUsername,
      );
    }

    // 비밀 메시지 상태 초기화
    setState(() {
      _secretMessageTarget = null;
    });
  }

  /// 🎯 단일 이미지를 개별 댓글로 전송
  Future<void> _submitSingleImageComment(File imageFile) async {
    final currentUser = context.read<UserProvider>().currentUser;
    if (currentUser == null) return;

    final replyTargetId = _replyTarget?.id;

    // 🎯 비밀댓글에 답장하는 경우 자동으로 PRIVATE로 설정
    String? finalVisibleToUsername = _secretMessageTarget;
    if (replyTargetId != null && _replyTarget != null) {
      final isReplyToPrivate =
          _replyTarget!.isSecret || _replyTarget!.visibility == 'PRIVATE';
      if (isReplyToPrivate) {
        finalVisibleToUsername = null;
      }
    }

    // 🎯 이미지가 있으면 서버 요청 없이 로컬 이미지로만 표시 (낙관적 업데이트)
    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.hashCode}';

    // 🎯 로컬 파일이 있으면 매핑 저장
    _localImageFiles[tempId] = imageFile;

    // 🎯 낙관적 업데이트만 수행 (서버 요청 없음)
    _commentService.addCommentLocalOnly(
      username: currentUser.username,
      content: '', // 🎯 이미지만 있는 댓글
      authorProfileImageUrl: currentUser.profileImageUrl,
      parentId: replyTargetId,
      localImagePath: imageFile.path,
      visibleToUsername: finalVisibleToUsername,
      tempId: tempId,
    );

    // 🎯 백그라운드에서 이미지 업로드 진행
    _uploadImageInBackground(imageFile, currentUser.username, tempId);
  }

  /// 🎯 백그라운드에서 이미지 업로드 (chat/username 경로 사용) - 단일 이미지
  Future<void> _uploadImageInBackground(
    File imageFile,
    String username,
    String tempCommentId, // 🎯 임시 댓글 ID
  ) async {
    try {
      final uploadService = context.read<UploadService>();

      // 🎯 댓글 이미지 업로드를 위한 태스크 생성
      final task = uploadService.enqueueFile(
        imageFile,
        kind: UploadKind.editorImage, // 🎯 나중에 chatImage로 변경 가능
        overrideName:
            'chat/${username}/${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}',
      );

      // 🎯 업로드 완료 대기 (비동기)
      task.addListener(() {
        if (task.state == UploadState.success && task.url != null) {
          // 🎯 R2 URL인지 확인 (pending://, 로컬 경로 제외)
          final url = task.url!;
          if (!url.startsWith('pending://') &&
              !url.startsWith('file://') &&
              !url.startsWith('/') &&
              (url.startsWith('http://') || url.startsWith('https://'))) {
            debugPrint('[CommentBottomSheet] ✅ 이미지 업로드 완료 (R2 URL): $url');
            // 성공 시 실패 목록에서 제거
            _failedUploads.remove(tempCommentId);
            _updateCommentImageUrl(tempCommentId, url);
          } else {
            debugPrint('[CommentBottomSheet] ⚠️ 유효하지 않은 URL (R2 URL 아님): $url');
          }
        } else if (task.state == UploadState.failed) {
          debugPrint('[CommentBottomSheet] ❌ 이미지 업로드 실패: ${task.error}');
          // 🎯 실패 시 댓글을 failed 상태로 변경
          if (mounted) {
            setState(() {
              _failedUploads.add(tempCommentId);
            });
            _commentService.markCommentAsFailed(tempCommentId);
          }
        }
      });
    } catch (e) {
      debugPrint('[CommentBottomSheet] 이미지 업로드 오류: $e');
    }
  }

  /// 🎯 이미지 업로드 완료 후 서버에 댓글 전송
  Future<void> _updateCommentImageUrl(
    String tempCommentId,
    String actualImageUrl,
  ) async {
    debugPrint('[CommentBottomSheet] ✅ 이미지 업로드 성공: $actualImageUrl');

    // 🎯 서버에 단일 이미지 URL로 댓글 전송
    await _commentService.addCommentWithImageUrl(
      tempCommentId: tempCommentId,
      imageUrl: actualImageUrl,
    );
  }

  // 🎯 드래그 핸들러 (부모에서 관리)
  void _handleHorizontalDragUpdate(
    String commentId,
    DragUpdateDetails details,
    bool isMe,
  ) {
    final notifier = _dragOffsetNotifiers.putIfAbsent(
      commentId,
      () => ValueNotifier(0.0),
    );
    final delta = details.delta.dx;
    final currentOffset = notifier.value;

    // 🎯 스트로크 길이(최대 이동거리) 줄임: 80 -> 56
    const maxStroke = 56.0;

    // 타인 댓글: 오른쪽으로만, 내 댓글: 왼쪽으로만
    if (!isMe && delta > 0) {
      notifier.value = (currentOffset + delta).clamp(0.0, maxStroke);
    } else if (isMe && delta < 0) {
      notifier.value = (currentOffset + delta).clamp(-maxStroke, 0.0);
    }

    // 기존 map도 유지(다른 로직 참조 대비)
    _dragOffsets[commentId] = notifier.value;
  }

  void _handleHorizontalDragEnd(
    String commentId,
    DragEndDetails details,
    VoidCallback onSwipeReply,
  ) {
    final notifier = _dragOffsetNotifiers[commentId];
    final offset = notifier?.value ?? _dragOffsets[commentId] ?? 0.0;

    // 🎯 답글 활성화 임계값 줄임: 40 -> 28
    const activateThreshold = 28.0;
    if (offset.abs() > activateThreshold) {
      // 임계값 초과 시 답글 실행
      HapticFeedback.mediumImpact();
      onSwipeReply();

      // 🎯 원위치로 복귀는 다음 프레임에 처리하여 블로킹 방지
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (notifier != null) notifier.value = 0.0;
          _dragOffsets[commentId] = 0.0;
        }
      });
    } else {
      // 원위치로 복귀 (애니메이션)
      if (notifier != null) notifier.value = 0.0;
      _dragOffsets[commentId] = 0.0;
    }
  }

  void _onLongPress(Offset offset, Comment comment) {
    HapticFeedback.mediumImpact();
    final currentUser = context.read<UserProvider>().currentUser;
    final isMyComment =
        currentUser != null && comment.author == currentUser.username;

    // 🎯 비밀댓글 권한 체크: 작성자이거나 포스트 작성자만 메뉴 표시
    final isPrivate = comment.isSecret || comment.visibility == 'PRIVATE';
    if (isPrivate) {
      final currentUsername = currentUser?.username;
      final isAuthor = comment.author == currentUsername;
      final isPostAuthor =
          widget.postAuthorUsername != null &&
          widget.postAuthorUsername == currentUsername;

      // 권한이 없으면 메뉴를 열지 않음
      if (!isAuthor && !isPostAuthor) {
        return;
      }
    }

    openCommentMenu(
      context,
      anchor: offset,
      comment: comment,
      isMyComment: isMyComment,
      postAuthorUsername: widget.postAuthorUsername, // 🎯 포스트 작성자 전달
    ).then((value) {
      if (value == null) return;
      if (value == 'reply') {
        setState(() => _replyTarget = comment);
        // 🎯 키보드 포커스는 다음 프레임에 처리하여 블로킹 방지
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusNode.requestFocus();
          }
        });
      } else if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: comment.content));
      } else if (value == 'edit') {
        setState(() {
          _editingComment = comment;
          _textController.text = comment.content;
          _replyTarget = null;
        });
        // 🎯 키보드 포커스는 다음 프레임에 처리하여 블로킹 방지
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusNode.requestFocus();
          }
        });
      } else if (value == 'delete') {
        _commentService.deleteComment(comment.id);
      } else {
        _commentService.toggleReaction(comment.id, value);
      }
    });
  }

  void _scrollToBottom() {
    if (_showNewMessageBadge) {
      _safeSetState(() => _showNewMessageBadge = false);
    }
    if (_itemScrollController.isAttached) {
      // reverse:true에서 builder index=0이 최신(맨 아래)
      _itemScrollController.jumpTo(index: 0);
    }
  }

  /// 카톡/인스타 방식: 타겟 댓글이 있을 법한 페이지를 한 번에 계산해서 로드
  Future<bool> _loadTargetPage(String commentId) async {
    // 로딩 인디케이터 즉시 표시
    if (mounted) {
      _safeSetState(() {
        _isLoadingTargetComment = true;
      });
    }

    try {
      // 1) 이미 로드된 댓글 중에 타겟이 있는지 확인 (정렬 없이)
      var comments = _commentService.comments;
      var targetIndex = comments.indexWhere((c) => c.id == commentId);

      if (targetIndex != -1) {
        debugPrint('[CommentBottomSheet] ✅ 타겟 댓글 이미 로드됨');
        return true;
      }

      // 2) 타겟 댓글이 있을 법한 페이지 계산
      // 전체 댓글 수와 현재 로드된 댓글 수를 비교해서 페이지 추정
      final totalCount = _commentService.getTotalCommentCount();
      final loadedCount = comments.length;
      const pageSize = 100; // 🎯 타겟 댓글 찾기용 페이지 크기

      // 🎯 타겟 댓글의 위치를 추정 (전체 댓글 중 어디쯤인지)
      // 현재는 정확한 위치를 모르므로, 중간 정도 페이지부터 시작
      // 또는 타겟 댓글의 createdAt을 기반으로 추정할 수 있지만, 일단 간단하게 처리

      // 전체 댓글이 이미 로드되어 있으면 찾을 수 없음
      if (loadedCount >= totalCount && totalCount > 0) {
        debugPrint('[CommentBottomSheet] ❌ 타겟 댓글을 찾을 수 없음: 모든 댓글 로드됨');
        return false;
      }

      // 3) 타겟 댓글을 찾을 때까지 배치 단위로 병렬 로드
      // 현재 로드된 페이지 다음부터 끝까지 배치 단위로 병렬 로드
      int estimatedPage = (loadedCount / pageSize).floor();
      int currentPage = estimatedPage;
      const maxAttempts = 50; // 무한 루프 방지 (최대 50페이지)
      const batchSize = 5; // 🎯 한 번에 병렬 로드할 페이지 수

      for (int attempt = 0; attempt < maxAttempts; attempt += batchSize) {
        // 더 이상 로드할 수 없으면 종료
        if (!_commentService.hasMoreComments) {
          debugPrint('[CommentBottomSheet] ❌ 타겟 댓글을 찾을 수 없음: 모든 페이지 로드 완료');
          return false;
        }

        // 🎯 배치 단위로 병렬 로드
        final pagesToLoad = <int>[];
        for (int i = 0; i < batchSize && currentPage + i < maxAttempts; i++) {
          if (_commentService.hasMoreComments) {
            pagesToLoad.add(currentPage + i);
          }
        }

        if (pagesToLoad.isEmpty) {
          break;
        }

        debugPrint('[CommentBottomSheet] 📦 배치 병렬 로드 시작: pages=$pagesToLoad');

        // 🎯 여러 페이지를 병렬로 로드 (Future.wait 사용)
        // CommentService의 _isLoading 때문에 실제로는 순차 실행되지만,
        // 구조상 병렬을 준비하고 빠르게 연속 호출
        final loadFutures =
            pagesToLoad.map((page) async {
              try {
                // 각 페이지를 로드 (CommentService가 동시 요청을 막을 수 있지만 빠르게 연속 호출)
                await _commentService.loadComments(targetPage: page);
                return page;
              } catch (e) {
                debugPrint(
                  '[CommentBottomSheet] ⚠️ 페이지 로드 실패: page=$page, error=$e',
                );
                return null;
              }
            }).toList();

        // 🎯 모든 페이지 로드 완료 대기 (병렬 구조, 실제로는 순차 실행될 수 있음)
        await Future.wait(loadFutures, eagerError: false);

        // 로드 완료 대기 (CommentService의 _isLoading이 false가 될 때까지)
        int waitCount = 0;
        while (_commentService.isLoading && waitCount < 50) {
          await Future.delayed(const Duration(milliseconds: 50)); // 더 빠른 체크
          waitCount++;
        }

        // 타겟 댓글 확인 (정렬 없이)
        comments = _commentService.comments;
        targetIndex = comments.indexWhere((c) => c.id == commentId);

        if (targetIndex != -1) {
          debugPrint('[CommentBottomSheet] ✅ 타겟 댓글 찾음: pages=$pagesToLoad');

          // 🎯 페이지 로드 후 렌더링 완료 대기 (키 생성 보장)
          await Future.delayed(const Duration(milliseconds: 200));
          await WidgetsBinding.instance.endOfFrame;

          // 🎯 setState로 리스트 업데이트 강제 (키가 생성되도록)
          if (mounted) {
            setState(() {});
            await Future.delayed(const Duration(milliseconds: 100));
            await WidgetsBinding.instance.endOfFrame;
          }

          return true;
        }

        // 다음 배치로 이동
        currentPage += batchSize;
      }

      debugPrint('[CommentBottomSheet] ❌ 타겟 댓글을 찾을 수 없음: 최대 시도 횟수 초과');
      return false;
    } finally {
      // 로딩 인디케이터 숨김
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _safeSetState(() {
              _isLoadingTargetComment = false;
            });
          }
        });
      }
    }
  }

  /// 키 기반 정확한 스크롤: Scrollable.ensureVisible 사용
  void _scrollToTargetComment(String commentId) async {
    _safeSetState(() => _isLoadingTargetComment = true);

    // 1) 타겟 댓글이 로드되었는지 확인 (createdAt 기준 정렬)
    var comments = _getSortedComments();
    var targetIndex = comments.indexWhere((c) => c.id == commentId);

    // 2) 못 찾으면 → locate API로 정확한 page만 로드 (실패 시 기존 스캔 로직 폴백)
    if (targetIndex == -1) {
      final found =
          await _loadTargetPageByLocate(commentId) ||
          await _loadTargetPage(commentId);
      if (!found || !mounted) {
        _safeSetState(() => _isLoadingTargetComment = false);
        return;
      }

      comments = _getSortedComments();
      targetIndex = comments.indexWhere((c) => c.id == commentId);
      if (targetIndex == -1) {
        debugPrint('[CommentBottomSheet] ❌ 타겟 댓글을 찾을 수 없음');
        _safeSetState(() => _isLoadingTargetComment = false);
        return;
      }
    }

    // 3) index 기반 즉시 점프 (서버 locate로 target page만 로드하므로 스캔/근처 이동 불필요)
    try {
      if (_itemScrollController.isAttached) {
        // reverse:true이므로 builder index로 변환
        final builderIndex = comments.length - 1 - targetIndex;
        _itemScrollController.jumpTo(index: builderIndex, alignment: 0.5);
      }

      // 바운스
      _safeSetState(() => _bouncingCommentId = commentId);
      _bounceController.forward(from: 0.0).then((_) {
        if (!mounted) return;
        _bounceController.reset();
        _safeSetState(() => _bouncingCommentId = null);
      });
    } catch (e) {
      debugPrint('[CommentBottomSheet] ❌ 스크롤 실패: $e');
    } finally {
      if (mounted) _safeSetState(() => _isLoadingTargetComment = false);
    }
  }

  // 🎯 성능 최적화: 타겟 댓글 캐싱
  Comment? _findTargetComment(String? parentId) {
    if (parentId == null || parentId == '0' || parentId.isEmpty) return null;

    // 캐시 확인
    if (_targetCommentCache.containsKey(parentId)) {
      return _targetCommentCache[parentId];
    }

    try {
      // 🎯 getAllComments() 대신 직접 _comments 사용 (정렬 없이)
      final target = _commentService.comments.firstWhere(
        (c) => c.id == parentId,
      );
      _targetCommentCache[parentId] = target;
      return target;
    } catch (_) {
      _targetCommentCache[parentId] = null;
      return null;
    }
  }

  // 🎯 정렬된 댓글 리스트 가져오기
  // 🎯 항상 최신 데이터를 사용하여 이모지 반응 변경 등이 즉시 반영되도록 함
  List<Comment> _getSortedComments() {
    // 🎯 항상 최신 _comments에서 가져와서 정렬 (이모지 반응 변경 등 즉시 반영)
    final sortedComments = List<Comment>.from(_commentService.comments)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return sortedComments;
  }

  Widget _buildEmptyState(BuildContext context) {
    final title = (widget.title).trim();
    final summary = (widget.postSummary ?? '').trim();
    final thumbnailUrl = (widget.postThumbnailUrl ?? '').trim();

    return Center(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: _inputSectionHeight + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child:
                  thumbnailUrl.isNotEmpty
                      ? CachedNetworkImage(
                        imageUrl: thumbnailUrl,
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 160),
                        fadeOutDuration: const Duration(milliseconds: 80),
                        placeholder:
                            (context, url) => Container(
                              width: 120,
                              height: 120,
                              color:
                                  Theme.of(context).colorScheme.surfaceVariant,
                            ),
                        errorWidget:
                            (context, error, stackTrace) => Container(
                              width: 120,
                              height: 120,
                              color:
                                  Theme.of(context).colorScheme.surfaceVariant,
                              child: Icon(
                                Icons.image_outlined,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.45),
                                size: 42,
                              ),
                            ),
                        memCacheWidth: 360,
                        maxWidthDiskCache: 360,
                      )
                      : Container(
                        width: 120,
                        height: 120,
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        child: Icon(
                          Icons.chat_bubble_outline,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.45),
                          size: 42,
                        ),
                      ),
            ),
            const SizedBox(height: 16),
            Text(
              title.isNotEmpty ? title : '이 게시물',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onBackground,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                summary,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onBackground.withOpacity(0.72),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              '첫 채팅을 시작해보세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onBackground,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 성능 최적화: 정렬된 댓글 리스트 캐싱 사용
    final comments = _getSortedComments();

    // 🎯 성능 최적화: currentUser를 build에서 한 번만 읽기
    final currentUser = context.read<UserProvider>().currentUser;

    final showLoadingSpinner = _commentService.isLoading && comments.isEmpty;

    if (showLoadingSpinner) {
      debugPrint('[CommentBottomSheet] 로딩 스피너 표시 - 댓글 없음');
    }

    return Stack(
      children: [
        // 🎯 타겟 댓글 로딩 인디케이터 (페이지네이션 스피너처럼 상단에 잠깐 표시)
        if (_isLoadingTargetComment)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow:
                      Theme.of(context).brightness == Brightness.light
                          ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ]
                          : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '답글로 이동 중…',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        GestureDetector(
          onTap: () => _focusNode.unfocus(),
          onHorizontalDragEnd: (details) {
            // 오른쪽으로 스와이프 (velocity.dx > 0)
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 300) {
              Navigator.of(context).maybePop();
            }
          },
          child: ClipRRect(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.background,
              ),
              child: Scaffold(
                // ✅ 키보드(viewInsets)로 인해 body 전체가 리사이즈되면 입력바가 "내려갔다가 올라오는" 튐이 커질 수 있음.
                // 입력바는 아래에서 viewInsets 만큼만 올려서 고정시키고, body는 리사이즈하지 않는다.
                resizeToAvoidBottomInset: false,
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  automaticallyImplyLeading: false,
                  toolbarHeight: 45,
                  scrolledUnderElevation: 0,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        color: Theme.of(
                          context,
                        ).colorScheme.onBackground.withOpacity(0.75),
                        size: 24,
                      ),
                    ),
                  ),
                  title: Text(
                    widget.title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onBackground,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                body: Column(
                  children: [
                    // 🎯 리스트 영역 (Expanded로 남은 공간 차지)
                    Expanded(
                      child: GestureDetector(
                        behavior:
                            HitTestBehavior
                                .translucent, // 🎯 하위 위젯이 탭 이벤트를 받을 수 있도록
                        onTap: () => _focusNode.unfocus(),
                        child:
                            showLoadingSpinner
                                ? Center(
                                  child: CircularProgressIndicator(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onBackground,
                                    strokeWidth: 2,
                                  ),
                                )
                                : comments.isEmpty
                                ? _buildEmptyState(context)
                                : Stack(
                                  children: [
                                    ScrollablePositionedList.builder(
                                      key: const PageStorageKey('comment_list'),
                                      itemScrollController:
                                          _itemScrollController,
                                      itemPositionsListener:
                                          _itemPositionsListener,
                                      reverse: true,
                                      padding: EdgeInsets.only(
                                        top:
                                            _isLoadingMore
                                                ? 60
                                                : 8, // 🎯 로드 모어 중일 때 상단 패딩 증가
                                        bottom: 8,
                                        left: 8,
                                        right: 8,
                                      ),
                                      itemCount: comments.length,
                                      itemBuilder: (context, index) {
                                        // 🎯 댓글 인덱스 계산
                                        final commentIndex =
                                            comments.length - 1 - index;

                                        final comment = comments[commentIndex];

                                        // GlobalKey 생성 (높이 측정용, 지연 생성으로 최적화)
                                        final commentKey = _commentKeys
                                            .putIfAbsent(
                                              comment.id,
                                              () => GlobalKey(),
                                            );

                                        // 🎯 성능 최적화: currentUser는 build에서 이미 읽음
                                        final isMe =
                                            currentUser != null &&
                                            comment.author ==
                                                currentUser.username;

                                        // 🎯 성능 최적화: 이전/다음 댓글 비교 최적화
                                        final bool showProfile;
                                        final bool showAuthorInfo;

                                        // reverse:true: commentIndex는 (comments.length - 1 - index)
                                        // - showProfile: 더 과거(chronological prev = commentIndex-1)와 비교
                                        // - showAuthorInfo: 더 최신(chronological next = commentIndex+1)과 비교
                                        if (commentIndex > 0) {
                                          final prevAuthor =
                                              comments[commentIndex - 1].author;
                                          showProfile =
                                              prevAuthor != comment.author;
                                        } else {
                                          showProfile = true;
                                        }

                                        if (commentIndex <
                                            comments.length - 1) {
                                          final nextAuthor =
                                              comments[commentIndex + 1].author;
                                          showAuthorInfo =
                                              nextAuthor != comment.author;
                                        } else {
                                          showAuthorInfo = true;
                                        }

                                        final targetComment =
                                            _findTargetComment(
                                              comment.parentId,
                                            );

                                        final isThisBouncing =
                                            _bouncingCommentId == comment.id;

                                        final dragNotifier =
                                            _dragOffsetNotifiers.putIfAbsent(
                                              comment.id,
                                              () => ValueNotifier(0.0),
                                            );

                                        return ValueListenableBuilder<double>(
                                          valueListenable: dragNotifier,
                                          builder: (context, dragOffset, _) {
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 0,
                                              ),
                                              child: AnimatedBuilder(
                                                animation: _bounceAnimation,
                                                builder: (context, child) {
                                                  return Transform.translate(
                                                    offset:
                                                        isThisBouncing
                                                            ? Offset(
                                                              0,
                                                              -30 *
                                                                  (_bounceAnimation
                                                                          .value -
                                                                      1.0),
                                                            )
                                                            : Offset.zero,
                                                    child: child,
                                                  );
                                                },
                                                child: CommentItem(
                                                  key: ValueKey(comment.id),
                                                  comment: comment,
                                                  commentService:
                                                      _commentService,
                                                  currentUser: currentUser,
                                                  isMe: isMe,
                                                  showProfile: showProfile,
                                                  showAuthorInfo:
                                                      showAuthorInfo,
                                                  onReactionToggle: (
                                                    commentId,
                                                    emoji,
                                                  ) {
                                                    _commentService
                                                        .toggleReaction(
                                                          commentId,
                                                          emoji,
                                                        );
                                                  },
                                                  onLongPress:
                                                      (offset, comment) =>
                                                          _onLongPress(
                                                            offset,
                                                            comment,
                                                          ),
                                                  onTapTargetComment:
                                                      _scrollToTargetComment,
                                                  targetComment: targetComment,
                                                  globalKey: commentKey,
                                                  bounceAnimationValue: 1.0,
                                                  isAnimating: false,
                                                  dragOffset: dragOffset,
                                                  onHorizontalDragUpdate: (
                                                    details,
                                                  ) {
                                                    _handleHorizontalDragUpdate(
                                                      comment.id,
                                                      details,
                                                      isMe,
                                                    );
                                                  },
                                                  onHorizontalDragEnd: (
                                                    details,
                                                  ) {
                                                    _handleHorizontalDragEnd(
                                                      comment.id,
                                                      details,
                                                      () {
                                                        // 🎯 setState와 requestFocus를 분리하여 블로킹 방지
                                                        setState(() {
                                                          _replyTarget =
                                                              comment;
                                                        });
                                                        // 🎯 키보드 포커스는 다음 프레임에 처리
                                                        WidgetsBinding.instance
                                                            .addPostFrameCallback((
                                                              _,
                                                            ) {
                                                              if (mounted) {
                                                                _focusNode
                                                                    .requestFocus();
                                                              }
                                                            });
                                                      },
                                                    );
                                                  },
                                                  onSwipeReply: () {
                                                    // 🎯 setState와 requestFocus를 분리하여 블로킹 방지
                                                    setState(() {
                                                      _replyTarget = comment;
                                                    });
                                                    // 🎯 키보드 포커스는 다음 프레임에 처리
                                                    WidgetsBinding.instance
                                                        .addPostFrameCallback((
                                                          _,
                                                        ) {
                                                          if (mounted) {
                                                            _focusNode
                                                                .requestFocus();
                                                          }
                                                        });
                                                  },
                                                  onProfileTap: (username) {
                                                    // 🎯 프로필 화면으로 이동
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute(
                                                        builder:
                                                            (
                                                              context,
                                                            ) => UserProfileScreen(
                                                              otherUser: User(
                                                                username:
                                                                    username,
                                                                profileImageUrl:
                                                                    comment
                                                                        .authorProfileImageUrl,
                                                              ),
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  postAuthorUsername:
                                                      widget
                                                          .postAuthorUsername, // 🎯 포스트 작성자 전달
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                    // 🎯 로드 모어 스피너 (상단에 표시)
                                    if (_isLoadingMore)
                                      Positioned(
                                        top: 8,
                                        left: 0,
                                        right: 0,
                                        child: Center(
                                          child: AnimatedBuilder(
                                            animation: _loadMoreSpinnerRotation,
                                            builder: (context, child) {
                                              return SizedBox(
                                                width: 32,
                                                height: 32,
                                                child: CustomSpinner(
                                                  progress: 1.0,
                                                  isAnimating: true,
                                                  rotation:
                                                      _loadMoreSpinnerRotation
                                                          .value,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                      ),
                    ),
                    // 🎯 입력 섹션 (키보드 위에 고정)
                    // - viewInsets가 내려가는 중에 0까지 내려갔다가(safe-area) 다시 올라오는 튐 방지:
                    //   "키보드 높이"가 safe-area보다 작아지면 더 이상 내려가지 않게 clamp
                    // ✅ 키보드 위치 보정은 "여기(바깥)"에서만 담당하고,
                    // `_buildInputSection()` 내부에서는 키보드 여부에 따른 SafeArea/패딩 토글을 제거해
                    // 키보드 dismiss 중 "과하게 내려갔다가 다시 올라오는" 2단 보정을 없앤다.
                    Container(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: _InputSectionWrapper(
                        onHeightChanged: (height) {
                          if (mounted && _inputSectionHeight != height) {
                            setState(() {
                              _inputSectionHeight = height;
                            });
                          }
                        },
                        child: _buildInputSection(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 🎯 맨 아래로 버튼 (오른쪽 하단)
        if (_showScrollToBottomButton)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            right: 16,
            bottom:
                (_isKeyboardActive &&
                        _replyTarget == null &&
                        _editingComment == null)
                    ? 70
                    : 110, // ✅ 일반 키보드: 70, 답글/수정: 100
            child: GestureDetector(
              onTap: _scrollToBottom,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface,
                  shape: BoxShape.circle,
                  boxShadow:
                      Theme.of(context).brightness == Brightness.light
                          ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                          : null,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.keyboard_arrow_down,
                      color: Theme.of(context).colorScheme.surface,
                      size: 28,
                    ),
                    // 새 메시지 배지
                    if (_showNewMessageBadge)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInputSection() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
      ),
      child: SafeArea(
        top: false, // 상단 SafeArea 비활성화
        bottom: true, // ✅ 항상 하단 SafeArea 유지 (키보드 보정은 바깥 AnimatedPadding에서 처리)
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTarget != null || _editingComment != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(
                  height: 0.3, // 🎯 더 얇게 (0.5 -> 0.3)
                  color: Theme.of(
                    context,
                  ).colorScheme.onBackground.withOpacity(0.2),
                ),
              ),
              SizedBox(height: 4),
              // 답글/편집 대상 표시 (더 얇게)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ), // 🎯 vertical 패딩 추가 (2px)
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _editingComment != null
                            ? AppLocalizations.of(
                              context,
                            ).translate('editing_comment')
                            : '${AppLocalizations.of(context).translate('reply_to')} ${_replyTarget!.author}',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onBackground.withOpacity(0.9),
                          fontSize: 14, // 🎯 폰트 크기 감소 (14 -> 12)
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        // 🎯 답글/편집 취소 시 명확한 동작
                        HapticFeedback.lightImpact();
                        setState(() {
                          _replyTarget = null;
                          _editingComment = null;
                          _textController.clear();
                          _selectedImageUrl = null;
                          _selectedImageFile = null;
                          _secretMessageTarget = null;
                        });
                        // 포커스 해제
                        _focusNode.unfocus();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4), // 🎯 패딩 감소 (8 -> 4)
                        child: Icon(
                          Icons.close,
                          color: Theme.of(
                            context,
                          ).colorScheme.onBackground.withOpacity(0.8),
                          size: 20, // 🎯 아이콘 크기 감소 (24 -> 20)
                        ),
                      ),
                    ),
                    const SizedBox(width: 4), // 🎯 간격 감소 (10 -> 4)
                  ],
                ),
              ),
            ],

            CommentInputSection(
              backgroundColor: Colors.transparent,
              foregroundColor: Theme.of(context).colorScheme.onBackground,
              commentController: _textController,
              focusNode: _focusNode,
              replyTarget: _replyTarget,
              editingComment: _editingComment,
              onSubmit: _submitComment,
              onCancelReply: () => setState(() => _replyTarget = null),
              onCancelEdit: () => setState(() => _editingComment = null),
              secretMessageTarget: _secretMessageTarget,
              onSecretMessageTargetChanged: (target) {
                setState(() {
                  _secretMessageTarget = target;
                });
              },
              comments: _commentService.comments, // 🎯 참여자 목록 추출용
              commentService: _commentService, // 🎯 채팅 참여자 목록 전달
              postAuthorUsername:
                  widget.postAuthorUsername, // 🎯 블로그 작성자 username
              selectedImageUrl: _selectedImageUrl, // 🎯 선택된 이미지 URL
              selectedImageFile: _selectedImageFile, // 🎯 선택된 이미지 파일
              onImageSelected: (imageUrl) {
                setState(() {
                  _selectedImageUrl = imageUrl;
                });
              },
              onImageFileSelected: (file) {
                // 🎯 각 이미지를 개별 댓글로 연속 전송
                _submitSingleImageComment(file);
              },
              onImageRemoved: () {
                setState(() {
                  _selectedImageUrl = null;
                  _selectedImageFile = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 댓글 입력 섹션 위젯
class CommentInputSection extends StatefulWidget {
  const CommentInputSection({
    super.key,
    required this.commentController,
    required this.focusNode,
    required this.replyTarget,
    required this.editingComment,
    required this.onSubmit,
    required this.onCancelReply,
    required this.onCancelEdit,
    this.backgroundColor,
    this.foregroundColor,
    this.secretMessageTarget, // 🎯 비밀 메시지 대상 사용자
    this.onSecretMessageTargetChanged, // 🎯 비밀 메시지 대상 변경 콜백
    this.comments = const [], // 🎯 참여자 목록 추출용
    this.commentService, // 🎯 채팅 참여자 목록 가져오기용
    this.postAuthorUsername, // 🎯 블로그 작성자 username (비밀 메시지용)
    this.selectedImageUrl, // 🎯 선택된 이미지 URL
    this.selectedImageFile, // 🎯 선택된 이미지 파일
    this.onImageSelected, // 🎯 이미지 선택 콜백
    this.onImageFileSelected, // 🎯 이미지 파일 선택 콜백
    this.onImageRemoved, // 🎯 이미지 제거 콜백
  });

  final TextEditingController commentController;
  final FocusNode focusNode;
  final Comment? replyTarget;
  final Comment? editingComment;
  final VoidCallback onSubmit;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final String? secretMessageTarget; // 🎯 비밀 메시지 대상 사용자
  final void Function(String?)?
  onSecretMessageTargetChanged; // 🎯 비밀 메시지 대상 변경 콜백
  final List<Comment> comments; // 🎯 참여자 목록 추출용
  final CommentService? commentService; // 🎯 채팅 참여자 목록 가져오기용
  final String? postAuthorUsername; // 🎯 블로그 작성자 username (비밀 메시지용)
  final String? selectedImageUrl; // 🎯 선택된 이미지 URL
  final File? selectedImageFile; // 🎯 선택된 이미지 파일
  final void Function(String)? onImageSelected; // 🎯 이미지 선택 콜백
  final void Function(File)? onImageFileSelected; // 🎯 이미지 파일 선택 콜백
  final VoidCallback? onImageRemoved; // 🎯 이미지 제거 콜백

  @override
  State<CommentInputSection> createState() => _CommentInputSectionState();
}

class _CommentInputSectionState extends State<CommentInputSection> {
  int _lastCursorPosition = 0;
  String? _mentionQuery; // 🎯 현재 멘션 검색어
  bool _isPrivate = false; // 🎯 비밀 챗 여부 (기본: 공개)
  String _previousText = ''; // 🎯 이전 텍스트 (삭제 감지용)
  bool _hasText = false; // 🎯 텍스트 입력 여부 (이미지 아이콘 표시용)

  /// 🎯 비밀 메시지 대상 선택 (블로그 작성자만 선택 가능)
  void _showSecretMessageTargetSelector() {
    final currentUser = context.read<UserProvider>().currentUser;
    final postAuthor = widget.postAuthorUsername;

    // 블로그 작성자가 없으면 비밀 메시지 불가
    if (postAuthor == null || postAuthor.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('비밀 메시지를 보낼 수 없습니다.'),
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() {
        _isPrivate = false;
        widget.onSecretMessageTargetChanged?.call(null);
      });
      return;
    }

    // 현재 사용자가 블로그 작성자인 경우 비밀 메시지 불가
    if (currentUser != null && currentUser.username == postAuthor) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('블로그 작성자는 비밀 메시지를 보낼 수 없습니다.'),
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() {
        _isPrivate = false;
        widget.onSecretMessageTargetChanged?.call(null);
      });
      return;
    }

    // 블로그 작성자를 비밀 메시지 대상으로 자동 설정
    setState(() {
      widget.onSecretMessageTargetChanged?.call(postAuthor);
    });
  }

  @override
  void initState() {
    super.initState();
    _previousText = widget.commentController.text;
    _hasText = widget.commentController.text.isNotEmpty; // 🎯 초기 텍스트 상태 확인
    widget.commentController.addListener(_onTextChanged);
    // 🎯 비밀 메시지 대상이 있으면 비밀 메시지 모드 활성화
    _isPrivate =
        widget.secretMessageTarget != null &&
        widget.secretMessageTarget!.isNotEmpty;
  }

  @override
  void didUpdateWidget(CommentInputSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🎯 비밀 메시지 대상이 변경되면 상태 업데이트
    if (widget.secretMessageTarget != oldWidget.secretMessageTarget) {
      _isPrivate =
          widget.secretMessageTarget != null &&
          widget.secretMessageTarget!.isNotEmpty;
    }
  }

  @override
  void dispose() {
    widget.commentController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    // 🎯 성능 최적화: 즉시 처리하지 않고 다음 프레임에 처리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final text = widget.commentController.text;
      final selection = widget.commentController.selection;
      final cursorPosition = selection.baseOffset;

      // 🎯 텍스트 입력 여부 업데이트 (이미지 아이콘 표시용)
      final hasText = text.trim().isNotEmpty;
      if (_hasText != hasText) {
        setState(() {
          _hasText = hasText;
        });
      }

      // 텍스트가 삭제되었는지 확인
      final isDeleting = text.length < _previousText.length;
      _previousText = text;

      // 커서 위치가 변경되지 않았으면 무시 (텍스트 삽입/삭제만 감지)
      if (cursorPosition == _lastCursorPosition && !isDeleting) {
        return;
      }
      _lastCursorPosition = cursorPosition;

      // @ 입력 감지
      if (cursorPosition > 0 && cursorPosition <= text.length) {
        final beforeCursor = text.substring(0, cursorPosition);

        // @로 시작하는 단어 찾기
        final lastAtIndex = beforeCursor.lastIndexOf('@');
        if (lastAtIndex != -1) {
          // @ 이후의 텍스트 추출 (공백이나 줄바꿈 전까지)
          final afterAt = beforeCursor.substring(lastAtIndex + 1);
          final spaceIndex = afterAt.indexOf(' ');
          final newlineIndex = afterAt.indexOf('\n');

          // 공백이나 줄바꿈이 있으면 멘션 모드 종료
          if (spaceIndex != -1 || newlineIndex != -1) {
            if (_mentionQuery != null) {
              setState(() {
                _mentionQuery = null;
              });
            }
            return;
          }

          // 삭제 중이고 @username 패턴 내에서 삭제가 발생하면 전체 삭제
          if (isDeleting && afterAt.isNotEmpty) {
            // @username 전체를 삭제
            final mentionEnd = lastAtIndex + 1 + afterAt.length;
            final beforeMention = text.substring(0, lastAtIndex);
            final afterMention = text.substring(mentionEnd);
            final newText = beforeMention + afterMention;

            widget.commentController.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: lastAtIndex),
            );

            setState(() {
              _mentionQuery = null;
            });
            _previousText = newText;
            _lastCursorPosition = lastAtIndex;
            return;
          }

          // @ 뒤에 텍스트가 있으면 멘션 오버레이 표시
          final mentionQuery = afterAt;
          if (_mentionQuery != mentionQuery) {
            setState(() {
              _mentionQuery = mentionQuery;
            });
          }
          return;
        }
      }

      // @가 없거나 멘션 범위를 벗어나면 오버레이 닫기
      if (_mentionQuery != null) {
        setState(() {
          _mentionQuery = null;
        });
      }
    });
  }

  void _insertMention(String username) {
    final text = widget.commentController.text;
    final selection = widget.commentController.selection;
    final cursorPosition = selection.baseOffset;

    if (cursorPosition > 0 && cursorPosition <= text.length) {
      final beforeCursor = text.substring(0, cursorPosition);
      final afterCursor = text.substring(cursorPosition);

      // @ 위치 찾기
      final lastAtIndex = beforeCursor.lastIndexOf('@');
      if (lastAtIndex != -1) {
        // @부터 커서 위치까지를 @username으로 교체
        final beforeAt = text.substring(0, lastAtIndex);
        final newText = '$beforeAt@$username $afterCursor';
        final newCursorPosition =
            beforeAt.length + username.length + 2; // @username + 공백

        widget.commentController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newCursorPosition),
        );
      }
    }

    setState(() {
      _mentionQuery = null;
    });
  }

  /// 🎯 이미지 선택 (업로드는 나중에) - 여러 이미지 지원
  Future<void> _pickAndUploadImage() async {
    try {
      final result = await Navigator.push<MediaPickerResult>(
        context,
        CupertinoPageRoute(
          fullscreenDialog: true,
          builder:
              (context) => MediaPickerScreen(
                initialMediaType: MediaType.image,
                maxSelectionCount: 5, // 🎯 최대 5개까지 선택 가능
                enableToggle: false, // 토글 없음 (이미지만)
                onMediaSelected: (file) {
                  // 선택 완료 시 처리
                },
              ),
        ),
      );

      if (result == null || result.files.isEmpty || !mounted) return;

      // 🎯 비밀 메시지 모드가 활성화되어 있으면 비밀 메시지 대상 설정
      if (_isPrivate && widget.secretMessageTarget == null) {
        // 🎯 비밀 메시지 모드가 켜져있는데 대상이 없으면 자동 설정
        _showSecretMessageTargetSelector();
      }

      // 🎯 선택된 모든 이미지를 연속적으로 전송 (각각을 개별 댓글로)
      for (final file in result.files) {
        // 🎯 각 이미지를 개별 댓글로 전송하기 위해 콜백 호출
        widget.onImageFileSelected?.call(file);
      }
    } catch (e) {
      debugPrint('이미지 선택 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('이미지 선택 오류: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color bgColor = widget.backgroundColor ?? scheme.surface;
    final Color fgColor = widget.foregroundColor ?? scheme.onSurface;

    // 🎯 상위에서 이미 패딩을 처리하므로 여기서는 추가 패딩 없음
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 멘션 오버레이 (언급 시에만 표시)
        if (_mentionQuery != null) ...[
          CommentMentionOverlay(
            searchQuery: _mentionQuery!,
            commentService: widget.commentService, // 🎯 채팅 참여자 목록 전달
            onSelect: (username) {
              _insertMention(username);
            },
            onClose: () {
              setState(() {
                _mentionQuery = null;
              });
            },
          ),
          SizedBox(height: 10),
        ],

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: Row(
            children: [
              // 🎯 비밀 메시지 토글 아이콘 (블로그 작성자와의 1:1 비밀 챗)
              // 블로그 작성자인 경우 아이콘 자체를 숨김
              if (widget.postAuthorUsername != null &&
                  widget.postAuthorUsername!.isNotEmpty)
                Builder(
                  builder: (context) {
                    final currentUser =
                        context.read<UserProvider>().currentUser;
                    final postAuthor = widget.postAuthorUsername;
                    // 현재 사용자가 블로그 작성자인 경우 비밀 메시지 기능 숨김
                    final isPostAuthor =
                        currentUser != null &&
                        currentUser.username == postAuthor;

                    // 블로그 작성자면 아이콘 자체를 숨김
                    if (isPostAuthor) {
                      return const SizedBox.shrink();
                    }

                    return Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Center(
                        // 🎯 세로 기준 가운데 정렬
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: IconButton(
                            onPressed: () {
                              setState(() {
                                _isPrivate = !_isPrivate;
                                // 비밀 메시지가 꺼지면 대상도 초기화
                                if (!_isPrivate) {
                                  widget.onSecretMessageTargetChanged?.call(
                                    null,
                                  );
                                } else {
                                  // 비밀 메시지 켜면 블로그 작성자를 대상으로 자동 설정
                                  _showSecretMessageTargetSelector();
                                }
                              });
                            },
                            icon: SvgPicture.asset(
                              _isPrivate
                                  ? 'assets/icons/lock.svg'
                                  : 'assets/icons/lock_open.svg',
                              width: 22,
                              height: 22,
                              color:
                                  _isPrivate
                                      ? Theme.of(context).colorScheme.primary
                                      : fgColor.withOpacity(0.5),
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(width: 8),

              // 텍스트 필드
              Expanded(
                child: TextField(
                  controller: widget.commentController,
                  focusNode: widget.focusNode,
                  cursorColor: fgColor,

                  // ✅ 여러 줄 입력 설정
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline, // 엔터 시 줄바꿈
                  maxLines: null, // 무제한 줄

                  style: TextStyle(
                    color: fgColor,
                    fontSize: 16, // 🎯 폰트 크기 감소 (18 -> 16)
                    fontWeight: FontWeight.w500,
                  ),

                  decoration: InputDecoration(
                    hintText:
                        widget.editingComment != null
                            ? AppLocalizations.of(
                              context,
                            ).translate('edit_comment_hint')
                            : widget.replyTarget != null
                            ? AppLocalizations.of(
                              context,
                            ).translate('write_reply')
                            : AppLocalizations.of(
                              context,
                            ).translate('write_comment'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(35),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: bgColor,
                    hintStyle: TextStyle(
                      color: fgColor.withOpacity(0.5),
                      fontSize: 16, // 🎯 폰트 크기 감소 (18 -> 16)
                      fontWeight: FontWeight.w500,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12, // 🎯 수직 패딩 감소 (12 -> 8)
                    ),
                    isDense: true,
                  ),

                  // ❌ onSubmitted 제거 (엔터를 줄바꿈으로 쓰기 위해)
                  // onSubmitted: (value) => onSubmit(),
                ),
              ),

              // 🎯 이미지 아이콘 (텍스트가 비어있을 때만 표시)
              if (!_hasText)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: _pickAndUploadImage,
                    child: SvgPicture.asset(
                      'assets/icons/editor_gallery.svg',
                      width: 29,
                      height: 29,
                      color: fgColor.withOpacity(0.5),
                    ),
                  ),
                ),

              // 보내기 아이콘
              Padding(
                padding: const EdgeInsets.only(left: 0, right: 20),
                child: GestureDetector(
                  onTap: widget.onSubmit,
                  child: Icon(
                    Icons.send_rounded,
                    size: 28,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 🎯 입력창 높이 측정용 래퍼 (성능 최적화)
class _InputSectionWrapper extends StatefulWidget {
  const _InputSectionWrapper({
    required this.onHeightChanged,
    required this.child,
  });

  final void Function(double height) onHeightChanged;
  final Widget child;

  @override
  State<_InputSectionWrapper> createState() => _InputSectionWrapperState();
}

class _InputSectionWrapperState extends State<_InputSectionWrapper> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 첫 렌더링 후 높이 측정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureHeight();
    });
  }

  void _measureHeight() {
    final context = _key.currentContext;
    if (context != null) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final height = renderBox.size.height;
        widget.onHeightChanged(height);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 높이 변화 감지를 위해 LayoutBuilder 사용 (최소한의 rebuild)
    return LayoutBuilder(
      builder: (context, constraints) {
        // 레이아웃이 변경되면 높이 재측정
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _measureHeight();
        });
        return Container(key: _key, child: widget.child);
      },
    );
  }
}
