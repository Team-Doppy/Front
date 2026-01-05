import 'package:flutter/material.dart';
import 'package:doppy/l10n/app_localizations.dart';

/// 시간 관련 유틸리티 함수
/// UTC 시간을 로컬 시간으로 변환하는 기능 제공
class TimeUtils {
  /// UTC 또는 로컬 시간 문자열(ISO 8601)을 로컬 DateTime으로 변환
  ///
  /// [utcString] 예:
  /// - UTC: "2024-01-01T12:00:00Z" 또는 "2024-01-01T12:00:00.000Z"
  /// - 로컬: "2024-01-01T12:00:00+09:00" (타임존 정보 포함)
  ///
  /// 반환: 로컬 시간대의 DateTime
  static DateTime toLocalTime(String utcString) {
    try {
      // ISO 8601 형식 파싱
      final dateTime = DateTime.parse(utcString);

      // UTC 시간이면 로컬로 변환
      if (dateTime.isUtc) {
        return dateTime.toLocal();
      }

      final hasTimeZoneInfo = _timeZoneRegex.hasMatch(
        utcString.toUpperCase().trim(),
      );

      if (hasTimeZoneInfo) {
        // ✅ 타임존 정보가 포함된 경우 (예: +09:00)
        // DateTime.parse는 이미 타임존 정보를 반영하여 파싱하므로
        // 추가 변환 없이 그대로 반환 (이미 로컬 시간대 기준)
        return dateTime;
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

  /// 현재 시간과 UTC 시간의 차이 계산 (UTC 기준)
  static Duration differenceFromNow(String utcString) {
    try {
      // ✅ UTC 시간을 UTC로 파싱
      final dateTime = DateTime.parse(utcString);
      final utcTime =
          dateTime.isUtc
              ? dateTime
              : DateTime.utc(
                dateTime.year,
                dateTime.month,
                dateTime.day,
                dateTime.hour,
                dateTime.minute,
                dateTime.second,
                dateTime.millisecond,
                dateTime.microsecond,
              );

      // ✅ 현재 시간을 UTC로 변환하여 비교
      final nowUtc = DateTime.now().toUtc();
      return nowUtc.difference(utcTime);
    } catch (e) {
      debugPrint('[TimeUtils] 현재 시간과의 차이 계산 실패: $e');
      return Duration.zero;
    }
  }

  /// 상대 시간 포맷팅 (로케일 적용)
  /// ✅ UTC 기준으로 계산 (타임존 문제 없음)
  /// [dateTime]은 UTC DateTime이어야 합니다.
  static String formatRelativeTime(BuildContext context, DateTime dateTime) {
    final loc = AppLocalizations.of(context);
    // ✅ 현재 시간을 UTC로 변환하여 비교
    final nowUtc = DateTime.now().toUtc();
    // ✅ dateTime이 UTC가 아니면 UTC로 변환
    final dateTimeUtc = dateTime.isUtc ? dateTime : dateTime.toUtc();
    final difference = nowUtc.difference(dateTimeUtc);

    // ✅ 음수 Duration 처리 (미래 시간인 경우)
    if (difference.isNegative) {
      return loc.translate('just_now_with_ago');
    }

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return loc.translate('just_now_with_ago');
        }
        return '${difference.inMinutes} ${loc.translate('min_ago')}';
      }
      return '${difference.inHours} ${loc.translate('hr_ago')}';
    } else if (difference.inDays == 1) {
      return loc.translate('yesterday');
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ${loc.translate('days_ago')}';
    } else if (difference.inDays < 30) {
      return '${difference.inDays ~/ 7} ${loc.translate('weeks_ago')}';
    } else if (difference.inDays < 365) {
      return '${difference.inDays ~/ 30} ${loc.translate('months_ago')}';
    } else {
      return '${difference.inDays ~/ 365} ${loc.translate('years_ago')}';
    }
  }

  /// UTC 시간 문자열을 상대 시간으로 포맷팅 (로케일 적용)
  /// ✅ UTC 기준으로 계산하여 타임존 차이 문제 해결
  static String formatRelativeTimeFromUtc(
    BuildContext context,
    String utcString,
  ) {
    try {
      // ✅ UTC 시간을 UTC로 파싱
      final dateTime = DateTime.parse(utcString);
      final utcTime =
          dateTime.isUtc
              ? dateTime
              : DateTime.utc(
                dateTime.year,
                dateTime.month,
                dateTime.day,
                dateTime.hour,
                dateTime.minute,
                dateTime.second,
                dateTime.millisecond,
                dateTime.microsecond,
              );

      // ✅ 현재 시간을 UTC로 변환하여 비교
      final nowUtc = DateTime.now().toUtc();
      final difference = nowUtc.difference(utcTime);

      // ✅ 음수 Duration 처리 (미래 시간인 경우)
      if (difference.isNegative) {
        return AppLocalizations.of(context).translate('just_now_with_ago');
      }

      final loc = AppLocalizations.of(context);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) {
            return loc.translate('just_now_with_ago');
          }
          return '${difference.inMinutes} ${loc.translate('min_ago')}';
        }
        return '${difference.inHours} ${loc.translate('hr_ago')}';
      } else if (difference.inDays == 1) {
        return loc.translate('yesterday');
      } else if (difference.inDays < 7) {
        return '${difference.inDays} ${loc.translate('days_ago')}';
      } else if (difference.inDays < 30) {
        return '${difference.inDays ~/ 7} ${loc.translate('weeks_ago')}';
      } else if (difference.inDays < 365) {
        return '${difference.inDays ~/ 30} ${loc.translate('months_ago')}';
      } else {
        return '${difference.inDays ~/ 365} ${loc.translate('years_ago')}';
      }
    } catch (e) {
      debugPrint('[TimeUtils] 상대 시간 포맷팅 실패: $utcString, 에러: $e');
      return AppLocalizations.of(context).translate('just_now');
    }
  }
}
