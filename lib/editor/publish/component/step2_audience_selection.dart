import 'package:doppy/data/models/system_category_keys.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Step 2: 공개 범위 선택 컴포넌트
class Step2AudienceSelection extends StatefulWidget {
  final bool audienceSelectAll;
  final bool audiencePrivateOnly;
  final bool audienceFriendsOnly;
  final ValueChanged<bool> onAudienceSelectAllChanged;
  final ValueChanged<bool> onAudiencePrivateOnlyChanged;
  final ValueChanged<bool> onAudienceFriendsOnlyChanged;
  // 그룹 기능 제거로 인해 그룹 관련 파라미터 제거

  const Step2AudienceSelection({
    super.key,
    required this.audienceSelectAll,
    required this.audiencePrivateOnly,
    required this.audienceFriendsOnly,
    required this.onAudienceSelectAllChanged,
    required this.onAudiencePrivateOnlyChanged,
    required this.onAudienceFriendsOnlyChanged,
    // 그룹 기능 제거로 인해 그룹 관련 파라미터 제거
  });

  @override
  State<Step2AudienceSelection> createState() => _Step2AudienceSelectionState();
}

class _Step2AudienceSelectionState extends State<Step2AudienceSelection> {
  @override
  Widget build(BuildContext context) {
    // 그룹 기능 제거로 인해 그룹 로딩 로직 제거

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 36),
          Text(
            context.tr('publish_audience_question'),
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
                        // 그룹 기능 제거로 인해 onSelectedAudienceGroupIdsChanged 제거
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
                        // 그룹 기능 제거로 인해 onSelectedAudienceGroupIdsChanged 제거
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
                        // 그룹 기능 제거로 인해 onSelectedAudienceGroupIdsChanged 제거
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

          // 그룹 기능 제거로 인해 그룹 섹션 제거
        ],
      ),
    );
  }
}
