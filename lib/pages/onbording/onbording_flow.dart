import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  late AnimationController _index0HintController; // ✅ index0 카드 미세 스와이프 힌트
  late AnimationController _index3HintController; // ✅ index3 카드 미세 스와이프 힌트
  int _currentIndex = 0; // 현재 인덱스 (0~4) - 사이드이펙트(키보드) 용
  bool _isDragging = false; // ✅ 전환(드래그) 중 Index2 애니메이션 pause 제어용
  static const double _stackAlignY = 0.15; // ✅ 카드를 위로 올리기 위해 값 감소
  static const int _totalSteps = 5; // 0,1,2,3,4 (5단계)
  static const double _bgFadeOutEnd = 0.25; // ✅ 나갈 때: 초반에 빠르게 페이드아웃(0~0.25)
  // ✅ 페이드인: 300ms 동안 진행 (전체 480ms 기준)
  static const double _bgFadeInStart = 1.0 - (300.0 / 480.0); // ≈ 0.375

  // ✅ Index1 입력 관련
  late final TextEditingController _index1NicknameController;
  bool _nicknameSubmitted = false; // ✅ 별명 제출 완료 여부
  String _submittedNickname = ''; // ✅ 제출된 별명 저장 (변화 감지용)
  bool _hasNavigatedToPostWrite = false; // ✅ PostWriteScreen으로 전환 여부
  bool _isProfileImageUploaded = false; // ✅ 프로필 사진 업로드 완료 여부
  bool _shouldHideIndicatorInIndex1 =
      false; // ✅ index1에서 인디케이터 숨김 여부 (키보드/완료 버튼)
  bool _rebuildScheduled = false;
  int _autoAdvanceNonce = 0; // ✅ index2 업로드 완료 후 자동 이동 예약 취소/무효화용
  bool _autoAdvanceInterrupted = false; // ✅ 사용자 인터럽션(탭/스와이프) 여부

  @override
  void initState() {
    super.initState();
    _index1NicknameController = TextEditingController();
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

    // ✅ index0 카드 "살짝 스와이프" 힌트 애니메이션 (아주 미세하게 반복)
    _index0HintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // ✅ 1초로 변경
    );

    // ✅ index3 카드 "살짝 스와이프" 힌트 애니메이션 (아주 미세하게 반복)
    _index3HintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // ✅ 1초로 변경
    );

    // ✅ 초기 진입 시 0번 인덱스이면 0.5초 지연 후 애니메이션 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentIndex == 0) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _currentIndex == 0) {
            _indicatorPulseController.repeat(reverse: true);
            _index0HintController.repeat(reverse: true);
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
    _index0HintController.dispose();
    _index3HintController.dispose();
    _index1NicknameController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    // build 중/프레임 중 들어오는 콜백(setState) 충돌 방지: 다음 프레임으로 미룸
    final phase = SchedulerBinding.instance.schedulerPhase;
    final shouldDefer =
        phase != SchedulerPhase.idle &&
        phase != SchedulerPhase.postFrameCallbacks;
    if (!shouldDefer) {
      setState(fn);
      return;
    }
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (!mounted) return;
      setState(fn);
    });
  }

  void _interruptIndex2AutoAdvance() {
    // ✅ 사용자 인터럽션이 들어오면, 예약된 자동 이동 취소
    _autoAdvanceInterrupted = true;
    _autoAdvanceNonce++;
  }

  void _scheduleIndex2AutoAdvanceIfNeeded() {
    // ✅ index2에서 업로드 완료(멋진데요?)가 뜬 후,
    // 사용자의 인터럽션이 없으면 잠깐 지연 후 다음으로 자동 이동
    if (_currentIndex != 2) return;
    if (!_isProfileImageUploaded) return;

    final nonce = ++_autoAdvanceNonce;
    _autoAdvanceInterrupted = false;

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      if (_autoAdvanceNonce != nonce) return;
      if (_autoAdvanceInterrupted) return;
      if (_currentIndex != 2) return;
      if (!_isProfileImageUploaded) return;
      if (_isDragging || _snapController.isAnimating) return;

      _snapController.animateTo(
        3.0,
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 480),
      );
    });
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
        // ✅ index1에서 임시로 바꾼 텍스트는 유지하지 않고, 마지막으로 "제출된 별명"으로 복원
        if (_nicknameSubmitted) {
          final text = _submittedNickname;
          _index1NicknameController.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        }
      }

      // ✅ 다시 index1로 돌아올 때도 항상 "제출된 별명"으로 시작
      if (newIndex == 1 && _nicknameSubmitted) {
        final text = _submittedNickname;
        _index1NicknameController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }

      // ✅ 업로드가 완료된 상태로 index2에 들어오면 자동 이동 예약
      if (newIndex == 2 && _isProfileImageUploaded) {
        _scheduleIndex2AutoAdvanceIfNeeded();
      }

      // ✅ 인디케이터 깜빡임 애니메이션 제어
      if (newIndex == 0) {
        // 0번 인덱스 진입: 0.5초 지연 후 애니메이션 시작
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _currentIndex == 0) {
            _indicatorPulseController.repeat(reverse: true);
            if (!_isDragging && !_snapController.isAnimating) {
              _index0HintController.repeat(reverse: true);
            }
          }
        });
      } else if (newIndex == 3) {
        // 3번 인덱스 진입: 0.5초 지연 후 애니메이션 시작
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _currentIndex == 3) {
            if (!_isDragging && !_snapController.isAnimating) {
              _index3HintController.repeat(reverse: true);
            }
          }
        });
      } else {
        // 다른 인덱스로 이동: 애니메이션 중지
        _indicatorPulseController.stop();
        _indicatorPulseController.reset();
        _index0HintController.stop();
        _index0HintController.reset();
        _index3HintController.stop();
        _index3HintController.reset();
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
      // ✅ AnimatedBuilder가 프레임마다 build하므로 여기서 setState로 강제 리빌드는 하지 않음
    }
  }

  void _onPanStart(DragStartDetails d) {
    if (!_isDragging) {
      setState(() => _isDragging = true);
    }
    // ✅ index2에서 스와이프 시작은 자동 이동 인터럽트로 간주
    if (_currentIndex == 2) {
      _interruptIndex2AutoAdvance();
    }
    // ✅ 사용자가 직접 밀기 시작하면 힌트 애니메이션은 즉시 중지
    if (_currentIndex == 0) {
      _index0HintController.stop();
      _index0HintController.reset();
    } else if (_currentIndex == 3) {
      _index3HintController.stop();
      _index3HintController.reset();
    }
    _snapController.stop();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final width = MediaQuery.of(context).size.width;

    // 양방향 스와이프 지원: 왼쪽(음수)은 forward, 오른쪽(양수)은 reverse
    // startX 기반 delta는 누적 적용 시 튀기 쉬워서, 프레임 delta 기반으로 누적
    // ✅ 스와이프 감도 약간 둔감하게: 0.92 배율 적용
    const double swipeSensitivity = 0.92;
    final p = (-d.delta.dx / width) * swipeSensitivity;

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
        onNicknameSubmitted: () => _handleNicknameSubmit(),
        submittedNickname: _submittedNickname, // ✅ 제출된 별명 전달
        onShouldHideIndicator: (shouldHide) {
          if (_shouldHideIndicatorInIndex1 == shouldHide) return;
          _safeSetState(() {
            _shouldHideIndicatorInIndex1 = shouldHide;
          });
        },
      ),
      2 => Index2Background(
        pauseAnimation: pauseIndex2Animation,
        onProfileImageUploaded: (isUploaded) {
          if (_isProfileImageUploaded == isUploaded) return;
          _safeSetState(() {
            _isProfileImageUploaded = isUploaded;
          });
          // ✅ 업로드 완료 콜백을 index2에서 받으면 자동 이동 예약
          if (isUploaded) {
            _scheduleIndex2AutoAdvanceIfNeeded();
          }
        },
      ),
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
          // ✅ index0로 다시 정착했으면 힌트 애니메이션 재개
          if ((_snapController.value - 0.0).abs() < 0.001 &&
              _currentIndex == 0 &&
              !_isDragging) {
            _index0HintController.repeat(reverse: true);
          }
          // ✅ index3로 다시 정착했으면 힌트 애니메이션 재개
          if ((_snapController.value - 3.0).abs() < 0.001 &&
              _currentIndex == 3 &&
              !_isDragging) {
            _index3HintController.repeat(reverse: true);
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTapDown: (_) {
          // ✅ index2에서 탭도 인터럽트로 간주(자동 이동 취소)
          if (_currentIndex == 2) {
            _interruptIndex2AutoAdvance();
          }
        },
        child: Stack(
          children: [
            // ===== Cards: snap + hint 로만 갱신 =====
            AnimatedBuilder(
              animation: _snapController,
              builder: (context, _) {
                final progress = _snapController.value;

                final baseT01 = progress.clamp(0.0, 1.0);
                final t01 = baseT01.clamp(0.0, 1.0);
                final t12 = (progress - 1.0).clamp(0.0, 1.0);
                final t23 = (progress - 2.0).clamp(0.0, 1.0);
                final t34 = (progress - 3.0).clamp(0.0, 1.0);

                final inDeck01 = progress < 1.0;
                final inHorizontalSlide12 = progress >= 1.0 && progress < 2.0;
                final inDeckStyle23 = progress >= 2.0 && progress < 3.0;
                final inDeck34 = progress >= 3.0;

                final showBackOnTop = t01 > 0.55;
                final showBackOnTop34 = t34 > 0.55;
                final atIndex3 = (progress - 3.0).abs() < 0.01;

                return Container(
                  color: Colors.transparent,
                  child: Stack(
                    children: [
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
                                ignoring: t01 > 0.995,
                                // ✅ index0에서만: 파란 카드 위젯 자체를 Transform으로 살짝 이동(눈속임)
                                // progress(t01)는 건드리지 않아서 BG 전환/스냅 로직 영향 없음
                                child: AnimatedBuilder(
                                  animation: _index0HintController,
                                  builder: (context, _) {
                                    final shouldWiggle =
                                        _currentIndex == 0 &&
                                        !_isDragging &&
                                        !_snapController.isAnimating &&
                                        progress < 0.02;
                                    final t =
                                        shouldWiggle
                                            ? Curves.easeInOutCubic.transform(
                                              _index0HintController.value,
                                            )
                                            : 0.0;
                                    // ✅ 더 넓은 운동 범위로 왼쪽으로 살짝 움직였다가 복귀
                                    final dx = -15.0 * t;
                                    return Transform.translate(
                                      offset: Offset(dx, 0),
                                      child: RepaintBoundary(
                                        child: FrontCard(
                                          progress: t01,
                                          color: const Color(0xFF5B7FFF),
                                          child: Opacity(
                                            opacity: ((t01 - 0.5).abs() * 2)
                                                .clamp(0.0, 1.0),
                                            child: const Index0CardContent(),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
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

                      if (inHorizontalSlide12) ...[
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: _HorizontalSlideMode(t: t12),
                          ),
                        ),
                      ],

                      if (inDeckStyle23) ...[
                        Align(
                          alignment: const Alignment(0, _stackAlignY),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const RepaintBoundary(
                                child: _StaticDeckCard(
                                  color: Color(0xFFFAFAFA),
                                  rotate: 0.10,
                                  translate: Offset(50, 14),
                                  scale: 0.90,
                                ),
                              ),
                              RepaintBoundary(
                                child: BackCard(
                                  progress: (1.0 - t23).clamp(0.0, 1.0),
                                  stackAlignY: _stackAlignY,
                                  color: AppColors.darkSurface,
                                  restTranslateX: -40,
                                  restTranslateY: 14,
                                  restRotate: -0.15,
                                ),
                              ),
                              IgnorePointer(
                                child: RepaintBoundary(
                                  child: FrontCard(
                                    progress: (1.0 - t23).clamp(0.0, 1.0),
                                    color: const Color(0xFF5B7FFF),
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

                      if (inDeck34) ...[
                        Align(
                          alignment: const Alignment(0, _stackAlignY),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (atIndex3) ...[
                                const RepaintBoundary(
                                  child: _StaticDeckCard(
                                    color: Color(0xFFFAFAFA),
                                    rotate: 0.10,
                                    translate: Offset(50, 14),
                                    scale: 0.90,
                                  ),
                                ),
                                const RepaintBoundary(
                                  child: _StaticDeckCard(
                                    color: AppColors.darkSurface,
                                    rotate: -0.15,
                                    translate: Offset(-40, 14),
                                    scale: 0.88,
                                  ),
                                ),
                                IgnorePointer(
                                  // ✅ index3에서도: 파란 카드 위젯 자체를 Transform으로 살짝 이동(눈속임)
                                  child: AnimatedBuilder(
                                    animation: _index3HintController,
                                    builder: (context, _) {
                                      final shouldWiggle =
                                          _currentIndex == 3 &&
                                          !_isDragging &&
                                          !_snapController.isAnimating &&
                                          (progress - 3.0).abs() < 0.01;
                                      final t =
                                          shouldWiggle
                                              ? Curves.easeInOutCubic.transform(
                                                _index3HintController.value,
                                              )
                                              : 0.0;
                                      // ✅ 더 넓은 운동 범위로 왼쪽으로 살짝 움직였다가 복귀
                                      final dx = -15.0 * t;
                                      return Transform.translate(
                                        offset: Offset(dx, 0),
                                        child: RepaintBoundary(
                                          child: FrontCard(
                                            progress: 0.0,
                                            color: const Color(0xFF5B7FFF),
                                            child: Opacity(
                                              opacity: 1.0,
                                              child: const Index3CardContent(),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ] else ...[
                                if (!showBackOnTop34)
                                  RepaintBoundary(
                                    child: BackCard(
                                      progress: t34,
                                      stackAlignY: _stackAlignY,
                                      color: const Color(0xFFFAFAFA),
                                    ),
                                  ),
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
                                  ignoring: t34 > 0.995,
                                  child: RepaintBoundary(
                                    child: FrontCard(
                                      progress: t34,
                                      color: const Color(0xFF5B7FFF),
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
                      ],
                    ],
                  ),
                );
              },
            ),

            // ===== Background: snapController로만 갱신 (힌트 애니메이션으로 BG/텍스트필드 리빌드 방지) =====
            // ✅ BG는 카드 위에 있어야 실제 입력 UI(index1 등)가 가려지지 않음
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _snapController,
                builder: (context, _) {
                  final progress = _snapController.value;
                  final from = progress.floor().clamp(0, _totalSteps - 1);
                  final delta = progress - from.toDouble();
                  final t = delta.abs().clamp(0.0, 1.0);

                  if (t < 0.001) {
                    return RepaintBoundary(
                      child: KeyedSubtree(
                        key: ValueKey('bg-$from'),
                        child: _buildBg(from),
                      ),
                    );
                  }

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
                          child: KeyedSubtree(
                            key: ValueKey('bg-$from'),
                            child: _buildBg(from),
                          ),
                        ),
                      ),
                      if (inOpacity > 0.0)
                        RepaintBoundary(
                          child: Opacity(
                            opacity: inOpacity,
                            child: KeyedSubtree(
                              key: ValueKey('bg-$to'),
                              child: _buildBg(to),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // ===== Indicator: snapController로만 갱신 =====
            AnimatedBuilder(
              animation: _snapController,
              builder: (context, _) {
                // ✅ index2는 기본적으로 숨김이지만, 프로필 업로드가 완료되면 표시
                if (_currentIndex == 2 && !_isProfileImageUploaded) {
                  return const SizedBox.shrink();
                }
                if (_currentIndex == 1 &&
                    (!_nicknameSubmitted || _shouldHideIndicatorInIndex1)) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_totalSteps, (index) {
                        // ✅ 현재 인덱스에 해당하는 닷만 활성화
                        final isActive = _currentIndex == index;
                        final shouldPulse = _currentIndex == 0 && index == 1;
                        return AnimatedBuilder(
                          animation: _indicatorPulseAnimation,
                          builder: (context, child) {
                            if (shouldPulse) {
                              final t = _indicatorPulseAnimation.value;
                              final grayColor = const Color.fromARGB(
                                255,
                                70,
                                70,
                                70,
                              );
                              final blueColor = const Color(0xFF5B7FFF);
                              final r =
                                  (grayColor.red +
                                          (blueColor.red - grayColor.red) * t)
                                      .round();
                              final g =
                                  (grayColor.green +
                                          (blueColor.green - grayColor.green) *
                                              t)
                                      .round();
                              final b =
                                  (grayColor.blue +
                                          (blueColor.blue - grayColor.blue) * t)
                                      .round();
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
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    isActive
                                        ? const Color(0xFF5B7FFF)
                                        : const Color.fromARGB(
                                          255,
                                          70,
                                          70,
                                          70,
                                        ).withOpacity(0.4),
                              ),
                            );
                          },
                        );
                      }),
                    ),
                  ),
                );
              },
            ),
          ],
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
            borderRadius: BorderRadius.circular(32),
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
                    borderRadius: BorderRadius.circular(32),
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
    final radius = 32.0 * (1.0 - eased); // 확대될수록 모서리 0에 수렴

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
              borderRadius: BorderRadius.circular(32),
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
              borderRadius: BorderRadius.circular(32),
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
