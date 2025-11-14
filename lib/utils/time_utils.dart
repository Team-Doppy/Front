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

      // UTC로 표시되어 있지만 isUtc가 false인 경우 명시적으로 변환
      // (예: ISO 문자열이 'Z'로 끝나는 경우)
      if (utcString.endsWith('Z')) {
        return DateTime.utc(
          dateTime.year,
          dateTime.month,
          dateTime.day,
          dateTime.hour,
          dateTime.minute,
          dateTime.second,
          dateTime.millisecond,
          dateTime.microsecond,
        ).toLocal();
      }

      // UTC 오프셋이 포함된 경우 (예: "+09:00")
      if (utcString.contains('+') || utcString.contains('-')) {
        // ISO 문자열을 파싱하면 자동으로 변환됨
        return dateTime.toLocal();
      }

      // 이미 로컬 시간으로 파싱된 경우
      return dateTime;
    } catch (e) {
      // 파싱 실패 시 현재 시간 반환
      print('[TimeUtils] 시간 파싱 실패: $utcString, 에러: $e');
      return DateTime.now();
    }
  }

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
      print('[TimeUtils] 시간 차이 계산 실패: $e');
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
      print('[TimeUtils] 현재 시간과의 차이 계산 실패: $e');
      return Duration.zero;
    }
  }
}
