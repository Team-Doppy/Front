import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Military Grid 그리팅 및 Phase 라벨 메시지
///
/// 새로운 시스템의 그리팅 키와 phase 라벨을 관리합니다.
class MilitaryGridMessages {
  // 앱 실행 중 메시지 캐시 (같은 앱 실행 중에는 동일한 메시지 유지)
  static final Map<String, String> _sessionCache = {};

  /// 한국어 그리팅 메시지 맵
  /// 키 형식: military.greeting.{phase} 또는 military.greeting.{phase}.{condition}
  /// Variation: baseKey.1, baseKey.2, baseKey.3 형식으로 여러 메시지 제공
  static const Map<String, String> koGreeting = {
    // ============================================================================
    // 입대 전 (preEnlistment)
    // ============================================================================
    'military.greeting.preEnlistment': '입대 전이에요\n지금 기록해두면 소중해질 거예요',
    'military.greeting.preEnlistment.1': '입대 전이에요\n지금 기록해두면 소중해질 거예요',
    'military.greeting.preEnlistment.2': '입대 전이에요\n추억을 남겨보세요',
    'military.greeting.preEnlistment.3': '입대 전이에요\n지금의 순간을 기록해요',
    'military.greeting.preEnlistment.monthLeft': 'D-30 이내\n입대가 다가와요',
    'military.greeting.preEnlistment.monthLeft.1': 'D-30 이내\n입대가 다가와요',
    'military.greeting.preEnlistment.monthLeft.2': 'D-30 이내\n곧 입대해요',
    'military.greeting.preEnlistment.monthLeft.3': 'D-30 이내\n입대 준비하세요',
    'military.greeting.preEnlistment.weekLeft': 'D-7 이내\n입대가 코앞이에요',
    'military.greeting.preEnlistment.weekLeft.1': 'D-7 이내\n입대가 코앞이에요',
    'military.greeting.preEnlistment.weekLeft.2': 'D-7 이내\n이제 정말 곧이에요',
    'military.greeting.preEnlistment.weekLeft.3': 'D-7 이내\n마지막 일주일이에요',
    'military.greeting.preEnlistment.soon': 'D-day\n입대일이에요',
    'military.greeting.preEnlistment.soon.1': 'D-day\n입대일이에요',
    'military.greeting.preEnlistment.soon.2': 'D-day\n오늘이 입대일이에요',
    'military.greeting.preEnlistment.soon.3': 'D-day\n드디어 입대하는 날이에요',

    // ============================================================================
    // 훈련소 (training)
    // ============================================================================
    'military.greeting.training': '훈련소에 있어요\n힘든 시간 기록해봐요',
    'military.greeting.training.1': '훈련소에 있어요\n힘든 시간 기록해봐요',
    'military.greeting.training.2': '훈련소에 있어요\n잘 버티고 있어요',
    'military.greeting.training.3': '훈련소에 있어요\n조금씩 적응하고 있어요',
    'military.greeting.training.week1': '훈련소 1주차\n잘 버티고 있어요',
    'military.greeting.training.week1.1': '훈련소 1주차\n잘 버티고 있어요',
    'military.greeting.training.week1.2': '훈련소 1주차\n첫 주를 보내고 있어요',
    'military.greeting.training.week1.3': '훈련소 1주차\n힘들지만 버티고 있어요',
    'military.greeting.training.week2': '훈련소 2주차\n조금씩 익숙해질 거예요',
    'military.greeting.training.week2.1': '훈련소 2주차\n조금씩 익숙해질 거예요',
    'military.greeting.training.week2.2': '훈련소 2주차\n이제 조금씩 적응했어요',
    'military.greeting.training.week2.3': '훈련소 2주차\n반이 지나갔어요',
    'military.greeting.training.week3': '훈련소 3주차\n거의 다 왔어요',
    'military.greeting.training.week3.1': '훈련소 3주차\n거의 다 왔어요',
    'military.greeting.training.week3.2': '훈련소 3주차\n마지막 주가 다가와요',
    'military.greeting.training.week3.3': '훈련소 3주차\n조금만 더 버티면 돼요',
    'military.greeting.training.week4': '훈련소 4주차\n마지막 주예요',
    'military.greeting.training.week4.1': '훈련소 4주차\n마지막 주예요',
    'military.greeting.training.week4.2': '훈련소 4주차\n곧 끝나요',
    'military.greeting.training.week4.3': '훈련소 4주차\n마지막이에요',

    // ============================================================================
    // 이병 (private)
    // ============================================================================
    'military.greeting.private': '이병이에요\n이제 조금씩 익숙해질 거예요',
    'military.greeting.private.1': '이병이에요\n이제 조금씩 익숙해질 거예요',
    'military.greeting.private.2': '이병이에요\n군생활에 적응 중이에요',
    'military.greeting.private.3': '이병이에요\n새로운 시작이에요',

    // ============================================================================
    // 일병 (privateFirstClass)
    // ============================================================================
    'military.greeting.privateFirstClass': '일병이에요\n멋진 군생활을 기대해요',
    'military.greeting.privateFirstClass.1': '일병이에요\n멋진 군생활을 기대해요',
    'military.greeting.privateFirstClass.2': '일병이에요\n이제 좀 더 자유로워요',
    'military.greeting.privateFirstClass.3': '일병이에요\n군생활이 익숙해졌어요',

    // ============================================================================
    // 상병 (corporal)
    // ============================================================================
    'military.greeting.corporal': '상병이에요\n선임이 되어가고 있어요',
    'military.greeting.corporal.1': '상병이에요\n선임이 되어가고 있어요',
    'military.greeting.corporal.2': '상병이에요\n후임들을 이끌고 있어요',
    'military.greeting.corporal.3': '상병이에요\n책임감이 커졌어요',

    // ============================================================================
    // 병장 (sergeant)
    // ============================================================================
    'military.greeting.sergeant': '병장이에요\n최고 계급이에요',
    'military.greeting.sergeant.1': '병장이에요\n최고 계급이에요',
    'military.greeting.sergeant.2': '병장이에요\n군생활의 마지막 단계예요',
    'military.greeting.sergeant.3': '병장이에요\n곧 전역이 보여요',

    // ============================================================================
    // 지나간 phase 조회 시 (past)
    // ============================================================================
    'military.greeting.past.training': '훈련소였어요\n그때의 추억이에요',
    'military.greeting.past.training.1': '훈련소였어요\n그때의 추억이에요',
    'military.greeting.past.training.2': '훈련소였어요\n힘들었던 시간이에요',
    'military.greeting.past.training.3': '훈련소였어요\n지나간 시간이에요',
    'military.greeting.past.private': '이병이었어요\n그때의 추억이에요',
    'military.greeting.past.private.1': '이병이었어요\n그때의 추억이에요',
    'military.greeting.past.private.2': '이병이었어요\n처음이었던 시간이에요',
    'military.greeting.past.private.3': '이병이었어요\n지나간 시간이에요',
    'military.greeting.past.privateFirstClass': '일병이었어요\n그때의 추억이에요',
    'military.greeting.past.privateFirstClass.1': '일병이었어요\n그때의 추억이에요',
    'military.greeting.past.privateFirstClass.2': '일병이었어요\n익숙해지던 시간이에요',
    'military.greeting.past.privateFirstClass.3': '일병이었어요\n지나간 시간이에요',
    'military.greeting.past.corporal': '상병이었어요\n그때의 추억이에요',
    'military.greeting.past.corporal.1': '상병이었어요\n그때의 추억이에요',
    'military.greeting.past.corporal.2': '상병이었어요\n선임이 되던 시간이에요',
    'military.greeting.past.corporal.3': '상병이었어요\n지나간 시간이에요',
    'military.greeting.past.sergeant': '병장이었어요\n그때의 추억이에요',
    'military.greeting.past.sergeant.1': '병장이었어요\n그때의 추억이에요',
    'military.greeting.past.sergeant.2': '병장이었어요\n최고 계급이었던 시간이에요',
    'military.greeting.past.sergeant.3': '병장이었어요\n지나간 시간이에요',

    // ============================================================================
    // 전역 관련
    // ============================================================================
    'military.greeting.dischargeSoon': 'D-30 이내\n전역이 보인다 뽀오오!',
    'military.greeting.dischargeSoon.1': 'D-30 이내\n전역이 보인다 뽀오오!',
    'military.greeting.dischargeSoon.2': 'D-30 이내\n곧 전역해요',
    'military.greeting.dischargeSoon.3': 'D-30 이내\n마지막 한 달이에요',
    'military.greeting.discharged': '전역했어요\n고생 많았어요',
    'military.greeting.discharged.1': '전역했어요\n고생 많았어요',
    'military.greeting.discharged.2': '전역했어요\n수고하셨어요',
    'military.greeting.discharged.3': '전역했어요\n새로운 시작이에요',

    // ============================================================================
    // 폴백
    // ============================================================================
    'military.greeting.default': '이번 주도 기록해봐요\n한 번만 채워도 돼요',
    'military.greeting.default.1': '이번 주도 기록해봐요\n한 번만 채워도 돼요',
    'military.greeting.default.2': '이번 주도 기록해봐요\n작은 기록도 소중해요',
    'military.greeting.default.3': '이번 주도 기록해봐요\n하나씩 채워가요',

    // ============================================================================
    // 여친 뷰 (곰신이 남친 그리드 조회 시)
    // ============================================================================
    // 입대 전
    'military.greeting.girlfriend.preEnlistment': '남친이 입대 전이에요\n지금 기록해두면 소중해질 거예요',
    'military.greeting.girlfriend.preEnlistment.1': '남친이 입대 전이에요\n지금 기록해두면 소중해질 거예요',
    'military.greeting.girlfriend.preEnlistment.2': '남친이 입대 전이에요\n추억을 남겨보세요',
    'military.greeting.girlfriend.preEnlistment.3': '남친이 입대 전이에요\n지금의 순간을 기록해요',
    
    // 훈련소
    'military.greeting.girlfriend.training': '남친이 훈련소에 있어요\n힘든 시간 잘 버티고 있어요',
    'military.greeting.girlfriend.training.1': '남친이 훈련소에 있어요\n힘든 시간 잘 버티고 있어요',
    'military.greeting.girlfriend.training.2': '남친이 훈련소에 있어요\n잘 버티고 있어요',
    'military.greeting.girlfriend.training.3': '남친이 훈련소에 있어요\n조금씩 적응하고 있어요',
    'military.greeting.girlfriend.training.week1': '남친이 훈련소 1주차예요\n잘 버티고 있어요',
    'military.greeting.girlfriend.training.week1.1': '남친이 훈련소 1주차예요\n잘 버티고 있어요',
    'military.greeting.girlfriend.training.week1.2': '남친이 훈련소 1주차예요\n첫 주를 보내고 있어요',
    'military.greeting.girlfriend.training.week1.3': '남친이 훈련소 1주차예요\n힘들지만 버티고 있어요',
    
    // 이병
    'military.greeting.girlfriend.private': '남친이 이병이에요\n이제 조금씩 익숙해질 거예요',
    'military.greeting.girlfriend.private.1': '남친이 이병이에요\n이제 조금씩 익숙해질 거예요',
    'military.greeting.girlfriend.private.2': '남친이 이병이에요\n군생활에 적응 중이에요',
    'military.greeting.girlfriend.private.3': '남친이 이병이에요\n새로운 시작이에요',
    
    // 일병
    'military.greeting.girlfriend.privateFirstClass': '남친이 일병이에요\n멋진 군생활을 기대해요',
    'military.greeting.girlfriend.privateFirstClass.1': '남친이 일병이에요\n멋진 군생활을 기대해요',
    'military.greeting.girlfriend.privateFirstClass.2': '남친이 일병이에요\n이제 좀 더 자유로워요',
    'military.greeting.girlfriend.privateFirstClass.3': '남친이 일병이에요\n군생활이 익숙해졌어요',
    
    // 상병
    'military.greeting.girlfriend.corporal': '남친이 상병이에요\n선임이 되어가고 있어요',
    'military.greeting.girlfriend.corporal.1': '남친이 상병이에요\n선임이 되어가고 있어요',
    'military.greeting.girlfriend.corporal.2': '남친이 상병이에요\n후임들을 이끌고 있어요',
    'military.greeting.girlfriend.corporal.3': '남친이 상병이에요\n책임감이 커졌어요',
    
    // 병장
    'military.greeting.girlfriend.sergeant': '남친이 병장이에요\n최고 계급이에요',
    'military.greeting.girlfriend.sergeant.1': '남친이 병장이에요\n최고 계급이에요',
    'military.greeting.girlfriend.sergeant.2': '남친이 병장이에요\n군생활의 마지막 단계예요',
    'military.greeting.girlfriend.sergeant.3': '남친이 병장이에요\n곧 전역이 보여요',
    
    // 지나간 phase 조회 시
    'military.greeting.girlfriend.past.training': '남친이 훈련소였어요\n그때의 추억이에요',
    'military.greeting.girlfriend.past.training.1': '남친이 훈련소였어요\n그때의 추억이에요',
    'military.greeting.girlfriend.past.training.2': '남친이 훈련소였어요\n힘들었던 시간이에요',
    'military.greeting.girlfriend.past.training.3': '남친이 훈련소였어요\n지나간 시간이에요',
    'military.greeting.girlfriend.past.private': '남친이 이병이었어요\n그때의 추억이에요',
    'military.greeting.girlfriend.past.private.1': '남친이 이병이었어요\n그때의 추억이에요',
    'military.greeting.girlfriend.past.private.2': '남친이 이병이었어요\n처음이었던 시간이에요',
    'military.greeting.girlfriend.past.private.3': '남친이 이병이었어요\n지나간 시간이에요',
    'military.greeting.girlfriend.past.privateFirstClass': '남친이 일병이었어요\n그때의 추억이에요',
    'military.greeting.girlfriend.past.privateFirstClass.1': '남친이 일병이었어요\n그때의 추억이에요',
    'military.greeting.girlfriend.past.privateFirstClass.2': '남친이 일병이었어요\n익숙해지던 시간이에요',
    'military.greeting.girlfriend.past.privateFirstClass.3': '남친이 일병이었어요\n지나간 시간이에요',
    'military.greeting.girlfriend.past.corporal': '남친이 상병이었어요\n그때의 추억이에요',
    'military.greeting.girlfriend.past.corporal.1': '남친이 상병이었어요\n그때의 추억이에요',
    'military.greeting.girlfriend.past.corporal.2': '남친이 상병이었어요\n선임이 되던 시간이에요',
    'military.greeting.girlfriend.past.corporal.3': '남친이 상병이었어요\n지나간 시간이에요',
    'military.greeting.girlfriend.past.sergeant': '남친이 병장이었어요\n그때의 추억이에요',
    'military.greeting.girlfriend.past.sergeant.1': '남친이 병장이었어요\n그때의 추억이에요',
    'military.greeting.girlfriend.past.sergeant.2': '남친이 병장이었어요\n최고 계급이었던 시간이에요',
    'military.greeting.girlfriend.past.sergeant.3': '남친이 병장이었어요\n지나간 시간이에요',
  };

  /// 한국어 Phase 라벨 맵
  /// 키 형식: phase.{phaseCode} 또는 phase.girlfriend.{phaseCode}
  static const Map<String, String> koPhaseLabel = {
    // 일반 (군인/입대예정)
    'phase.preEnlistment': '입대 전',
    'phase.training': '훈련소',
    'phase.private': '이병',
    'phase.privateFirstClass': '일병',
    'phase.corporal': '상병',
    'phase.sergeant': '병장',
    
    // 여친 뷰 (곰신이 남친 그리드 조회 시) - 일반 라벨과 동일하게 표시
    'phase.girlfriend.preEnlistment': '입대 전',
    'phase.girlfriend.training': '훈련소',
    'phase.girlfriend.private': '이병',
    'phase.girlfriend.privateFirstClass': '일병',
    'phase.girlfriend.corporal': '상병',
    'phase.girlfriend.sergeant': '병장',
  };

  /// 그리팅 메시지 가져오기 (랜덤 variation 선택)
  /// [greetingKey] - 서버에서 받은 greetingKey (예: "military.greeting.preEnlistment")
  /// 앱 실행 시마다 한 번만 선택되며, 이전 앱 실행 시 보였던 메시지는 최대한 지양
  static Future<String?> getGreetingMessage(String greetingKey) async {
    // 1. 세션 캐시 확인 (같은 앱 실행 중에는 동일한 메시지 유지)
    if (_sessionCache.containsKey(greetingKey)) {
      return _sessionCache[greetingKey];
    }

    // 2. 기본 키 확인
    final baseMessage = koGreeting[greetingKey];
    if (baseMessage == null) {
      return null;
    }

    // 3. Variation 키들 수집 (baseKey.1, baseKey.2, baseKey.3)
    final variations = <String>[];
    variations.add(greetingKey); // 기본 키도 포함

    for (int i = 1; i <= 3; i++) {
      final variationKey = '$greetingKey.$i';
      if (koGreeting.containsKey(variationKey)) {
        variations.add(variationKey);
      }
    }

    // 4. 이전 앱 실행 시 보였던 메시지 가져오기
    final recentMessages = await _getRecentMessages(greetingKey);

    // 5. 최근 메시지 제외하고 선택 가능한 메시지 필터링
    final availableMessages =
        variations.where((key) => !recentMessages.contains(key)).toList();

    // 6. 사용 가능한 메시지가 없으면 (모두 최근에 사용됨) 전체 목록 사용
    final candidates =
        availableMessages.isNotEmpty ? availableMessages : variations;

    // 7. 랜덤 선택
    final selectedKey = candidates[Random().nextInt(candidates.length)];

    // 8. 선택된 메시지 가져오기
    final selectedMessage = koGreeting[selectedKey];

    // 9. 세션 캐시에 저장 (같은 앱 실행 중에는 동일한 메시지 유지)
    if (selectedMessage != null) {
      _sessionCache[greetingKey] = selectedMessage;

      // 10. 최근 메시지에 추가 (다음 앱 실행 시 지양하기 위해)
      await _addRecentMessage(greetingKey, selectedKey);
    }

    return selectedMessage;
  }

  /// 최근 메시지 가져오기 (이전 앱 실행 시 보였던 메시지)
  static Future<List<String>> _getRecentMessages(String baseKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'military_greeting_recent_$baseKey';
      return prefs.getStringList(key) ?? [];
    } catch (e) {
      debugPrint('[MilitaryGridMessages] 최근 메시지 로드 실패: $e');
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
      final key = 'military_greeting_recent_$baseKey';
      final recent = prefs.getStringList(key) ?? [];

      // 이미 있으면 제거하고 맨 앞에 추가
      recent.remove(messageKey);
      recent.insert(0, messageKey);

      // 최대 5개 유지
      if (recent.length > 5) {
        recent.removeRange(5, recent.length);
      }

      await prefs.setStringList(key, recent);
    } catch (e) {
      debugPrint('[MilitaryGridMessages] 최근 메시지 저장 실패: $e');
    }
  }

  /// Phase 라벨 가져오기
  /// [labelKey] - 서버에서 받은 labelKey (예: "phase.preEnlistment")
  static String? getPhaseLabel(String labelKey) {
    return koPhaseLabel[labelKey];
  }

  /// 그리팅 메시지 존재 여부 확인
  static bool hasGreetingMessage(String greetingKey) {
    return koGreeting.containsKey(greetingKey);
  }

  /// Phase 라벨 존재 여부 확인
  static bool hasPhaseLabel(String labelKey) {
    return koPhaseLabel.containsKey(labelKey);
  }
}
