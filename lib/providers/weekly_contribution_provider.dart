import 'dart:async';
import 'package:doppy/data/models/weekly_contribution.dart';
import 'package:doppy/data/models/weekly_contribution_greeting.dart';
import 'package:flutter/foundation.dart';
import 'package:doppy/data/services/user_service.dart';
import 'package:doppy/pages/components/weekly_contribution_grid.dart';

/// 주차 기여도 프로바이더
class WeeklyContributionProvider extends ChangeNotifier {
  final UserService _userService = UserService();

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

  // 연도 선택 관련 상태
  int? _yearPickerSelectedYear;
  List<int>? _yearPickerYears;
  Function(int)? _yearPickerOnConfirm;

  /// 특정 연도의 기여도 데이터 가져오기
  List<WeeklyContributionData>? getContributions(int year) {
    return _contributionsByYear[year];
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
    _updateLockedState(); // 0개면 locked=true로 동기화
    notifyListeners(); // 캐시 삭제는 lock 변경 여부와 무관하게 UI 갱신이 필요
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
          clearCache(year);
          await loadContributions(year);
        } catch (e) {
          debugPrint('[WeeklyContributionProvider] 백그라운드 동기화 실패 (무시): $e');
        }
      });
    } else {
      // 🔄 서버에서 다시 로드 (안전하지만 느림)
      clearCache(year);
      await loadContributions(year);
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
          clearCache(year);
          await loadContributions(year);
        } catch (e) {
          debugPrint('[WeeklyContributionProvider] 삭제 후 서버 동기화 실패 (무시): $e');
        }
      }());
    } else {
      clearCache(year);
      await loadContributions(year);
      onPostRegister?.call();
    }
  }

  /// 내부 헬퍼: isLocked 상태 업데이트 (포스트 개수 변경 시 자동 호출)
  void _updateLockedState() {
    _isLocked = _totalPostCount <= 2;
  }
}
