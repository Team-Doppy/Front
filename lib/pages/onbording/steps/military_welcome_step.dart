import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 군인/입대 예정자 환영 화면 (마지막 온보딩 스텝)
class MilitaryWelcomeStep extends StatefulWidget {
  final Future<void> Function()? onConfirm;
  final VoidCallback? onBack;
  final MilitaryBranch? branch; // ✅ 온보딩 플로우에서 선택한 군종 직접 전달

  const MilitaryWelcomeStep({
    super.key,
    this.onConfirm,
    this.onBack,
    this.branch,
  });

  @override
  State<MilitaryWelcomeStep> createState() => _MilitaryWelcomeStepState();
}

class _MilitaryWelcomeStepState extends State<MilitaryWelcomeStep>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleOffset;
  late Animation<double> _subtitleOpacity;
  late Animation<Offset> _subtitleOffset;
  bool _isLoading = false; // ✅ 로딩 상태

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _titleOffset = Tween<Offset>(
      begin: const Offset(0, 0.8),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic),
      ),
    );

    _subtitleOffset = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic),
      ),
    );

    // 애니메이션 시작
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _getBranchImagePath(MilitaryBranch? branch) {
    if (branch == null) return 'assets/images/army_nobg.png';
    switch (branch) {
      case MilitaryBranch.army:
        return 'assets/images/army_nobg.png';
      case MilitaryBranch.navy:
        return 'assets/images/navy_nobg.png';
      case MilitaryBranch.airForce:
        return 'assets/images/airforce_nobg.png';
      case MilitaryBranch.marines:
        return 'assets/images/marin_nobg.png';
      default:
        return 'assets/images/army_nobg.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUser = userProvider.currentUser;
    final profileImageUrl = currentUser?.profileImageUrl ?? '';
    final username = currentUser?.username ?? '';
    // ✅ 위젯에서 전달받은 branch를 우선 사용, 없으면 currentUser에서 가져옴
    final branch = widget.branch ?? currentUser?.militaryInfo?.branch;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // 뒤로가기 버튼
            if (widget.onBack != null)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                    onPressed: widget.onBack,
                  ),
                ),
              ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 상단 텍스트 (애니메이션)
                    SlideTransition(
                      position: _titleOffset,
                      child: FadeTransition(
                        opacity: _titleOpacity,
                        child: Text(
                          '군생활과 성장을 담을게요',
                          textAlign: TextAlign.center,
                          style: LocaleTypography.setStyle(
                            context: context,
                            fontSize: 26,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 서브타이틀 (애니메이션)
                    SlideTransition(
                      position: _subtitleOffset,
                      child: FadeTransition(
                        opacity: _subtitleOpacity,
                        child: Text(
                          '나라를 지켜줘서 진심으로 감사합니다',
                          textAlign: TextAlign.center,
                          style: LocaleTypography.setStyle(
                            context: context,
                            fontSize: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7), // 연두색
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 60),
                    // 가운데 프로필 사진 원 + 군종 로고 (Stack)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // 프로필 원
                        Container(
                          width: 270,
                          height: 270,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.surfaceVariant, // 어두운 회색 원
                          ),
                          child: Center(
                            child: CommonProfileAvatar(
                              imageUrl: profileImageUrl,
                              username: username,
                              size: 260.0,
                              borderColor:
                                  Theme.of(context).colorScheme.surface,
                              borderWidth: 0,
                            ),
                          ),
                        ),
                        // 군종 로고 (오른쪽 아래)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.transparent,
                            ),
                            child: Image.asset(
                              _getBranchImagePath(branch),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // 하단 시작하기 버튼
            if (widget.onConfirm != null)
              Container(
                padding: EdgeInsets.only(
                  left: 50,
                  right: 50,
                  bottom: MediaQuery.of(context).padding.bottom,
                  top: 16,
                ),
                child: GestureDetector(
                  onTap:
                      _isLoading
                          ? null
                          : () {
                            setState(() => _isLoading = true);
                            // ✅ async confirm을 await해서 실패 시 로딩을 반드시 해제
                            Future<void>(() async {
                              try {
                                await widget.onConfirm?.call();
                              } catch (_) {
                                // 상위에서 ErrorHandler 처리 (여기서는 로딩만 해제)
                              } finally {
                                if (mounted) setState(() => _isLoading = false);
                              }
                            });
                          },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child:
                        _isLoading
                            ? Center(
                              child: SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.surface,
                                  ),
                                ),
                              ),
                            )
                            : Text(
                              '지금부터 시작하기',
                              textAlign: TextAlign.center,
                              style: LocaleTypography.setStyle(
                                context: context,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.surface,
                              ),
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
