import 'dart:async';
import 'package:doppy/data/models/weekly_contribution.dart';
import 'package:doppy/data/models/weekly_contribution_greeting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show GlobalKey, Color;
import 'package:doppy/utils/week_utils.dart';
import 'package:doppy/data/services/user_service.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/pages/components/weekly_contribution_grid.dart';

/// 주차 기여도 프로바이더
class WeeklyContributionProvider extends ChangeNotifier {
  final UserService _userService = UserService();

  // ✅ 계정 변경 감지를 위한 현재 사용자명 추적
  String? _currentUsername;

  // 연도별 기여도 데이터 캐싱
  final Map<int, List<WeeklyContributionData>> _contributionsByYear = {};

  // 연도별 greeting 데이터 캐싱
  final Map<int, WeeklyContributionGreeting?> _greetingsByYear = {};

  // 연도별 주차별 프리뷰 데이터 캐싱 (year -> weekNumber -> {title, thumbnailUrl})
  final Map<int, Map<int, Map<String, String?>>> _previewByYearAndWeek = {};

  // 로딩 상태 (연도별)
  final Map<int, bool> _loadingByYear = {};

  // 포스트 발행 시 호출될 콜백
  VoidCallback? onPostRegister;

  // 전체 포스트 개수 (서버에서 받은 값, 초기 로드 시 설정)
  int _totalPostCount = 0;

  // isLocked 상태 (post <= 2개면 true, 그렇지 않으면 false)
  bool _isLocked = false;

  // 블러 레이어 표시 여부 (연도 선택 시 사용)
  bool _showBlurOverlay = false;

  // ==============================
  // ✅ 코치마크 오버레이 (그리드 셀 타겟)
  // ==============================

  bool _showCoachmark = false;
  int _coachmarkStepIndex = 0;
  List<WeeklyCoachmarkStep> _coachmarkSteps = const [];
  bool _wasDismissedByUser = false; // ✅ 사용자가 명시적으로 닫았는지 추적

  // year -> weekNumber -> GlobalKey
  final Map<int, Map<int, GlobalKey>> _weekCellKeys = {};

  // 연도 선택 관련 상태
  int? _yearPickerSelectedYear;
  List<int>? _yearPickerYears;
  Function(int)? _yearPickerOnConfirm;

  /// 특정 연도의 기여도 데이터 가져오기
  List<WeeklyContributionData>? getContributions(int year) {
    // ✅ 계정 변경 감지 및 캐시 초기화
    _checkAndClearCacheIfUserChanged();
    return _contributionsByYear[year];
  }

  /// ✅ 계정 변경 감지 및 캐시 초기화 (보수적 캐싱)
  void _checkAndClearCacheIfUserChanged() {
    final currentUsername = AuthService().currentUsernameSync;
    if (_currentUsername != null &&
        currentUsername != null &&
        _currentUsername != currentUsername) {
      // 계정이 변경되었으면 모든 캐시 초기화
      debugPrint(
        '[WeeklyContributionProvider] 계정 변경 감지: $_currentUsername -> $currentUsername, 캐시 초기화',
      );
      clearAllCache();
      _weekCellKeys.clear();
      _wasDismissedByUser = false; // 코치마크도 리셋
    }
    _currentUsername = currentUsername;
  }

  /// 특정 연도의 greeting 데이터 가져오기
  WeeklyContributionGreeting? getGreeting(int year) {
    return _greetingsByYear[year];
  }

  /// 특정 연도/주차의 첫 번째 포스트 title과 thumbnailUrl만 가져오기 (프리뷰용, API 호출 없음)
  Map<String, String?>? getWeekPostPreview(int year, int weekNumber) {
    return _previewByYearAndWeek[year]?[weekNumber];
  }

  /// 특정 연도가 로딩 중인지 확인
  bool isLoading(int year) {
    return _loadingByYear[year] ?? false;
  }

  /// 전체 포스트 개수 가져오기
  int get totalPostCount => _totalPostCount;

  /// isLocked 상태 가져오기 (post <= 2개면 true, 그렇지 않으면 false)
  bool get isLocked => _isLocked;

  /// 블러 레이어 표시 여부
  bool get showBlurOverlay => _showBlurOverlay;

  /// 코치마크 모드 여부
  bool get showCoachmarkOverlay => _showCoachmark;

  /// ✅ 오버레이(연도피커/코치마크) 표시 여부 (main.dart에서 공용 딤 처리)
  bool get showAnyOverlay => _showBlurOverlay || _showCoachmark;

  WeeklyCoachmarkStep? get currentCoachmarkStep =>
      (_coachmarkSteps.isEmpty || _coachmarkStepIndex >= _coachmarkSteps.length)
          ? null
          : _coachmarkSteps[_coachmarkStepIndex];

  int get coachmarkStepIndex => _coachmarkStepIndex;
  int get coachmarkTotalSteps => _coachmarkSteps.length;

  void registerWeekCellKey(int year, int weekNumber, GlobalKey key) {
    _weekCellKeys.putIfAbsent(year, () => {})[weekNumber] = key;
  }

  GlobalKey? getWeekCellKey(int year, int weekNumber) {
    return _weekCellKeys[year]?[weekNumber];
  }

  void startCoachmark(List<WeeklyCoachmarkStep> steps) {
    _coachmarkSteps = steps;
    _coachmarkStepIndex = 0;
    _showCoachmark = true;
    notifyListeners();
  }

  void nextCoachmarkStep() {
    if (!_showCoachmark) return;
    if (_coachmarkStepIndex + 1 >= _coachmarkSteps.length) {
      closeCoachmark();
      return;
    }
    _coachmarkStepIndex++;
    notifyListeners();
  }

  void previousCoachmarkStep() {
    if (!_showCoachmark) return;
    if (_coachmarkStepIndex <= 0) return; // 첫 번째 스텝이면 동작하지 않음
    _coachmarkStepIndex--;
    notifyListeners();
  }

  void closeCoachmark() {
    // ✅ X 버튼 클릭 시 코치마크 모드 즉시 종료
    _showCoachmark = false;
    _coachmarkStepIndex = 0;
    _coachmarkSteps = const [];
    _wasDismissedByUser = true; // ✅ 사용자가 명시적으로 닫았음을 표시
    notifyListeners();
  }

  /// 사용자가 명시적으로 닫았는지 확인
  bool get wasDismissedByUser => _wasDismissedByUser;

  Map<int, GlobalKey> getWeekCellKeysForYear(int year) {
    return Map<int, GlobalKey>.unmodifiable(_weekCellKeys[year] ?? const {});
  }

  /// ✅ 요구사항 기반: 1/2/3 단계 스텝 자동 생성 후 시작 (테스트용)
  void startWeeklyStreakCoachmark({required int year, DateTime? now}) {
    final keys = _weekCellKeys[year];
    if (keys == null || keys.isEmpty) return;
    final n = now ?? DateTime.now();
    final todayWeek = (n.year == year) ? WeekUtils.getWeekNumber(n) : null;

    // postCount 맵 구성 (키가 없는 주는 제외)
    final postCountByWeek = <int, int>{};
    final contributions = _contributionsByYear[year];
    if (contributions != null) {
      for (final c in contributions) {
        if (keys.containsKey(c.weekNumber)) {
          postCountByWeek[c.weekNumber] = c.postCount;
        }
      }
    }

    int? latestPurpleWeek;
    for (final w in keys.keys) {
      final pc = postCountByWeek[w] ?? 0;
      if (pc > 0) {
        if (latestPurpleWeek == null || w > latestPurpleWeek) {
          latestPurpleWeek = w;
        }
      }
    }

    if (latestPurpleWeek == null && keys.keys.isNotEmpty) {
      final sorted = keys.keys.toList()..sort();
      latestPurpleWeek = sorted.last;
    }
    if (latestPurpleWeek == null) return;

    // 2단계: "이번 주" (보라색 fill 셀)을 타겟으로 함
    // 오늘 이전의 "빈 셀" 최신순 (neighbors 찾기용)
    int? latestPastEmpty;
    if (todayWeek != null) {
      for (final w in keys.keys) {
        if (w >= todayWeek) continue;
        final pc = postCountByWeek[w] ?? 0;
        if (pc == 0) {
          if (latestPastEmpty == null || w > latestPastEmpty) {
            latestPastEmpty = w;
          }
        }
      }
    }
    latestPastEmpty ??= latestPurpleWeek;

    // ✅ 2단계 타겟: "이번 주" (todayWeek가 있으면 todayWeek, 없으면 latestPurpleWeek)
    final step2TargetWeek = todayWeek ?? latestPurpleWeek;

    startCoachmark([
      WeeklyCoachmarkStep(
        kind: WeeklyCoachmarkKind.intro,
        year: year,
        weekNumber: latestPurpleWeek,
        message: '한 주에 한 칸씩 채워가요\n기록이 많을수록 색이 진해져요',
        colorSubstrings: {
          '한 주에 한 칸씩 채워가요': const Color.fromARGB(255, 138, 156, 255),
        }, // ✅ 첫 줄 lightPrimary 색상으로 강조
      ),
      WeeklyCoachmarkStep(
        kind: WeeklyCoachmarkKind.pastFill,
        year: year,
        weekNumber: step2TargetWeek, // ✅ "이번 주" (보라색 fill 셀)을 타겟으로
        message: '가입 후 1주일만 자유롭게\n지나간 주의 기록을 채울 수 있어요',
        colorSubstrings: {
          '가입 후 1주일만 자유롭게': const Color.fromARGB(255, 138, 156, 255),
        }, // ✅ 첫 줄 lightPrimary 색상으로 강조
      ),
      WeeklyCoachmarkStep(
        kind: WeeklyCoachmarkKind.interaction,
        year: year,
        weekNumber: latestPurpleWeek,
        message: '눌러서 그 주의 기록을 볼 수 있어요\n길게 누르면 미리보기가 나와요',
        colorSubstrings: {
          '눌러서 그 주의 기록': const Color.fromARGB(255, 138, 156, 255),
        }, // ✅ 첫 줄 primary 색상으로 강조
      ),
    ]);
  }

  /// 블러 레이어 표시 설정
  void setBlurOverlay(bool show) {
    if (_showBlurOverlay != show) {
      _showBlurOverlay = show;
      if (!show) {
        // 블러가 닫힐 때 연도 선택 상태 초기화
        _yearPickerSelectedYear = null;
        _yearPickerYears = null;
        _yearPickerOnConfirm = null;
      }
      notifyListeners();
    }
  }

  /// 연도 선택 UI 표시
  void showYearPicker({
    required int selectedYear,
    required List<int> years,
    required Function(int) onConfirm,
  }) {
    _yearPickerSelectedYear = selectedYear;
    _yearPickerYears = years;
    _yearPickerOnConfirm = onConfirm;
    _showBlurOverlay = true;
    notifyListeners();
  }

  /// 연도 선택 UI 닫기
  void closeYearPicker() {
    _showBlurOverlay = false;
    _yearPickerSelectedYear = null;
    _yearPickerYears = null;
    _yearPickerOnConfirm = null;
    notifyListeners();
  }

  /// 연도 선택 관련 getter
  int? get yearPickerSelectedYear => _yearPickerSelectedYear;
  List<int>? get yearPickerYears => _yearPickerYears;
  Function(int)? get yearPickerOnConfirm => _yearPickerOnConfirm;

  /// 서버에서 받은 총 포스트 개수 설정 (초기 로드 시)
  void setTotalPostCount(int totalPostCount) {
    // ✅ totalPostCount가 0인 경우에도 _isLocked를 반드시 동기화해야 한다.
    // ✅ totalPostCount/lock UI가 즉시 업데이트되도록 notify까지 보장한다.
    final prevCount = _totalPostCount;
    final prevLocked = _isLocked;

    _totalPostCount = totalPostCount;
    _updateLockedState();

    if (prevCount != _totalPostCount || prevLocked != _isLocked) {
      notifyListeners();
    }
  }

  /// 포스트 개수 증가 (포스트 발행 시)
  void incrementPostCount() {
    _totalPostCount++;
    _updateLockedState();
    // 🎯 즉시 UI 업데이트를 위해 notifyListeners 호출
    notifyListeners();
  }

  /// 포스트 개수 감소 (포스트 삭제 시)
  void decrementPostCount() {
    if (_totalPostCount <= 0) return;
    _totalPostCount--;
    _updateLockedState();
    // 🎯 즉시 UI 업데이트를 위해 notifyListeners 호출
    notifyListeners();
  }

  /// 특정 연도의 기여도 데이터 로드
  Future<void> loadContributions(int year) async {
    // ✅ 계정 변경 감지 및 캐시 초기화 (보수적 캐싱)
    _checkAndClearCacheIfUserChanged();

    // 이미 로드 중이거나 캐시에 있으면 스킵
    if (_loadingByYear[year] == true ||
        _contributionsByYear.containsKey(year)) {
      return;
    }

    _loadingByYear[year] = true;
    notifyListeners();

    try {
      final response = await _userService.getWeeklyContributions(year: year);

      // 🎯 서버 응답 디버깅 (greeting 필드 확인)
      debugPrint('[WeeklyContributionProvider] 서버 응답 전체: $response');
      debugPrint(
        '[WeeklyContributionProvider] greeting 필드 존재 여부: ${response.containsKey('greeting')}',
      );
      if (response.containsKey('greeting')) {
        debugPrint(
          '[WeeklyContributionProvider] greeting 값: ${response['greeting']}',
        );
        debugPrint(
          '[WeeklyContributionProvider] greeting 타입: ${response['greeting'].runtimeType}',
        );
      } else {
        debugPrint('[WeeklyContributionProvider] ⚠️ 서버 응답에 greeting 필드가 없습니다');
      }

      final contributionResponse = WeeklyContributionResponse.fromJson(
        response,
      );

      // WeeklyContributionData로 변환
      final contributions =
          contributionResponse.weeks.map((week) {
            return WeeklyContributionData(
              year: year,
              weekNumber: week.weekNumber,
              hasPost: week.myPosts.isNotEmpty,
              postCount: week.myPosts.length,
            );
          }).toList();

      // 프리뷰 데이터 캐싱 (title과 thumbnailUrl만)
      _previewByYearAndWeek[year] = {};
      for (final week in contributionResponse.weeks) {
        if (week.myPosts.isNotEmpty) {
          final firstPost = week.myPosts.first;
          _previewByYearAndWeek[year]![week.weekNumber] = {
            'title': firstPost['title'] as String?,
            'thumbnailUrl':
                firstPost['thumbnailUrl'] as String? ??
                firstPost['thumbnailImageUrl'] as String?,
          };
        } else {
          _previewByYearAndWeek[year]![week.weekNumber] = {
            'title': null,
            'thumbnailUrl': null,
          };
        }
      }

      // 캐싱
      _contributionsByYear[year] = contributions;
      _greetingsByYear[year] = contributionResponse.greeting;

      // 🎯 서버 greeting 응답 디버깅
      if (contributionResponse.greeting != null) {
        final g = contributionResponse.greeting!;
        debugPrint(
          '[WeeklyContributionProvider] 서버 greeting 응답: tier="${g.tier}", mode="${g.mode}", timeMeta="${g.timeMeta}"',
        );
      } else {
        debugPrint('[WeeklyContributionProvider] ⚠️ 서버 greeting이 null입니다');
      }

      debugPrint(
        '[WeeklyContributionProvider] $year년 데이터 로드 완료: ${contributions.length}주차',
      );

      _loadingByYear[year] = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[WeeklyContributionProvider] $year년 데이터 로드 실패: $e');
      _loadingByYear[year] = false;
      notifyListeners();
      rethrow;
    }
  }

  /// ✅ 특정 연도의 기여도 데이터를 "기존 UI는 유지한 채" 서버와 재동기화한다.
  /// - 기존 clearCache() 방식은 잠깐 데이터가 비면서(=null/empty) UI 색/레이아웃이 깜빡일 수 있음
  /// - 홈 진입 직후/온보딩 직후처럼 리빌드가 많을 때 특히 눈에 띔
  Future<void> reloadContributions(int year) async {
    // ✅ 계정 변경 감지 및 캐시 초기화 (보수적 캐싱)
    _checkAndClearCacheIfUserChanged();

    if (_loadingByYear[year] == true) return;

    _loadingByYear[year] = true;
    notifyListeners();

    try {
      final response = await _userService.getWeeklyContributions(year: year);
      final contributionResponse = WeeklyContributionResponse.fromJson(
        response,
      );

      final contributions =
          contributionResponse.weeks.map((week) {
            return WeeklyContributionData(
              year: year,
              weekNumber: week.weekNumber,
              hasPost: week.myPosts.isNotEmpty,
              postCount: week.myPosts.length,
            );
          }).toList();

      // 프리뷰 데이터 캐싱 (title과 thumbnailUrl만)
      _previewByYearAndWeek[year] = {};
      for (final week in contributionResponse.weeks) {
        if (week.myPosts.isNotEmpty) {
          final firstPost = week.myPosts.first;
          _previewByYearAndWeek[year]![week.weekNumber] = {
            'title': firstPost['title'] as String?,
            'thumbnailUrl':
                firstPost['thumbnailUrl'] as String? ??
                firstPost['thumbnailImageUrl'] as String?,
          };
        } else {
          _previewByYearAndWeek[year]![week.weekNumber] = {
            'title': null,
            'thumbnailUrl': null,
          };
        }
      }

      // 캐싱(덮어쓰기)
      _contributionsByYear[year] = contributions;
      _greetingsByYear[year] = contributionResponse.greeting;

      debugPrint(
        '[WeeklyContributionProvider] $year년 데이터 re-load 완료: ${contributions.length}주차',
      );
    } catch (e) {
      debugPrint('[WeeklyContributionProvider] $year년 데이터 re-load 실패: $e');
      rethrow;
    } finally {
      _loadingByYear[year] = false;
      notifyListeners();
    }
  }

  /// 특정 연도의 캐시 삭제 (강제 새로고침용)
  void clearCache(int year) {
    _contributionsByYear.remove(year);
    _greetingsByYear.remove(year);
    _previewByYearAndWeek.remove(year);
    _loadingByYear.remove(year);
    notifyListeners();
  }

  /// 모든 캐시 삭제
  void clearAllCache() {
    _contributionsByYear.clear();
    _greetingsByYear.clear();
    _previewByYearAndWeek.clear();
    _loadingByYear.clear();
    _totalPostCount = 0;
    _weekCellKeys.clear(); // ✅ 셀 키도 초기화
    _wasDismissedByUser = false; // ✅ 코치마크 상태도 리셋
    _updateLockedState(); // 0개면 locked=true로 동기화
    notifyListeners(); // 캐시 삭제는 lock 변경 여부와 무관하게 UI 갱신이 필요
  }

  /// ✅ 로그아웃/계정 변경 시 명시적으로 호출 (AuthProvider에서 사용)
  void logout() {
    clearAllCache();
    _currentUsername = null; // 사용자명도 초기화
    debugPrint('[WeeklyContributionProvider] 로그아웃 - 모든 캐시 초기화됨');
  }

  /// 포스트 발행 후 해당 연도 데이터 새로고침 및 상태 업데이트
  /// [optimisticUpdate]: true면 즉시 로컬 업데이트, false면 서버에서 다시 로드
  Future<void> refreshAfterPostPublished(
    int year, {
    int? weekNumber,
    bool optimisticUpdate = true,
  }) async {
    if (optimisticUpdate && weekNumber != null) {
      // ✅ 총 포스트 개수/락 상태는 항상 즉시 반영 (연도 캐시 유무와 무관)
      // - 락 상태에서 2개 → 3개가 되는 순간 즉시 unlock UI로 전환되어야 함
      incrementPostCount();
      WeeklyContributionGreeting.invalidateCache();
      onPostRegister?.call();

      // 🚀 즉시 로컬 업데이트 (빠른 UX)
      final contributions = _contributionsByYear[year];
      if (contributions != null) {
        // 해당 주차의 포스트 개수 증가
        final weekIndex = contributions.indexWhere(
          (c) => c.weekNumber == weekNumber,
        );
        if (weekIndex != -1) {
          final updated = List<WeeklyContributionData>.from(contributions);
          final existing = updated[weekIndex];
          updated[weekIndex] = WeeklyContributionData(
            year: existing.year,
            weekNumber: existing.weekNumber,
            hasPost: true,
            postCount: existing.postCount + 1,
          );
          _contributionsByYear[year] = updated;
        }
      }

      // 🔄 백그라운드에서 서버 동기화 (greeting 업데이트 목적)
      // - 기존 loadContributions는 캐시가 있으면 스킵하므로, 발행 후에는 강제 리로드가 필요
      Future<void>(() async {
        try {
          // UI에 먼저 로컬 업데이트를 반영한 뒤 서버 동기화
          await Future.delayed(const Duration(milliseconds: 500));
          await reloadContributions(year);
        } catch (e) {
          debugPrint('[WeeklyContributionProvider] 백그라운드 동기화 실패 (무시): $e');
        }
      });
    } else {
      // 🔄 서버에서 다시 로드 (안전하지만 느림)
      await reloadContributions(year);
      onPostRegister?.call();
    }
  }

  /// 포스트 삭제 후 해당 연도 데이터 새로고침 및 상태 업데이트
  /// [optimisticUpdate]: true면 즉시 로컬 업데이트, false면 서버에서 다시 로드
  Future<void> refreshAfterPostDeleted(
    int year, {
    int? weekNumber,
    bool optimisticUpdate = true,
  }) async {
    if (optimisticUpdate && weekNumber != null) {
      // ✅ 총 포스트 개수/락 상태는 항상 즉시 반영 (연도 캐시 유무와 무관)
      // - 언락 상태에서 3개 → 2개가 되는 순간 즉시 lock UI로 전환되어야 함
      decrementPostCount();
      WeeklyContributionGreeting.invalidateCache();
      onPostRegister?.call();

      final contributions = _contributionsByYear[year];
      if (contributions != null) {
        final weekIndex = contributions.indexWhere(
          (c) => c.weekNumber == weekNumber,
        );
        if (weekIndex != -1) {
          final updated = List<WeeklyContributionData>.from(contributions);
          final existing = updated[weekIndex];
          final nextCount = (existing.postCount - 1).clamp(0, 1 << 30);
          updated[weekIndex] = WeeklyContributionData(
            year: existing.year,
            weekNumber: existing.weekNumber,
            hasPost: nextCount > 0,
            postCount: nextCount,
          );
          _contributionsByYear[year] = updated;

          // 프리뷰 데이터에서도 첫 번째 포스트 제거
          final preview = _previewByYearAndWeek[year]?[weekNumber];
          if (preview != null && nextCount == 0) {
            // 포스트가 모두 삭제된 경우
            _previewByYearAndWeek[year]![weekNumber] = {
              'title': null,
              'thumbnailUrl': null,
            };
          } else if (preview != null && nextCount > 0) {
            // 다음 포스트가 있으면 업데이트 필요 (하지만 현재는 첫 번째만 저장하므로 null로 설정)
            // 실제로는 서버에서 다시 로드해야 하지만, 여기서는 null로 설정
            _previewByYearAndWeek[year]![weekNumber] = {
              'title': null,
              'thumbnailUrl': null,
            };
          }

          // ✅ 주차별 그리드 데이터가 바뀌었으므로 1회 notify
          notifyListeners();
        }
      }

      // 🔄 서버 동기화 (스트릭, 그리팅 메시지 업데이트 목적)
      // - 기존 loadContributions는 캐시가 있으면 스킵하므로, 삭제 후에는 강제 리로드가 필요
      // - 백그라운드에서 실행하되, 완료되면 그리팅과 스트릭 정보가 업데이트됨
      unawaited(() async {
        try {
          await reloadContributions(year);
        } catch (e) {
          debugPrint('[WeeklyContributionProvider] 삭제 후 서버 동기화 실패 (무시): $e');
        }
      }());
    } else {
      await reloadContributions(year);
      onPostRegister?.call();
    }
  }

  /// 내부 헬퍼: isLocked 상태 업데이트 (포스트 개수 변경 시 자동 호출)
  void _updateLockedState() {
    _isLocked = _totalPostCount <= 2;
  }
}

enum WeeklyCoachmarkKind { intro, pastFill, interaction }

/// 코치마크 단계 모델
class WeeklyCoachmarkStep {
  final WeeklyCoachmarkKind kind;
  final int year;
  final int weekNumber;
  final String message; // ✅ title 제거, message만 사용
  final Map<String, Color>? colorSubstrings; // ✅ 색상으로 강조할 텍스트 부분들 (텍스트 -> 색상)

  const WeeklyCoachmarkStep({
    required this.kind,
    required this.year,
    required this.weekNumber,
    required this.message,
    this.colorSubstrings, // ✅ 선택적: 강조할 부분과 색상 지정
  });
}
