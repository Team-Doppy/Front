import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:doppy/pages/onbording/steps/index0_step.dart';
import 'package:doppy/pages/onbording/steps/index1_bg.dart';
import 'package:doppy/pages/onbording/steps/index2_bg.dart';
import 'package:doppy/pages/onbording/steps/index3_step.dart';
import 'package:doppy/pages/onbording/steps/index4_bg.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:provider/provider.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow>
    with TickerProviderStateMixin {
  late AnimationController _snapController;
  late AnimationController _indicatorPulseController; // ✅ 인디케이터 깜빡임 애니메이션
  late Animation<double> _indicatorPulseAnimation;
  int _currentIndex = 0; // 현재 인덱스 (0~4) - 사이드이펙트(키보드) 용
  bool _isDragging = false; // ✅ 전환(드래그) 중 Index2 애니메이션 pause 제어용
  static const double _stackAlignY = 0.15; // ✅ 카드를 위로 올리기 위해 값 감소
  static const int _totalSteps = 5; // 0,1,2,3,4 (5단계)
  static const double _bgFadeOutEnd = 0.25; // ✅ 나갈 때: 초반에 빠르게 페이드아웃(0~0.25)
  // ✅ 페이드인: 300ms 동안 진행 (전체 480ms 기준)
  static const double _bgFadeInStart = 1.0 - (300.0 / 480.0); // ≈ 0.375

  // ✅ Index1 입력 관련(재생성/포커스 부하 줄이기 위해 상위에서 유지)
  late final TextEditingController _index1NicknameController;
  late final FocusNode _index1FocusNode;
  bool _nicknameSubmitted = false; // ✅ 별명 제출 완료 여부
  String _submittedNickname = ''; // ✅ 제출된 별명 저장 (변화 감지용)
  bool _hasNavigatedToPostWrite = false; // ✅ PostWriteScreen으로 전환 여부

  @override
  void initState() {
    super.initState();
    _index1NicknameController = TextEditingController();
    _index1FocusNode = FocusNode();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480), // 프레지 느낌: 여유롭고 쾌감 있는 전환
      lowerBound: 0.0,
      upperBound: (_totalSteps - 1).toDouble(), // 4.0
    )..addListener(() {
      // ✅ 최적화: 프레임마다 setState 금지 (build는 AnimatedBuilder가 처리)
      _updateCurrentIndex();
    });

    // ✅ 인디케이터 깜빡임 애니메이션
    _indicatorPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _indicatorPulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _indicatorPulseController,
        curve: Curves.easeInOut,
      ),
    );

    // ✅ 초기 진입 시 0번 인덱스이면 0.5초 지연 후 애니메이션 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentIndex == 0) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _currentIndex == 0) {
            _indicatorPulseController.repeat(reverse: true);
          }
        });
      }
    });

    // ✅ 온보딩 진입 시: 화이트 테마가 아니면 화이트 테마로 변경
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _applyOnboardingTheme();
      }
    });
  }

  /// ✅ 온보딩 모드에서 화이트 테마 적용 (화이트가 아닌 경우에만)
  void _applyOnboardingTheme() {
    try {
      final themeProvider = context.read<ThemeProvider>();
      final currentTheme = themeProvider.themeMode;

      // 화이트 테마가 아니면 화이트 테마로 변경
      if (currentTheme != ThemeMode.light) {
        themeProvider.setThemeMode(ThemeMode.light);
        debugPrint('[OnboardingFlow] 테마를 화이트로 변경 (원래: ${currentTheme.name})');
      }
    } catch (e) {
      debugPrint('[OnboardingFlow] 테마 적용 실패: $e');
    }
  }

  @override
  void dispose() {
    _snapController.dispose();
    _indicatorPulseController.dispose();
    _index1NicknameController.dispose();
    _index1FocusNode.dispose();
    super.dispose();
  }

  void _updateCurrentIndex() {
    // ✅ 로직 안정성: 항상 controller.value 기반
    final newIndex = (_snapController.value + 0.5).floor().clamp(
      0,
      _totalSteps - 1,
    );
    if (_currentIndex != newIndex) {
      final oldIndex = _currentIndex;
      _currentIndex = newIndex;
      // ✅ 인덱스 1에서 벗어날 때 키보드 즉시 내리기
      if (oldIndex == 1 && newIndex != 1) {
        FocusScope.of(context).unfocus();
      }

      // ✅ 인디케이터 깜빡임 애니메이션 제어
      if (newIndex == 0) {
        // 0번 인덱스 진입: 0.5초 지연 후 애니메이션 시작
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _currentIndex == 0) {
            _indicatorPulseController.repeat(reverse: true);
          }
        });
      } else {
        // 다른 인덱스로 이동: 애니메이션 중지
        _indicatorPulseController.stop();
        _indicatorPulseController.reset();
      }

      // ✅ index 4로 전환 시 PostWriteScreen으로 push
      if (newIndex == 4 && !_hasNavigatedToPostWrite) {
        _hasNavigatedToPostWrite = true;
        // 전환 애니메이션이 완료된 후 push
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            Navigator.of(context)
                .push(
                  PageRouteBuilder(
                    pageBuilder:
                        (context, animation, secondaryAnimation) =>
                            PostwriteScreen(mode: PostWriteMode.onboarding),
                    transitionDuration: const Duration(milliseconds: 300),
                    reverseTransitionDuration: const Duration(
                      milliseconds: 250,
                    ),
                    transitionsBuilder: (
                      context,
                      animation,
                      secondaryAnimation,
                      child,
                    ) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                  ),
                )
                .then((result) {
                  // ✅ pop 시 index 3으로 돌아가기
                  if (mounted && result == 'back') {
                    _hasNavigatedToPostWrite = false; // 다시 전환 가능하도록
                    _snapController.animateTo(
                      3.0,
                      curve: Curves.easeOutCubic,
                      duration: const Duration(milliseconds: 480),
                    );
                  }
                });
          }
        });
      }

      // ✅ 인디케이터 리빌드를 위해 setState 호출
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _onPanStart(DragStartDetails d) {
    if (!_isDragging) {
      setState(() => _isDragging = true);
    }
    _snapController.stop();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final width = MediaQuery.of(context).size.width;

    // 양방향 스와이프 지원: 왼쪽(음수)은 forward, 오른쪽(양수)은 reverse
    // startX 기반 delta는 누적 적용 시 튀기 쉬워서, 프레임 delta 기반으로 누적
    final p = (-d.delta.dx / width);

    // ✅ 별명 입력(index 1)에서는 다음(왼쪽 스와이프)만 막기, 이전(오른쪽 스와이프)은 허용
    if (_currentIndex == 1 && !_nicknameSubmitted) {
      // 왼쪽 스와이프(다음, p > 0)는 완전히 막기
      if (p > 0) {
        return;
      }
      // 오른쪽 스와이프(이전, p < 0)는 허용하되, 1.0 이하로만 제한
      final next = (_snapController.value + p).clamp(
        0.0,
        1.0, // index 1까지만 허용
      );
      _snapController.value = next;
      return;
    }

    final next = (_snapController.value + p).clamp(
      0.0,
      (_totalSteps - 1).toDouble(),
    );
    // controller.value 업데이트 -> listener가 setState 처리
    _snapController.value = next;
  }

  Widget _buildBg(int idx) {
    // ✅ 전환 중(Index2 BG의 반복 애니메이션/이미지 디코딩 등) 부하 완화
    final pauseIndex2Animation = _isDragging || _snapController.isAnimating;
    return switch (idx) {
      0 => Index0Background(name: 'affection_jh'),
      1 => Index1Background(
        nicknameController: _index1NicknameController,
        focusNode: _index1FocusNode,
        onNicknameSubmitted: () => _handleNicknameSubmit(),
        submittedNickname: _submittedNickname, // ✅ 제출된 별명 전달
      ),
      2 => Index2Background(pauseAnimation: pauseIndex2Animation),
      3 => const Index3Background(),
      4 => const Index4Background(),
      _ => const SizedBox.shrink(),
    };
  }

  double _bgOutOpacity(double t) {
    // t: 0..1 (bgFrom 기준 이동량)
    // ✅ “좀 일찍” 나가도록 초반에 빠르게 0으로
    final x = (t / _bgFadeOutEnd).clamp(0.0, 1.0);
    return (1.0 - Curves.easeOutCubic.transform(x)).clamp(0.0, 1.0);
  }

  double _bgInOpacity(double t) {
    // ✅ “거의 다 전환된 후” 마지막 200ms 정도로 페이드인
    // 480ms 기준: (1 - 0.60) = 0.40 구간 ≈ 192ms (요청 200ms 근사)
    final x = ((t - _bgFadeInStart) / (1.0 - _bgFadeInStart)).clamp(0.0, 1.0);
    return Curves.easeInOut.transform(x).clamp(0.0, 1.0);
  }

  /// ✅ 별명 제출 처리 (API 호출 및 상태 업데이트)
  Future<void> _handleNicknameSubmit() async {
    final nickname = _index1NicknameController.text.trim();
    if (nickname.isEmpty) return;

    try {
      // API 호출
      final userProvider = context.read<UserProvider>();
      // 현재 자기소개 가져오기 (없으면 빈 문자열)
      final currentSelfIntroduction =
          userProvider.selfIntroduction ??
          (userProvider.currentUser?.selfIntroduction ?? '');

      final success = await userProvider.updateProfileInfo(
        alias: nickname,
        selfIntroduction: currentSelfIntroduction,
      );

      if (success && mounted) {
        setState(() {
          _nicknameSubmitted = true;
          _submittedNickname = nickname; // ✅ 제출된 별명 저장
        });

        // 키보드 내리기
        FocusScope.of(context).unfocus();

        // 다음 페이지로 이동
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _snapController.animateTo(
              2.0,
              curve: Curves.easeOutCubic,
              duration: const Duration(milliseconds: 480),
            );
          }
        });
      } else if (mounted) {
        // 실패 메시지 표시
        ErrorHandler.showError(context, '별명 저장에 실패했습니다');
      }
    } catch (e) {
      debugPrint('[OnboardingFlow] 별명 저장 실패: $e');
      if (mounted) {
        ErrorHandler.showError(context, '별명 저장에 실패했습니다');
      }
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_isDragging) {
      setState(() => _isDragging = false);
    }
    final velocity = d.velocity.pixelsPerSecond.dx;
    // 속도 기반 임계값: 빠른 스와이프는 방향 우선
    const fastSwipeThreshold = 900.0;
    final progress = _snapController.value; // ✅ 롤백 버그 방지: 항상 현재 controller 값 사용

    int targetIndex;
    if (velocity < -fastSwipeThreshold) {
      // 왼쪽 스와이프: 다음 단계로
      targetIndex = progress.ceil().clamp(0, _totalSteps - 1);
    } else if (velocity > fastSwipeThreshold) {
      // 오른쪽 스와이프: 이전 단계로
      targetIndex = progress.floor().clamp(0, _totalSteps - 1);
    } else {
      // 느린 경우: 가장 가까운 단계로
      targetIndex = progress.round().clamp(0, _totalSteps - 1);
    }

    // ✅ 별명 입력 검증: index 1에서 다음(index 2)으로 넘어갈 때 별명이 제출되지 않았으면 완전히 막기
    if (_currentIndex == 1 && !_nicknameSubmitted) {
      // 별명이 제출되지 않았으면 다음으로 가는 것을 완전히 막기
      if (targetIndex > 1) {
        targetIndex = 1;
      }
      // 이전으로 가는 것은 허용 (targetIndex < 1은 이미 처리됨)
      // progress 값도 1.0 이하로 제한
      if (progress > 1.0) {
        _snapController.value = 1.0;
        return;
      }
    }

    // ✅ 1에서 벗어나는 전환이면 즉시 키보드 내리기
    if (_currentIndex == 1 && targetIndex != 1) {
      FocusScope.of(context).unfocus();
    }

    final targetValue = targetIndex.toDouble();
    if ((_snapController.value - targetValue).abs() < 0.001) {
      _snapController.value = targetValue;
      return;
    }

    _snapController
        .animateTo(
          targetValue,
          curve: Curves.easeOutCubic, // 빠르게 시작해서 느리게 끝나는 easing
          duration: const Duration(milliseconds: 480), // 프레지 느낌: 여유롭고 쾌감 있는 전환
        )
        .whenComplete(() {
          if (!mounted) return;
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        // ✅ 최적화: 애니메이션 프레임 갱신은 AnimatedBuilder가 담당
        child: AnimatedBuilder(
          animation: _snapController,
          builder: (context, _) {
            final progress = _snapController.value;
            // 구간별 정규화 진행도(항상 0~1)
            final t01 = progress.clamp(0.0, 1.0); // 0<->1 카드덱
            final t12 = (progress - 1.0).clamp(0.0, 1.0); // 1<->2 가로 슬라이드
            final t23 = (progress - 2.0).clamp(0.0, 1.0); // 2<->3 리버스 카드덱
            final t34 = (progress - 3.0).clamp(0.0, 1.0); // 3<->4 카드덱

            final inDeck01 = progress < 1.0;
            final inHorizontalSlide12 = progress >= 1.0 && progress < 2.0;
            final inDeckStyle23 = progress >= 2.0 && progress < 3.0;
            final inDeck34 = progress >= 3.0;

            final showBackOnTop = t01 > 0.55;
            final showBackOnTop34 = t34 > 0.55;
            final atIndex3 = (progress - 3.0).abs() < 0.01;

            return Container(
              // 기본 배경
              color: AppColors.lightSurfaceVariant.withOpacity(0.95),
              child: Stack(
                children: [
                  // ===== 0 <-> 1 : 카드덱 모드 =====
                  if (inDeck01) ...[
                    Align(
                      alignment: const Alignment(0, _stackAlignY),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (!showBackOnTop)
                            RepaintBoundary(
                              child: BackCard(
                                progress: t01,
                                color: const Color(0xFFFAFAFA),
                                stackAlignY: _stackAlignY,
                              ),
                            ),
                          IgnorePointer(
                            ignoring: t01 > 0.995, // 거의 끝까지 카드 유지
                            child: RepaintBoundary(
                              child: FrontCard(
                                progress: t01,
                                color: const Color(0xFF5B7FFF), // 인덱스 0: 파란색
                                child: Opacity(
                                  opacity: ((t01 - 0.5).abs() * 2).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  child: const Index0CardContent(),
                                ),
                              ),
                            ),
                          ),
                          if (showBackOnTop)
                            RepaintBoundary(
                              child: BackCard(
                                progress: t01,
                                color: const Color(0xFFFAFAFA),
                                stackAlignY: _stackAlignY,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  // ===== 1 <-> 2 : 가로 슬라이드 모드 =====
                  if (inHorizontalSlide12) ...[
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: _HorizontalSlideMode(t: t12),
                      ),
                    ),
                  ],

                  // ===== 2 <-> 3 : 리버스 카드덱 모드(구 1<->2) =====
                  // ✅ 2 -> 3 : 0 -> 1 로직을 "리버스"로 적용
                  // - 검정(인덱스2): BackCard를 역재생(풀스크린 -> 덱 카드로 축소/회전/이동)
                  // - 파랑(인덱스3): FrontCard를 역재생(왼쪽에서 들어오며 항상 앞)
                  // - 흰(인덱스4): 뒤에 장식으로 고정
                  if (inDeckStyle23) ...[
                    Align(
                      alignment: const Alignment(0, _stackAlignY),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 흰색 장식 카드(오른쪽 뒤)
                          const RepaintBoundary(
                            child: _StaticDeckCard(
                              color: Color(0xFFFAFAFA),
                              rotate: 0.10, // 흰색은 오른쪽으로 기울기
                              translate: Offset(50, 14),
                              scale: 0.90,
                            ),
                          ),

                          // 검정 카드: BackCard를 역재생 (progress = 1 - t23)
                          RepaintBoundary(
                            child: BackCard(
                              progress: (1.0 - t23).clamp(0.0, 1.0),
                              stackAlignY: _stackAlignY,
                              color: AppColors.darkSurface,
                              // ✅ 이동/회전 방향 반전
                              // 인덱스3 정지 포즈(검정 왼쪽)와 동일하게 맞춤
                              restTranslateX: -40,
                              restTranslateY: 14,
                              restRotate: -0.15, // 검정은 왼쪽으로 기울기
                            ),
                          ),

                          // 파란 카드: FrontCard를 역재생 (progress = 1 - t23) => 왼쪽에서 들어오며 항상 앞
                          IgnorePointer(
                            child: RepaintBoundary(
                              child: FrontCard(
                                progress: (1.0 - t23).clamp(0.0, 1.0),
                                color: const Color(0xFF5B7FFF),
                                // ✅ 이동/회전 방향 반전
                                slideSign: 1.0,
                                rotateSign: 1.0,
                                child: Opacity(
                                  opacity: ((t23 - 0.5).abs() * 2).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  child: const Index3CardContent(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ===== 3 <-> 4 : 카드덱 모드(구 2<->3) =====
                  if (inDeck34) ...[
                    Align(
                      alignment: const Alignment(0, _stackAlignY),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // ✅ 인덱스 3에 "정지"했을 때만 3장(검정/파랑/흰) 동시에 노출
                          // 드래그로 3->4 구간 진입(=t34 증가)하면 기존 카드덱 애니메이션으로 전환
                          if (atIndex3) ...[
                            const RepaintBoundary(
                              child: _StaticDeckCard(
                                // 흰(인덱스 4) - 오른쪽
                                color: Color(0xFFFAFAFA),
                                rotate: 0.10, // 흰색은 오른쪽으로 기울기
                                translate: Offset(50, 14),
                                scale: 0.90,
                              ),
                            ),
                            const RepaintBoundary(
                              child: _StaticDeckCard(
                                // 검정(인덱스 2) - 왼쪽
                                color: AppColors.darkSurface,
                                rotate: -0.15, // 검정은 왼쪽으로 기울기
                                translate: Offset(-40, 14),
                                scale: 0.88,
                              ),
                            ),

                            IgnorePointer(
                              child: RepaintBoundary(
                                child: FrontCard(
                                  progress: 0.0,
                                  color: const Color(0xFF5B7FFF), // 파란(인덱스 3)
                                  child: Opacity(
                                    opacity: 1.0, // 인덱스 3 정지 상태에서는 항상 1.0
                                    child: const Index3CardContent(),
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            if (!showBackOnTop34)
                              RepaintBoundary(
                                child: BackCard(
                                  progress: t34,
                                  stackAlignY: _stackAlignY,
                                  color: const Color(
                                    0xFFFAFAFA,
                                  ), // 인덱스 4: 흰색(확대되어 화면 덮음)
                                ),
                              ),
                            // ✅ 검정 카드도 파란 카드와 같이 옆으로 이동하며 사라지게(드래그 구간에서도 계속 렌더)
                            // 인덱스3 정지 포즈와 동일한 시작 포즈(-40,14 / -0.15 / 0.88)에서 출발해
                            // FrontCard와 동일한 곡선으로 옆으로 빠지게 만든다.
                            IgnorePointer(
                              child: RepaintBoundary(
                                child: _MovingDeckCard(
                                  progress: t34,
                                  color: AppColors.darkSurface,
                                  baseTranslate: const Offset(-40, 14),
                                  baseRotate: -0.15,
                                  baseScale: 0.88,
                                ),
                              ),
                            ),
                            IgnorePointer(
                              ignoring: t34 > 0.995, // 거의 끝까지 카드 유지
                              child: RepaintBoundary(
                                child: FrontCard(
                                  progress: t34,
                                  color: const Color(
                                    0xFF5B7FFF,
                                  ), // 인덱스 3: 파란색(사라지는 카드)
                                  child: Opacity(
                                    opacity: ((t34 - 0.5).abs() * 2).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    child: const Index3CardContent(),
                                  ),
                                ),
                              ),
                            ),
                            if (showBackOnTop34)
                              RepaintBoundary(
                                child: BackCard(
                                  progress: t34,
                                  stackAlignY: _stackAlignY,
                                  color: const Color(0xFFFAFAFA),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ], // ===== Background (index 기반) =====
                  Positioned.fill(
                    // ✅ BG 전환: 나갈 때는 일찍 페이드아웃, 들어올 때는 전환 막판에 페이드인
                    child: Builder(
                      builder: (context) {
                        // ✅ 실제 progress 기반으로 from 계산 (일관된 페이드아웃 보장)
                        final from = progress.floor().clamp(0, _totalSteps - 1);
                        final delta = progress - from.toDouble();
                        final t = delta.abs().clamp(0.0, 1.0);

                        // 정착 상태면 단일 BG만 렌더
                        if (t < 0.001) {
                          return RepaintBoundary(child: _buildBg(from));
                        }

                        // 방향 기반 다음 BG(1칸) 선택
                        final to = (from + (delta >= 0 ? 1 : -1)).clamp(
                          0,
                          _totalSteps - 1,
                        );

                        final outOpacity = _bgOutOpacity(t);
                        final inOpacity = _bgInOpacity(t);

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            RepaintBoundary(
                              child: Opacity(
                                opacity: outOpacity,
                                child: _buildBg(from),
                              ),
                            ),
                            // 들어오는 BG는 막판에만 등장
                            if (inOpacity > 0.0)
                              RepaintBoundary(
                                child: Opacity(
                                  opacity: inOpacity,
                                  child: _buildBg(to),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),

                  // ✅ 페이지 인디케이터 (하단 중앙, Stack 최상위 레이어)
                  // 별명 입력(index 1)에서는 항상 숨김
                  if (_currentIndex != 1 && _currentIndex != 2)
                    Positioned(
                      bottom: 40,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_totalSteps, (index) {
                            final isActive = (_currentIndex == index);
                            // ✅ 0번 인덱스일 때 2번째 닷(index 1)에 깜빡임 애니메이션
                            final shouldPulse =
                                _currentIndex == 0 && index == 1;

                            return AnimatedBuilder(
                              animation: _indicatorPulseAnimation,
                              builder: (context, child) {
                                // ✅ 펄스 시 파란색 0.5 opacity와 회색 0.4 opacity 사이를 부드럽게 전환
                                if (shouldPulse) {
                                  // 애니메이션 값에 따라 부드럽게 색상 전환
                                  // 0.0 -> 회색 0.4, 1.0 -> 파란색 0.5
                                  final t = _indicatorPulseAnimation.value;

                                  // 회색과 파란색의 RGB 값을 보간
                                  final grayColor = const Color.fromARGB(
                                    255,
                                    70,
                                    70,
                                    70,
                                  );
                                  final blueColor = const Color(0xFF5B7FFF);

                                  final r =
                                      (grayColor.red +
                                              (blueColor.red - grayColor.red) *
                                                  t)
                                          .round();
                                  final g =
                                      (grayColor.green +
                                              (blueColor.green -
                                                      grayColor.green) *
                                                  t)
                                          .round();
                                  final b =
                                      (grayColor.blue +
                                              (blueColor.blue -
                                                      grayColor.blue) *
                                                  t)
                                          .round();

                                  // opacity도 보간: 0.4 -> 0.8 (더 강한 펄스)
                                  final opacity = 0.4 + (0.7 - 0.4) * t;

                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color.fromRGBO(r, g, b, opacity),
                                    ),
                                  );
                                }

                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        isActive
                                            ? const Color(
                                              0xFF5B7FFF,
                                            ) // 파란색 (활성)
                                            : const Color.fromARGB(
                                              255,
                                              70,
                                              70,
                                              70,
                                            ).withOpacity(0.4), // 회색 (비활성)
                                  ),
                                );
                              },
                            );
                          }),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ===== 1<->2 가로 슬라이드 모드 =====
class _HorizontalSlideMode extends StatelessWidget {
  final double t; // 0..1
  const _HorizontalSlideMode({required this.t});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Stack(
      children: [
        const Positioned.fill(
          child: ColoredBox(color: Color(0xFFFAFAFA)), // 1단계 화면
        ),
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(width * (1.0 - t), 0),
            child: const ColoredBox(
              color: AppColors.darkSurface,
            ), // 2단계 화면  AppColors.darkSurface
          ),
        ),
      ],
    );
  }
}

class FrontCard extends StatelessWidget {
  final double progress;
  final Color color;
  final double slideSign; // -1: 기존(왼쪽으로), +1: 반전(오른쪽으로)
  final double rotateSign; // -1: 기존, +1: 반전
  final Widget? child;
  const FrontCard({
    required this.progress,
    this.color = const Color(0xFF5B7FFF), // 기본값: 파란색
    this.slideSign = -1.0,
    this.rotateSign = -1.0,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ 최적화: MediaQuery 값 캐싱
    final width = MediaQuery.of(context).size.width;

    // 빠르게 시작해서 느리게 끝나는 easing
    // progress가 거의 끝까지 가도 카드가 화면에 일부라도 보이도록 제한
    final clampedProgress = progress.clamp(0.0, 1.0); // 95%까지만 이동
    final eased = Curves.easeOut.transform(clampedProgress);

    // 카드 크기 (4:5 비율) - 더 크게 조정
    final cardWidth = width * 0.85; // ✅ 0.78 -> 0.85로 증가
    final cardHeight = cardWidth * 1.25; // 4:5 비율

    return Transform.translate(
      offset: Offset(slideSign * width * 1.1 * eased, 0),
      child: Transform.rotate(
        angle: rotateSign * 0.28 * eased,
        alignment: Alignment.bottomCenter,
        child: Container(
          width: cardWidth,
          height: cardHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.20),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child:
              child == null
                  ? null
                  : ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: child!,
                  ),
        ),
      ),
    );
  }
}

class BackCard extends StatelessWidget {
  final double progress;
  final double stackAlignY;
  final Color color;
  final double restTranslateX;
  final double restTranslateY;
  final double restRotate;
  const BackCard({
    required this.progress,
    required this.stackAlignY,
    this.color = AppColors.darkSurface, // AppColors.darkSurface
    this.restTranslateX = 50,
    this.restTranslateY = 0,
    this.restRotate = 0.15,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ 최적화: MediaQuery 값 캐싱
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final width = size.width;
    final height = size.height;
    final bottomInset = mediaQuery.padding.bottom;

    // 처음엔 뒤에, 나중엔 앞에 - 빠르게 시작해서 느리게 끝나는 easing
    final eased = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    // 확대/축소는 더 완만하게 느리게 진행 (더 부드러운 확대를 위해 느린 curve 사용)
    final clampedProgress = progress.clamp(0.0, 1.0);
    // Curves.decelerate는 더 부드럽고 느리게 확대됨
    final scaleEased = Curves.decelerate.transform(clampedProgress);

    // 카드 기본 크기 (4:5 비율) - 더 크게 조정
    final cardWidth = width * 0.85; // ✅ 0.78 -> 0.85로 증가
    final cardHeight = cardWidth * 1.25; // 4:5 비율

    // 스케일: 0.88 → 화면을 덮을 만큼 확대 (더 느린 easing 적용)
    final baseScale = 0.88 + 0.12 * scaleEased; // 0.88 → 1.0
    // 화면을 덮도록 확장 (가로/세로 중 더 큰 비율로)
    // 약간의 오버슈트를 줘서 상단이 미세하게 남는 케이스를 방지
    final expandScale = ([
              height / cardHeight,
              width / cardWidth,
            ].reduce((a, b) => a > b ? a : b) *
            1.08)
        .clamp(1.0, 6.0);
    final finalScale = baseScale + (scaleEased * (expandScale - baseScale));

    // X 이동: restTranslateX → 0 (뒤에서 앞으로)
    final translateX = restTranslateX * (1 - eased);

    // 카드 스택이 화면 중앙보다 아래에 있어서, 확대 시 "바닥이 고정"되며 아래 여백이 남음
    // -> 확대될수록 아래로 내려서 화면 하단까지 덮도록 보정
    final stackCenterY = (height * 0.5) + (height * 0.5 * stackAlignY);
    final cardBottomAtRest = stackCenterY + (cardHeight * 0.5);
    final bottomGap = (height - cardBottomAtRest).clamp(0.0, height);
    // 하단 홈 인디케이터/인셋까지 확실히 덮기 위한 오버슈트
    final translateY =
        (bottomGap + bottomInset + 24.0) * eased + restTranslateY * (1 - eased);

    // 회전: restRotate → 정면
    final rotate = restRotate * (1 - eased);

    // 닉네임 UI는 거의 끝까지 숨기고, 마지막에만 나타나게 (카드가 거의 끝까지 유지되도록)
    final contentOpacity = ((eased - 0.75) / 0.25).clamp(0.0, 1.0);
    final radius = 24.0 * (1.0 - eased); // 확대될수록 모서리 0에 수렴

    return Transform.translate(
      offset: Offset(translateX, translateY),
      child: Transform.scale(
        scale: finalScale,
        alignment: Alignment.bottomCenter,
        child: Transform.rotate(
          angle: rotate,
          alignment: Alignment.bottomCenter,
          child: Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: IgnorePointer(
                ignoring: contentOpacity < 0.98,
                child: Opacity(opacity: contentOpacity, child: Container()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// (이전 실험용 전환 위젯들은 더 이상 사용하지 않아서 제거됨)

/// 인덱스 2 "정지 상태"에서만 쓰는 고정 포즈 카드(뒤 카드 2장)
class _StaticDeckCard extends StatelessWidget {
  final Color color;
  final double rotate;
  final Offset translate;
  final double scale;

  const _StaticDeckCard({
    required this.color,
    required this.rotate,
    required this.translate,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cardWidth = width * 0.85; // ✅ 0.78 -> 0.85로 증가
    final cardHeight = cardWidth * 1.25;

    return Transform.translate(
      offset: translate,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.bottomCenter,
        child: Transform.rotate(
          angle: rotate,
          alignment: Alignment.bottomCenter,
          child: Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 2->3 드래그 중, 검정 카드도 파란 카드와 같은 방향으로 같이 빠지도록 하는 "이동 카드"
class _MovingDeckCard extends StatelessWidget {
  final double progress; // 0..1
  final Color color;
  final Offset baseTranslate;
  final double baseRotate;
  final double baseScale;

  const _MovingDeckCard({
    required this.progress,
    required this.color,
    required this.baseTranslate,
    required this.baseRotate,
    required this.baseScale,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // FrontCard와 동일한 easing으로 속도 맞춤
    // progress가 거의 끝까지 가도 카드가 화면에 일부라도 보이도록 제한
    final clampedProgress = progress.clamp(0.0, 1.0); // 95%까지만 이동
    final eased = Curves.easeOut.transform(clampedProgress);

    final cardWidth = width * 0.85; // ✅ 0.78 -> 0.85로 증가
    final cardHeight = cardWidth * 1.25;

    // FrontCard와 같은 곡선으로 좌측으로 빠짐(-) + 회전(-)
    final dx = baseTranslate.dx + (-width * 1.1 * eased);
    final dy = baseTranslate.dy;
    final rotate = baseRotate + (-0.28 * eased);
    final scale = baseScale;

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.bottomCenter,
        child: Transform.rotate(
          angle: rotate,
          alignment: Alignment.bottomCenter,
          child: Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.20),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
