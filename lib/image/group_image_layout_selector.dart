import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

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
    required this.previewAssets,
    this.onSelected,
  });

  /// 🎯 미리 로드된 AssetEntity 리스트 (썸네일 빠른 표시용)
  final List<AssetEntity> previewAssets;

  /// 선택 시 부모에서 원하는 타이밍/처리를 제어할 수 있도록 훅 제공.
  /// - null이면 기존처럼 `Navigator.pop(layout)`로 결과 반환
  final Future<void> Function(GroupImageLayout layout)? onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final imageCount = previewAssets.length;

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // ✅ "개별 이미지" 섹션: 프리뷰 없이 타이틀만
                    _LayoutSection(
                      title: l10n.t('individual_images'),
                      previewAssets: previewAssets,
                      previewLayout: GroupImageLayout.individual,
                      onTap: () async {
                        if (!context.mounted) return;
                        if (onSelected != null) {
                          await onSelected!(GroupImageLayout.individual);
                          return;
                        }
                        Navigator.of(context).pop(GroupImageLayout.individual);
                      },
                    ),
                    const SizedBox(height: 16),

                    // 2열 그리드
                    if (showGrid2)
                      _LayoutSection(
                        title: l10n.t('grid_2_column'),
                        previewAssets: previewAssets,
                        previewLayout: GroupImageLayout.grid2,
                        onTap: () async {
                          if (!context.mounted) return;
                          if (onSelected != null) {
                            await onSelected!(GroupImageLayout.grid2);
                            return;
                          }
                          Navigator.of(context).pop(GroupImageLayout.grid2);
                        },
                      ),
                    if (showGrid2) const SizedBox(height: 16),

                    // 3열 그리드
                    if (showGrid3)
                      _LayoutSection(
                        title: l10n.t('grid_3_column'),
                        previewAssets: previewAssets,
                        previewLayout: GroupImageLayout.grid3,
                        onTap: () async {
                          if (!context.mounted) return;
                          if (onSelected != null) {
                            await onSelected!(GroupImageLayout.grid3);
                            return;
                          }
                          Navigator.of(context).pop(GroupImageLayout.grid3);
                        },
                      ),
                    if (showGrid3) const SizedBox(height: 16),

                    // 페이지뷰
                    if (showPageView)
                      _LayoutSection(
                        title: l10n.t('pageview_layout'),
                        previewAssets: previewAssets,
                        previewLayout: GroupImageLayout.pageview,
                        onTap: () async {
                          if (!context.mounted) return;
                          if (onSelected != null) {
                            await onSelected!(GroupImageLayout.pageview);
                            return;
                          }
                          Navigator.of(context).pop(GroupImageLayout.pageview);
                        },
                      ),

                    const SizedBox(height: 30), // 하단 여백
                  ],
                ),
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

  /// ✅ 공통 메서드: 그룹 이미지 레이아웃 선택 모달 바텀시트 표시
  /// - AssetEntity만 사용 (파일 기반 프리뷰 제거)
  static Future<GroupImageLayout?> showLayoutSelector({
    required BuildContext context,
    required List<AssetEntity> previewAssets,
  }) async {
    return await showModalBottomSheet<GroupImageLayout>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder:
          (context) => FractionallySizedBox(
            heightFactor: 0.93,
            child: GroupImageLayoutSelector(previewAssets: previewAssets),
          ),
    );
  }

  /// ✅ 편집된 이미지(bytes)용 레이아웃 선택 메서드
  /// - simple_image_editor_screen에서 사용 (AssetEntity가 없는 경우)
  static Future<GroupImageLayout?> showLayoutSelectorForBytes({
    required BuildContext context,
    required List<Uint8List> previewBytes,
  }) async {
    return await showModalBottomSheet<GroupImageLayout>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder:
          (context) => FractionallySizedBox(
            heightFactor: 0.93,
            child: _GroupImageLayoutSelectorForBytes(
              previewBytes: previewBytes,
            ),
          ),
    );
  }
}

/// ✅ 편집된 이미지(bytes)용 레이아웃 선택 화면
class _GroupImageLayoutSelectorForBytes extends StatelessWidget {
  const _GroupImageLayoutSelectorForBytes({required this.previewBytes});

  final List<Uint8List> previewBytes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final imageCount = previewBytes.length;

    // 이미지 개수에 따라 표시할 레이아웃 결정
    final showGrid2 = imageCount >= 2 && imageCount % 2 == 0;
    final showGrid3 = imageCount >= 3 && imageCount % 3 == 0;
    final showPageView = imageCount >= 2;

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // 개별 이미지
                    _LayoutSectionForBytes(
                      title: l10n.t('individual_images'),
                      previewBytes: previewBytes,
                      previewLayout: GroupImageLayout.individual,
                      onTap:
                          () => Navigator.of(
                            context,
                          ).pop(GroupImageLayout.individual),
                    ),
                    const SizedBox(height: 16),

                    // 2열 그리드
                    if (showGrid2)
                      _LayoutSectionForBytes(
                        title: l10n.t('grid_2_column'),
                        previewBytes: previewBytes,
                        previewLayout: GroupImageLayout.grid2,
                        onTap:
                            () => Navigator.of(
                              context,
                            ).pop(GroupImageLayout.grid2),
                      ),
                    if (showGrid2) const SizedBox(height: 16),

                    // 3열 그리드
                    if (showGrid3)
                      _LayoutSectionForBytes(
                        title: l10n.t('grid_3_column'),
                        previewBytes: previewBytes,
                        previewLayout: GroupImageLayout.grid3,
                        onTap:
                            () => Navigator.of(
                              context,
                            ).pop(GroupImageLayout.grid3),
                      ),
                    if (showGrid3) const SizedBox(height: 16),

                    // 페이지뷰
                    if (showPageView)
                      _LayoutSectionForBytes(
                        title: l10n.t('pageview_layout'),
                        previewBytes: previewBytes,
                        previewLayout: GroupImageLayout.pageview,
                        onTap:
                            () => Navigator.of(
                              context,
                            ).pop(GroupImageLayout.pageview),
                      ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ bytes용 레이아웃 섹션
class _LayoutSectionForBytes extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final List<Uint8List> previewBytes;
  final GroupImageLayout previewLayout;

  const _LayoutSectionForBytes({
    required this.title,
    required this.onTap,
    required this.previewLayout,
    required this.previewBytes,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isIndividual = previewLayout == GroupImageLayout.individual;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding:
            isIndividual
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                : const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurface.withOpacity(0.3),
                ),
              ],
            ),
            // individual이 아닌 경우에만 프리뷰 표시
            if (!isIndividual) ...[const SizedBox(height: 12), _buildPreview()],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    switch (previewLayout) {
      case GroupImageLayout.individual:
        return const SizedBox.shrink(); // individual은 프리뷰 표시 안 함
      case GroupImageLayout.grid2:
        return _buildGrid2Preview();
      case GroupImageLayout.grid3:
        return _buildGrid3Preview();
      case GroupImageLayout.pageview:
        return _buildPageViewPreview();
    }
  }

  Widget _buildGrid2Preview() {
    final displayBytes = previewBytes.take(4).toList();
    return Column(
      children: [
        if (displayBytes.length >= 2)
          Row(
            children: [
              Expanded(child: _buildPreviewImage(displayBytes[0], height: 150)),
              const SizedBox(width: 4),
              Expanded(child: _buildPreviewImage(displayBytes[1], height: 150)),
            ],
          ),
        if (displayBytes.length >= 3) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _buildPreviewImage(displayBytes[2], height: 150)),
              const SizedBox(width: 4),
              if (displayBytes.length >= 4)
                Expanded(
                  child: _buildPreviewImage(displayBytes[3], height: 150),
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
    final displayBytes = previewBytes.take(6).toList();
    return Column(
      children: [
        if (displayBytes.length >= 3)
          Row(
            children: [
              Expanded(child: _buildPreviewImage(displayBytes[0], height: 140)),
              const SizedBox(width: 4),
              Expanded(child: _buildPreviewImage(displayBytes[1], height: 140)),
              const SizedBox(width: 4),
              Expanded(child: _buildPreviewImage(displayBytes[2], height: 140)),
            ],
          ),
        if (displayBytes.length >= 4) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _buildPreviewImage(displayBytes[3], height: 140)),
              const SizedBox(width: 4),
              if (displayBytes.length >= 5)
                Expanded(
                  child: _buildPreviewImage(displayBytes[4], height: 140),
                )
              else
                const Expanded(child: SizedBox()),
              const SizedBox(width: 4),
              if (displayBytes.length >= 6)
                Expanded(
                  child: _buildPreviewImage(displayBytes[5], height: 140),
                )
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPageViewPreview() {
    return StatefulBuilder(
      builder: (context, setState) {
        int currentPage = 0;
        final itemCount = previewBytes.length;

        return SizedBox(
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PageView.builder(
                itemCount: itemCount,
                controller: PageController(viewportFraction: 0.998),
                padEnds: false,
                onPageChanged: (index) {
                  setState(() {
                    currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(
                      left: 0,
                      right: index < itemCount - 1 ? 12 : 0,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildPreviewImage(
                        previewBytes[index],
                        height: 160,
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${currentPage + 1}/$itemCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPreviewImage(Uint8List bytes, {required double height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: height,
              width: double.infinity,
              color: Colors.grey.shade300,
              child: const Center(
                child: Icon(Icons.broken_image, color: Colors.grey, size: 24),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ✅ 정형화된 레이아웃 섹션: 타이틀 + 프리뷰 + 우측 화살표
class _LayoutSection extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final List<AssetEntity> previewAssets;
  final GroupImageLayout previewLayout;

  const _LayoutSection({
    required this.title,
    required this.onTap,
    required this.previewLayout,
    required this.previewAssets,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isIndividual = previewLayout == GroupImageLayout.individual;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding:
            isIndividual
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                : const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurface.withOpacity(0.3),
                ),
              ],
            ),
            // individual이 아닌 경우에만 프리뷰 표시
            if (!isIndividual) ...[const SizedBox(height: 12), _buildPreview()],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (previewAssets.isEmpty) {
      return const SizedBox.shrink();
    }

    switch (previewLayout) {
      case GroupImageLayout.individual:
        return const SizedBox.shrink(); // individual은 프리뷰 표시 안 함
      case GroupImageLayout.grid2:
        return _buildGrid2Preview();
      case GroupImageLayout.grid3:
        return _buildGrid3Preview();
      case GroupImageLayout.pageview:
        return _buildPageViewPreview();
    }
  }

  Widget _buildGrid2Preview() {
    final displayAssets = previewAssets.take(4).toList();
    return Column(
      children: [
        // 첫 번째 행 (2개)
        if (displayAssets.length >= 2)
          Row(
            children: [
              Expanded(
                child: _buildPreviewAsset(displayAssets[0], height: 150),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildPreviewAsset(displayAssets[1], height: 150),
              ),
            ],
          ),
        // 두 번째 행 (2개)
        if (displayAssets.length >= 3) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _buildPreviewAsset(displayAssets[2], height: 150),
              ),
              const SizedBox(width: 4),
              if (displayAssets.length >= 4)
                Expanded(
                  child: _buildPreviewAsset(displayAssets[3], height: 150),
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
    final displayAssets = previewAssets.take(6).toList();
    return Column(
      children: [
        // 첫 번째 행 (3개)
        if (displayAssets.length >= 3)
          Row(
            children: [
              Expanded(
                child: _buildPreviewAsset(displayAssets[0], height: 140),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildPreviewAsset(displayAssets[1], height: 140),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildPreviewAsset(displayAssets[2], height: 140),
              ),
            ],
          ),
        // 두 번째 행 (3개)
        if (displayAssets.length >= 4) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _buildPreviewAsset(displayAssets[3], height: 140),
              ),
              const SizedBox(width: 4),
              if (displayAssets.length >= 5)
                Expanded(
                  child: _buildPreviewAsset(displayAssets[4], height: 140),
                )
              else
                const Expanded(child: SizedBox()),
              const SizedBox(width: 4),
              if (displayAssets.length >= 6)
                Expanded(
                  child: _buildPreviewAsset(displayAssets[5], height: 140),
                )
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPageViewPreview() {
    return StatefulBuilder(
      builder: (context, setState) {
        int currentPage = 0;
        final itemCount = previewAssets.length;

        return SizedBox(
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 실제 PageView
              PageView.builder(
                itemCount: itemCount,
                controller: PageController(viewportFraction: 0.998),
                padEnds: false,
                onPageChanged: (index) {
                  setState(() {
                    currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(
                      left: 0,
                      right: index < itemCount - 1 ? 12 : 0,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildPreviewAsset(
                        previewAssets[index],
                        height: 160,
                      ),
                    ),
                  );
                },
              ),
              // 인디케이터
              Positioned(
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${currentPage + 1}/$itemCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 🎯 AssetEntity를 사용한 빠른 썸네일 표시
  Widget _buildPreviewAsset(AssetEntity asset, {required double height}) {
    return Builder(
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final thumbnailSize = (height * MediaQuery.of(context).devicePixelRatio)
            .round()
            .clamp(400, 800);

        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: AssetEntityImage(
              asset,
              isOriginal: false,
              thumbnailSize: ThumbnailSize(thumbnailSize, thumbnailSize),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('[GroupImageLayoutSelector] ❌ 썸네일 로드 실패: $error');
                return Container(
                  height: height,
                  width: double.infinity,
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
          ),
        );
      },
    );
  }
}
