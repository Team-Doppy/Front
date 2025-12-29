import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:doppy/l10n/app_localizations.dart';

enum GroupImageLayout {
  individual, // 개별 이미지
  grid2, // 2열 그리드
  grid3, // 3열 그리드
  pageview, // 페이지뷰
}

/// 그룹 이미지 레이아웃 선택 화면 (모달 바텀시트)
class GroupImageLayoutSelector extends StatelessWidget {
  const GroupImageLayoutSelector({
    super.key,
    this.previewImages,
    this.onSelected,
  });

  final List<File>? previewImages;

  /// 선택 시 부모에서 원하는 타이밍/처리를 제어할 수 있도록 훅 제공.
  /// - null이면 기존처럼 `Navigator.pop(layout)`로 결과 반환
  final Future<void> Function(GroupImageLayout layout)? onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final imageCount = previewImages?.length ?? 0;

    // 이미지 개수에 따라 표시할 레이아웃 결정
    final showGrid2 = _shouldShowGrid2(imageCount);
    final showGrid3 = _shouldShowGrid3(imageCount);
    final showPageView = _shouldShowPageView(imageCount);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 드래그 핸들
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // 타이틀
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.t('select_layout'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Icon(
                      Icons.close,
                      color: colorScheme.onSurface.withOpacity(0.6),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 레이아웃 옵션들
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // 개별 이미지 (항상 표시)
                  _LayoutOption(
                    title: l10n.t('individual_images'),
                    description: l10n.t('individual_images_description'),
                    icon: Icons.image,
                    previewImages: previewImages,
                    previewLayout: GroupImageLayout.individual,
                    onTap: () async {
                      if (!context.mounted) return;
                      if (onSelected != null) {
                        await onSelected!(GroupImageLayout.individual);
                        return;
                      }
                      // 🎯 레이아웃 타입 즉시 반환 (플레이스홀더 생성은 MediaUploadHandler에서 처리)
                      Navigator.of(context).pop(GroupImageLayout.individual);
                    },
                  ),
                  const SizedBox(height: 16),

                  // 2열 그리드
                  if (showGrid2) ...[
                    _LayoutOption(
                      title: l10n.t('grid_2_column'),
                      description: l10n.t('grid_2_column_description'),
                      icon: Icons.grid_view,
                      previewImages: previewImages,
                      previewLayout: GroupImageLayout.grid2,
                      onTap: () async {
                        if (!context.mounted) return;
                        if (onSelected != null) {
                          await onSelected!(GroupImageLayout.grid2);
                          return;
                        }
                        // 🎯 레이아웃 타입 즉시 반환 (플레이스홀더 생성은 MediaUploadHandler에서 처리)
                        Navigator.of(context).pop(GroupImageLayout.grid2);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 3열 그리드
                  if (showGrid3) ...[
                    _LayoutOption(
                      title: l10n.t('grid_3_column'),
                      description: l10n.t('grid_3_column_description'),
                      icon: Icons.grid_on,
                      previewImages: previewImages,
                      previewLayout: GroupImageLayout.grid3,
                      onTap: () async {
                        if (!context.mounted) return;
                        if (onSelected != null) {
                          await onSelected!(GroupImageLayout.grid3);
                          return;
                        }
                        // 🎯 레이아웃 타입 즉시 반환 (플레이스홀더 생성은 MediaUploadHandler에서 처리)
                        Navigator.of(context).pop(GroupImageLayout.grid3);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 페이지뷰
                  if (showPageView) ...[
                    _LayoutOption(
                      title: l10n.t('pageview_layout'),
                      description: l10n.t('pageview_layout_description'),
                      icon: Icons.swipe,
                      previewImages: previewImages,
                      previewLayout: GroupImageLayout.pageview,
                      onTap: () async {
                        if (!context.mounted) return;
                        if (onSelected != null) {
                          await onSelected!(GroupImageLayout.pageview);
                          return;
                        }
                        // 🎯 레이아웃 타입 즉시 반환 (플레이스홀더 생성은 MediaUploadHandler에서 처리)
                        Navigator.of(context).pop(GroupImageLayout.pageview);
                      },
                    ),
                  ],

                  const SizedBox(height: 30), // 하단 여백
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 2열 그리드 표시 여부 (짝수 개수일 때만)
  bool _shouldShowGrid2(int imageCount) {
    // 2개: 표시 (2열 1행)
    // 3개: 숨김 (홀수)
    // 4개: 표시 (2열 2행)
    // 5개: 숨김 (홀수)
    // 6개 이상: 짝수만 표시 (2열 3행)
    return imageCount >= 2 && imageCount % 2 == 0;
  }

  /// 3열 그리드 표시 여부
  bool _shouldShowGrid3(int imageCount) {
    // 2개: 숨김 (3열이 필요없음)
    // 3개: 표시 (3열 1행)
    // 4개: 표시 (3열 2행, 마지막 1개)
    // 5개: 숨김 (3열로는 어색함)
    // 6개 이상: 표시 (3열 2행)
    return imageCount >= 3 && imageCount % 3 == 0;
  }

  /// 페이지뷰 표시 여부
  bool _shouldShowPageView(int imageCount) {
    // 모든 경우에 표시 (제한 없음)
    return imageCount >= 2;
  }
}

class _LayoutOption extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  final List<File>? previewImages;
  final GroupImageLayout previewLayout;

  const _LayoutOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
    required this.previewLayout,
    this.previewImages,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: colorScheme.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurface.withOpacity(0.3),
                ),
              ],
            ),

            // 🎯 미리보기 이미지
            if (previewImages != null && previewImages!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildPreview(colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ColorScheme colorScheme) {
    if (previewImages == null || previewImages!.isEmpty) {
      return const SizedBox.shrink();
    }

    switch (previewLayout) {
      case GroupImageLayout.individual:
        return _buildIndividualPreview();
      case GroupImageLayout.grid2:
        return _buildGrid2Preview();
      case GroupImageLayout.grid3:
        return _buildGrid3Preview();
      case GroupImageLayout.pageview:
        return _buildPageViewPreview(colorScheme);
    }
  }

  Widget _buildIndividualPreview() {
    final displayImages = previewImages!.take(3).toList();

    return Column(
      children: [
        for (int i = 0; i < displayImages.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          _buildPreviewImage(displayImages[i], height: 60),
        ],
      ],
    );
  }

  Widget _buildGrid2Preview() {
    final displayImages = previewImages!.take(4).toList();

    return Column(
      children: [
        // 첫 번째 행 (2개)
        if (displayImages.length >= 2)
          Row(
            children: [
              Expanded(child: _buildPreviewImage(displayImages[0], height: 80)),
              const SizedBox(width: 2),
              Expanded(child: _buildPreviewImage(displayImages[1], height: 80)),
            ],
          ),
        // 두 번째 행 (2개)
        if (displayImages.length >= 3) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(child: _buildPreviewImage(displayImages[2], height: 80)),
              const SizedBox(width: 2),
              if (displayImages.length >= 4)
                Expanded(
                  child: _buildPreviewImage(displayImages[3], height: 80),
                )
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildGrid3Preview() {
    final displayImages = previewImages!.take(6).toList();

    return Column(
      children: [
        // 첫 번째 행 (3개)
        if (displayImages.length >= 3)
          Row(
            children: [
              Expanded(child: _buildPreviewImage(displayImages[0], height: 70)),
              const SizedBox(width: 2),
              Expanded(child: _buildPreviewImage(displayImages[1], height: 70)),
              const SizedBox(width: 2),
              Expanded(child: _buildPreviewImage(displayImages[2], height: 70)),
            ],
          ),
        // 두 번째 행 (3개)
        if (displayImages.length >= 4) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(child: _buildPreviewImage(displayImages[3], height: 70)),
              const SizedBox(width: 2),
              if (displayImages.length >= 5)
                Expanded(
                  child: _buildPreviewImage(displayImages[4], height: 70),
                )
              else
                const Expanded(child: SizedBox()),
              const SizedBox(width: 2),
              if (displayImages.length >= 6)
                Expanded(
                  child: _buildPreviewImage(displayImages[5], height: 70),
                )
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPageViewPreview(ColorScheme colorScheme) {
    final displayImages = previewImages!.take(3).toList();

    return Stack(
      alignment: Alignment.center,
      children: [
        // 배경 카드들 (깊이감 표현)
        if (displayImages.length >= 3)
          Transform.scale(
            scale: 0.9,
            child: Opacity(
              opacity: 0.3,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        if (displayImages.length >= 2)
          Transform.scale(
            scale: 0.95,
            child: Opacity(
              opacity: 0.5,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        // 메인 이미지
        if (displayImages.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _buildPreviewImage(displayImages[0], height: 120),
          ),
        // 인디케이터
        Positioned(
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '1/${previewImages!.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewImage(File file, {required double height}) {
    // 디버그 로그
    debugPrint('[GroupImageLayoutSelector] 이미지 경로: ${file.path}');
    debugPrint('[GroupImageLayoutSelector] 파일 존재: ${file.existsSync()}');

    return Builder(
      builder: (context) {
        final l10n = AppLocalizations.of(context);

        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            file,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            cacheWidth: 200, // 메모리 절약을 위해 크기 제한
            errorBuilder: (context, error, stackTrace) {
              debugPrint('[GroupImageLayoutSelector] ❌ 이미지 로드 실패: $error');
              debugPrint('[GroupImageLayoutSelector] 스택: $stackTrace');
              return Container(
                height: height,
                color: Colors.grey.shade300,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.t('load_failed_text'),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
