import 'dart:async';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:doppy/utils/network_utils.dart';
import 'custom_refresh_indicator.dart';

/// 에러 상태를 표시하는 공통 위젯
class ErrorStateWidget extends StatefulWidget {
  final NetworkError error;
  final VoidCallback? onRetry;
  final String? customTitle;
  final String? customMessage;
  final Widget? customIcon;
  final bool showRetryButton;
  final bool isRetrying;
  final void Function(double)? onPullProgress; // Pull progress 콜백 추가

  const ErrorStateWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.customTitle,
    this.customMessage,
    this.customIcon,
    this.showRetryButton = true,
    this.isRetrying = false,
    this.onPullProgress, // Pull progress 콜백 추가
  });

  @override
  State<ErrorStateWidget> createState() => _ErrorStateWidgetState();
}

class _ErrorStateWidgetState extends State<ErrorStateWidget> {
  StreamSubscription<bool>? _connectivitySubscription;
  double _pullProgress = 0.0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Material(
      color: Theme.of(context).colorScheme.background,
      child: CustomRefreshIndicator(
        top: 120,
        onRefresh: () async {
          if (widget.onRetry != null) {
            widget.onRetry!();
          }
        },
        onPullProgress: (progress) {
          setState(() {
            _pullProgress = progress;
          });
          if (widget.onPullProgress != null) {
            widget.onPullProgress!(progress);
          }
        },
        child: CustomScrollView(
          clipBehavior: Clip.none,
          slivers: [
            SliverAppBar(
              expandedHeight: topPadding + 100,
              toolbarHeight: 60,
              backgroundColor: Colors.transparent,
              automaticallyImplyLeading: false,
              elevation: 0,
              title: Opacity(
                opacity: 1.0 - _pullProgress,
                child: Row(
                  children: [
                    Text(
                      "doppy",
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Opacity(
                opacity: 1.0 - _pullProgress,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "오프라인 상태",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      // 새로고침 안내
                      Column(
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            "네트워크 연결을 확인해주세요",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.4),
                            size: 28,
                          ),
                          const SizedBox(height: 200),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 피드 영역(슬리버) 전용 오프라인/에러 표시 위젯
class ErrorStateSliver extends StatelessWidget {
  final NetworkError error;
  final VoidCallback? onRetry;
  final void Function(double)? onPullProgress;

  const ErrorStateSliver({
    super.key,
    required this.error,
    this.onRetry,
    this.onPullProgress,
  });

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // 간단한 pull 진행률 추정 (필요 시 고도화)
          final metrics = notification.metrics;
          if (metrics.pixels < 0 && onPullProgress != null) {
            final progress = (metrics.pixels.abs() / 120).clamp(0.0, 1.0);
            onPullProgress!(progress);
          }
          return false;
        },
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 100),
              Text(
                '오프라인 상태',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '네트워크 연결을 확인해주세요',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),

              Icon(
                Icons.keyboard_arrow_down,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                size: 28,
              ),
              const SizedBox(height: 200),
            ],
          ),
        ),
      ),
    );
  }
}
