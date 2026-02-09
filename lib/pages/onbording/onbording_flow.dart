import 'package:dio/dio.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/data/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:doppy/pages/onbording/steps/military_user_type_selection_step.dart';
import 'package:doppy/pages/onbording/steps/military_branch_step.dart';
import 'package:doppy/pages/onbording/steps/military_date_step.dart';
// import 'package:doppy/utils/military_time_utils.dart'; // 서버 중심 구조로 변경 - 계산 로직 제거
import 'package:doppy/pages/onbording/steps/military_user_search_step.dart';
import 'package:doppy/pages/onbording/steps/nickname_setting_step.dart';
import 'package:doppy/pages/onbording/steps/profile_setting_step.dart';
import 'package:doppy/pages/onbording/steps/military_welcome_step.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:provider/provider.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late PageController _pageController;
  int _currentPage = 0;

  // 🎯 온보딩 데이터
  UserType? _userType;
  MilitaryBranch? _branch = MilitaryBranch.army; // ✅ 기본값: 육군
  DateTime? _enlistmentDate;
  DateTime? _plannedEnlistmentDate;
  MilitaryRank? _currentRank;
  // ✅ 곰신 모드 로딩 상태 관리
  final ValueNotifier<bool> _girlfriendLoadingNotifier = ValueNotifier<bool>(
    false,
  );
  List<String> _connectedMilitaryUserIds = [];
  bool _userSearchCompleted = false;
  bool _nicknameCompleted = false;

  // 별명 입력 관련
  late final TextEditingController _nicknameController;
  String _submittedNickname = '';

  // 🎯 동적 단계 수 계산
  int get _totalSteps {
    if (_userType == null) return 1; // 역할 선택만

    if (_userType == UserType.girlfriend) {
      // 곰신: 역할(0) → 별명(1) → 프로필(2) → 군인 검색(3)
      return 4;
    } else if (_userType == UserType.military ||
        _userType == UserType.plannedEnlistment) {
      // 군인/입대 예정: 역할(0) → 군종(1) → 입대일(2) → 별명(3) → 프로필(4) → 환영(5)
      return 6;
    }
    return 1;
  }

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController();
    _pageController = PageController();

    // ✅ 역할 선택 Step이 기본으로 선택하는 값(현재: index=1 '입대 예정이에요')을
    // OnboardingFlow도 동일하게 초기화해, 첫 프레임 직후 _totalSteps 변경으로 PageView가
    // 재생성되며 "첫 진입 타이틀 애니메이션이 안 보이는" 문제를 방지한다.
    _userType ??= UserType.plannedEnlistment;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  bool _canProceedToNext() {
    switch (_currentPage) {
      case 0: // 역할 선택
        return _userType != null;
      case 1: // 조건부 단계
        if (_userType == UserType.girlfriend) {
          // 곰신: 별명 입력
          return _nicknameCompleted;
        } else if (_userType == UserType.military ||
            _userType == UserType.plannedEnlistment) {
          // 군인/입대 예정: 군종 선택 (기본값이 있으므로 항상 true)
          return true;
        }
        return false;
      case 2: // 조건부 단계 2
        if (_userType == UserType.girlfriend) {
          // 곰신: 프로필 업로드 (선택사항)
          return true; // 프로필은 필수 항목이 아님
        } else if (_userType == UserType.military) {
          // 이미 입대한 군인: 입대일 선택 (기본값이 있으므로 항상 true)
          return true;
        } else if (_userType == UserType.plannedEnlistment) {
          // 입대 예정자: 입대일 선택 (기본값이 있으므로 항상 true)
          return true;
        }
        return false;
      case 3: // 조건부 단계 3
        if (_userType == UserType.girlfriend) {
          // 곰신: 군인 검색 (반드시 선택 필요)
          return _userSearchCompleted && _connectedMilitaryUserIds.isNotEmpty;
        } else if (_userType == UserType.military ||
            _userType == UserType.plannedEnlistment) {
          // 군인/입대 예정: 별명 입력 (기본값이 있으므로 항상 true)
          return true;
        }
        return false;
      case 4: // 조건부 단계 4
        if (_userType == UserType.military ||
            _userType == UserType.plannedEnlistment) {
          // 군인/입대 예정: 프로필 업로드 (선택사항)
          return true; // 프로필은 필수 항목이 아님
        }
        return false;
      case 5: // 조건부 단계 5
        if (_userType == UserType.military ||
            _userType == UserType.plannedEnlistment) {
          // 군인/입대 예정: 환영 화면 (항상 진행 가능)
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  void _nextPage() {
    if (!mounted) return;
    if (!_canProceedToNext()) {
      ErrorHandler.showError(context, '필수 항목을 선택해주세요.');
      return;
    }
    if (_currentPage < _totalSteps - 1 && _pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _previousPage() {
    if (!mounted) return;
    if (_currentPage > 0 && _pageController.hasClients) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _buildPage(int index) {
    // Index 0: 역할 선택 (항상)
    if (index == 0) {
      return MilitaryUserTypeSelectionStep(
        key: const ValueKey('military_user_type_selection'), // 위젯 인스턴스 유지
        initialUserType: _userType,
        initialIsPlanned: _userType == UserType.plannedEnlistment,
        onUserTypeSelected: (type, isPlanned) {
          // build 중에 setState를 호출하지 않도록 addPostFrameCallback 사용
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _userType = type;
              if (type == UserType.military ||
                  type == UserType.plannedEnlistment) {
                _connectedMilitaryUserIds = [];
              }
            });
          });
        },
        onConfirm: _nextPage,
      );
    }

    // _userType이 아직 설정되지 않았으면 빈 화면
    if (_userType == null) {
      return const SizedBox.shrink();
    }

    // 곰신 모드: 역할(0) → 별명(1) → 프로필(2) → 군인 검색(3)
    if (_userType == UserType.girlfriend) {
      return switch (index) {
        1 => NicknameSettingStep(
          nicknameController: _nicknameController,
          userType: _userType,
          onNicknameSubmitted: () {
            // 로컬 상태만 업데이트 (API 호출 없음)
            setState(() {
              _submittedNickname = _nicknameController.text.trim();
              _nicknameCompleted = _submittedNickname.isNotEmpty;
            });
          },
          onConfirm: _nextPage,
          onBack: _previousPage,
        ),
        2 => ProfileSettingStep(
          pauseAnimation: false,
          onProfileImageUploaded: (isUploaded) {
            // 프로필 업로드는 선택 사항(진행 가능 여부에 영향 없음)
          },
          onConfirm: _nextPage, // 다음 버튼 클릭 시 검색 단계로
          onBack: _previousPage,
        ),
        3 => MilitaryUserSearchStep(
          userType: _userType!,
          initialUserIds: _connectedMilitaryUserIds,
          isLoadingNotifier: _girlfriendLoadingNotifier,
          onUserIdsSelected: (userIds) {
            if (mounted) {
              setState(() {
                _connectedMilitaryUserIds = userIds;
                // 선택 상태만 업데이트 (자동 완료는 하지 않음)
                _userSearchCompleted = userIds.isNotEmpty;
              });
              // 곰신 모드가 아닌 경우 자동 완료하지 않음 (확인 버튼 필요)
            }
          },
          onConfirm:
              _userType == UserType.girlfriend
                  ? () {
                    // 곰신 모드: 요청 보내기 버튼 클릭 시 온보딩 완료 후 스플래시로 이동
                    if (mounted) {
                      _girlfriendLoadingNotifier.value = true; // ✅ 로딩 시작
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (mounted) _completeOnboardingForGirlfriend();
                      });
                    }
                  }
                  : () {
                    // 가족/친구 모드: 확인 버튼 클릭 시 온보딩 완료
                    if (mounted) {
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (mounted) _completeOnboarding();
                      });
                    }
                  },
          onBack: _previousPage,
        ),
        _ => const SizedBox.shrink(),
      };
    }

    // 군인/입대 예정 모드
    if (_userType == UserType.military ||
        _userType == UserType.plannedEnlistment) {
      if (_userType == UserType.plannedEnlistment) {
        // 입대 예정: 역할(0) → 군종(1) → 입대일(2) → 별명(3) → 프로필(4)
        return switch (index) {
          1 => MilitaryBranchStep(
            initialBranch: _branch,
            onBranchSelected: (branch) {
              if (mounted) {
                setState(() {
                  _branch = branch;
                });
              }
            },
            onConfirm: _nextPage,
            onBack: _previousPage,
          ),
          2 => MilitaryDateStep(
            status: MilitaryStatus.beforeEnlistment,
            initialDate: _plannedEnlistmentDate,
            onDateSelected: (date) {
              if (mounted) {
                setState(() {
                  _plannedEnlistmentDate = date;
                });
              }
            },
            onConfirm: _nextPage,
            onBack: _previousPage,
          ),
          3 => NicknameSettingStep(
            nicknameController: _nicknameController,
            userType: _userType,
            onNicknameSubmitted: () {
              // 로컬 상태만 업데이트 (API 호출 없음)
              if (mounted) {
                setState(() {
                  _submittedNickname = _nicknameController.text.trim();
                  _nicknameCompleted = _submittedNickname.isNotEmpty;
                });
              }
            },
            onConfirm: _nextPage,
            onBack: _previousPage,
          ),
          4 => ProfileSettingStep(
            pauseAnimation: false,
            onProfileImageUploaded: (isUploaded) {
              // 프로필은 선택사항이므로 자동으로 온보딩 완료하지 않음
            },
            onConfirm: _nextPage, // 다음 버튼 클릭 시 환영 화면으로
            onBack: _previousPage,
          ),
          5 => MilitaryWelcomeStep(
            branch: _branch, // ✅ 선택한 군종 전달
            onConfirm: () async {
              // 시작하기 버튼 클릭 시 온보딩 완료
              await _completeOnboarding();
            },
            onBack: _previousPage,
          ),
          _ => const SizedBox.shrink(),
        };
      } else {
        // 군인: 역할(0) → 군종(1) → 입대일(2) → 별명(3) → 프로필(4)
        return switch (index) {
          1 => MilitaryBranchStep(
            initialBranch: _branch,
            onBranchSelected: (branch) {
              if (mounted) {
                setState(() {
                  _branch = branch;
                });
              }
            },
            onConfirm: _nextPage,
            onBack: _previousPage,
          ),
          2 => MilitaryDateStep(
            status: MilitaryStatus.afterEnlistment,
            initialDate: _enlistmentDate,
            onDateSelected: (date) {
              if (mounted) {
                setState(() {
                  _enlistmentDate = date;
                  // 서버에서 계급을 관리하므로 클라이언트에서 계산하지 않음
                  // _currentRank는 사용자가 직접 선택하거나 서버에서 받은 값을 사용
                });
              }
            },
            onConfirm: _nextPage,
            onBack: _previousPage,
          ),
          3 => NicknameSettingStep(
            nicknameController: _nicknameController,
            userType: _userType,
            onNicknameSubmitted: () {
              // 로컬 상태만 업데이트 (API 호출 없음)
              if (mounted) {
                setState(() {
                  _submittedNickname = _nicknameController.text.trim();
                  _nicknameCompleted = _submittedNickname.isNotEmpty;
                });
              }
            },
            onConfirm: _nextPage,
            onBack: _previousPage,
          ),
          4 => ProfileSettingStep(
            pauseAnimation: false,
            onProfileImageUploaded: (isUploaded) {
              // 프로필은 선택사항이므로 자동으로 온보딩 완료하지 않음
            },
            onConfirm: _nextPage, // 다음 버튼 클릭 시 환영 화면으로
            onBack: _previousPage,
          ),
          5 => MilitaryWelcomeStep(
            branch: _branch, // ✅ 선택한 군종 전달
            onConfirm: () async {
              // 시작하기 버튼 클릭 시 온보딩 완료
              await _completeOnboarding();
            },
            onBack: _previousPage,
          ),
          _ => const SizedBox.shrink(),
        };
      }
    }

    return const SizedBox.shrink();
  }

  /// 서버 에러 메시지 파싱
  String _parseServerErrorMessage(dynamic error) {
    String errorMessage = '정보 저장 중 오류가 발생했습니다.';

    if (error is DioException) {
      // 서버에서 반환한 에러 메시지 추출
      final responseData = error.response?.data;
      if (responseData != null) {
        if (responseData is String) {
          errorMessage = responseData;
        } else if (responseData is Map<String, dynamic>) {
          errorMessage =
              responseData['message']?.toString() ??
              responseData['error']?.toString() ??
              errorMessage;
        }
      }
    } else if (error.toString().contains('입대 후인 경우 현재 계급이 필요합니다')) {
      errorMessage = '입대 후인 경우 현재 계급이 필요합니다.';
    }

    return errorMessage;
  }

  Future<void> _completeOnboarding() async {
    // 🎯 서버에서 계급을 관리하므로 클라이언트에서 계산하지 않음
    // 사용자가 선택한 계급을 그대로 사용하거나, 서버에서 계산된 값을 받아서 사용

    // ✅ 필수값 검증 (assert로 앱이 죽지 않도록, 여기서 UX로 처리)
    if (_userType == null) {
      if (mounted) ErrorHandler.showError(context, '유저 타입을 선택해주세요.');
      return;
    }

    // 군인: 입대일만 필수 (계급은 서버에서 입대일로 자동 계산)
    if (_userType == UserType.military) {
      if (_enlistmentDate == null) {
        if (mounted) {
          ErrorHandler.showError(context, '입대일을 입력해주세요.');
        }
        return;
      }
    }

    // 입대예정: 예정 입대일 필수
    if (_userType == UserType.plannedEnlistment) {
      if (_plannedEnlistmentDate == null) {
        if (mounted) {
          ErrorHandler.showError(context, '예정 입대일을 입력해주세요.');
        }
        return;
      }
    }

    // 곰신: 연결된 군인 1명 필수
    if (_userType == UserType.girlfriend) {
      if (_connectedMilitaryUserIds.length != 1) {
        if (mounted) {
          ErrorHandler.showError(context, '연결할 군인 1명을 선택해주세요.');
        }
        return;
      }
    }

    // 🎯 MilitaryInfo 생성
    late final MilitaryInfo militaryInfo;
    try {
      militaryInfo = MilitaryInfo(
        userType: _userType!,
        branch: _branch ?? MilitaryBranch.army,
        status:
            _userType == UserType.plannedEnlistment
                ? MilitaryStatus.beforeEnlistment
                : (_userType == UserType.military
                    ? MilitaryStatus.afterEnlistment
                    : MilitaryStatus.afterEnlistment), // 곰신은 입대 후
        enlistmentDate: _enlistmentDate,
        currentRank: _currentRank, // 서버에서 계산하거나 사용자가 입력한 값 사용
        plannedEnlistmentDate: _plannedEnlistmentDate,
        connectedMilitaryUserIds:
            _connectedMilitaryUserIds.isNotEmpty
                ? _connectedMilitaryUserIds
                : null,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [OnboardingFlow] MilitaryInfo 생성 실패: $e');
      debugPrint('❌ [OnboardingFlow] Stack trace: $stackTrace');
      if (mounted) {
        ErrorHandler.showError(context, '군인 정보가 올바르지 않습니다. 입력값을 확인해주세요.');
      }
      return;
    }

    try {
      final userProvider = context.read<UserProvider>();

      // 🎯 프로필 업데이트 (militaryInfo 포함) - 먼저 저장
      // rethrow=true로 설정하여 exception을 받아서 에러 메시지 파싱
      try {
        final success = await userProvider.updateProfileInfo(
          alias: _submittedNickname.isNotEmpty ? _submittedNickname : '',
          militaryInfo: militaryInfo,
          shouldRethrow: true, // exception을 다시 던져서 에러 메시지 파싱
        );

        if (!success) {
          if (mounted) {
            ErrorHandler.showError(context, '정보 저장에 실패했습니다. 다시 시도해주세요.');
          }
          return;
        }
      } catch (e) {
        // 서버 에러 메시지 파싱
        final errorMessage = _parseServerErrorMessage(e);
        if (mounted) {
          ErrorHandler.showError(context, errorMessage);
        }
        return;
      }

      // 🎯 militaryInfo가 실제로 저장되었는지 확인
      // 서버에서 최신 정보를 다시 가져와서 확인
      await userProvider.fetchUserBundle();
      final savedUser = userProvider.currentUser;
      final savedMilitaryInfo = savedUser?.militaryInfo;

      if (savedMilitaryInfo == null) {
        debugPrint(
          '[OnboardingFlow] ⚠️ militaryInfo 저장 실패 - onboardingCompleted를 false로 설정하고 온보딩 플로우 유지',
        );

        // 🎯 militaryInfo 저장 실패 시 onboardingCompleted를 false로 설정
        try {
          await UserService().updateOnboardingCompleted(
            onboardingCompleted: false,
          );
          debugPrint('[OnboardingFlow] ✅ onboardingCompleted를 false로 설정 완료');
        } catch (e) {
          debugPrint('[OnboardingFlow] ⚠️ onboardingCompleted 수정 실패: $e');
        }

        if (mounted) {
          ErrorHandler.showError(context, '군인 정보 저장에 실패했습니다. 다시 시도해주세요.');
          // 🎯 온보딩 플로우에 머물러서 사용자가 다시 시도할 수 있도록 함
          // (현재 화면에 머물러 있으므로 자동으로 온보딩 플로우 유지)
        }
        return;
      }

      debugPrint(
        '[OnboardingFlow] ✅ militaryInfo 저장 확인: userType=${savedMilitaryInfo.userType}',
      );

      // 🎯 militaryInfo가 저장되었을 때만 온보딩 완료 플래그 설정
      if (mounted) {
        await UserService().updateOnboardingCompleted(
          onboardingCompleted: true,
        );

        // 🎯 홈 화면으로 이동
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      }
    } catch (e) {
      debugPrint('[OnboardingFlow] 완료 실패: $e');
      if (mounted) {
        // 서버 에러 메시지 파싱
        String errorMessage = _parseServerErrorMessage(e);
        ErrorHandler.showError(context, errorMessage);
      }
    }
  }

  /// 곰신 모드 전용 온보딩 완료 (스플래시를 거쳐 홈으로 이동)
  Future<void> _completeOnboardingForGirlfriend() async {
    try {
      // 🎯 MilitaryInfo 생성 (곰신 모드: branch와 status는 기본값 사용)
      final militaryInfo = MilitaryInfo(
        userType: _userType!,
        branch: MilitaryBranch.army, // ✅ 곰신은 기본값 사용
        status: MilitaryStatus.afterEnlistment, // ✅ 곰신은 기본값 사용
        enlistmentDate: null,
        currentRank: null,
        plannedEnlistmentDate: null,
        connectedMilitaryUserIds:
            _connectedMilitaryUserIds.isNotEmpty
                ? _connectedMilitaryUserIds
                : null,
      );

      final userProvider = context.read<UserProvider>();

      // 🎯 프로필 업데이트 (militaryInfo 포함) - 먼저 저장
      // shouldRethrow=true로 설정하여 exception을 받아서 에러 메시지 파싱
      try {
        final success = await userProvider.updateProfileInfo(
          alias: _submittedNickname.isNotEmpty ? _submittedNickname : '',
          militaryInfo: militaryInfo,
          shouldRethrow: true, // exception을 다시 던져서 에러 메시지 파싱
        );

        if (!success) {
          debugPrint(
            '[OnboardingFlow] ⚠️ updateProfileInfo 실패 (곰신) - onboardingCompleted를 false로 설정하고 온보딩 플로우 유지',
          );

          // 🎯 프로필 업데이트 실패 시 onboardingCompleted를 false로 설정
          try {
            await UserService().updateOnboardingCompleted(
              onboardingCompleted: false,
            );
            debugPrint(
              '[OnboardingFlow] ✅ onboardingCompleted를 false로 설정 완료 (곰신)',
            );
          } catch (e) {
            debugPrint(
              '[OnboardingFlow] ⚠️ onboardingCompleted 수정 실패 (곰신): $e',
            );
          }

          if (mounted) {
            _girlfriendLoadingNotifier.value = false; // ✅ 실패 시 로딩 해제
            ErrorHandler.showError(context, '정보 저장에 실패했습니다. 다시 시도해주세요.');
            // 🎯 온보딩 플로우에 머물러서 사용자가 다시 시도할 수 있도록 함
          }
          return;
        }
      } catch (e) {
        // 서버 에러 메시지 파싱
        final errorMessage = _parseServerErrorMessage(e);
        if (mounted) {
          _girlfriendLoadingNotifier.value = false; // ✅ 실패 시 로딩 해제
          ErrorHandler.showError(context, errorMessage);
        }
        return;
      }

      // 🎯 militaryInfo가 실제로 저장되었는지 확인
      // 서버에서 최신 정보를 다시 가져와서 확인
      await userProvider.fetchUserBundle();
      final savedUser = userProvider.currentUser;
      final savedMilitaryInfo = savedUser?.militaryInfo;

      if (savedMilitaryInfo == null) {
        debugPrint(
          '[OnboardingFlow] ⚠️ militaryInfo 저장 실패 (곰신) - onboardingCompleted를 false로 설정하고 온보딩 플로우 유지',
        );

        // 🎯 militaryInfo 저장 실패 시 onboardingCompleted를 false로 설정
        try {
          await UserService().updateOnboardingCompleted(
            onboardingCompleted: false,
          );
          debugPrint(
            '[OnboardingFlow] ✅ onboardingCompleted를 false로 설정 완료 (곰신)',
          );
        } catch (e) {
          debugPrint('[OnboardingFlow] ⚠️ onboardingCompleted 수정 실패 (곰신): $e');
        }

        if (mounted) {
          _girlfriendLoadingNotifier.value = false; // ✅ 실패 시 로딩 해제
          ErrorHandler.showError(context, '군인 정보 저장에 실패했습니다. 다시 시도해주세요.');
          // 🎯 온보딩 플로우에 머물러서 사용자가 다시 시도할 수 있도록 함
          // (현재 화면에 머물러 있으므로 자동으로 온보딩 플로우 유지)
        }
        return;
      }

      debugPrint(
        '[OnboardingFlow] ✅ militaryInfo 저장 확인 (곰신): userType=${savedMilitaryInfo.userType}',
      );

      // 🎯 곰신 요청 보내기 (연결된 군인에게)
      if (_connectedMilitaryUserIds.isNotEmpty) {
        final targetUsername = _connectedMilitaryUserIds.first;
        try {
          await userProvider.sendGirlfriendRequest(targetUsername);
          debugPrint(
            '[OnboardingFlow] ✅ 곰신 요청 보내기 완료: targetUsername=$targetUsername',
          );
        } catch (e) {
          debugPrint('[OnboardingFlow] ⚠️ 곰신 요청 보내기 실패: $e (온보딩은 계속 진행)');
          // 곰신 요청 보내기 실패해도 온보딩은 완료 처리 (나중에 다시 시도 가능)
        }
      }

      // 🎯 militaryInfo가 저장되었을 때만 온보딩 완료 플래그 설정
      if (mounted) {
        await UserService().updateOnboardingCompleted(
          onboardingCompleted: true,
        );

        // 🎯 스플래시 화면으로 이동 (스플래시가 홈으로 자동 이동)
        // 로딩 상태는 스플래시로 이동할 때까지 유지
        if (mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/splash', (route) => false);
          // ✅ 스플래시로 이동 후 로딩 해제 (스플래시가 홈으로 이동할 때까지 유지)
          Future.delayed(const Duration(milliseconds: 500), () {
            _girlfriendLoadingNotifier.value = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[OnboardingFlow] 곰신 모드 완료 실패: $e');
      if (mounted) {
        _girlfriendLoadingNotifier.value = false; // ✅ 에러 시 로딩 해제
        // 서버 에러 메시지 파싱
        final errorMessage = _parseServerErrorMessage(e);
        ErrorHandler.showError(context, errorMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: PageView.builder(
        // key 제거: itemCount 변경 시에도 위젯이 재생성되지 않도록
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // 스와이프 비활성화
        itemCount: _totalSteps,
        onPageChanged: (index) {
          if (mounted) {
            setState(() {
              _currentPage = index;
            });
          }
        },
        itemBuilder: (context, index) {
          // 인덱스 범위 체크
          if (index >= _totalSteps) {
            return const SizedBox.shrink();
          }
          return _buildPage(index);
        },
      ),
    );
  }
}
