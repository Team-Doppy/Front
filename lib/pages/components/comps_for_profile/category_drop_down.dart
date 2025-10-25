import 'dart:ui';

import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:doppy/pages/components/comps_for_profile/category_create_dialog.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/data/services/blog_service.dart';

// 카테고리 필터 관리
class CategoryFilterManager extends ValueNotifier<String?> {
  static final CategoryFilterManager _instance =
      CategoryFilterManager._internal();
  factory CategoryFilterManager() => _instance;
  CategoryFilterManager._internal() : super(null);

  void setCategory(String? category) {
    value = category;
  }

  void clearFilter() {
    value = null;
  }

  bool get isFiltered => value != null;
}

class CategoryDropDown {
  VoidCallback? _onCategoryChanged;

  /// 카테고리 변경 콜백 설정
  void setOnCategoryChanged(VoidCallback? callback) {
    _onCategoryChanged = callback;
  }

  /// 카테고리 드롭다운 표시
  void showCategoryDropdown(
    BuildContext context,
    GlobalKey buttonKey,
    BaseFeedProvider feedProvider,
  ) async {
    // 버튼 위치 계산
    final RenderBox? renderBox =
        buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final buttonPosition = renderBox?.localToGlobal(Offset.zero);
    // final buttonSize = renderBox?.size; // 현재는 사용하지 않음

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Stack(
          children: [
            // 배경 터치로 닫기
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(color: Colors.transparent),
              ),
            ),
            // 드롭다운 컨텐츠 - 버튼 아래에 정확히 위치
            Positioned(
              top: (buttonPosition?.dy ?? 100) - 80,
              left: buttonPosition?.dx ?? 20 - 15,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 280,
                      constraints: const BoxConstraints(maxHeight: 320),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.6),
                          width: 0.5,
                        ),
                      ),
                      child: ScrollbarTheme(
                        data: ScrollbarThemeData(
                          thumbVisibility: WidgetStateProperty.all(true),
                          trackVisibility: WidgetStateProperty.all(false),
                          thumbColor: WidgetStateProperty.all(
                            Colors.white.withOpacity(0.4),
                          ),
                          trackColor: WidgetStateProperty.all(
                            Colors.white.withOpacity(0.1),
                          ),
                          thickness: WidgetStateProperty.all(3.0),
                          radius: const Radius.circular(1.5),
                          crossAxisMargin: 3,
                          mainAxisMargin: 20,
                        ),
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            child: _buildCategoryContent(context, feedProvider),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 카테고리 드롭다운 내용 빌드
  Widget _buildCategoryContent(
    BuildContext context,
    BaseFeedProvider feedProvider,
  ) {
    final categories = feedProvider.categories;
    final postsByCategory = feedProvider.postsByCategory;
    final userInfo = feedProvider.userInfo;
    final isOwnProfile = userInfo?['isOwnProfile'] == true;

    print(
      '[CategoryDropDown] _buildCategoryContent - isOwnProfile: $isOwnProfile, categories: ${categories.length}개',
    );

    // 전체 포스트 수 계산
    final totalPosts = postsByCategory.values.fold<int>(
      0,
      (sum, posts) => sum + posts.length,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 카테고리 생성 버튼은 본인 프로필일 때만 표시
        if (isOwnProfile) _buildCreateCategoryButton(context, feedProvider),

        // 전체 탭
        _buildCategoryItem(
          title: '전체',
          count: totalPosts,
          isSelected:
              feedProvider.selectedBase == BaseFilter.all &&
              feedProvider.selectedCategoryId == null,
          context: context,
          onTap: () {
            feedProvider.selectBase(BaseFilter.all);
            Navigator.of(context).pop();
            _onCategoryChanged?.call();
          },
        ),

        // 시스템 카테고리들은 본인 프로필일 때만 표시
        if (isOwnProfile) ...[
          if (_getSystemCategoryCount(feedProvider, '나만보기') > 0) ...[
            _buildCategoryItem(
              title: '나만보기',
              count: _getSystemCategoryCount(feedProvider, '나만보기'),
              isSelected:
                  feedProvider.selectedBase == BaseFilter.private &&
                  feedProvider.selectedCategoryId == null,
              context: context,
              onTap: () {
                feedProvider.selectBase(BaseFilter.private);
                Navigator.of(context).pop();
                _onCategoryChanged?.call();
              },
            ),
          ],
          if (_getSystemCategoryCount(feedProvider, '그룹공유') > 0) ...[
            _buildCategoryItem(
              title: '그룹공유',
              count: _getSystemCategoryCount(feedProvider, '그룹공유'),
              isSelected:
                  feedProvider.selectedBase == BaseFilter.groups &&
                  feedProvider.selectedCategoryId == null,
              context: context,
              onTap: () {
                feedProvider.selectBase(BaseFilter.groups);
                Navigator.of(context).pop();
                _onCategoryChanged?.call();
              },
            ),
          ],
          if (_getSystemCategoryCount(feedProvider, '전체공개') > 0) ...[
            _buildCategoryItem(
              title: '전체공개',
              count: _getSystemCategoryCount(feedProvider, '전체공개'),
              isSelected:
                  feedProvider.selectedBase == BaseFilter.public &&
                  feedProvider.selectedCategoryId == null,
              context: context,
              onTap: () {
                feedProvider.selectBase(BaseFilter.public);
                Navigator.of(context).pop();
                _onCategoryChanged?.call();
              },
            ),
          ],
        ],

        Container(
          height: 1,
          margin: EdgeInsets.symmetric(horizontal: 16),
          color: Colors.white.withOpacity(0.1),
        ),

        // 사용자가 만든 카테고리
        ...categories
            .where((c) => !(c['isSystem'] == true))
            .map(
              (c) => Dismissible(
                key: ValueKey('cat-${c['id']}'),
                direction:
                    isOwnProfile
                        ? DismissDirection.endToStart
                        : DismissDirection.none,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  color: Colors.red.withOpacity(0.6),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) async => isOwnProfile,
                onDismissed: (_) {
                  if (isOwnProfile && feedProvider is MyProfileFeedProvider) {
                    _deleteCategory(context, feedProvider, c['id']);
                  }
                },
                child: _buildCategoryItem(
                  title: c['name'],
                  count: c['postCount'] ?? 0,
                  isSelected:
                      feedProvider.selectedCategoryId == c['id'].toString(),
                  context: context,
                  onTap: () {
                    feedProvider.selectCategory(c['id'].toString());
                    Navigator.of(context).pop();
                    _onCategoryChanged?.call();
                  },
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildCreateCategoryButton(
    BuildContext context,
    BaseFeedProvider feedProvider,
  ) {
    final feedModeManager = FeedDisplayModeManager();
    final isImageOnlyMode = feedModeManager.isImageOnly;

    // 이미지 전용 모드가 아니면 숨김
    if (!isImageOnlyMode) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          Navigator.of(context).pop();
          final name = await showDialog<String?>(
            context: context,
            builder: (_) => const CategoryCreateDialog(),
          );
          print('[CategoryDropDown] 다이얼로그 결과: $name');
          if (name != null && name.trim().isNotEmpty) {
            await _createCategory(context, feedProvider, name.trim());
            _onCategoryChanged?.call();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '새 카테고리 만들기',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.add,
                  color: Colors.white.withOpacity(0.9),
                  size: 20,
                ),
              ),
              SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }

  /// 카테고리 아이템 빌드
  Widget _buildCategoryItem({
    required String title,
    required int count,
    required bool isSelected,
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 시스템 카테고리별 포스트 수 계산
  int _getSystemCategoryCount(
    BaseFeedProvider feedProvider,
    String categoryName,
  ) {
    // 실제 포스트 데이터의 accessLevel을 기준으로 계산
    int count;
    switch (categoryName) {
      case '전체':
        count = feedProvider.totalPostCount;
        break;
      case '나만보기':
        count = feedProvider.privatePostCount;
        break;
      case '그룹공유':
        count = feedProvider.groupsPostCount;
        break;
      case '전체공개':
        count = feedProvider.publicPostCount;
        break;
      default:
        count = 0;
    }

    print('[CategoryDropDown] _getSystemCategoryCount($categoryName): $count');
    return count;
  }

  /// 카테고리 생성 (서버 API 호출)
  Future<void> _createCategory(
    BuildContext context,
    BaseFeedProvider feedProvider,
    String name,
  ) async {
    try {
      print('[CategoryDropDown] 카테고리 생성 시작: $name');

      // 0) 입력값 검증: 공백/중복/예약어(system_doppy_uncategorized) 금지
      final trimmed = name.trim();
      final lower = trimmed.toLowerCase();
      if (trimmed.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('카테고리 이름을 입력해 주세요')));
        }
        return;
      }
      const reserved = {'system_doppy_uncategorized'};
      if (reserved.contains(lower)) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('해당 이름은 사용할 수 없습니다')));
        }
        return;
      }
      final existingNames =
          feedProvider.categories
              .map((c) => (c['name']?.toString() ?? '').trim().toLowerCase())
              .toSet();
      if (existingNames.contains(lower)) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('이미 존재하는 카테고리입니다')));
        }
        return;
      }

      // 서버에 카테고리 생성 요청 (한 번만)
      final blogService = BlogService();
      final created = await blogService.createCategory(
        name: trimmed,
        isPrivate: false,
        description: '$trimmed 카테고리',
      );
      print('[CategoryDropDown] 카테고리 생성 성공');
      final newId = (created['data']?['id'] as int?) ?? -1;
      await feedProvider.refresh();
      if (newId != -1) {
        final ids = feedProvider.categories
            .map<int>((c) => (c['id'] as int))
            .toList(growable: true);
        // 0(미분류)이 섞여 있다면 항상 맨 뒤로 보장
        final hasZero = ids.contains(0);
        final withoutZero = ids.where((id) => id != 0).toList(growable: true);
        // 새 카테고리를 맨 앞에
        withoutZero.remove(newId);
        final ordered = <int>[newId, ...withoutZero];
        if (hasZero) ordered.add(0);

        // TODO: 카테고리 재정렬 API 연동 시 구현
      }
      _onCategoryChanged?.call();

      // 성공 메시지 (위젯 생명주기 안전 처리)
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('카테고리 "$trimmed"이 생성되었습니다')));
      }
    } catch (e) {
      print('[CategoryDropDown] 카테고리 생성 에러: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('카테고리 생성 중 오류가 발생했습니다')));
      }
    }
  }

  /// 카테고리 삭제 (서버 API 호출)
  Future<void> _deleteCategory(
    BuildContext context,
    MyProfileFeedProvider myProfileFeedProvider,
    int categoryId,
  ) async {
    try {
      print('[CategoryDropDown] 카테고리 삭제 시작: $categoryId');

      // 서버에 카테고리 삭제 요청
      final blogService = BlogService();
      await blogService.deleteCategory(categoryId);

      print('[CategoryDropDown] 카테고리 삭제 성공');
      // 전체 피드 데이터 강제 재로딩 (카테고리/포스트 등 전부)
      await myProfileFeedProvider.refresh();
      _onCategoryChanged?.call();

      // 성공 메시지
      _showSnackBarSafely(context, '카테고리가 삭제되었습니다');
    } catch (e) {
      print('[CategoryDropDown] 카테고리 삭제 에러: $e');
      _showSnackBarSafely(context, '카테고리 삭제 중 오류가 발생했습니다');
    }
  }

  /// 안전한 SnackBar 표시 (Scaffold가 없을 때 오류 방지)
  void _showSnackBarSafely(BuildContext context, String message) {
    try {
      // context가 유효하고 Scaffold가 있는지 확인
      if (context.mounted) {
        ErrorHandler.showInfo(context, message);
      }
    } catch (e) {
      // 오류 발생 시 콘솔에만 출력
      print('[CategoryDropDown] SnackBar 표시 오류: $e - 메시지: $message');
    }
  }
}
