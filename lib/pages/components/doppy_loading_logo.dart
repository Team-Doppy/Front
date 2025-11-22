import 'package:flutter/material.dart';

/// doppy 로딩 로고 위젯
///
/// "d[로딩]ppy" 텍스트와 로딩 인디케이터를 표시
class DoppyLoadingLogo extends StatelessWidget {
  const DoppyLoadingLogo({
    super.key,
    this.opacity = 1.0,
    this.showBackButton = false,
    this.onBack,
    this.spinnerColor,
    this.dTextSize,
    this.ppyTextSize,
    this.spinnerStrokeWidth,
    this.color,
  });

  /// 로고 투명도 (0.0 ~ 1.0)
  final double opacity;

  /// 뒤로가기 버튼 표시 여부
  final bool showBackButton;

  /// 뒤로가기 버튼 클릭 콜백
  final VoidCallback? onBack;

  /// 로딩 스피너 색상 (기본: onSurface)
  final Color? spinnerColor;

  /// "d" 텍스트 크기 (기본: 32)
  final double? dTextSize;

  /// "ppy" 텍스트 크기 (기본: 32)
  final double? ppyTextSize;

  final double? spinnerStrokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: AnimatedOpacity(
            opacity: opacity,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeIn,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "d",
                  style: TextStyle(
                    fontSize: dTextSize ?? 32,
                    fontWeight: FontWeight.w800,
                    color: color ?? Theme.of(context).colorScheme.onSurface,
                    letterSpacing: 1.2,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: SizedBox(
                    width: (ppyTextSize ?? 36) / 2,
                    height: (ppyTextSize ?? 36) / 2,
                    child: CircularProgressIndicator(
                      strokeWidth: spinnerStrokeWidth ?? 4.2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        color ??
                            spinnerColor ??
                            Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                Text(
                  "ppy",
                  style: TextStyle(
                    fontSize: ppyTextSize ?? 32,
                    fontWeight: FontWeight.w800,
                    color: color ?? Theme.of(context).colorScheme.onSurface,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),

        // 뒤로가기 버튼
        if (showBackButton)
          Positioned(
            top: 57,
            left: 4,
            child: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.75),
                size: 24,
              ),
              onPressed: onBack ?? () => Navigator.of(context).pop(),
            ),
          ),
      ],
    );
  }
}
