import 'dart:ui';
import 'package:flutter/material.dart';

class FeedFilterDropdown {
  /// 피드 필터 드롭다운 표시
  static void show(
    BuildContext context, {
    required bool isShowingFriendsOnly,
    required Function(bool) onFilterChanged,
  }) {
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
            // 드롭다운 컨텐츠
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 200,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 전체 보기
                          _buildFilterItem(
                            context: context,
                            icon: Icons.public,
                            title: '전체 보기',
                            subtitle: '모든 게시물',
                            isSelected: !isShowingFriendsOnly,
                            onTap: () {
                              Navigator.of(context).pop();
                              onFilterChanged(false);
                            },
                          ),
                          // 구분선
                          Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            color: Colors.white.withOpacity(0.1),
                          ),
                          // 친구만 보기
                          _buildFilterItem(
                            context: context,
                            icon: Icons.people,
                            title: '친구만 보기',
                            subtitle: '팔로우한 친구의 게시물',
                            isSelected: isShowingFriendsOnly,
                            onTap: () {
                              Navigator.of(context).pop();
                              onFilterChanged(true);
                            },
                          ),
                        ],
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

  /// 필터 아이템 빌드
  static Widget _buildFilterItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
