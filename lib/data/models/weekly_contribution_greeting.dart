import 'package:flutter/material.dart';
import 'package:doppy/l10n/greeting_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doppy/utils/week_utils.dart';
import 'dart:math';

/// 포스트 작성 직후 클라이언트 전용 상태
enum PostPublishContext {
  /// 이번 주에 이미 작성한 경우
  alreadyWrittenThisWeek,

  /// 이번 주 첫 기록 (평일)
  firstWrittenThisWeek,

  /// 이번 주 첫 기록 + 주말(클러치)
  weekendClutch,

  /// 이번 주에 처음 작성해서 스트릭 달성 (아찔하게 끝낸 상황)
  streakAchieved,
}

/// Greeting 데이터
class WeeklyContributionGreeting {
  final String tier;
  final String mode;
  final String timeMeta;
  final int currentStreak;
  final int longestStreak;
  final int weeksUntilStreak;

  // 🎯 메시지 선택 결과 캐시 (year, tier, mode, timeMeta 조합)
  static final Map<String, String?> _messageCache = {};
  static int? _cachedYear;
  static int? _cachedPostCount; // 포스트 개수 추적

  WeeklyContributionGreeting({
    required this.tier,
    required this.mode,
    required this.timeMeta,
    required this.currentStreak,
    required this.longestStreak,
    required this.weeksUntilStreak,
  });

  factory WeeklyContributionGreeting.fromJson(Map<String, dynamic> json) {
    return WeeklyContributionGreeting(
      tier: json['tier'] as String? ?? '',
      mode: json['mode'] as String? ?? '',
      timeMeta: json['timeMeta'] as String? ?? '',
      currentStreak: json['currentStreak'] as int? ?? 0,
      longestStreak: json['longestStreak'] as int? ?? 0,
      weeksUntilStreak: json['weeksUntilStreak'] as int? ?? 0,
    );
  }

  /// 메시지 가져오기 (클라이언트 전용 상태 우선, 서버 greeting 폴백)
  static Future<String?> getMessage({
    required BuildContext context,
    WeeklyContributionGreeting? greeting,
    PostPublishContext? postPublishContext,
    int? year,
  }) async {
    // 🎯 포스트 개수 확인 (변동 감지용)
    final currentPostCount = _getCurrentPostCount(greeting);

    // 🎯 캐시 무효화 조건 확인
    final shouldInvalidateCache = _shouldInvalidateCache(
      year: year,
      currentPostCount: currentPostCount,
    );

    if (shouldInvalidateCache) {
      debugPrint('[Greeting] 🔄 캐시 무효화 (년도 변경 또는 포스트 변동)');
      _messageCache.clear();
      _cachedYear = year;
      _cachedPostCount = currentPostCount;
    }

    // 🎯 캐시 키 생성 (year, tier, mode, timeMeta 조합)
    final normalized =
        greeting != null ? _normalizeGreetingKeyParts(greeting) : null;
    final cacheKey = _buildCacheKey(
      year: year,
      tier: normalized?.tier ?? '',
      mode: normalized?.mode ?? '',
      timeMeta: normalized?.timeMeta ?? '',
      postPublishContext: postPublishContext,
    );

    // 🎯 캐시에서 먼저 확인
    if (_messageCache.containsKey(cacheKey)) {
      final cachedMessage = _messageCache[cacheKey];
      if (cachedMessage != null) {
        debugPrint('[Greeting] ✅ 캐시에서 메시지 반환: $cacheKey');
        return cachedMessage;
      }
    }

    // 현재 언어 코드 가져오기
    final locale = Localizations.localeOf(context);
    final languageCode = locale.languageCode;

    // 1. 클라이언트 전용 상태 우선 처리 (랜덤 선택, 최근 메시지 제외)
    if (postPublishContext != null) {
      final normalizedForClient = _normalizeGreetingKeyParts(greeting);
      final tier = normalizedForClient.tier;
      final mode = normalizedForClient.mode;
      final timeMeta = normalizedForClient.timeMeta;

      final base =
          'greeting.client.postJustPublished.${postPublishContext.name}';

      final candidates = <String>[
        if (tier.isNotEmpty && mode.isNotEmpty && timeMeta.isNotEmpty)
          '$base.$tier.$mode.$timeMeta',
        if (tier.isNotEmpty && mode.isNotEmpty) '$base.$tier.$mode',
        if (tier.isNotEmpty) '$base.$tier',
        if (mode.isNotEmpty) '$base.$mode',
        base,
      ];

      for (final key in candidates) {
        final clientMessage = await _getRandomMessage(key, languageCode);
        if (clientMessage != null) {
          final finalMessage = _replacePlaceholders(
            clientMessage,
            greeting ?? _emptyGreeting(),
            year: year,
          );
          // 🎯 캐시에 저장
          _messageCache[cacheKey] = finalMessage;
          return finalMessage;
        }
      }
    }

    // 2. 서버 greeting 처리
    // 🎯 greeting이 null이고 과거 연도일 때: reflectionEmpty 메시지 시도
    final currentYear = WeekUtils.getCurrentYear();
    final isPastYear = year != null && year != currentYear;

    if (greeting == null) {
      debugPrint('[Greeting] ⚠️ greeting이 null입니다');

      // 과거 연도일 때 reflectionEmpty 메시지 시도
      if (isPastYear) {
        debugPrint(
          '[Greeting] 🎯 과거 연도($year)에서 greeting이 null, reflectionEmpty 메시지 시도',
        );

        // 여러 tier를 순서대로 시도 (stable -> growing -> early -> empty)
        final tiers = ['stable', 'growing', 'early', 'empty'];
        for (final tier in tiers) {
          final reflectionKey = 'greeting.$tier.reflectionEmpty';
          debugPrint('[Greeting] 🔍 시도: $reflectionKey');

          final reflectionMessage = GreetingMessages.getMessage(
            reflectionKey,
            languageCode: languageCode,
          );

          if (reflectionMessage != null) {
            debugPrint(
              '[Greeting] ✅ 과거 연도 reflectionEmpty 메시지 사용: $reflectionKey',
            );

            // 빈 greeting 객체 생성 (placeholder 치환용)
            final emptyGreeting = _emptyGreeting();
            final finalMessage = _replacePlaceholders(
              reflectionMessage,
              emptyGreeting,
              year: year,
            );
            // 🎯 캐시에 저장
            _messageCache[cacheKey] = finalMessage;
            return finalMessage;
          }
        }

        debugPrint('[Greeting] ❌ 과거 연도 reflectionEmpty 메시지를 찾을 수 없음');
      }

      return null;
    }

    // 🎯 과거 연도로 이동한 경우: reflection 모드면 바로 reflection 메시지 표시
    if (isPastYear) {
      final normalizedForReflection = _normalizeGreetingKeyParts(greeting);
      final mode = normalizedForReflection.mode;

      // reflection 모드인 경우 바로 reflection 메시지 사용
      if (mode.startsWith('reflection')) {
        final reflectionKey = 'greeting.${normalizedForReflection.tier}.$mode';
        debugPrint('[Greeting] 🎯 과거 연도($year) reflection 모드: $reflectionKey');

        final reflectionMessage = GreetingMessages.getMessage(
          reflectionKey,
          languageCode: languageCode,
        );

        if (reflectionMessage != null) {
          debugPrint('[Greeting] ✅ 과거 연도 reflection 메시지 사용: $reflectionKey');
          final finalMessage = _replacePlaceholders(
            reflectionMessage,
            greeting,
            year: year,
          );
          // 🎯 캐시에 저장
          _messageCache[cacheKey] = finalMessage;
          return finalMessage;
        }
      }
    }

    // normalized는 이미 위에서 생성됨
    if (normalized == null) {
      debugPrint('[Greeting] ⚠️ normalized가 null입니다');
      return null;
    }

    debugPrint(
      '[Greeting] 서버 응답: tier="${greeting.tier}", mode="${greeting.mode}", timeMeta="${greeting.timeMeta}"',
    );
    debugPrint(
      '[Greeting] 정규화 후: tier="${normalized.tier}", mode="${normalized.mode}", timeMeta="${normalized.timeMeta}"',
    );

    // 3. 메시지 키 생성 및 폴백 처리 (랜덤 선택, 최근 메시지 제외)
    String? messageKey;
    String? message;

    // timeMeta가 NONE이 아니면 3단계 키 시도
    if (normalized.timeMeta.isNotEmpty) {
      messageKey =
          'greeting.${normalized.tier}.${normalized.mode}.${normalized.timeMeta}';
      debugPrint('[Greeting] 🔍 3단계 키 시도: $messageKey');
      message = await _getRandomMessage(messageKey, languageCode);
      if (message != null) {
        debugPrint('[Greeting] ✅ 3단계 키 매칭 성공: $messageKey');
        final finalMessage = _replacePlaceholders(
          message,
          greeting,
          year: year,
        );
        // 🎯 캐시에 저장
        _messageCache[cacheKey] = finalMessage;
        return finalMessage;
      } else {
        debugPrint('[Greeting] ❌ 3단계 키 매칭 실패: $messageKey');
      }
    }

    // 2단계 키 시도 (tier.mode) - 랜덤 선택, 최근 메시지 제외
    if (normalized.tier.isNotEmpty && normalized.mode.isNotEmpty) {
      messageKey = 'greeting.${normalized.tier}.${normalized.mode}';
      debugPrint('[Greeting] 🔍 2단계 키 시도: $messageKey');
      message = await _getRandomMessage(messageKey, languageCode);
      if (message != null) {
        debugPrint('[Greeting] ✅ 2단계 키 매칭 성공: $messageKey');
        final finalMessage = _replacePlaceholders(
          message,
          greeting,
          year: year,
        );
        // 🎯 캐시에 저장
        _messageCache[cacheKey] = finalMessage;
        return finalMessage;
      } else {
        debugPrint('[Greeting] ❌ 2단계 키 매칭 실패: $messageKey');
      }
    }

    // 1단계 키 시도 (tier만)
    if (normalized.tier.isNotEmpty) {
      messageKey = 'greeting.${normalized.tier}';
      debugPrint('[Greeting] 🔍 1단계 키 시도: $messageKey');
      message = GreetingMessages.getMessage(
        messageKey,
        languageCode: languageCode,
      );
      if (message != null) {
        debugPrint('[Greeting] ✅ 1단계 키 매칭 성공: $messageKey');
        final finalMessage = _replacePlaceholders(
          message,
          greeting,
          year: year,
        );
        // 🎯 캐시에 저장
        _messageCache[cacheKey] = finalMessage;
        return finalMessage;
      } else {
        debugPrint('[Greeting] ❌ 1단계 키 매칭 실패: $messageKey');
      }
    }

    // 폴백: 기본 메시지
    debugPrint('[Greeting] ⚠️ 모든 키 매칭 실패, 폴백 사용');
    final defaultMessage = GreetingMessages.getMessage(
      'greeting.default',
      languageCode: languageCode,
    );
    if (defaultMessage != null) {
      debugPrint('[Greeting] ✅ 폴백 메시지 사용: greeting.default');
      final finalMessage = _replacePlaceholders(
        defaultMessage,
        greeting,
        year: year,
      );
      // 🎯 캐시에 저장
      _messageCache[cacheKey] = finalMessage;
      return finalMessage;
    }

    debugPrint('[Greeting] ❌ 폴백 메시지도 없음');
    return null;
  }

  /// 빈 greeting 객체 생성 (클라이언트 전용 메시지용)
  static WeeklyContributionGreeting _emptyGreeting() {
    return WeeklyContributionGreeting(
      tier: '',
      mode: '',
      timeMeta: '',
      currentStreak: 0,
      longestStreak: 0,
      weeksUntilStreak: 0,
    );
  }

  /// 랜덤 메시지 가져오기 (최근 메시지 제외, 같은 키에 여러 변형이 있을 경우)
  static Future<String?> _getRandomMessage(
    String baseKey,
    String languageCode,
  ) async {
    // 먼저 기본 키 시도
    final baseMessage = GreetingMessages.getMessage(
      baseKey,
      languageCode: languageCode,
    );
    if (baseMessage != null) {
      debugPrint('[Greeting] 📝 기본 키 존재: $baseKey');
      // 기본 키가 있으면, 변형들도 확인
      final variations = <String>[];
      variations.add(baseKey); // 기본 키도 포함

      // 변형 키들 확인 (baseKey.1, baseKey.2, ...)
      for (int i = 1; i <= 10; i++) {
        final variationKey = '$baseKey.$i';
        if (GreetingMessages.hasMessage(
          variationKey,
          languageCode: languageCode,
        )) {
          variations.add(variationKey);
        } else {
          break; // 연속되지 않으면 중단
        }
      }

      // 최근 메시지 가져오기
      final recentMessages = await _getRecentMessages(baseKey);
      final lastMessage = recentMessages.isNotEmpty ? recentMessages[0] : null;

      // 최근 메시지 제외하고 선택 가능한 메시지 필터링
      final availableMessages =
          variations.where((key) => !recentMessages.contains(key)).toList();

      debugPrint(
        '[Greeting] 🔍 변형: ${variations.length}개, 최근: ${recentMessages.length}개, 사용가능: ${availableMessages.length}개',
      );

      // 사용 가능한 메시지가 없으면 (모두 최근에 사용됨) 전체 목록 사용
      var candidates =
          availableMessages.isNotEmpty ? availableMessages : variations;

      // 🎯 변형이 1개뿐이고 이전 메시지와 같으면 null 반환하여 상위 단계로 폴백
      if (variations.length == 1 && lastMessage == variations[0]) {
        debugPrint('[Greeting] ⚠️ 변형 1개뿐이고 이전 메시지와 동일 → null 반환하여 상위 단계로 폴백');
        return null; // 상위 단계(2단계 또는 1단계)로 폴백
      }

      // 🎯 이전 메시지와 같으면 제외하고 다른 메시지 선택
      if (lastMessage != null && candidates.contains(lastMessage)) {
        if (candidates.length > 1) {
          // 이전 메시지를 제외
          candidates = candidates.where((key) => key != lastMessage).toList();
          debugPrint(
            '[Greeting] 🔄 이전 메시지 "$lastMessage" 제외, ${candidates.length}개 후보로 재선택',
          );
        } else {
          // 후보가 1개뿐인데 그것이 이전 메시지와 같으면, null 반환하여 상위 단계로 폴백
          debugPrint('[Greeting] ⚠️ 후보 1개뿐이고 이전 메시지와 동일 → null 반환하여 상위 단계로 폴백');
          return null; // 상위 단계로 폴백
        }
      }

      debugPrint(
        '[Greeting] 📋 후보 메시지: ${candidates.length}개 (전체 ${variations.length}개, 최근 ${recentMessages.length}개 제외${lastMessage != null ? ', 이전: "$lastMessage"' : ''})',
      );

      // 랜덤 선택 (앱 재시작 시에도 편향 줄이기)
      // 시간 기반 시드를 명시적으로 사용하여 매번 다른 랜덤 값 생성
      if (candidates.length > 1) {
        // 리스트를 섞어서 더 확실한 랜덤성 보장
        final shuffled = List<String>.from(candidates);
        final seed =
            DateTime.now().millisecondsSinceEpoch +
            DateTime.now().microsecondsSinceEpoch;
        final rnd = Random(seed);
        shuffled.shuffle(rnd);
        final selectedKey = shuffled.first;

        debugPrint(
          '[Greeting] 🎲 랜덤 선택: ${candidates.length}개 중 "$selectedKey" 선택 (시드: $seed)',
        );

        // 선택된 메시지를 최근 메시지에 추가
        await _addRecentMessage(baseKey, selectedKey);

        return GreetingMessages.getMessage(
          selectedKey,
          languageCode: languageCode,
        );
      } else if (candidates.length == 1) {
        // 메시지가 1개만 있는 경우
        final selectedKey = candidates[0];
        await _addRecentMessage(baseKey, selectedKey);
        return GreetingMessages.getMessage(
          selectedKey,
          languageCode: languageCode,
        );
      }

      debugPrint('[Greeting] ✅ 기본 메시지 반환: $baseKey');
      return baseMessage;
    }

    debugPrint('[Greeting] ❌ 키가 존재하지 않음: $baseKey');
    return null;
  }

  /// 서버 tier를 그대로 사용 (매핑 제거)
  /// 서버 tier: empty | early | growing | stable
  /// 클라이언트에 이미 정의된 tier를 그대로 사용
  static String _mapServerTierToClientTier(String serverTier) {
    final trimmed = serverTier.trim();
    if (trimmed.isEmpty) return '';

    final lower = trimmed.toLowerCase();

    // none/null/빈값 처리
    if (lower == 'none' || lower == 'null') {
      return '';
    }

    // 서버 tier를 그대로 사용 (소문자로 정규화)
    // 서버 tier: empty, early, growing, stable
    // 클라이언트에 이미 정의되어 있으므로 그대로 사용
    return lower;
  }

  /// 서버 mode를 그대로 사용 (camelCase 유지)
  /// mode는 camelCase를 유지해야 함 (streakMaintained, weekEmpty 등)
  /// 특정 tier에 없는 mode는 나중에 키 매칭 실패 시 상위 단계로 폴백됨
  static String _mapServerModeToClientMode(
    String serverMode,
    String clientTier,
  ) {
    final trimmed = serverMode.trim();
    if (trimmed.isEmpty) return '';

    // camelCase 유지: 서버가 보낸 원본 형식 그대로 사용
    // streakMaintained, weekEmpty, weekQuiet 등은 camelCase로 정의되어 있음
    return trimmed;
  }

  static ({String tier, String mode, String timeMeta})
  _normalizeGreetingKeyParts(WeeklyContributionGreeting? greeting) {
    if (greeting == null) {
      return (tier: '', mode: '', timeMeta: '');
    }

    // 원본 값 추출 (빈값 처리)
    final rawTier = greeting.tier.trim();
    final rawMode = greeting.mode.trim();
    final rawTimeMeta = greeting.timeMeta.trim();

    // tier 정규화: 서버 tier를 클라이언트 tier로 매핑
    String tier = '';
    if (rawTier.isNotEmpty) {
      tier = _mapServerTierToClientTier(rawTier);
    }

    // mode 정규화: 서버 mode를 클라이언트 mode로 매핑 (tier 고려)
    String mode = '';
    if (rawMode.isNotEmpty) {
      mode = _mapServerModeToClientMode(rawMode, tier);
    }

    // timeMeta 정규화: NONE/none/빈값 → 빈 문자열
    String timeMeta = '';
    if (rawTimeMeta.isNotEmpty) {
      final lowerTimeMeta = rawTimeMeta.toLowerCase();
      if (lowerTimeMeta != 'none' && lowerTimeMeta != 'null') {
        // 기존 메시지 키들이 YEAR_END, MID_MONTH 처럼 대문자이므로 통일
        timeMeta = rawTimeMeta.toUpperCase();
      }
    }

    debugPrint(
      '[Greeting] 정규화: rawTier="$rawTier" → tier="$tier", rawMode="$rawMode" → mode="$mode", rawTimeMeta="$rawTimeMeta" → timeMeta="$timeMeta"',
    );

    return (tier: tier, mode: mode, timeMeta: timeMeta);
  }

  /// 최근 메시지 가져오기 (상황별로 최근 5개 저장)
  static Future<List<String>> _getRecentMessages(String baseKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'greeting_recent_$baseKey';
      return prefs.getStringList(key) ?? [];
    } catch (e) {
      debugPrint('[WeeklyContributionGreeting] 최근 메시지 로드 실패: $e');
      return [];
    }
  }

  /// 최근 메시지에 추가 (최대 5개 유지)
  static Future<void> _addRecentMessage(
    String baseKey,
    String messageKey,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'greeting_recent_$baseKey';
      final recent = prefs.getStringList(key) ?? [];

      // 이미 있으면 제거 (중복 방지)
      recent.remove(messageKey);

      // 맨 앞에 추가
      recent.insert(0, messageKey);

      // 최대 5개만 유지
      if (recent.length > 5) {
        recent.removeRange(5, recent.length);
      }

      await prefs.setStringList(key, recent);
      debugPrint('[Greeting] 💾 최근 메시지 저장: $key → $recent');
    } catch (e) {
      debugPrint('[WeeklyContributionGreeting] 최근 메시지 저장 실패: $e');
    }
  }

  /// 보조 필드 치환 ({{currentStreak}}, {{longestStreak}}, {{weeksUntilStreak}}, {{year}})
  static String _replacePlaceholders(
    String message,
    WeeklyContributionGreeting greeting, {
    int? year,
  }) {
    String result = message;

    // {{year}} 치환
    if (year != null) {
      result = result.replaceAll('{{year}}', '$year');
    } else {
      // 년도가 없으면 "그해"로 폴백
      result = result.replaceAll('{{year}}년은', '그해');
      result = result.replaceAll('{{year}}년', '그해');
    }

    // {{currentStreak}} 치환 (0이어도 치환)
    result = result.replaceAll(
      '{{currentStreak}}',
      '${greeting.currentStreak}',
    );

    // {{longestStreak}} 치환 (0이어도 치환)
    result = result.replaceAll(
      '{{longestStreak}}',
      '${greeting.longestStreak}',
    );

    // {{weeksUntilStreak}} 치환 (0이어도 치환)
    result = result.replaceAll(
      '{{weeksUntilStreak}}',
      '${greeting.weeksUntilStreak}',
    );

    return result;
  }

  /// 캐시 키 생성
  static String _buildCacheKey({
    int? year,
    required String tier,
    required String mode,
    required String timeMeta,
    PostPublishContext? postPublishContext,
  }) {
    final parts = <String>[];
    if (year != null) parts.add('year:$year');
    if (postPublishContext != null) {
      parts.add('ctx:${postPublishContext.name}');
    }
    parts.add('tier:$tier');
    parts.add('mode:$mode');
    parts.add('timeMeta:$timeMeta');
    return parts.join('|');
  }

  /// 현재 포스트 개수 계산 (변동 감지용)
  static int _getCurrentPostCount(WeeklyContributionGreeting? greeting) {
    // 간단히 currentStreak을 사용 (실제로는 더 정확한 방법이 필요할 수 있음)
    return greeting?.currentStreak ?? 0;
  }

  /// 캐시 무효화 여부 확인
  static bool _shouldInvalidateCache({
    int? year,
    required int currentPostCount,
  }) {
    // 년도가 변경된 경우
    if (year != null && _cachedYear != null && year != _cachedYear) {
      return true;
    }

    // 포스트 개수가 변경된 경우 (추가/삭제)
    if (_cachedPostCount != null && currentPostCount != _cachedPostCount) {
      return true;
    }

    // 캐시가 비어있는 경우 (앱 시작 시)
    if (_cachedYear == null || _cachedPostCount == null) {
      return true;
    }

    return false;
  }

  /// 캐시 강제 무효화 (포스트 추가/삭제 시 호출)
  static void invalidateCache() {
    debugPrint('[Greeting] 🔄 캐시 강제 무효화');
    _messageCache.clear();
    _cachedYear = null;
    _cachedPostCount = null;
  }
}
