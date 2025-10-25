import 'package:flutter/material.dart';
import 'package:doppy/utils/network_utils.dart';

/// 에러 상태를 표시하는 공통 위젯
class ErrorStateWidget extends StatelessWidget {
  final NetworkError error;
  final VoidCallback? onRetry;
  final String? customTitle;
  final String? customMessage;
  final Widget? customIcon;
  final bool showRetryButton;

  const ErrorStateWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.customTitle,
    this.customMessage,
    this.customIcon,
    this.showRetryButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 에러 아이콘
            _buildErrorIcon(context),
            const SizedBox(height: 24),

            // 에러 제목
            Text(
              customTitle ?? NetworkUtils.getErrorTitle(error.type),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // 에러 메시지
            Text(
              customMessage ?? error.userMessage,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),

            // 재시도 버튼
            if (showRetryButton && error.isRetryable && onRetry != null) ...[
              const SizedBox(height: 32),
              _buildRetryButton(context),
            ],

            // 연결 상태 표시 (연결 에러인 경우)
            if (error.type == NetworkErrorType.noConnection) ...[
              const SizedBox(height: 16),
              _buildConnectionStatus(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorIcon(BuildContext context) {
    if (customIcon != null) return customIcon!;

    IconData iconData;
    Color iconColor;

    switch (error.type) {
      case NetworkErrorType.noConnection:
        iconData = Icons.wifi_off_rounded;
        iconColor = Colors.orange;
        break;
      case NetworkErrorType.timeout:
        iconData = Icons.access_time_rounded;
        iconColor = Colors.amber;
        break;
      case NetworkErrorType.serverError:
        iconData = Icons.build_rounded;
        iconColor = Colors.red;
        break;
      case NetworkErrorType.unauthorized:
        iconData = Icons.lock_outline_rounded;
        iconColor = Colors.purple;
        break;
      case NetworkErrorType.notFound:
        iconData = Icons.search_off_rounded;
        iconColor = Colors.blue;
        break;
      case NetworkErrorType.badRequest:
        iconData = Icons.warning_rounded;
        iconColor = Colors.orange;
        break;
      case NetworkErrorType.unknown:
        iconData = Icons.error_outline_rounded;
        iconColor = Colors.grey;
        break;
    }

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Icon(iconData, size: 40, color: iconColor.withOpacity(0.8)),
    );
  }

  Widget _buildRetryButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('다시 시도'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 2,
      ),
    );
  }

  Widget _buildConnectionStatus(BuildContext context) {
    return StreamBuilder<bool>(
      stream: NetworkManager.onConnectivityChanged,
      initialData: NetworkManager.isOnline,
      builder: (context, snapshot) {
        final isOnline = snapshot.data ?? false;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                isOnline
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  isOnline
                      ? Colors.green.withOpacity(0.3)
                      : Colors.red.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                size: 16,
                color: isOnline ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(
                isOnline ? '인터넷 연결됨' : '인터넷 연결 안됨',
                style: TextStyle(
                  color: isOnline ? Colors.green : Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 간단한 에러 상태 위젯 (인라인용)
class InlineErrorWidget extends StatelessWidget {
  final NetworkError error;
  final VoidCallback? onRetry;

  const InlineErrorWidget({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  NetworkUtils.getErrorTitle(error.type),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  error.userMessage,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (error.isRetryable && onRetry != null) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '재시도',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
