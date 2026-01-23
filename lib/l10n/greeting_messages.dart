/// 인사말 메시지 로케일 (한국어) — 서버 GreetingSpec(tier, mode, timeMeta) 기준
///
/// 키 조회: greeting.{tier}.{mode}.{timeMeta} → greeting.{tier}.{mode}[.1~.6] → greeting.{tier} → greeting.default
/// timeMeta는 streakMaintained에만 사용. {{currentStreak}} 치환.
class GreetingMessages {
  /// 한국어 인사말 맵
  static const Map<String, String> ko = {
    // ============================================================================
    // 클라이언트 전용 (포스트 작성 직후, 서버 GreetingSpec 아님)
    // ============================================================================
    'greeting.client.postJustPublished.alreadyWritten': '이번 주도 기록했어요\n잘하고 있어요',
    'greeting.client.postJustPublished.alreadyWritten.1':
        '이번 주도 기록했어요\n좋은 페이스예요',
    'greeting.client.postJustPublished.alreadyWritten.2':
        '이번 주도 채웠어요\n계속 이어가볼까요?',
    'greeting.client.postJustPublished.alreadyWritten.3':
        '이번 주도 기록했어요\n흐름을 유지하고 있어요',
    'greeting.client.postJustPublished.alreadyWritten.4':
        '이번 주도 기록했어요\n좋은 습관이에요',
    'greeting.client.postJustPublished.alreadyWritten.5':
        '이번 주도 채웠어요\n계속 이어가볼까요?',
    'greeting.client.postJustPublished.alreadyWritten.6':
        '이번 주도 기록했어요\n멋진 기록이에요',

    'greeting.client.postJustPublished.firstWrittenThisWeek':
        '이번 주 첫 기록이에요\n좋은 시작이에요',
    'greeting.client.postJustPublished.firstWrittenThisWeek.1':
        '이번 주를 시작했어요\n한 번만 채워도 충분해요',
    'greeting.client.postJustPublished.firstWrittenThisWeek.2':
        '이번 주 첫 칸 채웠어요\n흐름을 이어가요',
    'greeting.client.postJustPublished.firstWrittenThisWeek.3':
        '이번 주는 어떤 일이 있나요?\n가볍게 기록해봐요',
    'greeting.client.postJustPublished.firstWrittenThisWeek.4':
        '이번 주도 출발했어요\n좋은 페이스예요',
    'greeting.client.postJustPublished.firstWrittenThisWeek.5':
        '이번 주 첫 기록\n이제 흐름이 생겼어요',

    'greeting.client.postJustPublished.weekendClutch': '주말에 딱 기록했어요\n아찔하게 채웠어요',
    'greeting.client.postJustPublished.weekendClutch.1':
        '주말 클러치 성공\n이번 주도 무사히 채웠어요',
    'greeting.client.postJustPublished.weekendClutch.2':
        '마지막 순간 기록\n이번 주도 무사히 지켰어요',
    'greeting.client.postJustPublished.weekendClutch.3':
        '주말에 한 방\n이번 주도 무사히 지켰어요',
    'greeting.client.postJustPublished.weekendClutch.4':
        '좋은 주말이에요!\n이번 주도 흐름을 만들어냈어요',
    'greeting.client.postJustPublished.weekendClutch.5': '주말에 기록 완료\n좋은 페이스에요',

    'greeting.client.postJustPublished.streakAchieved':
        '{{currentStreak}}주 연속 기록\n아찔하게 끝냈어요',
    'greeting.client.postJustPublished.streakAchieved.1':
        '{{currentStreak}}주 연속 기록\n아찔하게 끝냈어요',
    'greeting.client.postJustPublished.streakAchieved.2':
        '{{currentStreak}}주 연속 기록\n마지막 순간에 기록했어요',
    'greeting.client.postJustPublished.streakAchieved.3':
        '{{currentStreak}}주 연속 기록\n아슬아슬하게 유지했어요',
    'greeting.client.postJustPublished.streakAchieved.4':
        '{{currentStreak}}주 연속 기록\n마지막에 기록했어요',
    'greeting.client.postJustPublished.streakAchieved.5':
        '{{currentStreak}}주 연속 기록\n아찔하게 유지했어요',
    'greeting.client.postJustPublished.streakAchieved.6':
        '{{currentStreak}}주 연속 기록\n무사히 이어갔어요',

    // ============================================================================
    // 서버 GreetingSpec — 폴백
    // ============================================================================
    'greeting.default': '이번 주도 기록해봐요\n한 번만 채워도 돼요',

    // ============================================================================
    // tier: empty (기록 없음, posts_count=0)
    // ============================================================================
    'greeting.empty.weekQuiet': '이번 주는 아직 조용해요\n어떤 일이 있나요?',
    'greeting.empty.weekQuiet.1': '이번 주, 아직 늦지 않아요\n오늘로 시작해볼까요?',
    'greeting.empty.weekQuiet.2': '이번 주는 비어있어요\n재밌는 일 있었나요?',
    'greeting.empty.weekQuiet.3': '이번 주 시작해볼까요\n오늘 한 줄부터',
    'greeting.empty.weekQuiet.4': '이번 주는 조용하네요\n지금 기록 몇 줄 남기기!',
    'greeting.empty.weekQuiet.5': '이번 주는 아직 비어있어요\n흐름을 다시 시작해볼까요?',
    'greeting.empty.weekQuiet.6': '이번 주는 고요해요\n가볍게 한 줄부터 시작해봐요',

    'greeting.empty.longInactive': '오랜만이에요\n다시 시작해볼까요',
    'greeting.empty.longInactive.1': '반가워요 시작은 가볍게\n오늘 기록 시작해볼까요?',
    'greeting.empty.longInactive.2': '오랜만이에요\n그동안 재밌는 일 있었나요?',
    'greeting.empty.longInactive.3': '다시 만나니 좋아요\n그동안 어떤 일들이 있었나요?',

    'greeting.empty.comebackQuiet': '다시 시작했군요\n이번 주부터 다시',
    'greeting.empty.comebackQuiet.1': '복귀를 환영해요\n이번 주부터 다시 시작해볼까요?',

    'greeting.empty.reflectionEmpty': '이 해는 비어있었어요\n다음엔 기록 시작해볼까요?',
    'greeting.empty.reflectionEmpty.1': '이 해는 조용했네요\n다음 해부터 기록 시작해볼까요?',

    'greeting.empty': '시작은 가볍게\n이번 주 한 번만 기록해봐요',

    // ============================================================================
    // tier: early (1~4 posts)
    // ============================================================================
    'greeting.early.weekActive': '이번 주도 기록했어요\n이어가면 쌓일거에요',
    'greeting.early.weekActive.1': '이번 주도 채웠어요\n계속 이어가면 쌓일거에요',
    'greeting.early.weekActive.2': '이번 주도 기록했어요\n앞으로 쌓일 기록을 기대해봐요',
    'greeting.early.weekActive.3': '이번 주도 기록했어요\n흐름을 만들기 시작했어요',
    'greeting.early.weekActive.4': '이번 주도 채웠어요\n점점 쌓일거에요',
    'greeting.early.weekActive.5': '이번 주도 기록했어요\n앞으로 쌓일 기록을 기대해봐요',
    'greeting.early.weekActive.6': '이번 주도 기록했어요\n앞으로 쌓일 기록을 기대해봐요',

    'greeting.early.weekQuiet': '이번 주는 고요하네요\n흐름을 한 번만 이어가면 쌓일거에요',
    'greeting.early.weekQuiet.1': '이번 주는 조용해요\n어떤 일이 있나요?',
    'greeting.early.weekQuiet.2': '이번 주는 고요하네요\n지금 기록 몇 줄 남기기!',
    'greeting.early.weekQuiet.3': '이번 주는 아직 조용해요\n흐름을 한 번만 이어가면 쌓일거에요',
    'greeting.early.weekQuiet.4': '이번 주는 비어있어요\n흐름을 다시 이어가볼까요?',
    'greeting.early.weekQuiet.5': '이번 주는 조용하네요\n가볍게 기록해봐요',
    'greeting.early.weekQuiet.6': '이번 주는 고요해요\n오늘 기록 시작해볼까요?',

    'greeting.early.weekQuietStreakPossible': '이번 주만 채우면 돼요\n스트릭을 이어가요',
    'greeting.early.weekQuietStreakPossible.1': '한 번만 남기면 돼요\n연속 기록을 세워볼까요?',
    'greeting.early.weekQuietStreakPossible.2':
        '이번 주 아직 비어있어요\n가볍게 기록하고 스트릭 지키기',

    'greeting.early.longInactive': '이번 주는 아직 늦지 않아요\n오늘로 시작해볼까요?',
    'greeting.early.longInactive.1': '이번 주는 아직 조용해요\n지금 기록 몇 줄 남기기!',
    'greeting.early.longInactive.2': '이번 주는 비어있어요\n흐름을 다시 이어가볼까요?',

    'greeting.early.comebackActive': '다시 시작했어요\n다시 흐름을 만들어가요',
    'greeting.early.comebackActive.1': '복귀했어요\n정말 환영해요',
    'greeting.early.comebackQuiet': '다시 시작했어요\n이번 주부터 다시 쌓아볼까요?',
    'greeting.early.comebackQuiet.1': '{{currentStreak}}주차로 돌아왔어요\n이번 주부터 다시',

    'greeting.early.streakMaintained': '{{currentStreak}}주 연속 기록\n무사히 이어가고 있어요',
    'greeting.early.streakMaintained.1':
        '{{currentStreak}}주 연속 기록\n습관이 자리 잡고 있어요',
    'greeting.early.streakMaintained.2':
        '{{currentStreak}}주차 기록 중\n정말 좋은 페이스예요',
    'greeting.early.streakMaintained.3': '{{currentStreak}}주 연속 기록\n정말 대단해요',
    'greeting.early.streakMaintained.4': '{{currentStreak}}주 기록 중\n꾸준히 쌓일거에요',
    'greeting.early.streakMaintained.5':
        '{{currentStreak}}주 연속 기록\n습관이 만들어지고 있어요',
    'greeting.early.streakMaintained.6':
        '{{currentStreak}}주차 기록 중\n흐름이 정말  대단해요',

    'greeting.early.reflectionVeryActive': '{{year}}년은 꽤 바쁘게 기록했어요\n잘했어요',
    'greeting.early.reflectionActive': '{{year}}년은 꾸준히 썼네요\n정말 대단해요',
    'greeting.early.reflectionModerate': '{{year}}년은 조금씩 기록했어요',
    'greeting.early.reflectionModest': '{{year}}년은 소소하게 기록했어요',
    'greeting.early.reflectionModestStreak': '{{year}}년에도 잘 쌓아왔어요',
    'greeting.early.reflectionEmpty': '{{year}}년은 고요해요',

    'greeting.early': '{{currentStreak}}주 연속 기록\n무사히 이어가고 있어요',

    // ============================================================================
    // tier: growing (5~14 posts)
    // ============================================================================
    'greeting.growing.weekActive': '이번 주도 기록했어요\n이대로만 이어가면 쌓일거에요',
    'greeting.growing.weekActive.1': '이번 주도 채웠어요\n계속 이어가면 쌓일거에요',
    'greeting.growing.weekActive.2': '이번 주도 기록했어요\n흐름을 유지하고 있어요',
    'greeting.growing.weekActive.3': '이번 주도 기록했어요\n흐름을 만들어나가고 있어요',
    'greeting.growing.weekActive.4': '이번 주도 채웠어요\n잘하고 있어요 점점 쌓일거에요',
    'greeting.growing.weekActive.5': '이번 주도 기록했어요\n멋진 페이스인데요?',
    'greeting.growing.weekActive.6': '이번 주도 기록했어요\n꾸준히 쌓아나가요!',

    'greeting.growing.weekQuiet': '이번 주는 고요하네요\n흐름을 한 번만 이어가면 쌓일거에요',
    'greeting.growing.weekQuiet.1': '이번 주는 조용해요\n조용한 나름의 여유가 있죠',
    'greeting.growing.weekQuiet.2': '이번 주는 고요하네요\n지금 기록 몇 줄 남기기!',
    'greeting.growing.weekQuiet.3': '이번 주는 아직 조용해요\n흐름을 이어가면 쌓일거에요',
    'greeting.growing.weekQuiet.4': '이번 주는 비어있어요\n흐름을 다시 이어가볼까요?',
    'greeting.growing.weekQuiet.5': '이번 주는 조용하네요\n가볍게 기록해봐요',
    'greeting.growing.weekQuiet.6': '이번 주는 고요해요\n어떤 일이 있었나요?',

    'greeting.growing.weekQuietStreakPossible': '이번 주만 채우면 돼요\n스트릭을 이어가요',
    'greeting.growing.weekQuietStreakPossible.1': '한 번만 남기면 돼요\n연속 기록 유지',
    'greeting.growing.weekQuietStreakPossible.2': '이번 주 아직 비어있어요\n소중한 스트릭 지키기',

    'greeting.growing.longInactive': '이번 주는 아직 늦지 않아요\n오늘로 시작해요',
    'greeting.growing.longInactive.1': '이번 주는 아직 조용해요\n지금 한 줄 남기기',
    'greeting.growing.longInactive.2': '이번 주는 비어있어요\n한 줄만 채워봐요',

    'greeting.growing.comebackActive': '{{currentStreak}}주차로 돌아왔어요\n이번 주부터 다시',
    'greeting.growing.comebackActive.1': '다시 시작했어요\n흐름을 복구해요',
    'greeting.growing.comebackQuiet': '{{currentStreak}}주차로 돌아왔어요\n이번 주부터 다시',
    'greeting.growing.comebackQuiet.1': '복귀했어요\n이번 주부터 다시',

    'greeting.growing.streakMaintained': '{{currentStreak}}주 연속 기록\n좋은 페이스예요',
    'greeting.growing.streakMaintained.1': '{{currentStreak}}주 연속 기록\n잘하고 있어요',
    'greeting.growing.streakMaintained.2':
        '{{currentStreak}}주차 기록 중\n이번 주도 한 번만',
    'greeting.growing.streakMaintained.3': '{{currentStreak}}주 연속 기록\n흐름을 이어가요',
    'greeting.growing.streakMaintained.4': '{{currentStreak}}주 기록 중\n계속 이어가요',
    'greeting.growing.streakMaintained.5': '{{currentStreak}}주 연속 기록\n좋은 습관이에요',
    'greeting.growing.streakMaintained.6':
        '{{currentStreak}}주차 기록 중\n이번 주도 채워봐요',

    'greeting.growing.reflectionVeryActive': '{{year}}년은 꽤 바쁘게 기록했어요\n잘했어요',
    'greeting.growing.reflectionActive': '{{year}}년은 꾸준히 썼던 편이에요',
    'greeting.growing.reflectionModerate': '{{year}}년은 조금씩 남겼어요',
    'greeting.growing.reflectionModest': '{{year}}년은 소소하게 기록했어요',
    'greeting.growing.reflectionModestStreak': '{{year}}년은 잊지 않고 이어갔어요',
    'greeting.growing.reflectionEmpty': '{{year}}년은 비어있었어요',

    'greeting.growing': '{{currentStreak}}주 연속 기록\n이번 주도 한 번만',

    // ============================================================================
    // tier: stable (15+ posts, active_weeks 충족)
    // ============================================================================
    'greeting.stable.weekActive': '이번 주도 기록했어요\n이대로만 이어가면 쌓일거에요',
    'greeting.stable.weekActive.1': '이번 주도 채웠어요\n잘하고 있어요',
    'greeting.stable.weekActive.2': '이번 주도 기록했어요\n흐름을 만들어나가고 있어요',
    'greeting.stable.weekActive.3': '이번 주도 채웠어요\n잘하고 있어요 점점 쌓일거에요',
    'greeting.stable.weekActive.4': '이번 주도 기록했어요\n멋진 기록이에요',
    'greeting.stable.weekActive.5': '이번 주도 기록했어요\n꾸준히 하면서 1년뒤를 기대해봐요',

    'greeting.stable.weekQuiet': '이번 주는 고요하네요\n흐름을 한 번만 이어가면 쌓일거에요',
    'greeting.stable.weekQuiet.1': '이번 주는 조용해요\n조용한 나름의 여유가 있죠',
    'greeting.stable.weekQuiet.2': '이번 주는 고요하네요\n재밌는 일이 있었나요?',
    'greeting.stable.weekQuiet.3': '이번 주는 아직 조용해요\n한 번만 남겨도 충분해요',
    'greeting.stable.weekQuiet.4': '이번 주는 비어있어요\n흐름을 다시 이어가볼까요?',
    'greeting.stable.weekQuiet.5': '이번 주는 조용하네요\n가볍게 기록해봐요',
    'greeting.stable.weekQuiet.6': '이번 주는 고요해요\n어떤 일이 있었나요?',

    'greeting.stable.weekQuietStreakPossible': '이번 주만 채우면 돼요\n스트릭을 이어가요',
    'greeting.stable.weekQuietStreakPossible.1': '한 번만 남기면 돼요\n이 흐름 놓치지 마요',
    'greeting.stable.weekQuietStreakPossible.2': '이번 주 아직 비어있어요\n한 줄로 스트릭 지키기',

    'greeting.stable.longInactive': '이번 주는 아직 조용해요\n지금 한 줄 남기기',
    'greeting.stable.longInactive.1': '이번 주는 아직 늦지 않아요\n오늘로 시작해요',
    'greeting.stable.longInactive.2': '이번 주는 비어있어요\n한 줄만 채워봐요',

    'greeting.stable.comebackActive': '{{currentStreak}}주차로 돌아왔어요\n여전히 꾸준하시네요',
    'greeting.stable.comebackActive.1': '다시 시작했어요\n이번 주부터 다시 쌓아볼까요?',
    'greeting.stable.comebackQuiet':
        '{{currentStreak}}주차로 돌아왔어요\n이번 주부터 다시 쌓아볼까요?',
    'greeting.stable.comebackQuiet.1': '복귀했어요\n다시 흐름을 만들어가요',

    'greeting.stable.streakMaintained': '{{currentStreak}}주 연속 기록\n꾸준함이 멋져요',
    'greeting.stable.streakMaintained.1': '{{currentStreak}}주 연속 기록\n잘하고 있어요',
    'greeting.stable.streakMaintained.2':
        '{{currentStreak}}주 연속 유지 중\n이번 주도 완주',
    'greeting.stable.streakMaintained.3': '{{currentStreak}}주 연속 기록\n흐름을 이어가요',
    'greeting.stable.streakMaintained.4': '{{currentStreak}}주 기록 중\n계속 이어가요',
    'greeting.stable.streakMaintained.5': '{{currentStreak}}주 연속 기록\n좋은 습관이에요',
    'greeting.stable.streakMaintained.6':
        '{{currentStreak}}주차 기록 중\n이번 주도 채워봐요',

    'greeting.stable.reflectionVeryActive': '{{year}}년은\n꽤 바쁘게 기록했어요',
    'greeting.stable.reflectionActive': '{{year}}년은\n꾸준히 썼네요',
    'greeting.stable.reflectionModerate': '{{year}}년은 조금씩 남겼어요',
    'greeting.stable.reflectionModest': '{{year}}년은\n소소하게 기록했어요',
    'greeting.stable.reflectionModestStreak': '{{year}}년은\n잊지 않고 이어갔어요',
    'greeting.stable.reflectionEmpty': '{{year}}년은\n비어있었어요',

    'greeting.stable': '{{currentStreak}}주 연속 기록\n이 흐름 놓치지 마요',

    // ============================================================================
    // timeMeta (streakMaintained만, early / growing / stable)
    // ============================================================================
    'greeting.early.streakMaintained.MONTH_START':
        '새로운 달이 시작되었어요\n이번 달도 파이팅해봐요',
    'greeting.early.streakMaintained.MID_MONTH': '벌써 월 중반\n이번 달도 채워봐요',
    'greeting.early.streakMaintained.MONTH_END': '이번 달 막바지\n남은 며칠 기록해요',
    'greeting.early.streakMaintained.YEAR_END': '올해도 이제 얼마 안 남았어요\n마지막까지 기록해요',

    'greeting.growing.streakMaintained.MONTH_START':
        '새로운 달이 시작되었어요\n이번 달도 파이팅해봐요',
    'greeting.growing.streakMaintained.MID_MONTH': '벌써 이번 달도 반 해냈어요\n꾸준히 쌓아나가요',
    'greeting.growing.streakMaintained.MONTH_END': '이번 달도 막바지!\n남은 며칠도 채워나가요',
    'greeting.growing.streakMaintained.YEAR_END':
        '올해도 이제 얼마 안 남았어요\n마지막까지 채워나가요',

    'greeting.stable.streakMaintained.MONTH_START': '이번 달 시작\n한 줄로 출발해요',
    'greeting.stable.streakMaintained.MID_MONTH':
        '벌써 월 중반\n{{currentStreak}}주 연속 기록 중',
    'greeting.stable.streakMaintained.MONTH_END':
        '이번 달도 막바지\n{{currentStreak}}주 연속 기록 중',
    'greeting.stable.streakMaintained.YEAR_END':
        '올해의 마무리\n{{currentStreak}}주 연속 기록 중',
  };

  /// GreetingSpec(tier, mode, timeMeta)으로 메시지 키 후보를 순서대로 반환 (있으면 사용, 없으면 다음)
  static List<String> resolveKeyCandidates(
    String tier,
    String mode,
    String? timeMeta,
  ) {
    final List<String> out = [];
    final bool useTimeMeta =
        (timeMeta != null && timeMeta != 'NONE' && mode == 'streakMaintained');
    if (useTimeMeta) {
      out.add('greeting.$tier.$mode.$timeMeta');
    }
    out.add('greeting.$tier.$mode');
    for (int i = 1; i <= 6; i++) out.add('greeting.$tier.$mode.$i');
    out.add('greeting.$tier');
    out.add('greeting.default');
    return out;
  }

  /// 후보 중 존재하는 첫 키의 메시지 반환. {{currentStreak}}는 [currentStreak]로 치환.
  static String? getMessageForSpec(
    String tier,
    String mode,
    String? timeMeta,
    int? currentStreak, {
    String languageCode = 'ko',
  }) {
    final map = languageCode == 'ko' ? ko : <String, String>{};
    for (final k in resolveKeyCandidates(tier, mode, timeMeta)) {
      final raw = map[k];
      if (raw == null || raw.isEmpty) continue;
      return raw.replaceAll('{{currentStreak}}', '${currentStreak ?? 0}');
    }
    return null;
  }

  /// [key]에 해당하는 메시지. {{currentStreak}}는 호출측에서 치환.
  static String? getMessage(String key, {String languageCode = 'ko'}) {
    if (languageCode == 'ko') return ko[key];
    return null;
  }

  static bool hasMessage(String key, {String languageCode = 'ko'}) {
    if (languageCode == 'ko') return ko.containsKey(key);
    return false;
  }
}
