import 'package:flutter/material.dart';
import '../../theme/app_text_styles.dart';

class AccountListItem extends StatelessWidget {
  final int index;
  final String nickname;
  final String userId;
  final String neighborCount;
  final bool selected;
  final VoidCallback onTap;

  const AccountListItem({
    super.key,
    required this.index,
    required this.nickname,
    required this.userId,
    required this.neighborCount,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.black.withOpacity(0.06) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  height: 46,
                  child: Image.asset(
                    'assets/images/profile_icon.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            flex: 0,
                            child: Text(
                              nickname,
                              style: AppTextStyles.withWeight(
                                AppTextStyles.withSize(
                                  AppTextStyles.bodyMedium,
                                  15,
                                ),
                                FontWeight.w600,
                              ).copyWith(color: Colors.black),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              userId,
                              style: AppTextStyles.withWeight(
                                AppTextStyles.withSize(
                                  AppTextStyles.bodySmall,
                                  11,
                                ),
                                FontWeight.w600,
                              ).copyWith(color: Colors.black),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        neighborCount,
                        style: AppTextStyles.withSize(
                          AppTextStyles.labelSmall,
                          10,
                        ).copyWith(color: Colors.black54),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.more_vert, color: Colors.black),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
