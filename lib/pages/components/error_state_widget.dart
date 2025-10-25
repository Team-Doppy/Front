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
    _setupAutoRetry();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _setupAutoRetry() {
    // 네트워크 연결 상태 변화 감지 시 자동 재시도
    _connectivitySubscription = NetworkManager.onConnectivityChanged.listen((
      isOnline,
    ) {
      if (isOnline && !widget.isRetrying && widget.onRetry != null) {
        print('[ErrorStateWidget] 네트워크 연결 복구 - 자동 재시도 실행');
        widget.onRetry?.call();
      }
    });
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
                          color: Colors.white,
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
