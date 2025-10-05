import 'package:doppy/pages/components/comps_for_profile/category_fullscreen_overlay.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/profile_feed_provider.dart';

enum FeedDisplayMode { card, imageOnly }

class FeedDisplayModeManager extends ValueNotifier<FeedDisplayMode> {
  static final FeedDisplayModeManager _instance =
      FeedDisplayModeManager._internal();

  factory FeedDisplayModeManager() => _instance;

  FeedDisplayModeManager._internal() : super(FeedDisplayMode.card);

  void switchToCard() => value = FeedDisplayMode.card;
  void switchToImageOnly() => value = FeedDisplayMode.imageOnly;

  bool get isCard => value == FeedDisplayMode.card;
  bool get isImageOnly => value == FeedDisplayMode.imageOnly;
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

    _overlayEntry = OverlayEntry(
      builder: (context) => const CategoryFullscreenOverlay(),
    );

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
  OverlayEntry? _overlayEntry;
  ScrollController? _verticalController;
  final Map<String, ScrollController> _horizontalControllers =
      <String, ScrollController>{};

  // Getters
  bool get isDragging => _isDragging;
  PostData? get draggedPost => _draggedPost;
  Offset get dragPosition => _dragPosition;
  String? get targetCategory => _targetCategory;

  // 드래그 시작
  void startDrag(PostData post, Offset globalPosition, BuildContext context) {
    print('🚀 [PostDragDropService] 드래그 시작: ${post.title}');
    _isDragging = true;
    _draggedPost = post;
    _dragPosition = globalPosition;
    _targetCategory = null;
    // NOTE: Draggable의 feedback을 사용할 것이므로 커스텀 오버레이는 사용하지 않음
    notifyListeners();
  }

  // Draggable(onDragStarted) 용 간소화된 시작 메서드
  void beginDrag(PostData post) {
    print('🚀 [PostDragDropService] beginDrag: ${post.title}');
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
    notifyListeners();
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
      const speed = 14.0; // 한 번에 이동 픽셀

      if (_dragPosition.dy < edge) {
        final next = (sc.offset - speed).clamp(
          0.0,
          sc.position.maxScrollExtent,
        );
        if (next != sc.offset) sc.jumpTo(next);
      } else if (_dragPosition.dy > screenHeight - edge) {
        final next = (sc.offset + speed).clamp(
          0.0,
          sc.position.maxScrollExtent,
        );
        if (next != sc.offset) sc.jumpTo(next);
      }
    } catch (_) {}
  }

  // 오버레이 제거
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 섹션(가로 리스트)별 스크롤 컨트롤러 제공
  ScrollController horizontalControllerFor(String sectionId) {
    return _horizontalControllers.putIfAbsent(
      sectionId,
      () => ScrollController(),
    );
  }

  // 포스트 카테고리 이동 (실제 구현 필요)
  void movePostToCategory(PostData post, String newCategory) {
    // TODO: 실제 API 호출로 포스트 카테고리 변경
    print('🚀 [PostDragDropService] 포스트 카테고리 이동 시작');
    print('   - 포스트 ID: ${post.id}');
    print('   - 포스트 제목: ${post.title}');
    print('   - 현재 카테고리: ${post.accessLevel}');
    print('   - 새로운 카테고리: $newCategory');

    // 실제로는 여기서 API 호출을 해야 합니다
    // await apiService.updatePostCategory(post.id, newCategory);

    // 성공 메시지
    print('✅ [PostDragDropService] 포스트 카테고리 이동 완료');
  }

  // 컨텍스트를 인자로 받아 로컬 피드를 즉시 반영
  void movePostToCategoryWithContext(
    BuildContext context,
    PostData post,
    String newCategory,
  ) {
    movePostToCategory(post, newCategory);
    try {
      AccessLevel level = AccessLevel.public;
      if (newCategory.contains('나만'))
        level = AccessLevel.private;
      else if (newCategory.contains('그룹'))
        level = AccessLevel.groups;
      context.read<ProfileFeedProvider>().updatePostAccessLevelById(
        post.id,
        level,
      );
    } catch (e) {
      print('⚠️ [PostDragDropService] 로컬 피드 반영 실패: $e');
    }
  }

  @override
  void dispose() {
    _removeOverlay();
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
