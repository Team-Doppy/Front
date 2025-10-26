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
  });

  /// 로고 투명도 (0.0 ~ 1.0)
  final double opacity;

  /// 뒤로가기 버튼 표시 여부
  final bool showBackButton;

  /// 뒤로가기 버튼 클릭 콜백
  final VoidCallback? onBack;

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
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
                Text(
                  "ppy",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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
            top: 40,
            left: 16,
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: onBack ?? () => Navigator.of(context).pop(),
            ),
          ),
      ],
    );
  }
}
