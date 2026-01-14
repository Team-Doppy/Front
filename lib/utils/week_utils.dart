import 'package:flutter/material.dart';

/// 주차(Week) 및 연도(Year) 관련 중앙 유틸리티
/// ISO 8601 기준으로 주차를 계산합니다.
///
/// 모든 주차/연도 관련 계산은 이 클래스를 통해서만 수행하여 일관성을 유지합니다.
class WeekUtils {
  WeekUtils._(); // private constructor (static only)

  /// ISO 8601 기준으로 날짜의 주차 번호를 계산합니다.
  ///
  /// ISO 8601 주차 규칙:
  /// - 주는 월요일에 시작하여 일요일에 끝납니다.
  /// - 연도의 첫 번째 주는 해당 연도의 첫 번째 목요일을 포함하는 주입니다.
  ///
  /// [date] - 계산할 날짜 (로컬 시간대)
  /// 반환: 주차 번호 (1-53)
  static int getWeekNumber(DateTime date) {
    // ISO 8601 주차 계산
    // 1. 해당 연도의 1월 4일을 찾습니다 (항상 첫 번째 주에 포함됨)
    final jan4 = DateTime(date.year, 1, 4);

    // 2. 1월 4일이 무슨 요일인지 계산 (1=월요일, 7=일요일)
    final jan4Weekday = jan4.weekday;

    // 3. 첫 번째 주의 시작일 계산 (1월 4일이 속한 주의 월요일)
    // jan4Weekday가 1(월)이면 -3일, 2(화)면 -4일, ..., 7(일)이면 -6일
    final daysToSubtract = jan4Weekday - 1;
    final firstWeekStart = jan4.subtract(Duration(days: daysToSubtract));

    // 4. 주어진 날짜가 속한 주의 월요일 계산
    final dateWeekday = date.weekday;
    final daysToMonday = dateWeekday - 1;
    final weekStart = date.subtract(Duration(days: daysToMonday));

    // 5. 첫 번째 주부터의 주차 수 계산
    final daysDifference = weekStart.difference(firstWeekStart).inDays;
    final weekNumber = (daysDifference ~/ 7) + 1;

    // 6. 연도 경계 처리
    // 만약 계산된 주차가 0 이하이면, 이전 연도의 마지막 주차입니다.
    if (weekNumber <= 0) {
      // 이전 연도의 마지막 주차를 직접 계산 (재귀 방지)
      final prevYear = date.year - 1;
      final prevJan4 = DateTime(prevYear, 1, 4);
      final prevJan4Weekday = prevJan4.weekday;
      final prevDaysToSubtract = prevJan4Weekday - 1;
      final prevFirstWeekStart = prevJan4.subtract(
        Duration(days: prevDaysToSubtract),
      );
      final prevDec28 = DateTime(prevYear, 12, 28);
      final prevDec28Weekday = prevDec28.weekday;
      final prevDaysToMonday = prevDec28Weekday - 1;
      final prevDec28WeekStart = prevDec28.subtract(
        Duration(days: prevDaysToMonday),
      );
      final prevDaysDifference =
          prevDec28WeekStart.difference(prevFirstWeekStart).inDays;
      return (prevDaysDifference ~/ 7) + 1;
    }

    // 7. 계산된 주차가 해당 연도의 최대 주차를 초과하면, 다음 연도의 첫 번째 주차입니다.
    // 재귀를 방지하기 위해 직접 계산
    final currentYear = date.year;
    final currentJan4 = DateTime(currentYear, 1, 4);
    final currentJan4Weekday = currentJan4.weekday;
    final currentDaysToSubtract = currentJan4Weekday - 1;
    final currentFirstWeekStart = currentJan4.subtract(
      Duration(days: currentDaysToSubtract),
    );
    final currentDec28 = DateTime(currentYear, 12, 28);
    final currentDec28Weekday = currentDec28.weekday;
    final currentDaysToMonday = currentDec28Weekday - 1;
    final currentDec28WeekStart = currentDec28.subtract(
      Duration(days: currentDaysToMonday),
    );
    final currentDaysDifference =
        currentDec28WeekStart.difference(currentFirstWeekStart).inDays;
    final maxWeeks = (currentDaysDifference ~/ 7) + 1;

    if (weekNumber > maxWeeks) {
      return 1; // 다음 연도의 첫 번째 주차
    }

    return weekNumber;
  }

  /// ISO 8601 기준으로 해당 연도의 총 주차 수를 계산합니다.
  ///
  /// ISO 8601 규칙:
  /// - 12월 28일이 포함된 주차가 해당 연도의 마지막 주차입니다.
  /// - 12월 28일의 주차 번호를 확인하면 해당 연도의 총 주차 수를 알 수 있습니다.
  ///
  /// [year] - 연도
  /// 반환: 해당 연도의 총 주차 수 (52 또는 53)
  static int getWeeksInYear(int year) {
    // 재귀를 방지하기 위해 직접 계산
    // 1. 해당 연도의 1월 4일을 찾습니다
    final jan4 = DateTime(year, 1, 4);
    final jan4Weekday = jan4.weekday;

    // 2. 첫 번째 주의 시작일 계산
    final daysToSubtract = jan4Weekday - 1;
    final firstWeekStart = jan4.subtract(Duration(days: daysToSubtract));

    // 3. 12월 28일이 속한 주의 월요일 계산
    final dec28 = DateTime(year, 12, 28);
    final dec28Weekday = dec28.weekday;
    final daysToMonday = dec28Weekday - 1;
    final dec28WeekStart = dec28.subtract(Duration(days: daysToMonday));

    // 4. 첫 번째 주부터 12월 28일 주까지의 주차 수 계산
    final daysDifference = dec28WeekStart.difference(firstWeekStart).inDays;
    final weekNumber = (daysDifference ~/ 7) + 1;

    return weekNumber;
  }

  /// 특정 연도와 주차의 시작일(월요일)을 반환합니다.
  ///
  /// [year] - 연도
  /// [weekNumber] - 주차 번호 (1부터 시작)
  /// 반환: 해당 주차의 시작일 (월요일, 로컬 시간대)
  static DateTime getWeekStartDate(int year, int weekNumber) {
    // 1. 해당 연도의 1월 4일을 찾습니다
    final jan4 = DateTime(year, 1, 4);
    final jan4Weekday = jan4.weekday;

    // 2. 첫 번째 주의 시작일 계산
    final daysToSubtract = jan4Weekday - 1;
    final firstWeekStart = jan4.subtract(Duration(days: daysToSubtract));

    // 3. 요청한 주차의 시작일 계산
    final weekStart = firstWeekStart.add(Duration(days: (weekNumber - 1) * 7));

    return weekStart;
  }

  /// 특정 연도와 주차의 종료일(일요일)을 반환합니다.
  ///
  /// [year] - 연도
  /// [weekNumber] - 주차 번호 (1부터 시작)
  /// 반환: 해당 주차의 종료일 (일요일, 로컬 시간대)
  static DateTime getWeekEndDate(int year, int weekNumber) {
    final weekStart = getWeekStartDate(year, weekNumber);
    // 일요일은 월요일로부터 6일 후
    return weekStart.add(const Duration(days: 6));
  }

  /// 특정 연도와 주차의 날짜 범위를 반환합니다.
  ///
  /// [year] - 연도
  /// [weekNumber] - 주차 번호 (1부터 시작)
  /// 반환: (시작일, 종료일) 튜플
  static ({DateTime start, DateTime end}) getWeekDateRange(
    int year,
    int weekNumber,
  ) {
    final start = getWeekStartDate(year, weekNumber);
    final end = getWeekEndDate(year, weekNumber);
    return (start: start, end: end);
  }

  /// 현재 날짜의 연도를 반환합니다.
  ///
  /// 반환: 현재 연도
  static int getCurrentYear() {
    return DateTime.now().year;
  }

  /// 현재 날짜의 주차 번호를 반환합니다.
  ///
  /// 반환: 현재 주차 번호 (1-53)
  static int getCurrentWeekNumber() {
    return getWeekNumber(DateTime.now());
  }

  /// 현재 날짜의 연도와 주차를 반환합니다.
  ///
  /// 반환: (연도, 주차) 튜플
  static ({int year, int weekNumber}) getCurrentYearAndWeek() {
    final now = DateTime.now();
    return (year: now.year, weekNumber: getWeekNumber(now));
  }

  /// 날짜가 특정 연도와 주차에 속하는지 확인합니다.
  ///
  /// [date] - 확인할 날짜
  /// [year] - 연도
  /// [weekNumber] - 주차 번호
  /// 반환: 해당 주차에 속하면 true
  static bool isDateInWeek(DateTime date, int year, int weekNumber) {
    final dateYear = date.year;
    final dateWeek = getWeekNumber(date);

    // 연도와 주차가 일치하는지 확인
    if (dateYear == year && dateWeek == weekNumber) {
      return true;
    }

    // 연도 경계 처리: 주차가 연도 경계를 넘을 수 있음
    // 예: 2025년 1월 1일이 2024년의 마지막 주차에 속할 수 있음
    final weekStart = getWeekStartDate(year, weekNumber);
    final weekEnd = getWeekEndDate(year, weekNumber);

    return date.isAfter(weekStart.subtract(const Duration(days: 1))) &&
        date.isBefore(weekEnd.add(const Duration(days: 1)));
  }

  /// UTC DateTime을 로컬 시간대로 변환한 후 주차 번호를 계산합니다.
  ///
  /// [utcDateTime] - UTC DateTime
  /// 반환: 주차 번호 (1-53)
  static int getWeekNumberFromUtc(DateTime utcDateTime) {
    final localDateTime = utcDateTime.toLocal();
    return getWeekNumber(localDateTime);
  }

  /// UTC DateTime을 로컬 시간대로 변환한 후 연도와 주차를 반환합니다.
  ///
  /// [utcDateTime] - UTC DateTime
  /// 반환: (연도, 주차) 튜플
  static ({int year, int weekNumber}) getYearAndWeekFromUtc(
    DateTime utcDateTime,
  ) {
    final localDateTime = utcDateTime.toLocal();
    return (year: localDateTime.year, weekNumber: getWeekNumber(localDateTime));
  }

  /// UTC 시간 문자열(ISO 8601)을 파싱하여 연도와 주차를 반환합니다.
  ///
  /// [utcString] - UTC 시간 문자열 (예: "2024-01-01T12:00:00Z")
  /// 반환: (연도, 주차) 튜플 또는 null (파싱 실패 시)
  static ({int year, int weekNumber})? getYearAndWeekFromUtcString(
    String utcString,
  ) {
    try {
      final dateTime = DateTime.parse(utcString);
      return getYearAndWeekFromUtc(dateTime);
    } catch (e) {
      debugPrint('[WeekUtils] UTC 문자열 파싱 실패: $utcString, 에러: $e');
      return null;
    }
  }

  /// 포스트 발행 시 사용할 현재 연도와 주차를 반환합니다.
  ///
  /// 이 메서드는 포스트 발행 시 서버로 전송할 year와 nthWeek 값을 제공합니다.
  ///
  /// 반환: (year, nthWeek) 튜플
  static ({int year, int nthWeek}) getCurrentYearAndWeekForPublish() {
    final now = DateTime.now();
    final year = now.year;
    final weekNumber = getWeekNumber(now);
    return (year: year, nthWeek: weekNumber);
  }

  /// 특정 UTC DateTime에 대한 연도와 주차를 반환합니다 (포스트 발행용).
  ///
  /// [utcDateTime] - 포스트 생성 시간 (UTC)
  /// 반환: (year, nthWeek) 튜플
  static ({int year, int nthWeek}) getYearAndWeekForPublish(
    DateTime utcDateTime,
  ) {
    final localDateTime = utcDateTime.toLocal();
    final year = localDateTime.year;
    final weekNumber = getWeekNumber(localDateTime);
    return (year: year, nthWeek: weekNumber);
  }
}
