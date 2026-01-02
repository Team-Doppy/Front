import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Step 3: 카테고리 선택 컴포넌트
class Step3CategorySelection extends StatefulWidget {
  final int? selectedCategoryId;
  final ValueChanged<int?> onSelectedCategoryIdChanged;
  final List<Map<String, dynamic>>? cachedCategories;
  final ValueChanged<List<Map<String, dynamic>>?> onCachedCategoriesChanged;
  final bool isLoadingCategories;
  final ValueChanged<bool> onIsLoadingCategoriesChanged;
  final bool showCategoryLoading;
  final ValueChanged<bool> onShowCategoryLoadingChanged;
  final bool isUploading; // 🎯 발행 중 상태
  final bool isActive; // 🎯 현재 step3가 활성화되어 있는지 여부

  const Step3CategorySelection({
    super.key,
    required this.selectedCategoryId,
    required this.onSelectedCategoryIdChanged,
    this.cachedCategories,
    required this.onCachedCategoriesChanged,
    required this.isLoadingCategories,
    required this.onIsLoadingCategoriesChanged,
    required this.showCategoryLoading,
    required this.onShowCategoryLoadingChanged,
    this.isUploading = false, // 🎯 기본값 false
    this.isActive = false, // 🎯 기본값 false
  });

  @override
  State<Step3CategorySelection> createState() => _Step3CategorySelectionState();
}

class _Step3CategorySelectionState extends State<Step3CategorySelection> {
  bool _isCreatingCategory = false;
  final TextEditingController _newCategoryController = TextEditingController();
  bool _hasShownEmptyBottomSheet = false; // 🎯 빈 상태 바텀시트 표시 여부

  @override
  void initState() {
    super.initState();
    // 카테고리 미리 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.cachedCategories == null &&
          !widget.isLoadingCategories) {
        _loadCategoriesOnce();
      }
    });
  }

  @override
  void didUpdateWidget(Step3CategorySelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🎯 step3가 활성화되어 있고, 카테고리가 빈 배열이 되었고, 아직 바텀시트를 띄우지 않았으면 자동으로 띄우기
    if (widget.isActive &&
        widget.cachedCategories != null &&
        widget.cachedCategories!.isEmpty &&
        !_hasShownEmptyBottomSheet &&
        !widget.isLoadingCategories) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isActive) {
          _hasShownEmptyBottomSheet = true;
          _showNetworkCheckBottomSheet();
        }
      });
    }
    // 🎯 카테고리가 다시 로드되면 플래그 리셋
    if (oldWidget.cachedCategories?.isEmpty == true &&
        widget.cachedCategories != null &&
        widget.cachedCategories!.isNotEmpty) {
      _hasShownEmptyBottomSheet = false;
    }
    // 🎯 step3가 비활성화되면 플래그 리셋
    if (oldWidget.isActive && !widget.isActive) {
      _hasShownEmptyBottomSheet = false;
    }
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = true; // 항상 다크모드 UI 사용
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 36),
          Text(
            context.tr('publish_category_question'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 20),
          Expanded(
            child:
                widget.cachedCategories == null
                    ? (widget.showCategoryLoading
                        ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : const SizedBox.shrink())
                    : ListView(
                      children: [
                        // 새 카테고리 만들기 버튼
                        _buildCreateCategoryButton(isDarkMode: isDarkMode),
                        const SizedBox(height: 12),
                        // 실제 카테고리 목록
                        ...widget.cachedCategories!.map((category) {
                          final id = category['id'] as int?;
                          var name =
                              category['name'] as String? ??
                              AppLocalizations.of(context).t('no_name');

                          if (name == 'system_doppy_uncategorized') {
                            name = AppLocalizations.of(
                              context,
                            ).t('uncategorized');
                          }

                          return _buildCategoryOption(
                            title: name,
                            isSelected: widget.selectedCategoryId == id,
                            isDarkMode: isDarkMode,
                            isDisabled: widget.isUploading, // 🎯 발행 중 비활성화
                            onTap: () {
                              if (!widget.isUploading) {
                                widget.onSelectedCategoryIdChanged(id);
                              }
                            },
                          );
                        }).toList(),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  /// 🎯 네트워크 연결 확인 바텀시트 표시
  void _showNetworkCheckBottomSheet() {
    // 🎯 step3가 활성화되어 있지 않으면 바텀시트 표시하지 않음
    if (!mounted || !widget.isActive) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder:
          (context) => _NetworkCheckBottomSheet(
            onRetry: () {
              Navigator.of(context).pop();
              // 카테고리 다시 로드
              _hasShownEmptyBottomSheet = false; // 재시도 시 플래그 리셋
              _loadCategoriesOnce();
            },
          ),
    ).then((_) {
      // 🎯 바텀시트가 닫힐 때 플래그 리셋하지 않음 (한 번만 자동 표시)
    });
  }

  Widget _buildCreateCategoryButton({required bool isDarkMode}) {
    // 🎯 발행 중이면 버튼 비활성화
    if (widget.isUploading) {
      return Opacity(
        opacity: 0.5,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).t('create_new_category'),
                  style: TextStyle(
                    color:
                        isDarkMode
                            ? Colors.white
                            : Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.9),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.add_circle_outline,
                color: Colors.white.withOpacity(0.8),
                size: 22,
              ),
            ],
          ),
        ),
      );
    }

    if (_isCreatingCategory) {
      // 인라인 텍스트 필드 표시
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              isDarkMode
                  ? Colors.grey.withOpacity(0.15)
                  : Colors.grey.shade200.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            TextField(
              cursorColor:
                  isDarkMode ? Colors.white : AppColors.darkTextPrimary,
              controller: _newCategoryController,
              autofocus: true,
              style: TextStyle(
                color: isDarkMode ? Colors.white : AppColors.darkTextPrimary,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).t('category_name_input'),
                hintStyle: TextStyle(
                  color:
                      isDarkMode
                          ? Colors.white.withOpacity(0.5)
                          : Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                  fontSize: 16,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isCreatingCategory = false;
                      _newCategoryController.clear();
                    });
                  },
                  child: Text(
                    context.tr('cancel'),
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color:
                          isDarkMode
                              ? Colors.white.withOpacity(0.7)
                              : Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _createNewCategory,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDarkMode
                            ? Colors.white.withOpacity(0.9)
                            : AppColors.darkTextPrimary,
                    foregroundColor:
                        isDarkMode ? Colors.black : AppColors.darkBackground,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context).t('add'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 새 카테고리 만들기 버튼
    return GestureDetector(
      onTap: () {
        setState(() {
          _isCreatingCategory = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                AppLocalizations.of(context).t('create_new_category'),
                style: TextStyle(
                  color:
                      isDarkMode
                          ? Colors.white
                          : Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.add_circle_outline,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createNewCategory() async {
    final name = _newCategoryController.text.trim();
    if (name.isEmpty) {
      ErrorHandler.showError(
        context,
        AppLocalizations.of(context).t('category_name_required'),
      );
      return;
    }

    try {
      // 🎯 카테고리 생성 응답에서 새로 만든 카테고리 ID 추출
      final response = await BlogService().createCategory(
        name: name,
        isPrivate: false,
        description: '',
      );

      final newCategoryId = response['data']?['id'] as int?;

      if (mounted) {
        setState(() {
          _isCreatingCategory = false;
          _newCategoryController.clear();
        });

        // 🎯 카테고리 목록 즉시 새로고침 (캐시 무효화하지 않고 직접 새로고침)
        // 기존 캐시를 유지하면서 로딩 시작
        widget.onIsLoadingCategoriesChanged(false); // 로딩 상태 리셋
        await _loadCategoriesOnce(newCategoryId: newCategoryId);
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: context.tr('category_create_failed'),
        );
      }
    }
  }

  Widget _buildCategoryOption({
    required String title,
    required bool isSelected,
    required bool isDarkMode,
    required VoidCallback onTap,
    bool isDisabled = false, // 🎯 비활성화 상태
  }) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap, // 🎯 비활성화 시 터치 차단
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0, // 🎯 비활성화 시 반투명
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? Colors.white.withOpacity(0.4)
                    : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check,
                  color: isDarkMode ? Colors.white : AppColors.darkTextPrimary,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadCategoriesOnce({int? newCategoryId}) async {
    // 🎯 이미 로딩 중이면 중복 호출 방지
    if (widget.isLoadingCategories) return;

    widget.onIsLoadingCategoriesChanged(true);
    widget.onShowCategoryLoadingChanged(false);

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted && widget.isLoadingCategories) {
        widget.onShowCategoryLoadingChanged(true);
      }
    });

    try {
      final currentUser =
          Provider.of<UserProvider>(context, listen: false).currentUser;
      final username = currentUser?.username ?? '';

      if (username.isEmpty) {
        throw Exception(context.tr('user_info_not_found'));
      }

      final categories = await BlogService().getUserCategories(username);
      if (mounted) {
        widget.onCachedCategoriesChanged(categories);
        widget.onIsLoadingCategoriesChanged(false);
        widget.onShowCategoryLoadingChanged(false);

        // 🎯 카테고리 로드 성공 시 플래그 리셋
        if (categories.isNotEmpty) {
          _hasShownEmptyBottomSheet = false;
        }

        // 🎯 새로 만든 카테고리가 있으면 자동 선택
        if (newCategoryId != null) {
          final newCategory = categories.firstWhere(
            (cat) => cat['id'] == newCategoryId,
            orElse: () => {},
          );
          if (newCategory.isNotEmpty) {
            widget.onSelectedCategoryIdChanged(newCategoryId);
            debugPrint(
              '[Step3CategorySelection] 새로 만든 카테고리 자동 선택: $newCategoryId',
            );
          }
        } else {
          // 🎯 기본 카테고리 자동 선택 (새로 만든 카테고리가 없는 경우)
          if (widget.selectedCategoryId == 0 && categories.isNotEmpty) {
            final hasUncategorized = categories.any((cat) => cat['id'] == 0);
            if (!hasUncategorized) {
              widget.onSelectedCategoryIdChanged(
                categories.first['id'] as int?,
              );
              debugPrint(
                '[Step3CategorySelection] 기본 카테고리 자동 선택: ${categories.first['id']}',
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Step3CategorySelection] 카테고리 로드 실패: $e');
      if (mounted) {
        // 🎯 에러 발생 시 빈 배열로 설정하여 빈 상태 UI 표시
        widget.onCachedCategoriesChanged([]);
        widget.onIsLoadingCategoriesChanged(false);
        widget.onShowCategoryLoadingChanged(false);
      }
    }
  }
}

/// 🎯 네트워크 연결 확인 바텀시트
class _NetworkCheckBottomSheet extends StatelessWidget {
  final VoidCallback onRetry;

  const _NetworkCheckBottomSheet({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들 바
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 아이콘
          Icon(
            Icons.wifi_off_rounded,
            size: 54,
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
          const SizedBox(height: 20),
          // 제목
          Text(
            l10n.t('network_connection_required'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // 메시지
          Text(
            l10n.t('network_connection_message'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),

          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                onRetry();
                Navigator.of(context).pop();
              },
              child: Text(
                l10n.t('retry'),
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}
