import 'dart:math';

/// 홈 인삿말(홈 텍스트) 문구 카탈로그 + 선택 로직.
///
/// 목표:
/// - 사용자의 "그리드/활동 상태"에 따라 다른 톤/내용의 문구를 보여준다.
/// - 동일 상태라도 여러 베리에이션을 준비해 반복 노출 피로를 줄인다.
/// - 선택은 seed를 통해 "너무 자주 바뀌는 깜빡임"을 방지한다(예: 하루 단위).
///
/// 사용자 요청 상태 매핑(예시):
/// 1) firstSignup: 처음 회원가입 직후
/// 2) empty: 비어있을 때(아직 기록 없음)
/// 3) weekNone: 이번 주 아직 안 남김(D1~D6)
/// 4) weekSome: 이번 주에 하나 이상 남김
/// 5) loyalStreak: 연속으로 꾸준(스트릭)
/// 6) comeback: 끊겼다가 복귀
/// 7) timeMeta: 이번 달/올해 등 시간감 문구(간헐적으로)
/// 8) misc: 기타 인삿말
enum HomeGreetingState {
  firstSignup,
  empty,
  weekNone,
  weekSome,
  loyalStreak,
  comeback,
  timeMeta,
  misc,
}

/// 홈 인삿말을 고르기 위한 입력 신호들.
/// (지금 코드베이스에서 구할 수 있는 값들 위주로 설계)
class HomeGreetingSignals {
  /// 사용자 표시명(없으면 null/빈 문자열)
  final String? displayName;

  /// 가입일(모르면 null)
  final DateTime? signupAt;

  /// 전체 포스트/활동 수
  final int totalPosts;

  /// 이번 주 포스트 수(ISO week 기준)
  final int postsThisWeek;

  /// 마지막 포스트 작성일(모르면 null)
  final DateTime? lastPostAt;

  /// "연속" 지표(일/주 단위 무엇이든 가능). 계산 로직은 호출자가 정한다.
  /// 예: 연속 7일 작성이면 7
  final int streakCount;

  /// 현재 시각(로컬 시간대 기준)
  ///
  /// 주의: 이 값은 사용자의 디바이스 시간대(로컬)를 사용합니다.
  /// 예: 한국(KST, UTC+9) 또는 미국 동부(EST, UTC-5) 등
  /// DateTime.now()를 그대로 전달하면 됩니다.
  final DateTime now;

  /// 문구 선택을 안정적으로 만들기 위한 salt.
  /// 예: userId, deviceId, 또는 displayName 등.
  final String seedSalt;

  const HomeGreetingSignals({
    required this.displayName,
    required this.signupAt,
    required this.totalPosts,
    required this.postsThisWeek,
    required this.lastPostAt,
    required this.streakCount,
    required this.now,
    required this.seedSalt,
  });
}

/// 홈 인삿말은 **항상 2줄**로 고정한다.
///
/// - line1: 상태/팩트(예: "2주 연속 기록", "이번 주 3개 기록")
/// - line2: 행동 유도/감정(예: "더 진하게 만들어봐요")
///
/// 각 줄은 RichText 렌더링을 위해 "조각(Chunk)" 단위로 관리한다.
/// Chunk마다 bold 여부를 미리 정의해둔다.
class HomeGreetingMessage {
  final List<HomeGreetingChunk> line1;
  final List<HomeGreetingChunk> line2;
  const HomeGreetingMessage({required this.line1, required this.line2});
}

class HomeGreetingChunk {
  final String text;
  final bool bold;
  const HomeGreetingChunk(this.text, {this.bold = false});
}

enum _ValueKey { name, streakWeeks, weekCount, month, year }

class _Part {
  final String? literal;
  final _ValueKey? valueKey;
  final bool bold;

  const _Part.literal(this.literal, {this.bold = false}) : valueKey = null;
  const _Part.value(this.valueKey, {this.bold = false}) : literal = null;
}

class _Template {
  final List<_Part> line1;
  final List<_Part> line2;
  const _Template({required this.line1, required this.line2});
}

class HomeGreetings {
  static const int _loyalStreakThreshold =
      10; // 기본값: streakCount >= 10 이면 "충성" 후보
  static const int _comebackGapDaysMin = 3; // 마지막 활동이 3일 이상 비면 "복귀" 후보

  /// 홈 인삿말을 선택한다.
  ///
  /// - seed는 기본적으로 "하루 단위로 고정"되도록 설계되어, 리빌드마다 바뀌지 않는다.
  /// - 시간감 문구(timeMeta)는 매일/매번 나오지 않도록 낮은 확률로 섞는다(조건 + seed 기반).
  static HomeGreetingMessage pick(HomeGreetingSignals s) {
    final baseState = _inferState(s);
    final seed = _dailySeed(s.now, s.seedSalt);
    final rng = Random(seed);

    // 간헐적으로 시간감(timeMeta) 문구 섞기 (너무 자주 나오지 않게)
    final meta = _maybePickTimeMeta(s, rng);
    if (meta != null) return meta;

    final templates =
        _templates[baseState] ?? _templates[HomeGreetingState.misc]!;
    final t = _pickOne(templates, rng);
    return _renderTemplate(t, s);
  }

  static HomeGreetingState _inferState(HomeGreetingSignals s) {
    // ✅ 로컬 시간대 기준으로 비교 (s.now와 s.signupAt 모두 로컬 시간대여야 함)
    final isNew =
        s.signupAt != null && s.now.difference(s.signupAt!).inHours < 24;
    if (isNew) return HomeGreetingState.firstSignup;

    if (s.totalPosts <= 0) return HomeGreetingState.empty;

    // comeback: 최근 복귀(이전엔 텀이 있었고, 지금은 이번 주 활동이 있음)
    if (s.lastPostAt != null) {
      final gapDays = s.now.difference(s.lastPostAt!).inDays;
      if (gapDays >= _comebackGapDaysMin && s.postsThisWeek > 0) {
        return HomeGreetingState.comeback;
      }
    }

    if (s.streakCount >= _loyalStreakThreshold)
      return HomeGreetingState.loyalStreak;

    if (s.postsThisWeek <= 0) return HomeGreetingState.weekNone;
    return HomeGreetingState.weekSome;
  }

  static HomeGreetingMessage? _maybePickTimeMeta(
    HomeGreetingSignals s,
    Random rng,
  ) {
    // ✅ 로컬 시간대 기준으로 월/일 계산 (미국/한국 등 사용자 위치에 따라 자동 적용)
    // 시즌/시간감 문구는 "조건이 맞을 때" + "낮은 빈도"로만 노출
    final isYearEnd = s.now.month == 12 && s.now.day >= 20;
    final isMonthEnd = s.now.day >= 25;
    final isMidMonth = s.now.day >= 13 && s.now.day <= 17;

    final shouldShow =
        (isYearEnd || isMonthEnd || isMidMonth) &&
        // 하루에 한 번 정도만 뜨게: seed 고정 + 0~99 중 일부만 통과
        (rng.nextInt(100) < 12);

    if (!shouldShow) return null;

    final pool = <_Template>[
      if (isYearEnd) ..._timeMetaYearEnd,
      if (isMonthEnd) ..._timeMetaMonthEnd,
      if (isMidMonth) ..._timeMetaMidMonth,
      ..._templates[HomeGreetingState.timeMeta]!,
    ];

    final t = _pickOne(pool, rng);
    return _renderTemplate(t, s);
  }

  static int _dailySeed(DateTime now, String salt) {
    // ✅ 로컬 시간대 기준으로 "하루" 계산 (미국/한국 등 사용자 위치에 따라 자동 적용)
    // 같은 사용자/기기에서 "하루 동안은 동일한 문구"를 유지하기 위한 seed
    // 예: 한국에서 2024-01-01 00:00 KST와 미국에서 2024-01-01 00:00 EST는 다른 dayKey
    final dayKey = now.year * 10000 + now.month * 100 + now.day;
    return _hash32('$dayKey|$salt');
  }

  static int _hash32(String input) {
    // 간단한 32-bit hash (FNV-1a 변형)
    int hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  static T _pickOne<T>(List<T> pool, Random rng) {
    if (pool.isEmpty) {
      throw StateError('[HomeGreetings] empty pool');
    }
    return pool[rng.nextInt(pool.length)];
  }

  static HomeGreetingMessage _renderTemplate(
    _Template t,
    HomeGreetingSignals s,
  ) {
    List<HomeGreetingChunk> renderLine(List<_Part> parts) {
      final chunks = <HomeGreetingChunk>[];
      for (final p in parts) {
        final literal = p.literal;
        if (literal != null) {
          if (literal.isEmpty) continue;
          chunks.add(HomeGreetingChunk(literal, bold: p.bold));
          continue;
        }
        final k = p.valueKey!;
        final v = _valueFor(k, s);
        if (v.isEmpty) continue;
        chunks.add(HomeGreetingChunk(v, bold: p.bold));
      }
      return chunks;
    }

    final line1 = renderLine(t.line1);
    final line2 = renderLine(t.line2);

    // ✅ 안전장치: 빈 줄이 되지 않게 fallback
    if (line1.isEmpty || line2.isEmpty) {
      return _renderTemplate(_templates[HomeGreetingState.misc]!.first, s);
    }
    return HomeGreetingMessage(line1: line1, line2: line2);
  }

  static String _valueFor(_ValueKey k, HomeGreetingSignals s) {
    switch (k) {
      case _ValueKey.name:
        final name = (s.displayName ?? '').trim();
        return name.isEmpty ? '여러분' : name;
      case _ValueKey.streakWeeks:
        return s.streakCount.toString();
      case _ValueKey.weekCount:
        return s.postsThisWeek.toString();
      case _ValueKey.month:
        return s.now.month.toString();
      case _ValueKey.year:
        return s.now.year.toString();
    }
  }

  // =========================
  // 문구 카탈로그(베리에이션)
  // =========================

  /// ✅ 상태별 "2줄 템플릿" 목록
  /// - 숫자 삽입 위치(weekCount, streakWeeks)는 line1에 고정
  /// - 강조(bold)는 템플릿이 결정(예: 숫자, 핵심 동사/형용사)
  static const Map<HomeGreetingState, List<_Template>> _templates = {
    HomeGreetingState.firstSignup: [
      _Template(
        line1: [_Part.literal('처음 오셨군요')],

        line2: [_Part.literal('첫 주를 시작해봐요')],
      ),
      _Template(
        line1: [_Part.literal('환영해요')],
        line2: [_Part.literal('첫 글을 남겨봐요')],
      ),
      _Template(
        line1: [
          _Part.value(_ValueKey.name), // 이름만 볼드
          _Part.literal('님 환영해요'),
        ],
        line2: [
          _Part.literal('가볍게 '),
          _Part.literal('한 줄부터 시작해요', bold: true), // 핵심만 볼드
        ],
      ),
    ],

    HomeGreetingState.empty: [
      _Template(
        line1: [_Part.literal('아직 기록이 없어요')],
        line2: [_Part.literal('첫 주를 채워봐요')],
      ),
      _Template(
        line1: [_Part.literal('빈 칸이네요')],
        line2: [
          _Part.literal('오늘 '),
          _Part.literal('한 줄부터 시작해요', bold: true), // 핵심만 볼드
        ],
      ),
      _Template(
        line1: [_Part.literal('시작은 가볍게')],
        line2: [_Part.literal('한 줄이면 충분해요')],
      ),
    ],

    HomeGreetingState.weekNone: [
      _Template(
        line1: [
          _Part.literal('이번 주 '),
          _Part.value(_ValueKey.weekCount, bold: true), // 숫자만 볼드
          _Part.literal('개 기록'),
        ],
        line2: [_Part.literal('이번 주도 한 번만')],
      ),
      _Template(
        line1: [_Part.literal('이번 주는 아직 조용해요')],
        line2: [
          _Part.literal('지금 '),
          _Part.literal('한 줄', bold: true), // 핵심만 볼드
          _Part.literal(' 남기기'),
        ],
      ),
      _Template(
        line1: [_Part.literal('이번 주, 아직 늦지 않아요')],
        line2: [_Part.literal('오늘로 시작해요')],
      ),
    ],

    HomeGreetingState.weekSome: [
      _Template(
        line1: [
          _Part.value(_ValueKey.weekCount, bold: true), // 숫자만 볼드
          _Part.literal('개 기록했어요'),
        ],
        line2: [_Part.literal('흐름을 이어가요')],
      ),
      _Template(
        line1: [_Part.literal('이번 주도 좋은 시작')],
        line2: [_Part.literal('조금만 더 채워봐요')],
      ),
      _Template(
        line1: [_Part.literal('페이스 좋아요')],
        line2: [_Part.literal('이번 주를 진하게')],
      ),
    ],

    HomeGreetingState.loyalStreak: [
      // 스크린샷 스타일: "2주 연속 기록" / "더 진하게 만들어봐요"
      _Template(
        line1: [
          _Part.value(_ValueKey.streakWeeks, bold: true), // 숫자만 볼드
          _Part.literal('주 연속 기록'),
        ],
        line2: [
          _Part.literal('더 '),
          _Part.literal('진하게', bold: true), // 핵심만 볼드
          _Part.literal(' 만들어봐요'),
        ],
      ),
      _Template(
        line1: [
          _Part.value(_ValueKey.streakWeeks, bold: true), // 숫자만 볼드
          _Part.literal('주 연속 유지 중'),
        ],
        line2: [_Part.literal('이번 주도 완주 가자')],
      ),
      _Template(
        line1: [
          _Part.value(_ValueKey.streakWeeks, bold: true), // 숫자만 볼드
          _Part.literal('주째 꾸준함'),
        ],
        line2: [_Part.literal('이 흐름, 놓치지 마요')],
      ),
    ],

    HomeGreetingState.comeback: [
      _Template(
        line1: [_Part.literal('오랜만이에요 돌아오셨네요')],
        line2: [_Part.literal('이번 주부터 다시')],
      ),
      _Template(
        line1: [_Part.literal('복귀 환영해요')],
        line2: [
          _Part.literal('부담 없이 '),
          _Part.literal('오늘만', bold: true), // 핵심만 볼드
        ],
      ),
      _Template(
        line1: [_Part.literal('다시 시작하는 순간부터')],
        line2: [_Part.literal('흐름은 복구돼요')],
      ),
    ],

    HomeGreetingState.timeMeta: [
      _Template(
        line1: [
          _Part.value(_ValueKey.month, bold: true), // 숫자만 볼드
          _Part.literal('월도 벌써'),
        ],
        line2: [
          _Part.literal('오늘을 '),
          _Part.literal('한 줄로', bold: true), // 핵심만 볼드
        ],
      ),
      _Template(
        line1: [_Part.literal('시간이 참 빠르네요')],
        line2: [_Part.literal('지금의 나를 남겨봐요')],
      ),
    ],

    HomeGreetingState.misc: [
      _Template(
        line1: [_Part.literal('안녕하세요')],
        line2: [
          _Part.literal('오늘도 '),
          _Part.literal('한 줄', bold: true), // 핵심만 볼드
          _Part.literal(' 남겨봐요'),
        ],
      ),
      _Template(
        line1: [_Part.literal('반가워요')],
        line2: [_Part.literal('가볍게 시작해요')],
      ),
      _Template(
        line1: [_Part.value(_ValueKey.name, bold: true)], // 이름만 볼드
        line2: [_Part.literal('잠깐만 들렀다 가도 좋아요')],
      ),
    ],
  };

  static const List<_Template> _timeMetaMonthEnd = [
    _Template(
      line1: [_Part.literal('이번 달도 막바지')],
      line2: [
        _Part.literal('남은 며칠, '),
        _Part.literal('진하게', bold: true), // 핵심만 볼드
      ],
    ),
    _Template(
      line1: [_Part.literal('이번 달의 마지막 페이지')],
      line2: [_Part.literal('한 줄로 마무리해요')],
    ),
  ];

  static const List<_Template> _timeMetaMidMonth = [
    _Template(
      line1: [_Part.literal('벌써 월 중반')],
      line2: [_Part.literal('이번 달도 채워봐요')],
    ),
    _Template(
      line1: [_Part.literal('이번 달 절반쯤')],
      line2: [_Part.literal('지금부터 시작해요')],
    ),
  ];

  static const List<_Template> _timeMetaYearEnd = [
    _Template(
      line1: [_Part.literal('올해도 이제 얼마 안 남았어요')],
      line2: [_Part.literal('마지막까지 기록해요')],
    ),
    _Template(
      line1: [_Part.literal('올해의 마무리')],
      line2: [_Part.literal('지금의 나를 남겨봐요')],
    ),
  ];
}
