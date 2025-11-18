import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EmptyFeedView extends StatelessWidget {
  final VoidCallback onWritePost;
  final VoidCallback onEditProfile;
  final VoidCallback onFindFriends;
  final VoidCallback onBrowse;

  const EmptyFeedView({
    Key? key,
    required this.onWritePost,
    required this.onEditProfile,
    required this.onFindFriends,
    required this.onBrowse,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Spacer(),

            // 상단 타이틀
            Text(
              '아직 친구글이 없습니다',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                height: 1.3,
                color: onSurface.withOpacity(0.95),
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: 20),

            // 메인 CTA 버튼 (글쓰기)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: onWritePost,
                child: Container(
                  height: 48,

                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: theme.colorScheme.surface.withOpacity(
                      theme.brightness == Brightness.dark ? 0.6 : 0.9,
                    ),
                    border: Border.all(
                      color: onSurface.withOpacity(0.08),
                      width: 1.3,
                    ),
                  ),
                  child: Text(
                    '전체 글 보러가기',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      color: onSurface.withOpacity(0.95),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MiniActionButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: onSurface.withOpacity(0.85)),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.05,
              color: onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
