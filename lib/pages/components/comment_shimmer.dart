import 'package:flutter/material.dart';

class CommentShimmer extends StatefulWidget {
  final int itemCount;
  final bool isPreview; // 미리보기용인지 전체 댓글용인지

  const CommentShimmer({super.key, this.itemCount = 3, this.isPreview = true});

  @override
  State<CommentShimmer> createState() => _CommentShimmerState();
}

class _CommentShimmerState extends State<CommentShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return _buildShimmerList();
      },
    );
  }

  Widget _buildShimmerList() {
    return Column(
      children: List.generate(
        widget.itemCount,
        (index) => _buildShimmerItem(index),
      ),
    );
  }

  Widget _buildShimmerItem(int index) {
    final isMe = index % 3 == 0; // 3개마다 내 댓글로 설정

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[_buildAvatarShimmer(), const SizedBox(width: 8)],

          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // 대댓글 표시 (랜덤하게)
                if (index % 4 == 0 && !isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: _buildTextShimmer(width: 40, height: 12),
                  ),

                // 댓글 버블
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isMe
                            ? Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.1)
                            : Theme.of(
                              context,
                            ).colorScheme.surfaceVariant.withOpacity(0.1),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTextShimmer(
                        width: _getRandomWidth(80, 200, index),
                        height: 16,
                      ),
                      if (index % 2 == 0) ...[
                        const SizedBox(height: 4),
                        _buildTextShimmer(
                          width: _getRandomWidth(60, 150, index),
                          height: 16,
                        ),
                      ],
                    ],
                  ),
                ),

                // 반응 표시 (랜덤하게)
                if (index % 3 == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildReactionShimmer(),
                        const SizedBox(width: 4),
                        _buildReactionShimmer(),
                      ],
                    ),
                  ),

                // 시간 표시
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _buildTextShimmer(width: 60, height: 11),
                ),
              ],
            ),
          ),

          if (isMe) ...[const SizedBox(width: 8), _buildAvatarShimmer()],
        ],
      ),
    );
  }

  Widget _buildAvatarShimmer() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _getShimmerColor(),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildTextShimmer({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _getShimmerColor(),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildReactionShimmer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getShimmerColor(),
        borderRadius: BorderRadius.circular(10),
      ),
      child: _buildTextShimmer(width: 30, height: 12),
    );
  }

  Color _getShimmerColor() {
    final progress = _animation.value;
    final opacity = (1.0 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0);
    return Colors.grey.withOpacity(0.3 + (opacity * 0.4));
  }

  double _getRandomWidth(double min, double max, int index) {
    return min + (index % 5) * (max - min) / 4;
  }
}
