import 'dart:math' as math;
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 곰신 모드 - 선택한 군인 확인 단계 (프로필 원 2개 + 하트)
class MilitaryGirlfriendConfirmationStep extends StatefulWidget {
  final String selectedUsername;
  final String? selectedProfileImageUrl;
  final String? selectedAlias;
  final VoidCallback? onConfirm;
  final VoidCallback? onBack;
  final ValueNotifier<bool>? isLoadingNotifier; // ✅ 로딩 상태 전달용

  const MilitaryGirlfriendConfirmationStep({
    super.key,
    required this.selectedUsername,
    this.selectedProfileImageUrl,
    this.selectedAlias,
    this.onConfirm,
    this.onBack,
    this.isLoadingNotifier,
  });

  @override
  State<MilitaryGirlfriendConfirmationStep> createState() =>
      _MilitaryGirlfriendConfirmationStepState();
}

/// 하트 파티클 데이터 클래스
class _HeartParticle {
  final String id;
  final Offset startPosition;
  final double startSize;
  final double rotation;
  final double horizontalOffset;
  final AnimationController controller;

  _HeartParticle({
    required this.id,
    required this.startPosition,
    required this.startSize,
    required this.rotation,
    required this.horizontalOffset,
    required this.controller,
  });
}

class _MilitaryGirlfriendConfirmationStepState
    extends State<MilitaryGirlfriendConfirmationStep>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isLoading = false; // ✅ 로딩 상태

  // ✅ 하트 파티클 관리
  final List<_HeartParticle> _heartParticles = [];
  late AnimationController _heartSpawnController;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 펄스 애니메이션 반복
    _pulseController.repeat(reverse: true);

    // ✅ 하트 파티클 생성 타이머
    _heartSpawnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), // 500ms마다 새 하트 생성
    )..repeat();

    _heartSpawnController.addListener(_spawnHeart);

    // ✅ 외부에서 로딩 상태 변경 감지
    widget.isLoadingNotifier?.addListener(_onLoadingChanged);
  }

  void _onLoadingChanged() {
    if (mounted) {
      setState(() {
        _isLoading = widget.isLoadingNotifier?.value ?? false;
      });
    }
  }

  /// 새로운 하트 파티클 생성
  void _spawnHeart() {
    if (!mounted) return;

    // 최대 파티클 개수 제한 (너무 많이 생성되지 않도록)
    if (_heartParticles.length >= 15) return;

    // 하트 아이콘 위치 기준으로 생성 (중앙 하트 아이콘 아래)
    final heartCenterX = MediaQuery.of(context).size.width / 2;
    final heartCenterY = MediaQuery.of(context).size.height / 2 - 70; // 프로필 위쪽

    // 랜덤 시작 위치 (하트 아이콘 주변) - 가로 범위 확대
    final startX =
        heartCenterX +
        (_random.nextDouble() - 0.5) * 200; // -100 ~ +100 범위 (더 넓게)
    final startY = heartCenterY + 40 + _random.nextDouble() * 30;

    // 랜덤 속성
    final size = 16.0 + _random.nextDouble() * 12.0; // 16~28px
    final rotation = _random.nextDouble() * 2 * math.pi;
    final horizontalOffset = (_random.nextDouble() - 0.5) * 120; // 좌우 흔들림 범위 확대

    final controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: 2000 + _random.nextInt(1000), // 2~3초
      ),
    );

    final particle = _HeartParticle(
      id:
          DateTime.now().millisecondsSinceEpoch.toString() +
          _random.nextInt(1000).toString(),
      startPosition: Offset(startX, startY),
      startSize: size,
      rotation: rotation,
      horizontalOffset: horizontalOffset,
      controller: controller,
    );

    setState(() {
      _heartParticles.add(particle);
    });

    // 애니메이션 완료 시 파티클 제거
    controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _heartParticles.remove(particle);
        });
        controller.dispose();
      }
    });
  }

  @override
  void dispose() {
    widget.isLoadingNotifier?.removeListener(_onLoadingChanged);
    _pulseController.dispose();
    _heartSpawnController.dispose();
    // 모든 하트 파티클 컨트롤러 정리
    for (final particle in _heartParticles) {
      particle.controller.dispose();
    }
    _heartParticles.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUser = userProvider.currentUser;
    final myProfileImageUrl = currentUser?.profileImageUrl ?? '';
    final myUsername = currentUser?.username ?? '';
    final myAlias = currentUser?.alias ?? myUsername;

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
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 프로필 원 2개 + 하트
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              children: [
                                CommonProfileAvatar(
                                  imageUrl: myProfileImageUrl,
                                  username: myUsername,
                                  size: 140.0,
                                  borderColor: Colors.transparent,
                                  borderWidth: 0,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  myAlias,
                                  style: LocaleTypography.setStyle(
                                    context: context,
                                    fontSize: 16,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),

                            SizedBox(width: 16),
                            // 선택한 군인 프로필 원 + 별명 (Hero 애니메이션만 적용)
                            Column(
                              children: [
                                Hero(
                                  tag:
                                      'selected_profile_${widget.selectedUsername}',
                                  child: Material(
                                    color: Colors.transparent,
                                    child: CommonProfileAvatar(
                                      imageUrl: widget.selectedProfileImageUrl,
                                      username: widget.selectedUsername,
                                      size: 140.0,
                                      borderColor: Colors.transparent,
                                      borderWidth: 0,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.selectedAlias ??
                                      widget.selectedUsername,
                                  style: LocaleTypography.setStyle(
                                    context: context,
                                    fontSize: 16,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // ✅ 하트 파티클 오버레이
                  ..._heartParticles.map((particle) {
                    return AnimatedBuilder(
                      animation: particle.controller,
                      builder: (context, child) {
                        final progress = particle.controller.value;
                        final curve = Curves.easeOut.transform(progress);

                        // 위로 이동 (페이드아웃)
                        final offsetY = -curve * 250; // 최대 250px 위로
                        final offsetX =
                            math.sin(progress * math.pi * 2) *
                            particle.horizontalOffset *
                            curve; // 좌우 흔들림

                        // 페이드아웃
                        final opacity = (1.0 - progress).clamp(0.0, 1.0);

                        // 스케일 (작아지면서 사라짐)
                        final scale = 1.0 - progress * 0.3;

                        // 회전
                        final rotation = particle.rotation + progress * math.pi;

                        return Positioned(
                          left: particle.startPosition.dx + offsetX,
                          top: particle.startPosition.dy + offsetY,
                          child: Opacity(
                            opacity: opacity,
                            child: Transform.scale(
                              scale: scale,
                              child: Transform.rotate(
                                angle: rotation,
                                child: Icon(
                                  Icons.favorite,
                                  color: const Color.fromARGB(
                                    255,
                                    255,
                                    103,
                                    92,
                                  ),
                                  size: particle.startSize,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ],
              ),
            ),
            // 하단 요청 보내기 버튼
            if (widget.onConfirm != null)
              Container(
                padding: EdgeInsets.only(
                  left: 50,
                  right: 50,
                  bottom: MediaQuery.of(context).padding.bottom,
                  top: 16,
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap:
                          _isLoading
                              ? null
                              : () {
                                setState(() {
                                  _isLoading = true;
                                });
                                // 로딩 시작 후 콜백 호출
                                widget.onConfirm?.call();
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
                                  '요청 보내기',
                                  textAlign: TextAlign.center,
                                  style: LocaleTypography.setStyle(
                                    context: context,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                  ),
                                ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${widget.selectedAlias ?? widget.selectedUsername}이(가) 확인하면 시작돼요',
                      textAlign: TextAlign.center,
                      style: LocaleTypography.setStyle(
                        context: context,
                        fontSize: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
