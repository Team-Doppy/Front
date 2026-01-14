import 'package:flutter/material.dart';

/// 세련된 빈 상태 위젯
/// 겹쳐진 카드, 텍스트 프롬프트, 액션 버튼을 포함한 빈 상태 UI
class ElegantEmptyState extends StatelessWidget {
  /// 프롬프트 텍스트
  final String message;

  /// 버튼 텍스트
  final String buttonText;

  /// 버튼 아이콘
  final IconData? buttonIcon;

  /// 버튼 클릭 콜백
  final VoidCallback? onButtonPressed;

  /// 버튼을 숨길 때 표시할 메시지
  final String? hideButtonMessage;

  /// 버튼을 숨길 때 표시할 커스텀 위젯
  /// hideButtonMessage보다 우선순위가 높습니다
  final Widget? hideButtonWidget;

  /// 카드 너비 (기본값: 200)
  final double cardWidth;

  /// 카드 높이 (기본값: 120)
  final double cardHeight;

  const ElegantEmptyState({
    super.key,
    required this.message,
    required this.buttonText,
    this.buttonIcon,
    this.onButtonPressed,
    this.hideButtonMessage,
    this.hideButtonWidget,
    this.cardWidth = 250,
    this.cardHeight = 120,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 겹쳐진 카드들 (깊이감 있는 그림자)
          _StackedCards(
            theme: theme,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
          ),
          const SizedBox(height: 40),
          // 텍스트 프롬프트
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // 버튼 또는 숨김 상태 위젯
          if (onButtonPressed != null)
            ElevatedButton(
              onPressed: onButtonPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.onSurface.withOpacity(0.9),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                shadowColor: Colors.black.withOpacity(0.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (buttonIcon != null) ...[
                    Icon(buttonIcon, size: 20, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    buttonText,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else if (hideButtonWidget != null)
            hideButtonWidget!
          else if (hideButtonMessage != null)
            Text(
              hideButtonMessage!,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

/// 겹쳐진 카드 위젯
class _StackedCards extends StatelessWidget {
  final ThemeData theme;
  final double cardWidth;
  final double cardHeight;

  const _StackedCards({
    required this.theme,
    required this.cardWidth,
    required this.cardHeight,
  });

  Widget _buildCard({
    required Offset offset,
    required double shadowOpacity,
    required double blurRadius,
    required Offset shadowOffset,
  }) {
    return Transform.translate(
      offset: offset,
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 세 번째 카드 (가장 뒤)
        _buildCard(
          offset: const Offset(0, 8),
          shadowOpacity: 0.05,
          blurRadius: 8,
          shadowOffset: const Offset(0, 2),
        ),
        // 두 번째 카드 (중간)
        _buildCard(
          offset: const Offset(0, 4),
          shadowOpacity: 0.08,
          blurRadius: 12,
          shadowOffset: const Offset(0, 4),
        ),
        // 첫 번째 카드 (가장 앞)
        _buildCard(
          offset: Offset.zero,
          shadowOpacity: 0.1,
          blurRadius: 16,
          shadowOffset: const Offset(0, 6),
        ),
      ],
    );
  }
}
