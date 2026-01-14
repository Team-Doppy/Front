import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/blur_overlay_provider.dart';

/// 전역 블러 오버레이 위젯 (확장 가능한 구조)
/// contentBuilder를 통해 위에 표시될 UI를 주입할 수 있음
class BlurOverlayWidget extends StatelessWidget {
  final Widget Function(
    BuildContext context,
    int weekNumber,
    int year,
    Offset position,
    AnimationController controller,
  )?
  contentBuilder;

  /// 앱바 커스터마이징용 빌더 (선택적)
  /// 제공하지 않으면 기본 앱바(주차 정보 + 닫기 버튼) 표시
  final Widget Function(
    BuildContext context,
    int weekNumber,
    int year,
    AnimationController controller,
    VoidCallback onClose,
  )?
  appBarBuilder;

  const BlurOverlayWidget({super.key, this.contentBuilder, this.appBarBuilder});

  @override
  Widget build(BuildContext context) {
    return Consumer<BlurOverlayProvider>(
      builder: (context, blurProvider, child) {
        if (!blurProvider.isVisible) {
          return const SizedBox.shrink();
        }

        final weekNumber = blurProvider.longPressedWeek;
        final year = blurProvider.longPressedYear;
        final position = blurProvider.longPressPosition;
        final controller = blurProvider.animationController;
        final overlayType = blurProvider.overlayType;

        if (controller == null || weekNumber == null || year == null) {
          return const SizedBox.shrink();
        }

        final screenSize = MediaQuery.of(context).size;
        final targetPosition =
            position ?? Offset(screenSize.width / 2, screenSize.height / 2);

        return AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final progress = controller.value;
            // 🎯 블러가 더 빨리 나타나도록 (프리뷰와 동시에 보이도록)
            final blurProgress = (progress * 1.5).clamp(0.0, 1.0);
            final blurSigma = 10.0 * blurProgress;
            final opacity = progress;

            // 닫기 함수
            void handleClose() {
              controller
                  .animateTo(0.0, duration: const Duration(milliseconds: 100))
                  .then((_) {
                    if (context.mounted) {
                      context.read<BlurOverlayProvider>().hideBlurOverlay();
                    }
                  });
            }

            return Positioned.fill(
              child: Opacity(
                opacity: opacity,
                child: Stack(
                  children: [
                    // 전체 화면 블러 배경 (빈 여백 - 탭하면 닫힘)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: handleClose,
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: blurSigma,
                            sigmaY: blurSigma,
                          ),
                          child: Container(
                            width: screenSize.width,
                            height: screenSize.height,
                            color: Colors.black.withOpacity(0.3 * opacity),
                          ),
                        ),
                      ),
                    ),
                    // 주입된 콘텐츠 (contentBuilder가 있으면 사용)
                    // 🎯 weekPostList일 때는 PostList의 SliverAppBar를 사용하므로 별도 앱바 제거
                    if (contentBuilder != null)
                      overlayType == BlurOverlayType.weekPostList
                          ? // weekPostList일 때는 전체 화면으로 표시
                          Positioned.fill(
                            child: contentBuilder!(
                              context,
                              weekNumber,
                              year,
                              targetPosition,
                              controller,
                            ),
                          )
                          : // longPress일 때는 작은 위젯으로 표시
                          AnimatedPositioned(
                            duration: const Duration(
                              milliseconds: 250,
                            ), // 🎯 100ms → 50ms로 빠르게
                            curve: Curves.easeOut,
                            left: targetPosition.dx - 125,
                            top: targetPosition.dy - 100,
                            child: Opacity(
                              // 🎯 프리뷰 위젯도 블러와 동시에 나타나도록 opacity 조절
                              opacity: progress,
                              child: Transform.scale(
                                // 🎯 스케일 애니메이션: 0.8에서 1.0으로 커지도록
                                scale: 0.5 + (0.5 * progress),
                                child: contentBuilder!(
                                  context,
                                  weekNumber,
                                  year,
                                  targetPosition,
                                  controller,
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
