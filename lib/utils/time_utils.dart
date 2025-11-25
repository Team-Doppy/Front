import 'package:flutter/material.dart';

/// 시간 관련 유틸리티 함수
/// UTC 시간을 로컬 시간으로 변환하는 기능 제공
class TimeUtils {
  /// UTC 시간 문자열(ISO 8601)을 로컬 DateTime으로 변환
  ///
  /// [utcString] 예: "2024-01-01T12:00:00Z" 또는 "2024-01-01T12:00:00.000Z"
  ///
  /// 반환: 로컬 시간대의 DateTime
  static DateTime toLocalTime(String utcString) {
    try {
      // ISO 8601 형식 파싱
      final dateTime = DateTime.parse(utcString);

      // 이미 로컬 시간이면 그대로 반환
      if (dateTime.isUtc) {
        return dateTime.toLocal();
      }

      final hasTimeZoneInfo = _timeZoneRegex.hasMatch(
        utcString.toUpperCase().trim(),
      );

      if (hasTimeZoneInfo) {
        // ISO 문자열이 Z 또는 +hh:mm 오프셋을 포함하면 DateTime.parse가 이미 현지화 처리
        return dateTime.toLocal();
      }

      // 타임존 정보가 없지만 서버는 UTC로 보낸다고 가정 → UTC로 간주 후 변환
      final assumedUtc = DateTime.utc(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        dateTime.hour,
        dateTime.minute,
        dateTime.second,
        dateTime.millisecond,
        dateTime.microsecond,
      );
      return assumedUtc.toLocal();
    } catch (e) {
      // 파싱 실패 시 현재 시간 반환
      debugPrint('[TimeUtils] 시간 파싱 실패: $utcString, 에러: $e');
      return DateTime.now();
    }
  }

  static final RegExp _timeZoneRegex = RegExp(
    r'(Z|[+\-]\d{2}:\d{2})$',
    caseSensitive: false,
  );

  /// UTC DateTime을 로컬 DateTime으로 변환
  static DateTime utcToLocal(DateTime utcDateTime) {
    if (utcDateTime.isUtc) {
      return utcDateTime.toLocal();
    }
    return utcDateTime;
  }

  /// 로컬 DateTime을 UTC DateTime으로 변환
  static DateTime localToUtc(DateTime localDateTime) {
    if (localDateTime.isUtc) {
      return localDateTime;
    }
    return localDateTime.toUtc();
  }

  /// 현재 시간을 UTC로 반환
  static DateTime nowUtc() {
    return DateTime.now().toUtc();
  }

  /// 현재 로컬 시간 반환
  static DateTime nowLocal() {
    return DateTime.now();
  }

  /// UTC 시간 문자열을 로컬 DateTime으로 변환 (실패 시 null 반환)
  ///
  /// [utcString] 예: "2024-01-01T12:00:00Z" 또는 "2024-01-01T12:00:00.000Z"
  ///
  /// 반환: 로컬 시간대의 DateTime 또는 null (파싱 실패 시)
  static DateTime? toLocalTimeOrNull(String? utcString) {
    if (utcString == null || utcString.isEmpty) {
      return null;
    }
    try {
      return toLocalTime(utcString);
    } catch (_) {
      return null;
    }
  }

  /// UTC 시간 문자열이 유효한지 확인
  static bool isValidUtcString(String utcString) {
    try {
      DateTime.parse(utcString);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 두 시간 사이의 차이를 계산 (로컬 시간 기준)
  static Duration difference(String utcString1, String utcString2) {
    try {
      final time1 = toLocalTime(utcString1);
      final time2 = toLocalTime(utcString2);
      return time2.difference(time1);
    } catch (e) {
      debugPrint('[TimeUtils] 시간 차이 계산 실패: $e');
      return Duration.zero;
    }
  }

  /// 현재 시간과 UTC 시간의 차이 계산
  static Duration differenceFromNow(String utcString) {
    try {
      final utcTime = toLocalTime(utcString);
      final now = DateTime.now();
      return now.difference(utcTime);
    } catch (e) {
      debugPrint('[TimeUtils] 현재 시간과의 차이 계산 실패: $e');
      return Duration.zero;
    }
  }
}
