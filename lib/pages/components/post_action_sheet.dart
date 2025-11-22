import 'package:doppy/data/models/post_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/search_video_widgets.dart';

class PostActionSheet {
  static void show(
    BuildContext context, {
    required PostData post,
    required VoidCallback onDelete,
    required VoidCallback onMoveCategory,
    required VoidCallback onChangeAccessLevel,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            decoration: const BoxDecoration(color: Colors.transparent),
            child: Stack(
              children: [
                // 🎯 블러 배경 탭 감지
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                // 🎯 모달 컨텐츠
                Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () {}, // 컨텐츠 탭 시 닫히지 않도록
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 🎯 썸네일 이미지 또는 영상 (작게)
                          if (post.thumbnailImageUrl.isNotEmpty)
                            Builder(
                              builder: (context) {
                                // 🎯 영상인지 확인
                                final url =
                                    post.thumbnailImageUrl.toLowerCase();
                                final isVideo =
                                    url.endsWith('.mp4') ||
                                    url.endsWith('.mov') ||
                                    url.endsWith('.m4v') ||
                                    url.contains('/videos/') ||
                                    url.contains('video');

                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 120,
                                    height: 100,
                                    child:
                                        isVideo
                                            ? ThumbnailVideoPlayer(
                                              videoUrl: post.thumbnailImageUrl,
                                              width: 120,
                                              height: 100,
                                            )
                                            : CachedNetworkImage(
                                              imageUrl: post.thumbnailImageUrl,
                                              width: 120,
                                              height: 100,
                                              fit: BoxFit.cover,
                                              placeholder:
                                                  (context, url) => ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: ShimmerBox(
                                                      width: 120,
                                                      height: 100,
                                                    ),
                                                  ),
                                              errorWidget:
                                                  (
                                                    context,
                                                    url,
                                                    error,
                                                  ) => Container(
                                                    width: 120,
                                                    height: 100,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .surfaceVariant,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Icon(
                                                      Icons.image_not_supported,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withOpacity(0.3),
                                                    ),
                                                  ),
                                            ),
                                  ),
                                );
                              },
                            ),
                          if (post.thumbnailImageUrl.isNotEmpty)
                            const SizedBox(height: 12),
                          // 🎯 포스트 제목 (작게)
                          Builder(
                            builder: (context) {
                              final l10n = AppLocalizations.of(context);
                              return Text(
                                post.title.isNotEmpty
                                    ? post.title
                                    : (l10n.translate('post')),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.8),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          // 삭제 버튼
                          Builder(
                            builder: (context) {
                              final l10n = AppLocalizations.of(context);
                              final theme = Theme.of(context);
                              return _buildActionItem(
                                context,
                                label: l10n.translate('delete_post'),
                                textColor: theme.colorScheme.error,
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  Navigator.pop(context);
                                  onDelete();
                                },
                              );
                            },
                          ),
                          // 디바이더
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 0,
                            endIndent: 0,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.05),
                          ),
                          // 카테고리 이동 버튼
                          _buildActionItem(
                            context,
                            label: '카테고리 이동',
                            textColor: Theme.of(context).colorScheme.onSurface,
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              Navigator.pop(context);
                              onMoveCategory();
                            },
                          ),
                          // 디바이더
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 0,
                            endIndent: 0,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.05),
                          ),
                          // 공개범위 변경 버튼
                          Builder(
                            builder: (context) {
                              final l10n = AppLocalizations.of(context);
                              final theme = Theme.of(context);
                              return _buildActionItem(
                                context,
                                label: l10n.translate('change_access_level'),
                                textColor: theme.colorScheme.onSurface,
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  Navigator.pop(context);
                                  onChangeAccessLevel();
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          // 취소 버튼
                          Builder(
                            builder: (context) {
                              final l10n = AppLocalizations.of(context);
                              final theme = Theme.of(context);
                              return SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.of(context).pop();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.onSurface
                                        .withOpacity(0.03),
                                    foregroundColor:
                                        theme.colorScheme.onSurface,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    l10n.translate('cancel'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  static Widget _buildActionItem(
    BuildContext context, {
    required String label,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
