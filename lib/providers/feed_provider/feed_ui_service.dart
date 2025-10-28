import 'package:doppy/data/services/blog_service.dart';
import 'dart:async';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FeedDisplayMode { card, imageOnly }

class FeedDisplayModeManager extends ValueNotifier<FeedDisplayMode> {
  static final FeedDisplayModeManager _instance =
      FeedDisplayModeManager._internal();

  factory FeedDisplayModeManager() => _instance;

  FeedDisplayModeManager._internal() : super(FeedDisplayMode.imageOnly) {
    // 기본: 이미지 전용. SharedPreferences에서 복원
    _restoreFromPrefs();
  }

  static const _prefsKey = 'feed_display_mode';

  void switchToCard() {
    value = FeedDisplayMode.card;
    _saveToPrefs();
  }

  void switchToImageOnly() {
    value = FeedDisplayMode.imageOnly;
    _saveToPrefs();
  }

  bool get isCard => value == FeedDisplayMode.card;
  bool get isImageOnly => value == FeedDisplayMode.imageOnly;

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        value == FeedDisplayMode.card ? 'card' : 'imageOnly',
      );
    } catch (_) {}
  }

  Future<void> _restoreFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_prefsKey);
      if (v == 'card') {
        super.value = FeedDisplayMode.card;
      } else if (v == 'imageOnly') {
        super.value = FeedDisplayMode.imageOnly;
      } else {
        super.value = FeedDisplayMode.imageOnly; // 기본값
      }
      // ignore: avoid_print
      print('[FeedDisplayModeManager] 복원 모드: ${super.value}');
      notifyListeners();
    } catch (_) {}
  }
}

class CategoryOverlayProvider extends ChangeNotifier {
  OverlayEntry? _overlayEntry;
  String? _categoryTitle;
  List<dynamic> _categoryPosts = [];

  bool get isVisible => _overlayEntry != null;
  String? get categoryTitle => _categoryTitle;
  List<dynamic> get categoryPosts => _categoryPosts;

  void showCategoryOverlay(
    BuildContext context,
    String title,
    List<dynamic> posts,
  ) {
    if (_overlayEntry != null) return; // 이미 표시 중이면 무시

    _categoryTitle = title;
    _categoryPosts = posts;

    Overlay.of(context).insert(_overlayEntry!);
    notifyListeners();
  }

  void hideCategoryOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _categoryTitle = null;
    _categoryPosts = [];
    notifyListeners();
  }
}

class PostDragDropService extends ChangeNotifier {
  bool _isDragging = false;
  PostData? _draggedPost;
  Offset _dragPosition = Offset.zero;
  String? _targetCategory;
  String? _hoverSectionKey; // 현재 손가락이 위치한 섹션(행)의 키
  String? _activeControllerKey; // 현재 활성화된 스크롤 컨트롤러 키 (배타적)
  OverlayEntry? _overlayEntry;
  ScrollController? _verticalController;
  final Map<String, ScrollController> _horizontalControllers =
      <String, ScrollController>{};
  Timer? _autoScrollTimer;

  // 자동 스크롤 동작 중 여부 (그리드 내 재배치 감지 일시 중지를 위해 노출)
  bool get isAutoScrolling => _autoScrollTimer != null;

  // 엣지 진입 순간부터 해제될 때까지 리오더 감지를 억제하는 래치
  bool _reorderSuppressed = false;
  bool get suppressReorder => _reorderSuppressed;

  // 드래그 위치 업데이트 스로틀링 제거(부자연스러운 끊김 방지)

  // Getters
  bool get isDragging => _isDragging;
  PostData? get draggedPost => _draggedPost;
  Offset get dragPosition => _dragPosition;
  String? get targetCategory => _targetCategory;

  // 드래그 시작
  void beginDrag(PostData post) {
    _isDragging = true;
    _draggedPost = post;
    _targetCategory = null;
    _reorderTargetIndex = null;
    notifyListeners();
  }

  // 드래그 위치 업데이트
  void updateDragPosition(Offset globalPosition) {
    _dragPosition = globalPosition;
    _maybeAutoScrollVertical();
    _maybeAutoScrollHorizontal();
    notifyListeners();
  }

  // 현재 드래그 위치에서 활성화되어야 할 컨트롤러 찾기
  String? _getActiveControllerKey() {
    if (!_isDragging) return null;

    // hoverSectionKey에서 category ID만 추출
    if (_hoverSectionKey != null) {
      return _hoverSectionKey!.split('_row').first;
    }

    // 기본 카테고리만 있는 경우
    return _targetCategory;
  }

  // 가로 재정렬 타겟 인덱스
  int? _reorderTargetIndex;
  int? get reorderTargetIndex => _reorderTargetIndex;
  void setReorderTargetIndex(int? index) {
    if (_reorderTargetIndex != index) {
      _reorderTargetIndex = index;
      notifyListeners();
    }
  }

  // 드래그 종료
  void endDrag() {
    // 오버레이 제거
    _removeOverlay();
    _stopAutoScroll();

    if (_draggedPost != null && _targetCategory != null) {
      // 실제 이동 처리는 DragTarget.onAccept에서 컨텍스트로 처리
      print('포스트 "${_draggedPost!.title}" 드롭 처리 완료(별도 onAccept 처리)');
    } else if (_draggedPost != null) {
      print('드래그 취소됨: ${_draggedPost!.title}');
    }

    _isDragging = false;
    _draggedPost = null;
    _dragPosition = Offset.zero;
    _targetCategory = null;
    _hoverSectionKey = null;
    _activeControllerKey = null; // 배타적 스크롤 리셋
    _reorderTargetIndex = null;
    // 드래그 직후 짧은 그레이스 기간: 스냅 로직 비활성화(프로필 스크롤 가드에서 사용)
    _snapGraceUntil = DateTime.now().add(const Duration(milliseconds: 250));
    notifyListeners();
  }

  // === 스냅 억제용 플래그(드래그 중/직후) ===
  DateTime? _snapGraceUntil;
  bool get shouldSuppressSnap {
    if (_isDragging) return true;
    if (_snapGraceUntil == null) return false;
    return DateTime.now().isBefore(_snapGraceUntil!);
  }

  // 드롭 타겟 설정
  void setDropTarget(String? category) {
    if (_targetCategory != category) {
      print('🎯 [PostDragDropService] 드롭 타겟 변경: $_targetCategory -> $category');
      _targetCategory = category;
      notifyListeners();
    }
  }

  // 현재 손가락이 위치한 섹션(행) 키를 등록
  void setHoverSectionKey(String sectionKey) {
    if (_hoverSectionKey != sectionKey) {
      _hoverSectionKey = sectionKey;
    }
  }

  // 프로필 세로 스크롤러 등록
  void setVerticalController(ScrollController controller) {
    _verticalController = controller;
  }

  void _maybeAutoScrollVertical() {
    if (!_isDragging) return;
    final sc = _verticalController;
    if (sc == null || !sc.hasClients) return;

    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final screenHeight = view.physicalSize.height / view.devicePixelRatio;
      const edge = 80.0; // 상/하단 오토 스크롤 트리거 영역
      // 가장자리에 가까울수록 속도를 높이고, 멀수록 낮추는 스무싱
      // 기본(포스트) 느리게, 엣지 억제 중에는 약간 빠르게
      final bool boost = _reorderSuppressed;
      final double minSpeed = boost ? 12.0 : 8.0;
      final double maxSpeed = boost ? 26.0 : 18.0;

      if (_dragPosition.dy < edge) {
        final ratio = (1.0 - (_dragPosition.dy / edge)).clamp(0.0, 1.0);
        final speed = minSpeed + (maxSpeed - minSpeed) * ratio;
        final next = (sc.offset - speed).clamp(
          0.0,
          sc.position.maxScrollExtent,
        );
        if (next != sc.offset) sc.jumpTo(next);
      } else if (_dragPosition.dy > screenHeight - edge) {
        final ratio = (1.0 - ((screenHeight - _dragPosition.dy) / edge)).clamp(
          0.0,
          1.0,
        );
        final speed = minSpeed + (maxSpeed - minSpeed) * ratio;
        final next = (sc.offset + speed).clamp(
          0.0,
          sc.position.maxScrollExtent,
        );
        if (next != sc.offset) sc.jumpTo(next);
      }
    } catch (_) {}
  }

  void _maybeAutoScrollHorizontal() {
    if (!_isDragging) return;

    final String? requestedKey = _getActiveControllerKey();
    if (requestedKey == null) return;

    // 배타적 스크롤: 새로운 키가 요청되면 활성 키 업데이트
    if (_activeControllerKey != requestedKey) {
      _activeControllerKey = requestedKey;
    }

    final sc = _horizontalControllers[_activeControllerKey];
    if (sc == null || !sc.hasClients) return;

    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final screenWidth = view.physicalSize.width / view.devicePixelRatio;
      const edge = 80.0;
      const minSpeed = 8.0;
      const maxSpeed = 18.0;

      if (_dragPosition.dx < edge) {
        final ratio = (1.0 - (_dragPosition.dx / edge)).clamp(0.0, 1.0);
        final speed = minSpeed + (maxSpeed - minSpeed) * ratio;
        final next = (sc.offset - speed).clamp(
          0.0,
          sc.position.maxScrollExtent,
        );
        if (next != sc.offset) sc.jumpTo(next);
      } else if (_dragPosition.dx > screenWidth - edge) {
        final ratio = (1.0 - ((screenWidth - _dragPosition.dx) / edge)).clamp(
          0.0,
          1.0,
        );
        final speed = minSpeed + (maxSpeed - minSpeed) * ratio;
        final next = (sc.offset + speed).clamp(
          0.0,
          sc.position.maxScrollExtent,
        );
        if (next != sc.offset) sc.jumpTo(next);
      }
    } catch (_) {}
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  // 오버레이 제거
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 섹션(가로 리스트)별 스크롤 컨트롤러 제공
  // category ID만 사용하여 키로 저장 (row 정보 없음)
  ScrollController horizontalControllerFor(String categoryId) {
    return _horizontalControllers.putIfAbsent(
      categoryId,
      () => ScrollController(),
    );
  }

  // 포스트 카테고리 이동 (새로운 API 연동)
  Future<void> movePostToCategory(
    PostData post,
    int targetCategoryId, {
    int? targetPosition,
  }) async {
    print('   - 포스트 ID: ${post.id}');
    print('   - 포스트 제목: ${post.title}');
    print('   - 타겟 카테고리 ID: $targetCategoryId');
    print('   - 타겟 위치: $targetPosition');

    try {
      // 새로운 API 호출
      await BlogService().movePostToCategory(
        postId: int.parse(post.id),
        targetCategoryId: targetCategoryId,
        targetPosition: targetPosition,
      );

      print('✅ [PostDragDropService] 포스트 카테고리 이동 완료');
    } catch (e) {
      print('❌ [PostDragDropService] 포스트 카테고리 이동 실패: $e');
      rethrow;
    }
  }

  // 컨텍스트를 인자로 받아 로컬 피드를 즉시 반영 (새로운 API 구조)
  Future<void> movePostToCategoryWithContext(
    BuildContext context,
    PostData post,
    int targetCategoryId, {
    int? targetPosition,
    BaseFeedProvider? provider,
  }) async {
    provider ??= context.read<BaseFeedProvider>();

    // 백업: 원래 카테고리 정보 저장
    String? sourceCategoryId;
    int? sourcePosition;
    Map<String, dynamic>? backupPost;

    // 원본 위치 찾기
    for (final categoryId in provider.postsByCategory.keys) {
      final posts = provider.postsByCategory[categoryId]!;
      final idx = posts.indexWhere((p) => '${p['id']}' == post.id);
      if (idx != -1) {
        sourceCategoryId = categoryId;
        sourcePosition = idx;
        backupPost = Map<String, dynamic>.from(posts[idx]);
        break;
      }
    }

    // 동일한 위치에 드롭하는 경우 서버 요청하지 않음
    if (sourceCategoryId == targetCategoryId.toString() &&
        sourcePosition == targetPosition) {
      return;
    }

    print(
      '[FeedService] 포스트 이동 시작: ${post.id} ($sourceCategoryId[$sourcePosition] → $targetCategoryId[$targetPosition])',
    );

    // 1) 낙관적 로컬 반영 (먼저 UI 업데이트)
    provider.movePostLocally(post.id, targetCategoryId, targetPosition);

    // 2) 서버 저장 시도
    try {
      await movePostToCategory(
        post,
        targetCategoryId,
        targetPosition: targetPosition,
      );
      print('[FeedService] 서버 저장 완료');
    } catch (e) {
      print('⚠️ [FeedService] 서버 이동 실패, 롤백: $e');

      // 3) 실패 시 롤백
      if (sourceCategoryId != null && backupPost != null) {
        provider.movePostLocally(
          post.id,
          int.tryParse(sourceCategoryId) ?? 0,
          sourcePosition,
        );
      }

      // 사용자에게 알림
      try {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이동 실패: 서버 오류가 발생했습니다')));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _stopAutoScroll();
    for (final ctrl in _horizontalControllers.values) {
      ctrl.dispose();
    }
    _horizontalControllers.clear();
    super.dispose();
  }
}

// 피드 드래그 오버레이 위젯
class _FeedDragOverlay extends StatefulWidget {
  const _FeedDragOverlay({required this.dragService});

  final PostDragDropService dragService;

  @override
  State<_FeedDragOverlay> createState() => _FeedDragOverlayState();
}

class _FeedDragOverlayState extends State<_FeedDragOverlay> {
  @override
  void initState() {
    super.initState();
    // 드래그 서비스의 변경사항을 듣기 위해 리스너 등록
    widget.dragService.addListener(_onDragServiceChanged);
  }

  @override
  void dispose() {
    widget.dragService.removeListener(_onDragServiceChanged);
    super.dispose();
  }

  void _onDragServiceChanged() {
    // 드래그 위치가 변경될 때마다 위젯을 다시 빌드
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasTarget = widget.dragService.targetCategory != null;

    return Positioned(
      left: widget.dragService.dragPosition.dx - 75,
      top: widget.dragService.dragPosition.dy - 100,
      child: IgnorePointer(
        child: Stack(
          children: [
            Transform.rotate(
              angle: 0.05, // 살짝 기울어짐 효과
              child: Container(
                width: 150,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color:
                          hasTarget
                              ? Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.4)
                              : Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      widget.dragService.draggedPost?.thumbnailImageUrl ?? '',
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) =>
                              const Icon(Icons.error),
                    ),
                  ),
                ),
              ),
            ),

            // 드롭 타겟 표시
            if (hasTarget)
              Positioned(
                bottom: -25,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '${widget.dragService.targetCategory}로 이동',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
