import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/recap/recap_doc.dart';
import 'package:doppy/pages/components/recap/reveal_on_scroll.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class RecapRenderer extends StatelessWidget {
  const RecapRenderer({
    super.key,
    required this.doc,
    required this.scrollController,
  });

  final RecapDoc doc;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    debugPrint('[RecapRenderer] 렌더링 시작 - blocks 개수: ${doc.blocks.length}');

    if (doc.blocks.isEmpty) {
      debugPrint('[RecapRenderer] ⚠️ blocks가 비어있음!');
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        for (final block in doc.blocks) ...[
          RevealOnScroll(
            scrollController: scrollController,
            motion: block.motion,
            child: _RecapBlockView(
              block: block,
              scrollController: scrollController,
            ),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _RecapBlockView extends StatelessWidget {
  const _RecapBlockView({required this.block, required this.scrollController});

  final RecapBlock block;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[RecapBlockView] 렌더링 - type: ${block.type}, motion: ${block.motion}',
    );
    final result = switch (block.type) {
      'h1' => _H1(block: block),
      'h2' => _H2(block: block),
      'h3' => _H3(block: block),
      'quote' => _Quote(block: block),
      'spacer' => _Spacer(block: block),
      'imageGrid' => _ImageGrid(
        block: block,
        scrollController: scrollController,
      ),
      'imageSingle' => _ImageSingle(
        block: block,
        scrollController: scrollController,
      ),
      // 하위 호환성
      'sectionHeader' => _H1(block: block),
      'paragraph' => _H3(block: block),
      'textBlock' => _H3(block: block),
      'highlight' => _H2(block: block),
      'sectionBreak' => _Spacer(block: block),
      _ => _H3(block: block),
    };
    debugPrint('[RecapBlockView] 위젯 생성 완료 - type: ${block.type}');
    return result;
  }
}

// =============================================================================
// 📝 텍스트 스펙 통일: h1, h2, h3, quote
// =============================================================================

Color? _parseColor(String? colorStr) {
  if (colorStr == null || colorStr.isEmpty) return null;

  // #RRGGBB 또는 #AARRGGBB 형식 파싱
  final hex = colorStr.replaceAll('#', '');
  if (hex.length == 6) {
    return Color(int.parse('FF$hex', radix: 16));
  } else if (hex.length == 8) {
    return Color(int.parse(hex, radix: 16));
  }
  return null;
}

class _H1 extends StatelessWidget {
  const _H1({required this.block});

  final RecapBlock block;

  @override
  Widget build(BuildContext context) {
    final text =
        block.data['text']?.toString() ?? block.data['title']?.toString() ?? '';
    final colorStr = block.data['color']?.toString();
    final color = _parseColor(colorStr) ?? AppColors.darkTextPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: LocaleTypography.style(
          context: context,
          fontSize: 28,
          fontWeight: FontWeight.w900,
          height: 1.2,
          color: color,
        ),
      ),
    );
  }
}

class _H2 extends StatelessWidget {
  const _H2({required this.block});

  final RecapBlock block;

  @override
  Widget build(BuildContext context) {
    final text =
        block.data['text']?.toString() ?? block.data['title']?.toString() ?? '';
    final colorStr = block.data['color']?.toString();
    final color =
        _parseColor(colorStr) ?? AppColors.darkTextPrimary.withOpacity(0.85);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: LocaleTypography.style(
          context: context,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          height: 1.3,
          color: color,
        ),
      ),
    );
  }
}

class _H3 extends StatelessWidget {
  const _H3({required this.block});

  final RecapBlock block;

  @override
  Widget build(BuildContext context) {
    final text = block.data['text']?.toString() ?? '';
    final paragraphs =
        text.split('\n').where((p) => p.trim().isNotEmpty).toList();
    final colorStr = block.data['color']?.toString();
    final color = _parseColor(colorStr) ?? AppColors.darkTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final para in paragraphs) ...[
            Text(
              para.trim(),
              textAlign: TextAlign.center,
              style: LocaleTypography.style(
                context: context,
                fontSize: 18,
                fontWeight: FontWeight.w400,
                height: 1.6,
                color: color,
              ),
            ),
            if (para != paragraphs.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ImageGrid extends StatefulWidget {
  const _ImageGrid({required this.block, required this.scrollController});

  final RecapBlock block;
  final ScrollController scrollController;

  @override
  State<_ImageGrid> createState() => _ImageGridState();
}

class _ImageGridState extends State<_ImageGrid> {
  final Map<int, GlobalKey> _itemKeys = {};
  Map<int, double> _fadeProgress = {}; // 0..1, 순차 등장 진행도
  final GlobalKey _gridKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    _updateFade();
  }

  void _updateFade() {
    if (!mounted) return;
    final ctx = _gridKey.currentContext;
    final ro = ctx?.findRenderObject();
    if (ro is! RenderBox) return;

    final screenH = MediaQuery.sizeOf(context).height;
    // ✅ 화면 중간 정도(40% 지점)에 왔을 때 촉발되도록 설정
    final viewportTop = screenH * 0.4;
    final viewportBottom = screenH;

    final globalTop = ro.localToGlobal(Offset.zero).dy;
    final h = ro.size.height;

    final itemTop = globalTop;
    final itemBottom = globalTop + h;

    final visibleTop = math.max(itemTop, viewportTop);
    final visibleBottom = math.min(itemBottom, viewportBottom);
    final visible = math.max(0.0, visibleBottom - visibleTop);
    final visibleFrac = (h <= 0) ? 0.0 : (visible / h).clamp(0.0, 1.0);

    // ✅ 전체 그리드의 노출률: 화면 중간에 왔을 때부터 시작되도록 조정
    // visibleFrac가 0.5 이상일 때부터 진행도가 시작되도록
    final gridProgress = ((visibleFrac - 0.3) / 0.7).clamp(0.0, 1.0);

    bool needsUpdate = false;
    final newProgress = <int, double>{};

    // 각 아이템에 대해 인덱스 순서(0,1,2,3...)로 진행도 계산
    final items =
        (widget.block.data['items'] as List? ?? []).whereType<Map>().toList();
    final totalItems = items.length;

    for (int i = 0; i < totalItems; i++) {
      // 각 아이템의 시작 지연 (인덱스 순서대로)
      final delay = i * 0.2; // 각 아이템마다 0.2씩 지연
      // 아이템별 진행도 (0..1)
      final itemProgress = ((gridProgress - delay) / (1 - delay)).clamp(
        0.0,
        1.0,
      );
      newProgress[i] = itemProgress;

      if ((itemProgress - (_fadeProgress[i] ?? 0.0)).abs() > 0.01) {
        needsUpdate = true;
      }
    }

    if (needsUpdate) {
      setState(() => _fadeProgress = newProgress);
    }
  }

  @override
  Widget build(BuildContext context) {
    final columnsRaw = widget.block.data['columns'];
    final columns =
        (columnsRaw is int ? columnsRaw : int.tryParse('$columnsRaw')) ?? 2;
    final items =
        (widget.block.data['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      key: _gridKey,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns.clamp(2, 3),
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (context, index) {
        if (!_itemKeys.containsKey(index)) {
          _itemKeys[index] = GlobalKey();
        }

        final url = items[index]['imageUrl']?.toString() ?? '';
        final caption = items[index]['caption']?.toString();
        final progress = _fadeProgress[index] ?? 0.0;
        final curved = Curves.easeOutCubic.transform(progress);

        // 페이드 인 + 약간의 스케일 효과
        final opacity = curved;
        final scale = 0.4 + curved * 0.6;

        return AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          child: Transform.scale(
            scale: scale,
            child: ClipRRect(
              key: _itemKeys[index],
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget:
                        (context, u, e) => Container(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                        ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.4),
                        ],
                      ),
                    ),
                  ),
                  if (caption != null && caption.trim().isNotEmpty)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LocaleTypography.style(
                          context: context,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// 📝 줄글 영역 확장
// =============================================================================

class _Quote extends StatelessWidget {
  const _Quote({required this.block});

  final RecapBlock block;

  @override
  Widget build(BuildContext context) {
    final text = block.data['text']?.toString() ?? '';
    final author = block.data['author']?.toString();
    final colorStr = block.data['color']?.toString();
    final color = _parseColor(colorStr) ?? Colors.white.withOpacity(0.85);
    final authorColorStr = block.data['authorColor']?.toString();
    final authorColor =
        _parseColor(authorColorStr) ?? Colors.white.withOpacity(0.65);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.darkSurfaceVariant,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: LocaleTypography.style(
              context: context,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: color,
            ),
          ),
          if (author != null && author.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '— $author',
                textAlign: TextAlign.right,
                style: LocaleTypography.style(
                  context: context,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: authorColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Spacer extends StatelessWidget {
  const _Spacer({required this.block});

  final RecapBlock block;

  @override
  Widget build(BuildContext context) {
    final heightRaw = block.data['height'];
    final height =
        (heightRaw is num)
            ? heightRaw.toDouble()
            : (int.tryParse('$heightRaw')?.toDouble() ?? 60.0);

    return SizedBox(height: height);
  }
}

// =============================================================================
// 🖼️ 이미지 애니메이션 강화
// =============================================================================

class _ImageSingle extends StatefulWidget {
  const _ImageSingle({required this.block, required this.scrollController});

  final RecapBlock block;
  final ScrollController scrollController;

  @override
  State<_ImageSingle> createState() => _ImageSingleState();
}

class _ImageSingleState extends State<_ImageSingle> {
  final GlobalKey _imageKey = GlobalKey();
  double _slideProgress = 0.0; // 0..1, 오른쪽에서 등장 진행도
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideo = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);

    // ✅ 초기에 URL 확인하여 비디오 여부 판단
    final url = widget.block.data['imageUrl']?.toString() ?? '';
    _isVideo = url.toLowerCase().endsWith('.mp4');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSlide();
      if (_isVideo && url.isNotEmpty) {
        _initializeVideo(url);
      }
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo(String url) async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: const {'Accept': 'video/*', 'Connection': 'keep-alive'},
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      await _videoController!.initialize();

      if (mounted && _videoController != null) {
        await _videoController!.setVolume(0.0); // 음소거
        await _videoController!.setLooping(true); // 루프
        await _videoController!.play(); // 자동 재생
        setState(() => _isVideoInitialized = true);
      }
    } catch (e) {
      debugPrint('[RecapRenderer] 비디오 초기화 실패: $e');
      if (mounted) {
        setState(() => _isVideo = false); // 실패 시 이미지로 폴백
      }
    }
  }

  void _onScroll() {
    _updateSlide();
  }

  void _updateSlide() {
    if (!mounted) return;
    final ctx = _imageKey.currentContext;
    final ro = ctx?.findRenderObject();
    if (ro is! RenderBox) return;

    final screenH = MediaQuery.sizeOf(context).height;
    // ✅ 화면 중간 정도(40% 지점)에 왔을 때 촉발되도록 설정
    final viewportTop = screenH * 0.4;
    final viewportBottom = screenH;

    final globalTop = ro.localToGlobal(Offset.zero).dy;
    final h = ro.size.height;

    final itemTop = globalTop;
    final itemBottom = globalTop + h;

    final visibleTop = math.max(itemTop, viewportTop);
    final visibleBottom = math.min(itemBottom, viewportBottom);
    final visible = math.max(0.0, visibleBottom - visibleTop);
    final visibleFrac = (h <= 0) ? 0.0 : (visible / h).clamp(0.0, 1.0);

    // ✅ 화면 중간에 왔을 때부터 시작되도록 조정
    // visibleFrac가 0.3 이상일 때부터 진행도가 시작되도록
    final nextProgress = ((visibleFrac - 0.3) / 0.7).clamp(0.0, 1.0);
    if ((nextProgress - _slideProgress).abs() < 0.01) return;
    setState(() => _slideProgress = nextProgress);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.block.data['imageUrl']?.toString() ?? '';
    final caption = widget.block.data['caption']?.toString();

    if (url.isEmpty) return const SizedBox.shrink();

    final curved = Curves.easeOutCubic.transform(_slideProgress);
    final screenWidth = MediaQuery.sizeOf(context).width;
    // 오른쪽에서 왼쪽으로 슬라이드: translateX = (1 - progress) * screenWidth
    final translateX = (1 - curved) * screenWidth * 0.5; // 30%만 이동
    final opacity = curved;

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      child: Transform.translate(
        offset: Offset(translateX, 0),
        child: ClipRRect(
          child: SizedBox(
            height: 420,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ✅ 비디오 또는 이미지 렌더링
                if (_isVideo && _isVideoInitialized && _videoController != null)
                  VideoPlayer(_videoController!)
                else if (_isVideo && !_isVideoInitialized)
                  Container(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    child: const Center(child: CircularProgressIndicator()),
                  )
                else
                  CachedNetworkImage(
                    key: _imageKey,
                    imageUrl: url,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget:
                        (context, u, e) => Container(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                        ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.3),
                      ],
                    ),
                  ),
                ),
                if (caption != null && caption.trim().isNotEmpty)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: Text(
                      caption,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: LocaleTypography.style(
                        context: context,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
