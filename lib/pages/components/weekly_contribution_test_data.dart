import 'dart:math' as math;
import 'package:doppy/pages/components/weekly_contribution_grid.dart';
import 'package:doppy/utils/week_utils.dart';

/// 주차별 기여도 그리드 테스트 데이터 생성 유틸리티
/// 모든 주차 데이터를 JSON에 명시적으로 포함 (빈 셀은 {}로 간결하게)
class WeeklyContributionTestData {
  WeeklyContributionTestData._();

  /// JSON 데이터를 WeeklyContributionData 리스트로 변환
  /// 모든 주차 데이터를 JSON에 명시적으로 포함 (빈 셀은 {}로 간결하게)
  static List<WeeklyContributionData> _parseJsonData(
    int year,
    List<Map<String, dynamic>> jsonWeeks,
  ) {
    final contributions = <WeeklyContributionData>[];

    // JSON에서 모든 주차 데이터 파싱 (빈 셀은 {}로 표현)
    for (final week in jsonWeeks) {
      final weekNum = week['weekNumber'] as int;
      final postCount = week['postCount'] as int? ?? 0;
      contributions.add(
        WeeklyContributionData(
          year: year,
          weekNumber: weekNum,
          hasPost: postCount > 0,
          postCount: postCount,
        ),
      );
    }

    return contributions;
  }

  /// 테스트 케이스 1: 가입일 연도 초반 (1월 1일)
  static ({
    DateTime signupAt,
    DateTime asOf,
    List<WeeklyContributionData> contributions,
    int year,
  })
  generateTestCase1() {
    final year = WeekUtils.getCurrentYear();
    final signupAt = DateTime(year, 1, 1);
    final asOf = DateTime(year, 1, 16);
    final signupWeek = WeekUtils.getWeekNumber(signupAt);
    final todayWeek = WeekUtils.getWeekNumber(asOf);
    final totalWeeks = WeekUtils.getWeeksInYear(year);

    // 모든 주차 데이터 명시 (빈 셀은 {}로 간결하게)
    final jsonData = <Map<String, dynamic>>[];
    for (int week = 1; week <= totalWeeks; week++) {
      // 오늘 주차 이후는 포스트 없음
      if (week > todayWeek) {
        jsonData.add({'weekNumber': week}); // 빈 셀
        continue;
      }
      if (week == signupWeek + 5) {
        jsonData.add({'weekNumber': week, 'postCount': 3});
      } else if (week == signupWeek + 10) {
        jsonData.add({'weekNumber': week, 'postCount': 5});
      } else if (week == signupWeek + 15) {
        jsonData.add({'weekNumber': week, 'postCount': 2});
      } else {
        jsonData.add({'weekNumber': week}); // 빈 셀
      }
    }

    return (
      signupAt: signupAt,
      asOf: asOf,
      contributions: _parseJsonData(year, jsonData),
      year: year,
    );
  }

  /// 테스트 케이스 2: 가입일 연도 중반 (18번째 주)
  static ({
    DateTime signupAt,
    DateTime asOf,
    List<WeeklyContributionData> contributions,
    int year,
  })
  generateTestCase2() {
    final year = WeekUtils.getCurrentYear();
    // 18번째 주의 시작일(월요일)을 가입일로 설정
    final signupAt = WeekUtils.getWeekStartDate(year, 17);
    final asOf = WeekUtils.getWeekEndDate(year, 17);
    final signupWeek = 17; // 직접 18주차로 설정
    final todayWeek = WeekUtils.getWeekNumber(asOf);
    final totalWeeks = WeekUtils.getWeeksInYear(year);

    final jsonData = <Map<String, dynamic>>[];
    for (int week = 1; week <= totalWeeks; week++) {
      // 오늘 주차 이후는 포스트 없음
      if (week > todayWeek) {
        jsonData.add({'weekNumber': week}); // 빈 셀
        continue;
      }
      if (week == signupWeek) {
        jsonData.add({'weekNumber': week, 'postCount': 2});
      } else if (week == signupWeek + 3) {
        jsonData.add({'weekNumber': week, 'postCount': 5});
      } else if (week == signupWeek + 7) {
        jsonData.add({'weekNumber': week, 'postCount': 8});
      } else if (week == signupWeek + 12) {
        jsonData.add({'weekNumber': week, 'postCount': 3});
      } else if (week == signupWeek + 20) {
        jsonData.add({'weekNumber': week, 'postCount': 1});
      } else {
        jsonData.add({'weekNumber': week}); // 빈 셀
      }
    }

    return (
      signupAt: signupAt,
      asOf: asOf,
      contributions: _parseJsonData(year, jsonData),
      year: year,
    );
  }

  /// 테스트 케이스 3: 가입일 연도 말 (11월 1일)
  static ({
    DateTime signupAt,
    DateTime asOf,
    List<WeeklyContributionData> contributions,
    int year,
  })
  generateTestCase3() {
    final year = WeekUtils.getCurrentYear();
    final signupAt = DateTime(year, 11, 1);
    final asOf = DateTime(year, 12, 20);
    final signupWeek = WeekUtils.getWeekNumber(signupAt);
    final todayWeek = WeekUtils.getWeekNumber(asOf);
    final totalWeeks = WeekUtils.getWeeksInYear(year);

    final jsonData = <Map<String, dynamic>>[];
    for (int week = 1; week <= totalWeeks; week++) {
      // 오늘 주차 이후는 포스트 없음
      if (week > todayWeek) {
        jsonData.add({'weekNumber': week}); // 빈 셀
        continue;
      }
      if (week == signupWeek) {
        jsonData.add({'weekNumber': week, 'postCount': 1});
      } else if (week == signupWeek + 2) {
        jsonData.add({'weekNumber': week, 'postCount': 4});
      } else if (week == signupWeek + 5) {
        jsonData.add({'weekNumber': week, 'postCount': 2});
      } else {
        jsonData.add({'weekNumber': week}); // 빈 셀
      }
    }

    return (
      signupAt: signupAt,
      asOf: asOf,
      contributions: _parseJsonData(year, jsonData),
      year: year,
    );
  }

  /// 테스트 케이스 4: 포스트 많은 주차들
  static ({
    DateTime signupAt,
    DateTime asOf,
    List<WeeklyContributionData> contributions,
    int year,
  })
  generateTestCase4() {
    final year = WeekUtils.getCurrentYear();
    final signupAt = DateTime(year, 3, 15);
    final asOf = DateTime(year, 10, 10);
    final signupWeek = WeekUtils.getWeekNumber(signupAt);
    final todayWeek = WeekUtils.getWeekNumber(asOf);
    final totalWeeks = WeekUtils.getWeeksInYear(year);

    final jsonData = <Map<String, dynamic>>[];
    for (int week = 1; week <= totalWeeks; week++) {
      // 오늘 주차 이후는 포스트 없음
      if (week > todayWeek) {
        jsonData.add({'weekNumber': week}); // 빈 셀
        continue;
      }
      if (week >= signupWeek && week <= signupWeek + 10) {
        // 연속된 주차에 많은 포스트
        final postCount =
            (week - signupWeek) % 3 == 0
                ? 10
                : ((week - signupWeek) % 3 == 1 ? 7 : 5);
        jsonData.add({'weekNumber': week, 'postCount': postCount});
      } else if (week == signupWeek + 15) {
        jsonData.add({'weekNumber': week, 'postCount': 15});
      } else {
        jsonData.add({'weekNumber': week}); // 빈 셀
      }
    }

    return (
      signupAt: signupAt,
      asOf: asOf,
      contributions: _parseJsonData(year, jsonData),
      year: year,
    );
  }

  /// 테스트 케이스 5: 포스트 적은 주차들
  static ({
    DateTime signupAt,
    DateTime asOf,
    List<WeeklyContributionData> contributions,
    int year,
  })
  generateTestCase5() {
    final year = WeekUtils.getCurrentYear();
    final signupAt = DateTime(year, 6, 1);
    final asOf = DateTime(year, 9, 1);
    final signupWeek = WeekUtils.getWeekNumber(signupAt);
    final todayWeek = WeekUtils.getWeekNumber(asOf);
    final totalWeeks = WeekUtils.getWeeksInYear(year);

    final jsonData = <Map<String, dynamic>>[];
    for (int week = 1; week <= totalWeeks; week++) {
      // 오늘 주차 이후는 포스트 없음
      if (week > todayWeek) {
        jsonData.add({'weekNumber': week}); // 빈 셀
        continue;
      }
      if (week == signupWeek + 5) {
        jsonData.add({'weekNumber': week, 'postCount': 1});
      } else if (week == signupWeek + 12) {
        jsonData.add({'weekNumber': week, 'postCount': 1});
      } else if (week == signupWeek + 20) {
        jsonData.add({'weekNumber': week, 'postCount': 1});
      } else {
        jsonData.add({'weekNumber': week}); // 빈 셀
      }
    }

    return (
      signupAt: signupAt,
      asOf: asOf,
      contributions: _parseJsonData(year, jsonData),
      year: year,
    );
  }

  /// 테스트 케이스 6: 빈 셀 그라데이션 테스트 (활동 주차가 멀리 떨어져 있음)
  static ({
    DateTime signupAt,
    DateTime asOf,
    List<WeeklyContributionData> contributions,
    int year,
  })
  generateTestCase6() {
    final year = WeekUtils.getCurrentYear();
    final signupAt = DateTime(year, 4, 1);
    final asOf = DateTime(year, 12, 10);
    final signupWeek = WeekUtils.getWeekNumber(signupAt);
    final todayWeek = WeekUtils.getWeekNumber(asOf);
    final totalWeeks = WeekUtils.getWeeksInYear(year);

    final jsonData = <Map<String, dynamic>>[];
    for (int week = 1; week <= totalWeeks; week++) {
      // 오늘 주차 이후는 포스트 없음
      if (week > todayWeek) {
        jsonData.add({'weekNumber': week}); // 빈 셀
        continue;
      }
      if (week == signupWeek + 2) {
        jsonData.add({'weekNumber': week, 'postCount': 5});
      } else if (week == signupWeek + 25) {
        jsonData.add({'weekNumber': week, 'postCount': 8});
      } else if (week == signupWeek + 40) {
        jsonData.add({'weekNumber': week, 'postCount': 3});
      } else {
        jsonData.add({'weekNumber': week}); // 빈 셀
      }
    }

    return (
      signupAt: signupAt,
      asOf: asOf,
      contributions: _parseJsonData(year, jsonData),
      year: year,
    );
  }

  /// 테스트 케이스 7: 최소 2행 보장 (가입일이 연말에 가까움)
  static ({
    DateTime signupAt,
    DateTime asOf,
    List<WeeklyContributionData> contributions,
    int year,
  })
  generateTestCase7() {
    final year = WeekUtils.getCurrentYear();
    final signupAt = DateTime(year, 12, 20);
    final asOf = DateTime(year, 12, 28);
    final signupWeek = WeekUtils.getWeekNumber(signupAt);
    final todayWeek = WeekUtils.getWeekNumber(asOf);
    final totalWeeks = WeekUtils.getWeeksInYear(year);

    final jsonData = <Map<String, dynamic>>[];
    for (int week = 1; week <= totalWeeks; week++) {
      // 오늘 주차 이후는 포스트 없음
      if (week > todayWeek) {
        jsonData.add({'weekNumber': week}); // 빈 셀
        continue;
      }
      if (week == signupWeek) {
        jsonData.add({'weekNumber': week, 'postCount': 2});
      } else if (week == signupWeek + 1) {
        jsonData.add({'weekNumber': week, 'postCount': 1});
      } else {
        jsonData.add({'weekNumber': week}); // 빈 셀
      }
    }

    return (
      signupAt: signupAt,
      asOf: asOf,
      contributions: _parseJsonData(year, jsonData),
      year: year,
    );
  }

  /// 테스트 케이스 8: 오늘 주차 + 미리보기 1행
  static ({
    DateTime signupAt,
    DateTime asOf,
    List<WeeklyContributionData> contributions,
    int year,
  })
  generateTestCase8() {
    final year = WeekUtils.getCurrentYear();
    final signupAt = DateTime(year, 2, 1);
    final asOf = DateTime(year, 5, 20);
    final signupWeek = WeekUtils.getWeekNumber(signupAt);
    final todayWeek = WeekUtils.getWeekNumber(asOf);
    final totalWeeks = WeekUtils.getWeeksInYear(year);

    final jsonData = <Map<String, dynamic>>[];
    for (int week = 1; week <= totalWeeks; week++) {
      if (week >= signupWeek && week <= todayWeek) {
        // 가입 주부터 오늘 주까지 포스트 분산
        if (week == todayWeek) {
          // 오늘 주는 특히 많게
          jsonData.add({'weekNumber': week, 'postCount': 10});
        } else if (week % 4 == 0) {
          jsonData.add({'weekNumber': week, 'postCount': 3});
        } else if (week % 4 == 1) {
          jsonData.add({'weekNumber': week, 'postCount': 6});
        } else if (week % 4 == 2) {
          jsonData.add({'weekNumber': week, 'postCount': 2});
        } else {
          jsonData.add({'weekNumber': week}); // 빈 셀
        }
      } else {
        jsonData.add({'weekNumber': week}); // 빈 셀
      }
    }

    return (
      signupAt: signupAt,
      asOf: asOf,
      contributions: _parseJsonData(year, jsonData),
      year: year,
    );
  }

  /// 테스트 케이스 9: 연말(asOf가 연말) - 최소 45개 셀
  static ({
    DateTime signupAt,
    DateTime asOf,
    List<WeeklyContributionData> contributions,
    int year,
  })
  generateTestCase9() {
    final year = WeekUtils.getCurrentYear();
    final signupAt = DateTime(year, 1, 1); // 가입은 연초로 두고
    final asOf = DateTime(year, 12, 20); // 기준일을 연말로 둬서 셀을 많이 보이게
    final signupWeek = WeekUtils.getWeekNumber(signupAt);
    final todayWeek = WeekUtils.getWeekNumber(asOf);
    final totalWeeks = WeekUtils.getWeeksInYear(year);

    final jsonData = <Map<String, dynamic>>[];
    for (int week = 1; week <= totalWeeks; week++) {
      // 오늘 주차 이후는 포스트 없음
      if (week > todayWeek) {
        jsonData.add({'weekNumber': week}); // 빈 셀
        continue;
      }
      if (week >= signupWeek && week <= todayWeek) {
        // 가입 주부터 오늘 주까지 포스트 분산 (최소 45개 셀 = 약 6-7행)
        if ((week - signupWeek) % 3 == 0) {
          jsonData.add({'weekNumber': week, 'postCount': 4});
        } else if ((week - signupWeek) % 3 == 1) {
          jsonData.add({'weekNumber': week, 'postCount': 6});
        } else {
          jsonData.add({'weekNumber': week, 'postCount': 3});
        }
      } else {
        jsonData.add({'weekNumber': week}); // 빈 셀
      }
    }

    return (
      signupAt: signupAt,
      asOf: asOf,
      contributions: _parseJsonData(year, jsonData),
      year: year,
    );
  }

  /// 테스트 케이스 10: 연중반(asOf가 중반) - 최소 30개 셀
  static ({
    DateTime signupAt,
    DateTime asOf,
    List<WeeklyContributionData> contributions,
    int year,
  })
  generateTestCase10() {
    final year = WeekUtils.getCurrentYear();
    final signupAt = DateTime(year, 1, 1);
    final asOf = DateTime(year, 7, 15); // 연중반 기준일
    final signupWeek = WeekUtils.getWeekNumber(signupAt);
    final todayWeek = WeekUtils.getWeekNumber(asOf);
    final totalWeeks = WeekUtils.getWeeksInYear(year);

    final jsonData = <Map<String, dynamic>>[];
    final endWeek = math.min(todayWeek, totalWeeks);
    for (int week = 1; week <= totalWeeks; week++) {
      if (week >= signupWeek && week <= endWeek) {
        // 가입 주부터 오늘 주까지 포스트 분산 (최소 30개 셀 = 약 4-5행)
        if ((week - signupWeek) % 4 == 0) {
          jsonData.add({'weekNumber': week, 'postCount': 5});
        } else if ((week - signupWeek) % 4 == 1) {
          jsonData.add({'weekNumber': week, 'postCount': 7});
        } else if ((week - signupWeek) % 4 == 2) {
          jsonData.add({'weekNumber': week, 'postCount': 3});
        } else {
          jsonData.add({'weekNumber': week, 'postCount': 4});
        }
      } else {
        jsonData.add({'weekNumber': week}); // 빈 셀
      }
    }

    return (
      signupAt: signupAt,
      asOf: asOf,
      contributions: _parseJsonData(year, jsonData),
      year: year,
    );
  }
}
