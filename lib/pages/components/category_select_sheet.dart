import 'dart:ui';

import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';

// 상태 관리 헬퍼 클래스
class _CategoryStateHelper {
  int? selectedCategoryId;
  bool initialized = false;
  bool isLoading = false;

  void reset() {
    selectedCategoryId = null;
    initialized = false;
    isLoading = false;
  }
}

class CategorySelectSheet {
  // 상태 관리 헬퍼 인스턴스
  static final _StateHelper = _CategoryStateHelper();

  /// 카테고리 선택 바텀시트 표시
  static void show(
    BuildContext context, {
    required String postId,
    required int? currentCategoryId,
    required Function(int? categoryId) onChanged,
  }) async {
    debugPrint(
      '[CategorySelectSheet] show 호출 - postId: $postId, currentCategoryId: $currentCategoryId',
    );
    _StateHelper.reset(); // 상태 초기화
    final parentContext = context; // 부모 context 저장

    try {
      // 🎯 로컬 피드에서 카테고리 목록 가져오기 (서버 호출 없음)
      final feedProvider = MyProfileFeedProvider();
      final categories = feedProvider.categories;

      if (!context.mounted) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (BuildContext bottomSheetContext) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              // 초기 상태 설정 (한 번만)
              if (!_StateHelper.initialized) {
                // 🎯 현재 카테고리 ID를 초기 선택값으로 설정 (null이면 0으로 처리)
                _StateHelper.selectedCategoryId = currentCategoryId ?? 0;
                _StateHelper.initialized = true;
              }

              // 현재 선택된 카테고리 ID (null이면 0으로 처리)
              final activeCategoryId = _StateHelper.selectedCategoryId ?? 0;
              final originalCategoryId = currentCategoryId ?? 0;

              return Stack(
                children: [
                  // 배경 영역 (바깥 부분) - 탭하면 닫힘
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                  // 바텀시트 컨텐츠
                  DraggableScrollableSheet(
                    initialChildSize: 0.6,
                    minChildSize: 0.4,
                    maxChildSize: 0.9,
                    builder: (context, scrollController) {
                      return GestureDetector(
                        onTap: () {
                          // 바텀시트 내부를 탭해도 닫히지 않도록 이벤트 소비
                        },
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surface.withOpacity(0.95),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(24),
                                ),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surface.withOpacity(0.6),
                                  width: 0.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  // 핸들 바
                                  Container(
                                    margin: const EdgeInsets.only(
                                      top: 12,
                                      bottom: 8,
                                    ),
                                    width: 38,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // 카테고리 리스트
                                  Expanded(
                                    child: RawScrollbar(
                                      controller: scrollController,
                                      thumbColor: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.3),
                                      radius: const Radius.circular(20),
                                      thickness: 4,
                                      thumbVisibility: false,
                                      child: SingleChildScrollView(
                                        controller: scrollController,
                                        child: _buildCategoryContent(
                                          bottomSheetContext,
                                          activeCategoryId,
                                          categories,
                                          setModalState,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // 완료 버튼
                                  _buildDoneButton(
                                    bottomSheetContext,
                                    parentContext,
                                    activeCategoryId,
                                    originalCategoryId,
                                    postId,
                                    onChanged,
                                    setModalState,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.handleError(context, e);
      }
    }
  }

  /// 카테고리 아이템 빌드
  static Widget _buildCategoryItem({
    required String title,
    required bool isSelected,
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        borderRadius: BorderRadius.circular(20),
        color: Colors.transparent,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color:
                  isSelected
                      ? Theme.of(context).colorScheme.onSurface.withOpacity(0.9)
                      : Colors.transparent,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
                      fontSize: 16,
                      color:
                          isSelected && isDarkMode
                              ? AppColors.darkSurface
                              : isSelected && !isDarkMode
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check,
                    color:
                        isSelected && isDarkMode
                            ? AppColors.darkSurface
                            : isSelected && !isDarkMode
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 카테고리 바텀시트 내용 빌드
  static Widget _buildCategoryContent(
    BuildContext bottomSheetContext,
    int? activeCategoryId,
    List<Map<String, dynamic>> categories,
    StateSetter setModalState,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              bottomSheetContext.tr('select_category'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Theme.of(bottomSheetContext).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 미분류
          _buildCategoryItem(
            title: bottomSheetContext.tr('uncategorized'),
            isSelected: activeCategoryId == 0,
            context: bottomSheetContext,
            onTap: () {
              setModalState(() {
                _StateHelper.selectedCategoryId = 0;
              });
            },
          ),

          // 카테고리 리스트
          ...categories.where((c) => !(c['isSystem'] == true)).map((category) {
            final categoryId = category['id'] as int?;
            final isCurrentCategory = categoryId == activeCategoryId;
            return _buildCategoryItem(
              title: category['name']?.toString() ?? '',
              isSelected: isCurrentCategory,
              context: bottomSheetContext,
              onTap: () {
                setModalState(() {
                  _StateHelper.selectedCategoryId = categoryId;
                });
              },
            );
          }),

          // BottomSheet 하단 여백
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// 완료 버튼 빌드
  static Widget _buildDoneButton(
    BuildContext bottomSheetContext,
    BuildContext parentContext,
    int activeCategoryId,
    int originalCategoryId,
    String postId,
    Function(int? categoryId) onChanged,
    StateSetter setModalState,
  ) {
    // 🎯 변경 여부 확인 (다른 카테고리를 선택했을 때만 활성화)
    final hasChanged = activeCategoryId != originalCategoryId;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 디바이더 - 화면 너비 전체
          Container(
            width: double.infinity,
            height: 0.5,
            color: Theme.of(
              bottomSheetContext,
            ).colorScheme.onSurface.withOpacity(0.1),
          ),
          // GestureDetector로 변경 (배경 없음, 전체 영역 클릭 가능)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                hasChanged && !_StateHelper.isLoading
                    ? () async {
                      // 로딩 시작 (즉시 UI 업데이트)
                      setModalState(() {
                        _StateHelper.isLoading = true;
                      });
                      // UI 업데이트 완료 대기
                      await Future.delayed(Duration.zero);

                      try {
                        // 🎯 선택된 카테고리 ID (0이면 null로 변환)
                        final selectedCategoryId =
                            activeCategoryId == 0 ? null : activeCategoryId;

                        // 카테고리 변경 API 호출
                        final blogService = BlogService();
                        await blogService.movePostToCategory(
                          postId: int.parse(postId),
                          targetCategoryId: activeCategoryId,
                        );

                        // 성공 시 콜백 호출
                        onChanged(selectedCategoryId);

                        // 바텀시트 닫기
                        if (bottomSheetContext.mounted) {
                          Navigator.of(bottomSheetContext).pop();
                        }

                        // 성공 메시지 표시
                        if (parentContext.mounted) {
                          ErrorHandler.showInfo(
                            parentContext,
                            parentContext.tr('category_changed'),
                          );
                        }
                      } catch (e) {
                        debugPrint('[CategorySelectSheet] 카테고리 변경 실패: $e');
                        // 로딩 해제
                        setModalState(() {
                          _StateHelper.isLoading = false;
                        });

                        // 에러 메시지 표시
                        if (parentContext.mounted) {
                          ErrorHandler.handleError(parentContext, e);
                        }
                      }
                    }
                    : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_StateHelper.isLoading)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          hasChanged
                              ? Theme.of(
                                bottomSheetContext,
                              ).colorScheme.onSurface
                              : Theme.of(
                                bottomSheetContext,
                              ).colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ),
                    )
                  else
                    Text(
                      '변경하기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                            hasChanged
                                ? Theme.of(
                                  bottomSheetContext,
                                ).colorScheme.onSurface
                                : Theme.of(
                                  bottomSheetContext,
                                ).colorScheme.onSurface.withOpacity(0.3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
