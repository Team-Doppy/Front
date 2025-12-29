import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'utils/filter_presets.dart';

/// 필터 편집 바텀시트
class FilterEditorBottomSheet extends StatefulWidget {
  const FilterEditorBottomSheet({
    super.key,
    required this.selectedFilter,
    required this.filterIntensity,
    required this.imageBytes,
    required this.onFilterChanged,
    required this.onFilterIntensityChanged,
    this.isExistingNodeEdit = false,
  });

  final FilterModel? selectedFilter;
  final double filterIntensity;
  final Uint8List imageBytes;
  final ValueChanged<FilterModel?> onFilterChanged;
  final ValueChanged<double> onFilterIntensityChanged;
  final bool isExistingNodeEdit;

  @override
  State<FilterEditorBottomSheet> createState() =>
      _FilterEditorBottomSheetState();
}

class _FilterEditorBottomSheetState extends State<FilterEditorBottomSheet> {
  // 썸네일 이미지 캐시 (70x70 크기로 리사이즈된 이미지)
  ui.Image? _thumbnailImage;
  bool _isLoadingThumbnail = false;
  // 슬라이더 드래그 상태 추적
  bool _isSliderDragging = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(FilterEditorBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBytes != widget.imageBytes) {
      _thumbnailImage?.dispose();
      _thumbnailImage = null;
      _loadThumbnail();
    }
  }

  @override
  void dispose() {
    _thumbnailImage?.dispose();
    super.dispose();
  }

  /// 원본 이미지를 70x70 썸네일로 리사이즈
  Future<void> _loadThumbnail() async {
    if (_isLoadingThumbnail || _thumbnailImage != null) return;
    _isLoadingThumbnail = true;

    try {
      // 원본 이미지 로드
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final originalImage = frame.image;

      // 70x70으로 리사이즈
      const thumbnailWidth = 70.0;
      const thumbnailHeight = 70.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..filterQuality = FilterQuality.low;

      canvas.drawImageRect(
        originalImage,
        Rect.fromLTWH(
          0,
          0,
          originalImage.width.toDouble(),
          originalImage.height.toDouble(),
        ),
        const Rect.fromLTWH(0, 0, thumbnailWidth, thumbnailHeight),
        paint,
      );

      final picture = recorder.endRecording();
      final thumbnail = await picture.toImage(
        thumbnailWidth.toInt(),
        thumbnailHeight.toInt(),
      );

      originalImage.dispose();
      picture.dispose();

      if (mounted) {
        setState(() {
          _thumbnailImage = thumbnail;
          _isLoadingThumbnail = false;
        });
      }
    } catch (e) {
      debugPrint('썸네일 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoadingThumbnail = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fgColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 필터 리스트 (슬라이더 드래그 중일 때는 수치 칩 표시)
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, top: 10, bottom: 4),
          child:
              _thumbnailImage == null
                  ? const SizedBox.shrink() // ✅ 로딩 스피너 제거
                  : SizedBox(
                    height: 100, // ✅ 높이 감소
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child:
                          _isSliderDragging
                              ? // ✅ 슬라이더 드래그 중: 수치 칩만 표시 (필터 칩과 같은 위치)
                              ListView.builder(
                                key: const ValueKey('intensity_chip'),
                                shrinkWrap: true,
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                itemCount: 1,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                              width: 2,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '${(widget.filterIntensity * 100).round()}%',
                                              style: TextStyle(
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '강도',
                                          style: TextStyle(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )
                              : // ✅ 평소: 필터 칩 리스트 표시
                              ListView.builder(
                                key: const ValueKey('filter_list'),
                                shrinkWrap: true,
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ), // ✅ 패딩 추가로 잘림 방지
                                itemCount: presetFiltersList.length,
                                itemBuilder: (context, index) {
                                  final filterModel = presetFiltersList[index];
                                  final isSelected =
                                      widget.selectedFilter?.name ==
                                      filterModel.name;
                                  // ✅ 필터가 선택되고 강도가 0보다 크면 primary 테두리
                                  final hasFilterApplied =
                                      isSelected && widget.filterIntensity > 0;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            widget.onFilterChanged(filterModel);
                                          },
                                          child: Container(
                                            width: 56, // ✅ 작게 변경
                                            height: 56, // ✅ 작게 변경
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle, // ✅ 원형
                                              border: Border.all(
                                                color:
                                                    hasFilterApplied
                                                        ? Theme.of(
                                                          context,
                                                        ).colorScheme.primary
                                                        : fgColor.withOpacity(
                                                          0.2,
                                                        ),
                                                width:
                                                    hasFilterApplied
                                                        ? 2.5
                                                        : 1.5,
                                              ),
                                            ),
                                            child: ClipOval(
                                              // ✅ ClipRRect 대신 ClipOval
                                              child: ColorFiltered(
                                                colorFilter: ColorFilter.matrix(
                                                  filterModel.getMatrix(),
                                                ),
                                                child: CustomPaint(
                                                  painter:
                                                      _FilterThumbnailPainter(
                                                        _thumbnailImage!,
                                                      ),
                                                  size: Size.infinite,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          filterModel.name,
                                          style: TextStyle(
                                            color:
                                                hasFilterApplied
                                                    ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                    : fgColor,
                                            fontSize: 10, // ✅ 작게
                                            fontWeight:
                                                hasFilterApplied
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                    ),
                  ),
        ),
        // ✅ 필터 강도 슬라이더 (필터가 선택되었을 때만 표시)
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child:
              widget.selectedFilter != null &&
                      widget.selectedFilter!.name != '원본'
                  ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 2), // ✅ 간격 더 줄임
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ), // ✅ 패딩 더 줄임
                        child: _FilterIntensitySlider(
                          value: widget.filterIntensity,
                          onChanged: widget.onFilterIntensityChanged,
                          onDragStart: () {
                            setState(() {
                              _isSliderDragging = true;
                            });
                          },
                          onDragEnd: () {
                            setState(() {
                              _isSliderDragging = false;
                            });
                          },
                          textColor: fgColor,
                        ),
                      ),
                    ],
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// 필터 강도 슬라이더 (크롭 에디터 스타일)
class _FilterIntensitySlider extends StatefulWidget {
  const _FilterIntensitySlider({
    required this.value,
    required this.onChanged,
    required this.onDragStart,
    required this.onDragEnd,
    required this.textColor,
  });

  final double value; // 0.0 ~ 1.0
  final ValueChanged<double> onChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final Color textColor;

  @override
  State<_FilterIntensitySlider> createState() => _FilterIntensitySliderState();
}

class _FilterIntensitySliderState extends State<_FilterIntensitySlider> {
  double? _dragStartX;
  double? _dragStartValue;

  void _onPanStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _dragStartValue = widget.value;
    widget.onDragStart();
  }

  void _onPanUpdate(DragUpdateDetails details, double width) {
    if (_dragStartX == null || _dragStartValue == null) return;

    final deltaX = details.localPosition.dx - _dragStartX!;
    const range = 1.0; // 0.0 ~ 1.0
    // ✅ 한 번의 드래그로 0~100까지 도달 가능하도록 감도 상향 (필터 UX)
    // - width만큼 드래그하면 range(=1.0)를 거의 커버
    final deltaValue = (deltaX / width) * (range / 1.0);
    final newValue = (_dragStartValue! + deltaValue).clamp(0.0, 1.0);
    widget.onChanged(newValue);
  }

  void _onPanEnd(DragEndDetails details) {
    _dragStartX = null;
    _dragStartValue = null;
    widget.onDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _onPanStart,
          onHorizontalDragUpdate:
              (details) => _onPanUpdate(details, constraints.maxWidth),
          onHorizontalDragEnd: _onPanEnd,
          child: SizedBox(
            height: 50,
            child: CustomPaint(
              painter: _FilterIntensityRulerPainter(
                currentValue: widget.value,
                textColor: widget.textColor,
              ),
              size: Size(constraints.maxWidth, 50),
            ),
          ),
        );
      },
    );
  }
}

/// 필터 강도 룰러 페인터
class _FilterIntensityRulerPainter extends CustomPainter {
  final double currentValue; // 0.0 ~ 1.0
  final Color textColor;

  _FilterIntensityRulerPainter({
    required this.currentValue,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint =
        Paint()
          ..color = textColor.withOpacity(0.3)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;

    final majorTickPaint =
        Paint()
          ..color = textColor.withOpacity(0.5)
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;

    final centerPaint =
        Paint()
          ..color = textColor
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round;

    final centerX = size.width / 2;
    final bottomY = size.height - 8;

    // 화면에 표시할 범위 (중앙 기준 좌우 0.25씩)
    const visibleRange = 0.25;
    final pixelsPerUnit = size.width / (visibleRange * 2);

    // ✅ 틱 간격 더 촘촘하게 (0.05 -> 0.02) => 2% 단위 느낌
    const tickInterval = 0.02;
    const min = 0.0;
    const max = 1.0;

    // ✅ 가운데 바는 항상 표시
    canvas.drawLine(
      Offset(centerX, bottomY),
      Offset(centerX, bottomY - 24),
      centerPaint,
    );

    for (double tickValue = min; tickValue <= max; tickValue += tickInterval) {
      final relative = tickValue - currentValue;

      if (relative.abs() > visibleRange) continue;

      final x = centerX + relative * pixelsPerUnit;
      // ✅ 0.1(=10%) 단위마다 주요 틱
      final isMajor = (tickValue * 100).round() % 10 == 0;

      // ✅ 현재 값 위치는 건너뛰기 (가운데 바가 이미 그려졌으므로)
      if ((relative.abs() < 0.01)) continue;

      if (isMajor) {
        canvas.drawLine(
          Offset(x, bottomY),
          Offset(x, bottomY - 16),
          majorTickPaint,
        );
        // 숫자 표시
        final textSpan = TextSpan(
          text: (tickValue * 100).round().toString(),
          style: TextStyle(
            color: textColor.withOpacity(0.5),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, bottomY - 32),
        );
      } else {
        canvas.drawLine(Offset(x, bottomY), Offset(x, bottomY - 8), tickPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_FilterIntensityRulerPainter oldDelegate) {
    return oldDelegate.currentValue != currentValue ||
        oldDelegate.textColor != textColor;
  }
}

/// 필터 썸네일 Painter (cover 방식)
class _FilterThumbnailPainter extends CustomPainter {
  final ui.Image image;

  _FilterThumbnailPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final imageAspectRatio = imageSize.width / imageSize.height;
    final containerAspectRatio = size.width / size.height;

    Rect dstRect;
    if (imageAspectRatio > containerAspectRatio) {
      // 이미지가 더 넓음: 높이에 맞춤
      final scaledWidth = size.height * imageAspectRatio;
      final offsetX = (size.width - scaledWidth) / 2;
      dstRect = Rect.fromLTWH(offsetX, 0, scaledWidth, size.height);
    } else {
      // 이미지가 더 높음: 너비에 맞춤
      final scaledHeight = size.width / imageAspectRatio;
      final offsetY = (size.height - scaledHeight) / 2;
      dstRect = Rect.fromLTWH(0, offsetY, size.width, scaledHeight);
    }

    final srcRect = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
    canvas.drawImageRect(image, srcRect, dstRect, Paint());
  }

  @override
  bool shouldRepaint(_FilterThumbnailPainter oldDelegate) {
    return oldDelegate.image != image;
  }
}

/// 필터 유틸리티
class FilterUtils {
  const FilterUtils._();

  /// 필터 모델을 ColorMatrix로 변환
  ///
  /// [filter]: 선택된 필터 모델 (null이면 필터 없음)
  /// [intensity]: 필터 강도 (0.0 ~ 1.0, 기본값 1.0)
  ///
  /// 필터가 null이면 null 반환
  static List<double>? getFilterMatrix(
    FilterModel? filter, {
    double intensity = 1.0,
  }) {
    if (filter == null) {
      return null;
    }
    final matrix = filter.getMatrix();
    if (intensity == 1.0) {
      return matrix;
    }
    // 필터 강도 적용: 원본과 필터를 블렌딩
    // identity matrix (원본)
    final identity = [
      1.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
    ];
    // 필터 행렬과 원본 행렬을 intensity 비율로 블렌딩
    final blended = List<double>.generate(20, (i) {
      return identity[i] * (1.0 - intensity) + matrix[i] * intensity;
    });
    return blended;
  }

  /// 필터 스와이프로 다음/이전 필터 선택
  ///
  /// [currentFilter]: 현재 선택된 필터
  /// [deltaX]: 스와이프 방향 (양수: 왼쪽, 음수: 오른쪽)
  ///
  /// 다음/이전 필터를 반환
  static FilterModel? getNextFilter(FilterModel? currentFilter, double deltaX) {
    final filters = presetFiltersList;
    final currentIndex =
        currentFilter != null
            ? filters.indexWhere((f) => f.name == currentFilter.name)
            : 0;
    if (currentIndex == -1) return filters[0];

    int newIndex;
    if (deltaX > 0) {
      // 왼쪽 스와이프: 이전 필터
      newIndex = currentIndex > 0 ? currentIndex - 1 : filters.length - 1;
    } else {
      // 오른쪽 스와이프: 다음 필터
      newIndex = currentIndex < filters.length - 1 ? currentIndex + 1 : 0;
    }
    return filters[newIndex];
  }
}
