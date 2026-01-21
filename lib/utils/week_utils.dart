import 'package:flutter/material.dart';

/// 주차(Week) 및 연도(Year) 관련 중앙 유틸리티
/// 1월 1일부터 시작하는 방식으로 주차를 계산합니다.
///
/// 모든 주차/연도 관련 계산은 이 클래스를 통해서만 수행하여 일관성을 유지합니다.
class WeekUtils {
  WeekUtils._(); // private constructor (static only)

  /// 월 기준 "주차"를 계산합니다. (한국 달력 UX에 맞춘 규칙)
  ///
  /// 규칙(기본):
  /// - 주 시작은 월요일
  /// - 1주차는 "해당 월의 첫 번째 월요일"이 속한 주로 본다.
  /// - 다만, 월 1일이 첫 월요일 이전인 경우(월초 자투리 구간)는 1주차로 취급한다.
  ///
  /// 예) 2026년 1월(1일=목):
  /// - 1주차: 1/1~1/11(월초 자투리 + 첫 full week)
  /// - 2주차: 1/12~1/18
  /// - 3주차: 1/19~1/25
  /// - 4주차: 1/26~2/1
  static int getWeekOfMonth(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final firstDayOfMonth = DateTime(d.year, d.month, 1);

    // 첫 월요일(해당 월 안에서) 찾기
    final deltaToMonday = (DateTime.monday - firstDayOfMonth.weekday + 7) % 7;
    final firstMonday = firstDayOfMonth.add(Duration(days: deltaToMonday));

    // 월초 자투리(첫 월요일 이전)는 1주차로 취급
    if (d.isBefore(firstMonday)) return 1;

    final diffDays = d.difference(firstMonday).inDays;
    return (diffDays ~/ 7) + 1;
  }

  /// 월 기준 주차(weekOfMonth)의 시작일을 반환합니다.
  ///
  /// - weekOfMonth=1은 "월초 자투리 + 첫 월요일이 속한 주"의 시작일(=해당 월 1일)을 반환합니다.
  /// - weekOfMonth>=2는 (첫 월요일 + (weekOfMonth-1)*7) 을 반환합니다.
  static DateTime getWeekStartDateOfMonth(
    int year,
    int month,
    int weekOfMonth,
  ) {
    final firstDayOfMonth = DateTime(year, month, 1);
    final deltaToMonday = (DateTime.monday - firstDayOfMonth.weekday + 7) % 7;
    final firstMonday = firstDayOfMonth.add(Duration(days: deltaToMonday));

    if (weekOfMonth <= 1) return firstDayOfMonth;
    return firstMonday.add(Duration(days: (weekOfMonth - 1) * 7));
  }

  /// 월 기준 주차(weekOfMonth)의 "해당 연도 주차(weekOfYear)"를 반환합니다.
  static int getWeekOfYearFromMonthWeek({
    required int year,
    required int month,
    required int weekOfMonth,
  }) {
    final start = getWeekStartDateOfMonth(year, month, weekOfMonth);
    return getWeekNumber(start);
  }

  /// 1월 1일부터 시작하는 방식으로 날짜의 주차 번호를 계산합니다.
  ///
  /// 주차 계산 규칙:
  /// - 1월 1일부터 7일씩 나누어 주차를 계산합니다.
  /// - 1주차: 1/1 ~ 1/7, 2주차: 1/8 ~ 1/14, 3주차: 1/15 ~ 1/21, ...
  ///
  /// [date] - 계산할 날짜 (로컬 시간대)
  /// 반환: 주차 번호 (1-53)
  static int getWeekNumber(DateTime date) {
    // 1. 해당 연도의 1월 1일을 찾습니다
    final jan1 = DateTime(date.year, 1, 1);

    // 2. 1월 1일부터 경과한 일수 계산
    final daysSinceJan1 = date.difference(jan1).inDays;

    // 3. 주차 계산 (0일부터 시작하므로 +1)
    final weekNumber = (daysSinceJan1 ~/ 7) + 1;

    // 4. 연도 경계 처리
    // 만약 날짜가 이전 연도이면, 이전 연도의 마지막 주차를 반환
    if (date.year < jan1.year) {
      final prevYear = date.year;
      final prevJan1 = DateTime(prevYear, 1, 1);
      final prevDec31 = DateTime(prevYear, 12, 31);
      final prevDaysSinceJan1 = prevDec31.difference(prevJan1).inDays;
      return (prevDaysSinceJan1 ~/ 7) + 1;
    }

    // 5. 다음 연도로 넘어간 경우
    if (date.year > jan1.year) {
      return 1; // 다음 연도의 첫 번째 주차
    }

    return weekNumber;
  }

  /// 1월 1일부터 시작하는 방식으로 해당 연도의 총 주차 수를 계산합니다.
  ///
  /// 규칙:
  /// - 1월 1일부터 12월 31일까지 7일씩 나누어 계산합니다.
  ///
  /// [year] - 연도
  /// 반환: 해당 연도의 총 주차 수 (52 또는 53)
  static int getWeeksInYear(int year) {
    final jan1 = DateTime(year, 1, 1);
    final dec31 = DateTime(year, 12, 31);
    final daysDifference = dec31.difference(jan1).inDays;
    return (daysDifference ~/ 7) + 1;
  }

  /// 특정 연도와 주차의 시작일을 반환합니다.
  ///
  /// [year] - 연도
  /// [weekNumber] - 주차 번호 (1부터 시작)
  /// 반환: 해당 주차의 시작일 (1월 1일부터 7일씩 계산)
  static DateTime getWeekStartDate(int year, int weekNumber) {
    final jan1 = DateTime(year, 1, 1);
    // (weekNumber - 1) * 7일을 더하면 해당 주차의 시작일
    return jan1.add(Duration(days: (weekNumber - 1) * 7));
  }

  /// 특정 연도와 주차의 종료일을 반환합니다.
  ///
  /// [year] - 연도
  /// [weekNumber] - 주차 번호 (1부터 시작)
  /// 반환: 해당 주차의 종료일 (시작일로부터 6일 후)
  static DateTime getWeekEndDate(int year, int weekNumber) {
    final weekStart = getWeekStartDate(year, weekNumber);
    // 시작일로부터 6일 후가 종료일
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
