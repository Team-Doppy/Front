import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 커스텀 새로고침 인디케이터 위젯
/// 8개의 날개가 진행률에 따라 하나씩 채워지는 스피너
class CustomRefreshIndicator extends StatefulWidget {
  final Widget child;
  final Future<void> Function()? onRefresh;
  final void Function(double)? onPullProgress; // 당기는 진행률 콜백 (0.0 ~ 1.0)
  final double triggerDistance;
  final double maxDistance;
  final double top;
  final double startVisibleDistance; // 🎯 스피너가 처음 표시되는 거리

  const CustomRefreshIndicator({
    super.key,
    required this.child,
    this.top = 20,
    this.onRefresh,
    this.onPullProgress,
    this.triggerDistance = 80.0, // 200.0에서 100.0으로 절반으로 줄임
    this.maxDistance = 160.0, // 300.0에서 150.0으로 절반으로 줄임
    this.startVisibleDistance = 30.0, // 🎯 스피너가 처음 표시되는 거리 (기본값 30)
  });

  @override
  State<CustomRefreshIndicator> createState() => _CustomRefreshIndicatorState();
}

class _CustomRefreshIndicatorState extends State<CustomRefreshIndicator>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  double _pullDistance = 0.0;
  bool _isRefreshing = false;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_animationController);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool _onNotification(ScrollNotification notification) {
    if (_isRefreshing) return false;

    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;

      // 맨 위에서 아래로 당길 때만 처리
      if (metrics.pixels <= 0 && notification.scrollDelta != null) {
        if (notification.scrollDelta! < 0) {
          // 아래로 당김 - 날개들이 하나씩 밝아짐
          setState(() {
            _pullDistance = (_pullDistance + (-notification.scrollDelta!) * 0.5)
                .clamp(0.0, widget.maxDistance);
          });
          widget.onPullProgress?.call(_getProgress());
        } else if (notification.scrollDelta! > 0 && _pullDistance > 0) {
          // 위로 올림 - 이미 밝아진 날개들은 유지하고 전체적으로만 축소
          setState(() {
            _pullDistance = (_pullDistance - notification.scrollDelta! * 0.8)
                .clamp(0.0, widget.maxDistance);
          });
          widget.onPullProgress?.call(_getProgress());
        }
      }
    }

    return false;
  }

  void _handleRefreshEnd() async {
    if (_isRefreshing) return;

    final progress = _getProgress();

    if (progress >= 1.0 && widget.onRefresh != null) {
      // 8개가 모두 찬 상태에서 새로고침 실행
      setState(() {
        _isRefreshing = true;
        _isAnimating = true;
      });

      _animationController.repeat();

      try {
        await widget.onRefresh!();
      } finally {
        if (mounted) {
          setState(() {
            _isRefreshing = false;
            _isAnimating = false;
            _pullDistance = 0.0;
          });
          _animationController.stop();
          widget.onPullProgress?.call(0.0);
        }
      }
    } else {
      // 충분히 당기지 않았으면 원래 위치로 복귀
      setState(() {
        _pullDistance = 0.0;
      });
      widget.onPullProgress?.call(0.0);
    }
  }

  double _getProgress() {
    // 🎯 startVisibleDistance부터 triggerDistance까지의 범위로 progress 계산
    // 스피너가 보이기 시작할 때 progress가 0에 가깝게 시작하도록
    if (_pullDistance <= widget.startVisibleDistance) {
      return 0.0;
    }
    final effectiveDistance = _pullDistance - widget.startVisibleDistance;
    final effectiveRange = widget.triggerDistance - widget.startVisibleDistance;
    return (effectiveDistance / effectiveRange).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _getProgress();
    final isVisible =
        _pullDistance > widget.startVisibleDistance ||
        _isRefreshing; // 🎯 startVisibleDistance 이상 당겨야 표시

    return Listener(
      onPointerUp: (_) {
        // 손을 놓았을 때 새로고침 처리
        if (!_isRefreshing && _pullDistance > 0) {
          _handleRefreshEnd();
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: Stack(
          children: [
            widget.child,
            if (isVisible)
              Positioned(
                top: widget.top,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return CustomSpinner(
                        progress: progress,
                        isAnimating: _isAnimating,
                        rotation: _rotationAnimation.value,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 8개 날개 스피너 위젯
class CustomSpinner extends StatelessWidget {
  final double progress; // 0.0 ~ 1.0
  final bool isAnimating;
  final double rotation;

  const CustomSpinner({
    required this.progress,
    required this.isAnimating,
    required this.rotation,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: CustomPaint(
        painter: _SpinnerPainter(
          progress: progress,
          isAnimating: isAnimating,
          rotation: rotation,
        ),
      ),
    );
  }
}

/// 8개 날개 스피너 페인터
class _SpinnerPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0
  final bool isAnimating;
  final double rotation;

  _SpinnerPainter({
    required this.progress,
    required this.isAnimating,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 회전 변환 적용 (애니메이션 중일 때만)
    if (isAnimating) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation * 2 * math.pi);
      canvas.translate(-center.dx, -center.dy);
    }

    // 8개의 날개를 그리기
    for (int i = 0; i < 8; i++) {
      final angle = (i * 45.0) * (math.pi / 180.0); // 각 날개의 각도 (45도씩)
      final opacity = _calculateOpacity(i, progress);

      final paint =
          Paint()
            ..color = Colors.grey.withOpacity(opacity)
            ..strokeWidth = 3.3
            ..strokeCap = StrokeCap.round;

      // 날개의 시작점과 끝점 계산 - 중앙 원 반지름 4, 전체 반지름 15
      final startRadius = 6.0; // 중앙 원 반지름
      final endRadius = 13.0; // 전체 반지름

      final startX = center.dx + startRadius * math.cos(angle);
      final startY = center.dy + startRadius * math.sin(angle);
      final endX = center.dx + endRadius * math.cos(angle);
      final endY = center.dy + endRadius * math.sin(angle);

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }

    if (isAnimating) {
      canvas.restore();
    }
  }

  double _calculateOpacity(int wingIndex, double progress) {
    // 진행률에 따라 날개들의 투명도 계산
    // 1.5시 방향(wingIndex=1, 45도)부터 시계방향으로 하나씩 밝아짐
    // 8등분해서 각 구간마다 날개가 한 번에 밝아짐
    final filledWings = (progress * 8).floor(); // 현재 밝아진 날개 개수 (0~8)

    // 각 날개가 밝아져야 하는 임계점 계산
    // wingIndex 1부터 시작하도록 오프셋 적용
    final threshold = (wingIndex + 9) % 8; // wingIndex 1: 0, 2: 1, ..., 0: 7

    // threshold보다 많은 날개가 채워졌으면 이 날개는 밝음
    if (filledWings > threshold) {
      return 0.9; // 밝은 상태
    } else {
      return 0.0; // 완전히 어두운 상태
    }
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isAnimating != isAnimating ||
        oldDelegate.rotation != rotation;
  }
}
