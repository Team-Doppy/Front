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

  String? _lastLoadedKey; // 🎯 마지막으로 로드된 weekNumber/year 조합

  @override
  void initState() {
    super.initState();
    // 초기 데이터 로드 (한 번만)
    _loadPreview();
    _lastLoadedKey = '${widget.year}-${widget.weekNumber}';
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(WeekLongPressPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // year나 weekNumber가 변경된 경우에만 다시 로드
    if (oldWidget.year != widget.year ||
        oldWidget.weekNumber != widget.weekNumber) {
      // 🎯 새로운 주차로 변경 시 이미지 로드 상태 리셋
      setState(() {
        _isImageLoaded = false;
        _lastLoadedKey = null;
      });
      _loadPreview();
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
                      memCacheWidth: 200,
                      placeholder: (context, url) {
                        return SizedBox(width: 250, height: 200);
                      },
                      imageBuilder: (context, imageProvider) {
                        final currentKey =
                            '${widget.year}-${widget.weekNumber}';
                        if (!_isImageLoaded) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted &&
                                !_isImageLoaded &&
                                _lastLoadedKey != currentKey) {
                              setState(() {
                                _isImageLoaded = true;
                                _lastLoadedKey = currentKey;
                              });
                            }
                          });
                        }
                        return Image(image: imageProvider, fit: BoxFit.cover);
                      },
                      errorWidget: (context, url, error) {
                        final currentKey =
                            '${widget.year}-${widget.weekNumber}';
                        if (!_isImageLoaded) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted &&
                                !_isImageLoaded &&
                                _lastLoadedKey != currentKey) {
                              setState(() {
                                _isImageLoaded = true;
                                _lastLoadedKey = currentKey;
                              });
                            }
                          });
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
                ],
              ),
            ),
          ),
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
