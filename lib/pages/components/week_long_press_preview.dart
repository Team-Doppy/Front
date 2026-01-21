import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/providers/weekly_contribution_provider.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 롱프레스 프리뷰 전용 위젯 (이미지 + 제목)
class WeekLongPressPreview extends StatefulWidget {
  final int weekNumber;
  final int year;

  const WeekLongPressPreview({
    super.key,
    required this.weekNumber,
    required this.year,
  });

  @override
  State<WeekLongPressPreview> createState() => _WeekLongPressPreviewState();
}

class _WeekLongPressPreviewState extends State<WeekLongPressPreview>
    with SingleTickerProviderStateMixin {
  Map<String, String?>? _cachedPreview; // 🎯 데이터를 한 번만 읽어서 캐싱
  bool _isImageLoaded = false; // 🎯 이미지 로드 완료 여부
  bool _isAnimationStarted = false; // 🎯 애니메이션이 시작되었는지 여부
  late AnimationController _fadeController; // 🎯 그래디언트/타이틀 페이드인 애니메이션
  late Animation<double> _fadeAnimation;
  String? _lastLoadedKey; // 🎯 마지막으로 로드된 weekNumber/year 조합

  @override
  void initState() {
    super.initState();
    // 초기 데이터 로드 (한 번만)
    _loadPreview();
    _lastLoadedKey = '${widget.year}-${widget.weekNumber}';

    // 🎯 그래디언트/타이틀 페이드인 애니메이션 초기화
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(WeekLongPressPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // year나 weekNumber가 변경된 경우에만 다시 로드
    final currentKey = '${widget.year}-${widget.weekNumber}';
    if (oldWidget.year != widget.year ||
        oldWidget.weekNumber != widget.weekNumber) {
      // 🎯 새로운 주차로 변경 시 이미지 로드 상태 및 애니메이션 리셋
      setState(() {
        _isImageLoaded = false;
        _isAnimationStarted = false;
        _lastLoadedKey = null;
      });
      _fadeController.reset();
      _loadPreview();
    } else if (_lastLoadedKey == currentKey && _isAnimationStarted) {
      // 🎯 같은 주차로 돌아왔고 이미 애니메이션이 실행된 경우, 즉시 완료 상태로 설정
      if (_fadeController.status != AnimationStatus.completed) {
        _fadeController.value = 1.0;
      }
    }
  }

  void _loadPreview() {
    final weeklyProvider = context.read<WeeklyContributionProvider>();
    _cachedPreview = weeklyProvider.getWeekPostPreview(
      widget.year,
      widget.weekNumber,
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;

    // ✅ 캐시된 데이터 사용 (리빌드 시에도 재조회 없음)
    // preview가 null이면 다시 로드 시도
    var preview = _cachedPreview;
    if (preview == null) {
      _loadPreview();
      preview = _cachedPreview;
    }

    final title = preview?['title'] ?? '';
    final thumbnailUrl = preview?['thumbnailUrl'] ?? '';

    // ✅ 이미지 URL이 있으면 바로 이미지 위젯 표시 (ShimmerBox 스킵)
    if (thumbnailUrl.isNotEmpty) {
      return RepaintBoundary(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 250,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ✅ 이미지가 있으면 바로 이미지 위젯 표시
                  RepaintBoundary(
                    child: CachedNetworkImage(
                      imageUrl: thumbnailUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration(milliseconds: 200),
                      fadeOutDuration: Duration(milliseconds: 200),
                      memCacheWidth: 500,
                      placeholder: (context, url) {
                        return ShimmerBox(
                          width: 250,
                          height: 200,
                          borderRadius: BorderRadius.circular(16),
                        );
                      },
                      imageBuilder: (context, imageProvider) {
                        final currentKey =
                            '${widget.year}-${widget.weekNumber}';
                        if (!_isImageLoaded && !_isAnimationStarted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted &&
                                !_isImageLoaded &&
                                !_isAnimationStarted &&
                                _lastLoadedKey != currentKey) {
                              setState(() {
                                _isImageLoaded = true;
                                _isAnimationStarted = true;
                                _lastLoadedKey = currentKey;
                              });
                              _fadeController.forward();
                            }
                          });
                        } else if (_lastLoadedKey == currentKey &&
                            _isAnimationStarted) {
                          if (_fadeController.status !=
                              AnimationStatus.completed) {
                            _fadeController.value = 1.0;
                          }
                        }
                        return Image(image: imageProvider, fit: BoxFit.cover);
                      },
                      errorWidget: (context, url, error) {
                        final currentKey =
                            '${widget.year}-${widget.weekNumber}';
                        if (!_isImageLoaded && !_isAnimationStarted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted &&
                                !_isImageLoaded &&
                                !_isAnimationStarted &&
                                _lastLoadedKey != currentKey) {
                              setState(() {
                                _isImageLoaded = true;
                                _isAnimationStarted = true;
                                _lastLoadedKey = currentKey;
                              });
                              _fadeController.forward();
                            }
                          });
                        } else if (_lastLoadedKey == currentKey &&
                            _isAnimationStarted) {
                          if (_fadeController.status !=
                              AnimationStatus.completed) {
                            _fadeController.value = 1.0;
                          }
                        }
                        return Container(
                          color: surfaceVariant,
                          child: Icon(
                            Icons.image_not_supported,
                            color: onSurface.withOpacity(0.3),
                          ),
                        );
                      },
                    ),
                  ),
                  // 제목 오버레이 (하단) - 이미지 로드 후 애니메이션으로 표시
                  // ✅ Positioned는 Stack의 직접 자식이어야 하므로, FadeTransition을 Positioned 안으로 이동
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                        child: Text(
                          title.isNotEmpty ? title : '${widget.weekNumber}주차',
                          style: LocaleTypography.style(
                            context: context,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                        ),
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

    // 로딩 중 (데이터가 아직 로드되지 않은 경우)
    if (preview == null) {
      debugPrint('[WeekLongPressPreview] preview is null, showing shimmer');
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ShimmerBox(
          width: 250,
          height: 200,
          borderRadius: BorderRadius.circular(16),
        ),
      );
    }

    // 데이터 없음 (이미지 URL이 없고 title도 없음)
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 250,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Center(
          child: Text(
            '${widget.weekNumber}주차',
            style: LocaleTypography.style(
              context: context,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
