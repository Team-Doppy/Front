import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/comment_item.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';

class CommentBottomSheet extends StatefulWidget {
  const CommentBottomSheet({
    super.key,
    required this.title,
    required this.commentService,
    this.scrollToCommentId, // 🎯 특정 댓글로 스크롤할 댓글 ID
  });
  final String title;
  final CommentService commentService;
  final String? scrollToCommentId; // 🎯 특정 댓글로 스크롤할 댓글 ID

  @override
  State<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends State<CommentBottomSheet>
    with SingleTickerProviderStateMixin {
  late final CommentService _commentService;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _commentKeys = {}; // 높이 측정용 GlobalKey

  Comment? _replyTarget;
  Comment? _editingComment;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  String? _bouncingCommentId;

  bool _showScrollToBottomButton = false; // 맨 아래로 버튼 표시 여부
  bool _showNewMessageBadge = false; // 새 메시지 알림 표시 여부
  int _lastCommentCount = 0; // 마지막 댓글 수
  bool _isKeyboardActive = false; // 키보드 활성화 상태
  bool _isInitialLoad = true; // 🎯 처음 열었을 때만 페이드인 적용
  bool _isLoadingTargetComment = false; // 타겟 댓글 로딩 중 표시 여부
  double _inputSectionHeight = 80.0; // 🎯 입력창 높이 (기본값, 실제 높이로 업데이트)

  // 🎯 성능 최적화: 타겟 댓글 캐싱
  final Map<String, Comment?> _targetCommentCache = {};

  // 🎯 드래그 상태 관리 (부모에서 관리)
  final Map<String, double> _dragOffsets = {};

  @override
  void initState() {
    super.initState();
    _commentService = widget.commentService;
    _commentService.addListener(_onCommentsChanged);
    _scrollController.addListener(_onScroll);

    // 🎯 초기 댓글 수 확인 (프레임 렌더링 후 정확한 개수로 판단)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _lastCommentCount = _commentService.getAllComments().length;

        // 🎯 초기 댓글 수에 따라 스크롤 방향 결정
        // 18개 미만: reverse=false (위에서부터, 페이지네이션 불필요)
        // 18개 이상: reverse=true (아래에서부터, 채팅 앱 방식)

        // 🎯 초기 로드 완료 후 페이드인 비활성화 (더 빠르게)
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() {
              _isInitialLoad = false;
            });
          }
        });

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
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {
        _isKeyboardActive = _focusNode.hasFocus;
        // 🎯 키보드가 내려가면 답글/수정 모드 취소
        if (!_focusNode.hasFocus) {
          _replyTarget = null;
          _editingComment = null;
        }
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // 🎯 맨 아래로 버튼 표시 여부 (스크롤 방향에 따라 다름)
    final bool isAtBottom;

    // reverse:true이면 offset < 100이면 아래
    isAtBottom = offset < 100;

    if (_showScrollToBottomButton != !isAtBottom) {
      setState(() {
        _showScrollToBottomButton = !isAtBottom;
      });
    }

    // reverse:true: maxScroll 가까이 = 과거 댓글(상단)
    if (maxScroll > 0 &&
        maxScroll - offset < 400 &&
        !_commentService.isLoading &&
        _commentService.hasMoreComments) {
      _commentService.loadComments();
    }
  }

  @override
  void dispose() {
    _commentService.removeListener(_onCommentsChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _bounceController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCommentsChanged() {
    if (!mounted) return;

    final allComments = _commentService.getAllComments();
    final currentCount = allComments.length;

    // 🎯 성능 최적화: currentUser는 필요할 때만 읽기
    User? currentUser;

    // 삭제된 댓글의 GlobalKey 정리
    final currentCommentIds = allComments.map((c) => c.id).toSet();
    _commentKeys.removeWhere((id, key) => !currentCommentIds.contains(id));
    // 삭제된 댓글의 드래그 오프셋 정리
    _dragOffsets.removeWhere((id, offset) => !currentCommentIds.contains(id));

    // 새 댓글이 추가되었는지 확인
    if (currentCount > _lastCommentCount && !_commentService.isLoading) {
      if (allComments.isNotEmpty) {
        currentUser ??= context.read<UserProvider>().currentUser;
        // 🎯 항상 최신 데이터로 정렬 (캐시 제거)
        final sortedComments = List<Comment>.from(allComments)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final latestComment = sortedComments.last;
        final commentAge = DateTime.now().difference(
          TimeUtils.toLocalTime(latestComment.createdAt),
        );

        if (commentAge.inSeconds < 3) {
          final isMyComment = latestComment.author == currentUser?.username;
          if (isMyComment) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scrollToBottom();
            });
          } else if (_showScrollToBottomButton) {
            setState(() => _showNewMessageBadge = true);
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) setState(() => _showNewMessageBadge = false);
            });
          }
        }
      }
    }

    _lastCommentCount = currentCount;

    // 🎯 notifyListeners() 호출 시 항상 setState 호출 (이모지 변경 등 모든 변경사항 반영)
    if (mounted) {
      setState(() {});
    }
  }

  void _submitComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final currentUser = context.read<UserProvider>().currentUser;
    if (currentUser == null) return;

    // 편집 모드
    if (_editingComment != null) {
      final commentId = _editingComment!.id;

      // 🎯 즉시 상태 초기화 (딜레이 없이)
      setState(() {
        _editingComment = null;
        _textController.clear();
      });

      // 서버 요청은 백그라운드에서 처리 (await 제거)
      _commentService.updateComment(commentId, text);
      return;
    }

    // 새 댓글/답글 추가
    final replyTargetId = _replyTarget?.id;

    // 🎯 즉시 상태 초기화 (딜레이 없이)
    setState(() {
      _textController.clear();
      _replyTarget = null;
    });

    // 서버 요청은 백그라운드에서 처리 (await 제거)
    _commentService.addComment(
      username: currentUser.username,
      content: text,
      authorProfileImageUrl: currentUser.profileImageUrl, // 🎯 프로필 이미지 즉시 전달
      parentId: replyTargetId,
    );
  }

  // 🎯 드래그 핸들러 (부모에서 관리)
  void _handleHorizontalDragUpdate(
    String commentId,
    DragUpdateDetails details,
    bool isMe,
  ) {
    setState(() {
      final delta = details.delta.dx;
      final currentOffset = _dragOffsets[commentId] ?? 0.0;
      // 타인 댓글: 오른쪽으로만 (왼쪽에서 오른쪽), 내 댓글: 왼쪽으로만 (오른쪽에서 왼쪽)
      if (!isMe && delta > 0) {
        _dragOffsets[commentId] = (currentOffset + delta).clamp(0.0, 80.0);
      } else if (isMe && delta < 0) {
        _dragOffsets[commentId] = (currentOffset + delta).clamp(-80.0, 0.0);
      }
    });
  }

  void _handleHorizontalDragEnd(
    String commentId,
    DragEndDetails details,
    VoidCallback onSwipeReply,
  ) {
    final offset = _dragOffsets[commentId] ?? 0.0;
    if (offset.abs() > 40.0) {
      // 임계값 초과 시 답글 실행
      HapticFeedback.mediumImpact();
      onSwipeReply();
    }

    // 원위치로 복귀 (애니메이션)
    setState(() {
      _dragOffsets[commentId] = 0.0;
    });
  }

  void _onLongPress(Offset offset, Comment comment) {
    HapticFeedback.mediumImpact();
    final currentUser = context.read<UserProvider>().currentUser;
    final isMyComment =
        currentUser != null && comment.author == currentUser.username;
    openCommentMenu(
      context,
      anchor: offset,
      comment: comment,
      isMyComment: isMyComment,
    ).then((value) {
      if (value == null) return;
      if (value == 'reply') {
        setState(() => _replyTarget = comment);
        _focusNode.requestFocus();
      } else if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: comment.content));
      } else if (value == 'edit') {
        setState(() {
          _editingComment = comment;
          _textController.text = comment.content;
          _replyTarget = null;
        });
        _focusNode.requestFocus();
      } else if (value == 'delete') {
        _commentService.deleteComment(comment.id);
      } else {
        _commentService.toggleReaction(comment.id, value);
      }
    });
  }

  void _scrollToBottom() {
    // 🎯 맨 아래(최신 댓글)로 스크롤
    if (!_scrollController.hasClients) return;

    final targetOffset = 0.0; // 0이 맨 아래

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    // 새 메시지 배지 숨김
    if (_showNewMessageBadge) {
      setState(() {
        _showNewMessageBadge = false;
      });
    }
  }

  /// 카톡/인스타 방식: 타겟 댓글이 있을 법한 페이지를 한 번에 계산해서 로드
  Future<bool> _loadTargetPage(String commentId) async {
    // 로딩 인디케이터 즉시 표시
    if (mounted) {
      setState(() {
        _isLoadingTargetComment = true;
      });
    }

    try {
      // 1) 이미 로드된 댓글 중에 타겟이 있는지 확인
      var comments = _commentService.getAllComments();
      var targetIndex = comments.indexWhere((c) => c.id == commentId);

      if (targetIndex != -1) {
        debugPrint('[CommentBottomSheet] ✅ 타겟 댓글 이미 로드됨');
        return true;
      }

      // 2) 타겟 댓글이 있을 법한 페이지 계산
      // 전체 댓글 수와 현재 로드된 댓글 수를 비교해서 페이지 추정
      final totalCount = _commentService.getTotalCommentCount();
      final loadedCount = comments.length;
      const pageSize = 20;

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

        // 타겟 댓글 확인
        comments = _commentService.getAllComments();
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
            setState(() {
              _isLoadingTargetComment = false;
            });
          }
        });
      }
    }
  }

  /// 키 기반 정확한 스크롤: Scrollable.ensureVisible 사용
  void _scrollToTargetComment(String commentId) async {
    if (!_scrollController.hasClients) {
      // 스크롤 컨트롤러가 준비되지 않았으면 다음 프레임에서 재시도
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToTargetComment(commentId);
        }
      });
      return;
    }

    // 1) 타겟 댓글이 로드되었는지 확인
    var comments = _commentService.getAllComments();
    var targetIndex = comments.indexWhere((c) => c.id == commentId);

    // 2) 못 찾으면 → 타겟이 있을 법한 페이지를 한 번에 로드
    if (targetIndex == -1) {
      final found = await _loadTargetPage(commentId);
      if (!found || !mounted) {
        if (mounted) {
          setState(() {
            _isLoadingTargetComment = false;
          });
        }
        return;
      }

      // 다시 인덱스 찾기 (최신 상태로)
      comments = _commentService.getAllComments();
      targetIndex = comments.indexWhere((c) => c.id == commentId);
      if (targetIndex == -1) {
        debugPrint('[CommentBottomSheet] ❌ 타겟 댓글을 찾을 수 없음');
        if (mounted) {
          setState(() {
            _isLoadingTargetComment = false;
          });
        }
        return;
      }
    }

    // 3) 타겟 댓글의 GlobalKey 생성 (itemBuilder에서 생성되지만 미리 생성)
    final targetKey = _commentKeys.putIfAbsent(commentId, () => GlobalKey());

    // 4) 타겟 댓글로 대략적인 위치로 먼저 스크롤 (ListView 렌더링 범위 안으로 가져오기)
    // reverse:true이므로 역순 인덱스 계산
    final reversedIndex = comments.length - 1 - targetIndex;

    // 대략적인 아이템 높이 추정 (평균 60px)
    const estimatedItemHeight = 60.0;
    final estimatedOffset = reversedIndex * estimatedItemHeight;

    // maxScrollExtent 확인 (NaN 체크)
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (!maxScroll.isFinite || maxScroll < 0) {
      debugPrint('[CommentBottomSheet] ⚠️ 유효하지 않은 maxScrollExtent: $maxScroll');
      if (mounted) {
        setState(() {
          _isLoadingTargetComment = false;
        });
      }
      return;
    }

    if (!estimatedOffset.isFinite) {
      debugPrint(
        '[CommentBottomSheet] ⚠️ 유효하지 않은 estimatedOffset: $estimatedOffset',
      );
      if (mounted) {
        setState(() {
          _isLoadingTargetComment = false;
        });
      }
      return;
    }

    final clampedOffset = estimatedOffset.clamp(0.0, maxScroll);
    if (!clampedOffset.isFinite) {
      debugPrint(
        '[CommentBottomSheet] ⚠️ 유효하지 않은 clampedOffset: $clampedOffset',
      );
      if (mounted) {
        setState(() {
          _isLoadingTargetComment = false;
        });
      }
      return;
    }

    debugPrint(
      '[CommentBottomSheet] 📍 대략적 위치로 스크롤: index=$targetIndex, reversed=$reversedIndex, offset=$clampedOffset',
    );

    // 대략적인 위치로 jumpTo (타겟 댓글이 ListView 렌더링 범위 안에 들어오도록)
    _scrollController.jumpTo(clampedOffset);

    // 5) 스크롤 후 렌더링 완료 대기 (타겟 댓글이 ListView에 렌더링되도록)
    await Future.delayed(const Duration(milliseconds: 200));
    await WidgetsBinding.instance.endOfFrame;

    // 6) setState로 리스트 업데이트 강제 (키가 생성되도록)
    if (mounted) {
      setState(() {});
    }

    // 7) 렌더링 완료 대기
    await Future.delayed(const Duration(milliseconds: 200));
    await WidgetsBinding.instance.endOfFrame;

    // 8) 키의 context가 준비될 때까지 대기 (재시도 로직)
    BuildContext? targetContext;
    for (int retry = 0; retry < 15; retry++) {
      if (!mounted) return;

      await WidgetsBinding.instance.endOfFrame;
      targetContext = targetKey.currentContext;

      if (targetContext != null) {
        debugPrint(
          '[CommentBottomSheet] ✅ 타겟 댓글 context 찾음 (시도: ${retry + 1})',
        );
        break;
      }

      // context가 없으면 setState로 리빌드 강제
      if (mounted) {
        setState(() {});
      }

      if (retry < 14) {
        // 재시도 간격 점진적 증가
        await Future.delayed(Duration(milliseconds: 100 + (retry * 30)));
      }
    }

    if (targetContext == null) {
      debugPrint('[CommentBottomSheet] ❌ 타겟 댓글의 context를 찾을 수 없음 (최대 재시도 초과)');
      if (mounted) {
        setState(() {
          _isLoadingTargetComment = false;
        });
      }
      return;
    }

    // 8) Scrollable.ensureVisible로 정확한 위치로 스크롤
    try {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );

      // 9) 바운싱 애니메이션
      if (mounted) {
        setState(() => _bouncingCommentId = commentId);
        _bounceController.forward(from: 0.0).then((_) {
          if (mounted) {
            _bounceController.reset();
            setState(() => _bouncingCommentId = null);
          }
        });
      }
    } catch (e) {
      debugPrint('[CommentBottomSheet] ❌ 스크롤 실패: $e');
    }

    // 10) 로딩 인디케이터 숨김
    if (mounted) {
      setState(() {
        _isLoadingTargetComment = false;
      });
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
      final allComments = _commentService.getAllComments();
      final target = allComments.firstWhere((c) => c.id == parentId);
      _targetCommentCache[parentId] = target;
      return target;
    } catch (_) {
      _targetCommentCache[parentId] = null;
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 성능 최적화: 정렬된 댓글 리스트 캐싱
    final allComments = _commentService.getAllComments();
    // 🎯 항상 최신 데이터로 정렬 (캐시 제거)
    final comments = List<Comment>.from(allComments)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // 🎯 성능 최적화: currentUser를 build에서 한 번만 읽기
    final currentUser = context.read<UserProvider>().currentUser;

    final showLoadingSpinner = _commentService.isLoading && comments.isEmpty;

    if (showLoadingSpinner) {
      debugPrint('[CommentBottomSheet] 로딩 스피너 표시 - 댓글 없음');
    }

    return Stack(
      children: [
        // 타겟 댓글 로딩 인디케이터
        if (_isLoadingTargetComment)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).colorScheme.background,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(16),

                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.onBackground,
                        ),
                      ),
                    ],
                  ),
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
                body: Stack(
                  children: [
                    // 🎯 성능 최적화: ListView는 고정 높이 (키보드 높이 직접 반영 안 함)
                    Positioned.fill(
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
                                : RawScrollbar(
                                  controller: _scrollController,
                                  thumbColor: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.3),
                                  thickness: 4,
                                  radius: const Radius.circular(2),
                                  thumbVisibility: false,
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      key: const PageStorageKey('comment_list'),
                                      controller: _scrollController,
                                      reverse: true, // 🎯 동적 스크롤 방향
                                      padding: EdgeInsets.only(
                                        top: 8,
                                        bottom:
                                            _inputSectionHeight +
                                            8, // 🎯 입력창 높이만큼 padding 추가
                                        left: 8,
                                        right: 8,
                                      ),
                                      itemCount: comments.length,
                                      cacheExtent: 500,
                                      itemBuilder: (context, index) {
                                        // 🎯 댓글 인덱스 계산
                                        final commentIndex =
                                            comments.length -
                                            1 -
                                            index; // reverse:true일 때 역순

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

                                        if (commentIndex > 0) {
                                          final prevAuthor =
                                              comments[commentIndex - 1].author;
                                          showProfile =
                                              prevAuthor != comment.author;
                                        } else {
                                          showProfile =
                                              true; // 첫 번째 댓글은 항상 프로필 표시
                                        }

                                        if (commentIndex <
                                            comments.length - 1) {
                                          final nextAuthor =
                                              comments[commentIndex + 1].author;
                                          showAuthorInfo =
                                              nextAuthor != comment.author;
                                        } else {
                                          showAuthorInfo =
                                              true; // 마지막 댓글은 항상 작성자 정보 표시
                                        }

                                        final targetComment =
                                            _findTargetComment(
                                              comment.parentId,
                                            );

                                        final isThisBouncing =
                                            _bouncingCommentId == comment.id;

                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 0,
                                          ),
                                          child: AnimatedOpacity(
                                            opacity: _isInitialLoad ? 0.0 : 1.0,
                                            duration: const Duration(
                                              milliseconds:
                                                  150, // 🎯 더 빠른 페이드인 (300ms → 150ms)
                                            ),
                                            curve: Curves.easeOut,
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
                                                commentService: _commentService,
                                                currentUser: currentUser,
                                                isMe: isMe,
                                                showProfile: showProfile,
                                                showAuthorInfo: showAuthorInfo,
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
                                                dragOffset:
                                                    _dragOffsets[comment.id] ??
                                                    0.0,
                                                onHorizontalDragUpdate: (
                                                  details,
                                                ) {
                                                  _handleHorizontalDragUpdate(
                                                    comment.id,
                                                    details,
                                                    isMe,
                                                  );
                                                },
                                                onHorizontalDragEnd: (details) {
                                                  _handleHorizontalDragEnd(
                                                    comment.id,
                                                    details,
                                                    () {
                                                      setState(() {
                                                        _replyTarget = comment;
                                                      });
                                                      _focusNode.requestFocus();
                                                    },
                                                  );
                                                },
                                                onSwipeReply: () {
                                                  setState(
                                                    () =>
                                                        _replyTarget = comment,
                                                  );
                                                  _focusNode.requestFocus();
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
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                      ),
                    ),
                    // 🎯 성능 최적화: 입력창을 Positioned로 키보드 위에 고정 (카톡/인스타 구조)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: MediaQuery.of(context).viewInsets.bottom,
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
    // 🎯 성능 최적화: 입력창은 Positioned로 고정되므로 AnimatedPadding 제거
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 0,
        bottom: keyboardHeight > 0 ? 0 : bottomInset / 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
      ),
      child: SafeArea(
        top: false, // 상단 SafeArea 비활성화
        bottom: keyboardHeight == 0, // 키보드가 없을 때만 하단 SafeArea 활성화
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTarget != null || _editingComment != null) ...[
              Divider(
                height: 0.5,
                color: Theme.of(
                  context,
                ).colorScheme.onBackground.withOpacity(0.2),
              ),
              SizedBox(height: 4),
              // 답글/편집 대상 표시
              Container(
                padding: const EdgeInsets.all(4),

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
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _replyTarget = null;
                          _editingComment = null;
                          _textController.clear();
                        });
                      },
                      child: Icon(
                        Icons.close,
                        color: Theme.of(
                          context,
                        ).colorScheme.onBackground.withOpacity(0.7),
                        size: 20,
                      ),
                    ),
                    SizedBox(width: 10),
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
            ),
          ],
        ),
      ),
    );
  }
}

/// 댓글 입력 섹션 위젯
class CommentInputSection extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color bgColor = backgroundColor ?? scheme.surface;
    final Color fgColor = foregroundColor ?? scheme.onSurface;

    // 🎯 상위에서 이미 패딩을 처리하므로 여기서는 추가 패딩 없음
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 입력창
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: commentController,
                focusNode: focusNode,
                cursorColor: fgColor,

                // ✅ 여러 줄 입력 설정
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline, // 엔터 시 줄바꿈
                maxLines: null, // 무제한 줄

                style: TextStyle(color: fgColor),
                decoration: InputDecoration(
                  hintText:
                      editingComment != null
                          ? AppLocalizations.of(
                            context,
                          ).translate('edit_comment_hint')
                          : replyTarget != null
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
                  hintStyle: TextStyle(color: fgColor.withOpacity(0.5)),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12, // 높이 확보
                  ),
                  suffixIcon: IconButton(
                    onPressed: onSubmit,
                    icon: Icon(Icons.send_rounded, size: 24, color: fgColor),
                  ),
                ),

                // ❌ onSubmitted 제거 (엔터를 줄바꿈으로 쓰기 위해)
                // onSubmitted: (value) => onSubmit(),
              ),
            ),
          ],
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
