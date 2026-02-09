import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/military_grid_model.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:doppy/l10n/military_grid_messages.dart';
import 'package:flutter/material.dart';

/// Military Grid 셀 롱프레스 프리뷰 전용 위젯 (이미지 + 제목)
/// 기존 WeekLongPressPreview를 Phase/Cell 기반으로 변경
class MilitaryCellLongPressPreview extends StatefulWidget {
  final Phase phase;
  final Cell cell;

  const MilitaryCellLongPressPreview({
    super.key,
    required this.phase,
    required this.cell,
  });

  @override
  State<MilitaryCellLongPressPreview> createState() =>
      _MilitaryCellLongPressPreviewState();
}

class _MilitaryCellLongPressPreviewState
    extends State<MilitaryCellLongPressPreview> {
  bool _isImageLoaded = false;
  String? _lastLoadedKey;

  @override
  void initState() {
    super.initState();
    _lastLoadedKey = _getCellKey();
  }

  @override
  void didUpdateWidget(MilitaryCellLongPressPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase.phase != widget.phase.phase ||
        oldWidget.cell.slotIndex != widget.cell.slotIndex) {
      setState(() {
        _isImageLoaded = false;
        _lastLoadedKey = null;
      });
    }
  }

  String _getCellKey() {
    return '${widget.phase.phase}-${widget.cell.slotIndex}';
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;

    // 휴가 포스트 우선, 없으면 첫 번째 포스트
    PostMeta? previewPost;
    try {
      previewPost = widget.cell.myPosts.firstWhere(
        (p) => p.isLeaveOrPreEnlistment,
      );
    } catch (_) {
      previewPost =
          widget.cell.myPosts.isNotEmpty ? widget.cell.myPosts.first : null;
    }

    final thumbnailUrl = previewPost?.thumbnailUrl ?? '';

    // 이미지 URL이 있으면 이미지 위젯 표시
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
                  RepaintBoundary(
                    child: CachedNetworkImage(
                      imageUrl: thumbnailUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 200),
                      fadeOutDuration: const Duration(milliseconds: 200),
                      memCacheWidth: 200,
                      placeholder: (context, url) {
                        return const SizedBox(width: 250, height: 200);
                      },
                      imageBuilder: (context, imageProvider) {
                        final currentKey = _getCellKey();
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
                        final currentKey = _getCellKey();
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

    // 데이터 없음
    // ✅ Phase 라벨 가져오기
    final phaseLabel =
        MilitaryGridMessages.getPhaseLabel(widget.phase.labelKey) ??
        widget.phase.phase;

    // ✅ 프리뷰 텍스트 생성
    String previewText;
    if (widget.phase.phase == 'preEnlistment') {
      // 입대전: "입대 n주전" 형식
      previewText = '입대 ${widget.cell.slotIndex}주전';
    } else {
      // 일반 phase: "상병 n주차" 형식
      previewText = '$phaseLabel ${widget.cell.slotIndex}주차';
    }

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
            previewText,
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
