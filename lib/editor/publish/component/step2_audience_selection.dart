import 'package:doppy/data/models/system_category_keys.dart';
import 'package:doppy/pages/screens/group_selection_screen.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Step 2: 공개 범위 선택 컴포넌트
class Step2AudienceSelection extends StatefulWidget {
  final Set<int> selectedAudienceGroupIds;
  final bool audienceSelectAll;
  final bool audiencePrivateOnly;
  final bool audienceFriendsOnly;
  final ValueChanged<bool> onAudienceSelectAllChanged;
  final ValueChanged<bool> onAudiencePrivateOnlyChanged;
  final ValueChanged<bool> onAudienceFriendsOnlyChanged;
  final ValueChanged<Set<int>> onSelectedAudienceGroupIdsChanged;
  final bool showGroupLoading;
  final bool isGroupLoadingStarted;
  final ValueChanged<bool> onShowGroupLoadingChanged;
  final ValueChanged<bool> onIsGroupLoadingStartedChanged;

  const Step2AudienceSelection({
    super.key,
    required this.selectedAudienceGroupIds,
    required this.audienceSelectAll,
    required this.audiencePrivateOnly,
    required this.audienceFriendsOnly,
    required this.onAudienceSelectAllChanged,
    required this.onAudiencePrivateOnlyChanged,
    required this.onAudienceFriendsOnlyChanged,
    required this.onSelectedAudienceGroupIdsChanged,
    required this.showGroupLoading,
    required this.isGroupLoadingStarted,
    required this.onShowGroupLoadingChanged,
    required this.onIsGroupLoadingStartedChanged,
  });

  @override
  State<Step2AudienceSelection> createState() => _Step2AudienceSelectionState();
}

class _Step2AudienceSelectionState extends State<Step2AudienceSelection> {
  @override
  Widget build(BuildContext context) {
    return Consumer<GroupProvider>(
      builder: (context, groupProvider, child) {
        // 그룹 목록 로드
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (groupProvider.myGroups.isEmpty &&
              !groupProvider.isLoading &&
              !widget.isGroupLoadingStarted) {
            widget.onIsGroupLoadingStartedChanged(true);
            widget.onShowGroupLoadingChanged(false);

            Future.delayed(const Duration(milliseconds: 1000), () {
              if (mounted && groupProvider.isLoading) {
                widget.onShowGroupLoadingChanged(true);
              }
            });

            groupProvider.fetchMyGroups();
          }
        });

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 36),
              Text(
                '누구에게 공개할까요?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: AppColors.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 20),

              // 전체공개/나만보기 선택 영역
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    // 전체공개
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color:
                            widget.audienceSelectAll
                                ? Colors.white.withOpacity(0.4)
                                : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            widget.onAudienceSelectAllChanged(true);
                            widget.onAudiencePrivateOnlyChanged(false);
                            widget.onAudienceFriendsOnlyChanged(false);
                            widget.onSelectedAudienceGroupIdsChanged({});
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    SystemCategoryKeys.getDisplayText(
                                      context,
                                      SystemCategoryKeys.public,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (widget.audienceSelectAll)
                                  const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 나만보기
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color:
                            widget.audiencePrivateOnly
                                ? Colors.white.withOpacity(0.4)
                                : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            widget.onAudiencePrivateOnlyChanged(true);
                            widget.onAudienceSelectAllChanged(false);
                            widget.onAudienceFriendsOnlyChanged(false);
                            widget.onSelectedAudienceGroupIdsChanged({});
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    SystemCategoryKeys.getDisplayText(
                                      context,
                                      SystemCategoryKeys.private,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (widget.audiencePrivateOnly)
                                  const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 친구공유
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color:
                            widget.audienceFriendsOnly
                                ? Colors.white.withOpacity(0.4)
                                : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            widget.onAudienceFriendsOnlyChanged(true);
                            widget.onAudiencePrivateOnlyChanged(false);
                            widget.onAudienceSelectAllChanged(false);
                            widget.onSelectedAudienceGroupIdsChanged({});
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    SystemCategoryKeys.getDisplayText(
                                      context,
                                      SystemCategoryKeys.friends,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (widget.audienceFriendsOnly)
                                  const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 🎯 그룹 섹션 (항상 표시 - 그룹이 없어도 "그룹 만들기" 버튼은 항상 보여야 함)
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  '그룹',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),

              // 그룹 리스트
              Expanded(
                child:
                    groupProvider.isLoading
                        ? (widget.showGroupLoading
                            ? const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                            : const SizedBox.shrink())
                        : Builder(
                          builder: (context) {
                            final filteredGroups =
                                groupProvider.myGroups
                                    .where((group) => group.isSystem != true)
                                    .toList();

                            return ListView(
                              children: [
                                // 기존 그룹 목록
                                ...filteredGroups.map((group) {
                                  final isSelected = widget
                                      .selectedAudienceGroupIds
                                      .contains(group.id);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color:
                                          isSelected
                                              ? Colors.white.withOpacity(0.4)
                                              : Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          final newSelectedIds = Set<int>.from(
                                            widget.selectedAudienceGroupIds,
                                          );
                                          if (isSelected) {
                                            newSelectedIds.remove(group.id);
                                          } else {
                                            widget.onAudienceSelectAllChanged(
                                              false,
                                            );
                                            widget.onAudiencePrivateOnlyChanged(
                                              false,
                                            );
                                            widget.onAudienceFriendsOnlyChanged(
                                              false,
                                            );
                                            newSelectedIds.add(group.id);
                                          }
                                          widget
                                              .onSelectedAudienceGroupIdsChanged(
                                                newSelectedIds,
                                              );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  group.name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              if (isSelected)
                                                const Icon(
                                                  Icons.check,
                                                  color: Colors.white,
                                                  size: 22,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),

                                // 🎯 그룹 만들기 셀 (항상 마지막에 표시)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap:
                                          () => _navigateToGroupSelection(
                                            context,
                                            groupProvider,
                                          ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.add_circle_outline,
                                              color: Colors.white.withOpacity(
                                                0.8,
                                              ),
                                              size: 22,
                                            ),
                                            const SizedBox(width: 12),
                                            const Expanded(
                                              child: Text(
                                                '그룹 만들기',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _navigateToGroupSelection(
    BuildContext context,
    GroupProvider groupProvider,
  ) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                const GroupSelectionScreen(),
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );

    // 🎯 그룹 선택 화면에서 돌아올 때 API 호출 제거
    // 그룹 생성 시 GroupProvider.createGroup()에서 이미 로컬 캐시가 업데이트되므로
    // 추가 API 호출이 불필요합니다.
  }
}
