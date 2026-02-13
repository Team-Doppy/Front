import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../utils/shimmer_box.dart';
import '../../../editor/utils/editor_localization.dart';

enum GroupImageLayout {
  individual, // 개별 이미지
  grid2, // 2열 그리드
  grid3, // 3열 그리드
  pageview, // 페이지뷰
}

/// 그룹 이미지 레이아웃 선택 화면 (모달 바텀시트)
/// asset별 썸네일 Future를 한 번만 생성해 재사용 → 리빌드 시 깜빡임 방지
class GroupImageLayoutSelector extends StatefulWidget {
  const GroupImageLayoutSelector({
    super.key,
    required this.previewAssets,
    this.onSelected,
  });

  /// 🎯 미리 로드된 AssetEntity 리스트 (썸네일 빠른 표시용)
  final List<AssetEntity> previewAssets;

  /// 선택 시 부모에서 원하는 타이밍/처리를 제어할 수 있도록 훅 제공.
  /// - null이면 기존처럼 `Navigator.pop(layout)`로 결과 반환
  final Future<void> Function(
    BuildContext selectorContext,
    GroupImageLayout layout,
  )?
  onSelected;

  @override
  State<GroupImageLayoutSelector> createState() =>
      _GroupImageLayoutSelectorState();

  /// ✅ 공통 메서드: 그룹 이미지 레이아웃 선택 전체 화면 표시
  static Future<void> showLayoutSelector({
    required BuildContext context,
    required List<AssetEntity> previewAssets,
    Future<void> Function(
      BuildContext selectorContext,
      GroupImageLayout layout,
    )?
    onSelected,
  }) async {
    const duration = Duration(milliseconds: 180);
    await Navigator.push<void>(
      context,
      PageRouteBuilder(
        transitionDuration: duration,
        reverseTransitionDuration: duration,
        pageBuilder: (context, animation, secondaryAnimation) =>
            GroupImageLayoutSelector(
              previewAssets: previewAssets,
              onSelected: onSelected,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// ✅ 편집된 이미지(bytes)용 레이아웃 선택 메서드
  static Future<GroupImageLayout?> showLayoutSelectorForBytes({
    required BuildContext context,
    required List<Uint8List> previewBytes,
  }) async {
    const duration = Duration(milliseconds: 180);
    return await Navigator.push<GroupImageLayout?>(
      context,
      PageRouteBuilder(
        transitionDuration: duration,
        reverseTransitionDuration: duration,
        pageBuilder: (context, animation, secondaryAnimation) {
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              elevation: 0,
              leading: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
                child: Icon(
                  Icons.close,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                  size: 24,
                ),
              ),
              title: Text(
                context.tr('select_layout'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              centerTitle: true,
            ),
            body: _GroupImageLayoutSelectorForBytes(previewBytes: previewBytes),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

class _GroupImageLayoutSelectorState extends State<GroupImageLayoutSelector> {
  /// asset.id별 Future 한 번만 생성 → FutureBuilder가 같은 Future를 쓰면 리빌드 시 깜빡임 없음
  final Map<String, Future<Uint8List?>> _thumbnailFutureCache = {};
  static const int _kPreviewThumbSize = 600;

  Future<Uint8List?> _thumbnailFuture(AssetEntity asset) {
    return _thumbnailFutureCache.putIfAbsent(
      asset.id,
      () => asset.thumbnailDataWithSize(
        const ThumbnailSize(_kPreviewThumbSize, _kPreviewThumbSize),
      ),
    );
  }

  bool _shouldShowGrid2(int imageCount) {
    return imageCount >= 2 && imageCount % 2 == 0;
  }

  bool _shouldShowGrid3(int imageCount) {
    return imageCount >= 3 && imageCount % 3 == 0;
  }

  bool _shouldShowPageView(int imageCount) {
    return imageCount >= 2;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageCount = widget.previewAssets.length;
    final showGrid2 = _shouldShowGrid2(imageCount);
    final showGrid3 = _shouldShowGrid3(imageCount);
    final showPageView = _shouldShowPageView(imageCount);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Icon(
            Icons.close,
            color: colorScheme.onSurface.withOpacity(0.6),
            size: 24,
          ),
        ),
        title: Text(
          context.tr('select_layout'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _LayoutSection(
                      title: context.tr('individual_images'),
                      previewAssets: widget.previewAssets,
                      previewLayout: GroupImageLayout.individual,
                      getThumbnailFuture: _thumbnailFuture,
                      onTap: () async {
                        if (!context.mounted) return;
                        if (widget.onSelected != null) {
                          await widget.onSelected!(
                            context,
                            GroupImageLayout.individual,
                          );
                          return;
                        }
                        Navigator.of(context).pop(GroupImageLayout.individual);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (showGrid2)
                      _LayoutSection(
                        title: context.tr('grid_2_column'),
                        previewAssets: widget.previewAssets,
                        previewLayout: GroupImageLayout.grid2,
                        getThumbnailFuture: _thumbnailFuture,
                        onTap: () async {
                          if (!context.mounted) return;
                          if (widget.onSelected != null) {
                            await widget.onSelected!(
                              context,
                              GroupImageLayout.grid2,
                            );
                            return;
                          }
                          Navigator.of(context).pop(GroupImageLayout.grid2);
                        },
                      ),
                    if (showGrid2) const SizedBox(height: 16),
                    if (showGrid3)
                      _LayoutSection(
                        title: context.tr('grid_3_column'),
                        previewAssets: widget.previewAssets,
                        previewLayout: GroupImageLayout.grid3,
                        getThumbnailFuture: _thumbnailFuture,
                        onTap: () async {
                          if (!context.mounted) return;
                          if (widget.onSelected != null) {
                            await widget.onSelected!(
                              context,
                              GroupImageLayout.grid3,
                            );
                            return;
                          }
                          Navigator.of(context).pop(GroupImageLayout.grid3);
                        },
                      ),
                    if (showGrid3) const SizedBox(height: 16),
                    if (showPageView)
                      _LayoutSection(
                        title: context.tr('pageview_layout'),
                        previewAssets: widget.previewAssets,
                        previewLayout: GroupImageLayout.pageview,
                        getThumbnailFuture: _thumbnailFuture,
                        onTap: () async {
                          if (!context.mounted) return;
                          if (widget.onSelected != null) {
                            await widget.onSelected!(
                              context,
                              GroupImageLayout.pageview,
                            );
                            return;
                          }
                          Navigator.of(context).pop(GroupImageLayout.pageview);
                        },
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

/// ✅ 편집된 이미지(bytes)용 레이아웃 선택 화면
class _GroupImageLayoutSelectorForBytes extends StatelessWidget {
  const _GroupImageLayoutSelectorForBytes({required this.previewBytes});

  final List<Uint8List> previewBytes;

  @override
  Widget build(BuildContext context) {
    final imageCount = previewBytes.length;

    // 이미지 개수에 따라 표시할 레이아웃 결정
    final showGrid2 = imageCount >= 2 && imageCount % 2 == 0;
    final showGrid3 = imageCount >= 3 && imageCount % 3 == 0;
    final showPageView = imageCount >= 2;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),

            // 레이아웃 옵션들
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // 개별 이미지
                    _LayoutSectionForBytes(
                      title: context.tr('individual_images'),
                      previewBytes: previewBytes,
                      previewLayout: GroupImageLayout.individual,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(GroupImageLayout.individual),
                    ),
                    const SizedBox(height: 16),

                    // 2열 그리드
                    if (showGrid2)
                      _LayoutSectionForBytes(
                        title: context.tr('grid_2_column'),
                        previewBytes: previewBytes,
                        previewLayout: GroupImageLayout.grid2,
                        onTap: () =>
                            Navigator.of(context).pop(GroupImageLayout.grid2),
                      ),
                    if (showGrid2) const SizedBox(height: 16),

                    // 3열 그리드
                    if (showGrid3)
                      _LayoutSectionForBytes(
                        title: context.tr('grid_3_column'),
                        previewBytes: previewBytes,
                        previewLayout: GroupImageLayout.grid3,
                        onTap: () =>
                            Navigator.of(context).pop(GroupImageLayout.grid3),
                      ),
                    if (showGrid3) const SizedBox(height: 16),

                    // 페이지뷰
                    if (showPageView)
                      _LayoutSectionForBytes(
                        title: context.tr('pageview_layout'),
                        previewBytes: previewBytes,
                        previewLayout: GroupImageLayout.pageview,
                        onTap: () => Navigator.of(
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
      pressedOpacity: 1.0, // ✅ 터치 시 어두워지는 효과 제거
      onPressed: onTap,
      child: Container(
        padding: isIndividual
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
                controller: PageController(viewportFraction: 0.7),
                padEnds: false,
                onPageChanged: (index) {
                  setState(() {
                    currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
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

/// PageView + 현재 페이지 인디케이터 (상태 유지)
class _PageViewPreviewContent extends StatefulWidget {
  final int itemCount;
  final Widget Function(int index) itemBuilder;

  const _PageViewPreviewContent({
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  State<_PageViewPreviewContent> createState() =>
      _PageViewPreviewContentState();
}

class _PageViewPreviewContentState extends State<_PageViewPreviewContent> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final itemCount = widget.itemCount;
    return SizedBox(
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            itemCount: itemCount,
            controller: PageController(viewportFraction: 0.7),
            padEnds: false,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) => widget.itemBuilder(index),
          ),
          Positioned(
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentPage + 1}/$itemCount',
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
  }
}

/// ✅ 정형화된 레이아웃 섹션: 타이틀 + 프리뷰 + 우측 화살표
class _LayoutSection extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final List<AssetEntity> previewAssets;
  final GroupImageLayout previewLayout;

  /// asset별 Future 한 번만 반환 (State에서 캐시) → 같은 Future로 깜빡임 방지
  final Future<Uint8List?> Function(AssetEntity) getThumbnailFuture;

  const _LayoutSection({
    required this.title,
    required this.onTap,
    required this.previewLayout,
    required this.previewAssets,
    required this.getThumbnailFuture,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isIndividual = previewLayout == GroupImageLayout.individual;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: 1.0, // ✅ 터치 시 어두워지는 효과 제거
      onPressed: onTap,
      child: Container(
        padding: isIndividual
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
    return _PageViewPreviewContent(
      itemCount: previewAssets.length,
      itemBuilder: (index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildPreviewAsset(previewAssets[index], height: 160),
        ),
      ),
    );
  }

  /// 🎯 State에서 캐시한 Future 사용 → 리빌드해도 같은 Future라 깜빡임 없음
  Widget _buildPreviewAsset(AssetEntity asset, {required double height}) {
    final future = getThumbnailFuture(asset);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: FutureBuilder<Uint8List?>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ShimmerBox(
                width: double.infinity,
                height: height,
                borderRadius: BorderRadius.circular(4),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _buildPreviewPlaceholder(context, height);
            }
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _buildPreviewPlaceholder(context, height),
            );
          },
        ),
      ),
    );
  }

  static Widget _buildPreviewPlaceholder(BuildContext context, double height) {
    return Container(
      height: height,
      width: double.infinity,
      color: Colors.grey.shade300,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image, color: Colors.grey, size: 24),
            const SizedBox(height: 4),
            Text(
              context.tr('editor_load_failed'),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
