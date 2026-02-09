import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/overlay/letter_recipient_selection_overlay.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/theme/app_colors.dart';

/// 글쓰기 모드 선택 화면
class PostModeSelectionScreen extends StatelessWidget {
  const PostModeSelectionScreen({super.key});

  /// 사용자 타입에 따라 선택 가능한 모드 목록 반환
  /// ✅ promise는 PreEnlistmentCTA에서만 사용되므로 여기서는 제외
  static List<PostModeOption> getAvailableModes(UserType? userType) {
    switch (userType) {
      case UserType.girlfriend:
        // 곰신: MILITARY_LIFE, LEAVE_OR_PRE_ENLISTMENT, GENERAL, LETTER
        return [
          PostModeOption.militaryLife,
          PostModeOption.leaveOrPreEnlistment,
          PostModeOption.general,
          PostModeOption.letter,
        ];
      case UserType.military:
        // 군인: MILITARY_LIFE, LEAVE_OR_PRE_ENLISTMENT, GENERAL, LETTER (promise 제외)
        return [
          PostModeOption.militaryLife,
          PostModeOption.leaveOrPreEnlistment,
          PostModeOption.general,
          PostModeOption.letter,
        ];
      case UserType.plannedEnlistment:
        // 입대 예정자: LEAVE_OR_PRE_ENLISTMENT, GENERAL (promise 제외)
        return [PostModeOption.leaveOrPreEnlistment, PostModeOption.general];
      case UserType.discharged:
      case UserType.dischargedWithPartner:
        // 전역자/꽃신: GENERAL
        return [PostModeOption.general];
      default:
        // 기본: promise 제외한 모든 모드
        return [
          PostModeOption.militaryLife,
          PostModeOption.leaveOrPreEnlistment,
          PostModeOption.general,
          PostModeOption.letter,
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUser = userProvider.currentUser;
    final userType =
        currentUser?.militaryInfo?.userType ??
        (currentUser?.role != null
            ? UserTypeExtension.fromServerRole(currentUser!.role!)
            : null);

    final availableModes = getAvailableModes(userType);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.75),
            size: 24,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: SafeArea(
          child: ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(20),
            shrinkWrap: true,
            children:
                availableModes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final mode = entry.value;
                  return _ModeCard(
                    mode: mode,
                    animationDelay: Duration(milliseconds: 100 * index),
                    onTap: () {
                      // ✅ letter 모드는 수신인 선택 화면을 먼저 push
                      if (mode == PostModeOption.letter) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (_) => const LetterRecipientSelectionScreen(),
                          ),
                        );
                      } else {
                        // ✅ 모드별 empty state 메시지와 자동 포커스 설정
                        String? emptyStateMessage;
                        bool disableAutoFocus = false;

                        if (mode == PostModeOption.general) {
                          emptyStateMessage = '어느 포스트든 작성해봐요';
                          disableAutoFocus = true;
                        } else if (mode == PostModeOption.militaryLife) {
                          // daily는 자동 포커스 유지, empty state 메시지 설정
                          emptyStateMessage = '이번주는 어떤 일이 있었나요?';
                          disableAutoFocus = false;
                        } else if (mode == PostModeOption.promise) {
                          // promise는 자동 포커스 유지, empty state 메시지 설정
                          emptyStateMessage = '나의 목표 적어보기';
                          disableAutoFocus = false;
                        } else if (mode ==
                            PostModeOption.leaveOrPreEnlistment) {
                          // leaveOrPreEnlistment는 자동 포커스 제거, empty state 메시지 설정
                          emptyStateMessage = '사회에서 추억 남기기';
                          disableAutoFocus = true;
                        } else {
                          // 그 외 모드는 자동 포커스 제거
                          disableAutoFocus = true;
                        }

                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder:
                                (_) => PostwriteScreen(
                                  isEditingMode: false,
                                  mode: mode.toPostWriteMode(),
                                  emptyStateMessage: emptyStateMessage,
                                  disableAutoFocus: disableAutoFocus,
                                ),
                          ),
                        );
                      }
                    },
                  );
                }).toList(),
          ),
        ),
      ),
    );
  }
}

/// 글쓰기 모드 옵션
enum PostModeOption {
  militaryLife,
  leaveOrPreEnlistment,
  general,
  letter,
  promise,
}

extension PostModeOptionExtension on PostModeOption {
  /// PostWriteMode로 변환
  PostWriteMode toPostWriteMode() {
    switch (this) {
      case PostModeOption.militaryLife:
        return PostWriteMode.militaryLife;
      case PostModeOption.leaveOrPreEnlistment:
        return PostWriteMode.leaveOrPreEnlistment;
      case PostModeOption.general:
        return PostWriteMode.public;
      case PostModeOption.letter:
        return PostWriteMode.letter;
      case PostModeOption.promise:
        return PostWriteMode.promise;
    }
  }

  /// 모드 제목
  String get title {
    switch (this) {
      case PostModeOption.militaryLife:
        return '군생활 중 기록하기';
      case PostModeOption.leaveOrPreEnlistment:
        return '사회에서 추억 기록';
      case PostModeOption.general:
        return '자유롭게 기록하기';
      case PostModeOption.letter:
        return '친구에게 보내기';
      case PostModeOption.promise:
        return 'PROMISE';
    }
  }
}

/// 모드 선택 카드
class _ModeCard extends StatefulWidget {
  final PostModeOption mode;
  final Duration animationDelay;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.animationDelay,
    required this.onTap,
  });

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack),
      ),
    );

    // 애니메이션 딜레이 후 시작
    Future.delayed(widget.animationDelay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? AppColors.darkBackground : AppColors.lightSurfaceVariant;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    widget.mode.title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
