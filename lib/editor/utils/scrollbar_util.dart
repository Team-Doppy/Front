import 'package:flutter/material.dart';

/// 공통 스크롤바 유틸리티
/// PostWriteScreen과 PostReaderScreen에서 일관된 스크롤바 디자인을 제공합니다.
class ScrollbarUtil {
  /// 기본 스크롤바 두께
  static const double defaultThickness = 6.0;

  /// 기본 스크롤바 반경
  static const Radius defaultRadius = Radius.circular(20);

  /// 공통 스크롤바 위젯 생성
  ///
  /// [controller] 스크롤 컨트롤러
  /// [child] 스크롤 가능한 자식 위젯
  /// [thickness] 스크롤바 두께 (기본값: 4.0)
  /// [radius] 스크롤바 반경 (기본값: Radius.circular(12))
  /// [thumbColor] 스크롤바 색상 (기본값: onSurfaceVariant)
  /// [minThumbLength] 최소 스크롤바 길이 (기본값: 48.0)
  static Widget buildScrollbar({
    required ScrollController controller,
    required Widget child,
    double? thickness,
    Radius? radius,
    Color? thumbColor,
    double? minThumbLength,
  }) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return RawScrollbar(
          thickness: thickness ?? defaultThickness,
          controller: controller,
          radius: radius ?? defaultRadius,
          thumbColor:
              thumbColor ?? theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
          minThumbLength: minThumbLength ?? 28.0,
          child: child,
        );
      },
    );
  }

  /// 커스텀 스크롤바 색상 가져오기
  ///
  /// [context] BuildContext
  /// [opacity] 투명도 (0.0 ~ 1.0, 기본값: 0.5)
  static Color getScrollbarColor(BuildContext context, {double opacity = 0.5}) {
    return Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(opacity);
  }
}
