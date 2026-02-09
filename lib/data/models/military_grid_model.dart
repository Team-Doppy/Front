/// 군인 그리드 API 응답 모델
class MilitaryGridResponse {
  final List<Phase> phases;
  final String greetingKey;
  final List<String> availablePhases; // 조회 가능한 phase 코드 목록
  final String? currentPhase; // 이번 응답의 phase

  MilitaryGridResponse({
    required this.phases,
    required this.greetingKey,
    this.availablePhases = const [],
    this.currentPhase,
  });

  factory MilitaryGridResponse.fromJson(Map<String, dynamic> json) {
    return MilitaryGridResponse(
      phases:
          (json['phases'] as List? ?? [])
              .map((p) => Phase.fromJson(p as Map<String, dynamic>))
              .toList(),
      greetingKey:
          json['greetingKey'] as String? ?? 'military.greeting.default',
      availablePhases:
          (json['availablePhases'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      currentPhase: json['currentPhase'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'phases': phases.map((p) => p.toJson()).toList(),
      'greetingKey': greetingKey,
      'availablePhases': availablePhases,
      if (currentPhase != null) 'currentPhase': currentPhase,
    };
  }
}

/// 복무 단계 (Phase)
class Phase {
  final String phase; // preEnlistment, training, private, etc.
  final String labelKey; // phase.preEnlistment, phase.training, etc.
  final int slotCount; // 해당 단계의 총 주차 수
  final List<Cell> cells; // 주 단위 셀 목록
  final String? gridKey; // 그리드 키 (서버에서 추가된 필드)

  Phase({
    required this.phase,
    required this.labelKey,
    required this.slotCount,
    required this.cells,
    this.gridKey,
  });

  factory Phase.fromJson(Map<String, dynamic> json) {
    return Phase(
      phase: json['phase'] as String,
      labelKey: json['labelKey'] as String,
      slotCount: json['slotCount'] as int? ?? 0,
      cells:
          (json['cells'] as List? ?? [])
              .map((c) => Cell.fromJson(c as Map<String, dynamic>))
              .toList(),
      gridKey: json['gridKey'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'phase': phase,
      'labelKey': labelKey,
      'slotCount': slotCount,
      'cells': cells.map((c) => c.toJson()).toList(),
      if (gridKey != null) 'gridKey': gridKey,
    };
  }
}

/// 그리드 셀 (주 단위)
class Cell {
  final int slotIndex; // 단계 내 N주차 (1-based)
  final int year; // 연도
  final int week; // 주차 (1-53)
  final bool currentWeek; // 이번 주가 속한 셀인지 여부
  final List<PostMeta> myPosts; // 해당 셀의 포스트 메타

  Cell({
    required this.slotIndex,
    required this.year,
    required this.week,
    required this.currentWeek,
    required this.myPosts,
  });

  factory Cell.fromJson(Map<String, dynamic> json) {
    return Cell(
      slotIndex: json['slotIndex'] as int? ?? 0,
      year: json['year'] as int? ?? 0, // ✅ null일 수 있으므로 기본값 0
      week: json['week'] as int? ?? 0, // ✅ null일 수 있으므로 기본값 0
      currentWeek: json['currentWeek'] as bool? ?? false, // ✅ 이번 주가 속한 셀인지 여부
      myPosts:
          (json['myPosts'] as List? ?? [])
              .map((p) => PostMeta.fromJson(p as Map<String, dynamic>))
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slotIndex': slotIndex,
      'year': year,
      'week': week,
      'myPosts': myPosts.map((p) => p.toJson()).toList(),
    };
  }

  /// 포스트가 있는지 확인
  bool get hasPost => myPosts.isNotEmpty;

  /// 포스트 개수
  int get postCount => myPosts.length;
}

/// 포스트 메타 (그리드 셀에 표시되는 최소 정보)
class PostMeta {
  final String id;
  final String title;
  final String thumbnailUrl;
  final String?
  lifePhase; // MILITARY_LIFE, LEAVE_OR_PRE_ENLISTMENT, SUPPORT, null
  final String? author; // ✅ 포스트 작성자 username

  PostMeta({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    this.lifePhase,
    this.author,
  });

  factory PostMeta.fromJson(Map<String, dynamic> json) {
    return PostMeta(
      id: json['id'] as String,
      title: json['title'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String,
      lifePhase: json['lifePhase'] as String?,
      author: json['author'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      if (lifePhase != null) 'lifePhase': lifePhase,
      if (author != null) 'author': author,
    };
  }

  /// 휴가/입대 전 포스트인지 확인
  bool get isLeaveOrPreEnlistment => lifePhase == 'LEAVE_OR_PRE_ENLISTMENT';

  /// 부대 안 포스트인지 확인
  bool get isMilitaryLife => lifePhase == 'MILITARY_LIFE';

  /// 응원 포스트인지 확인
  bool get isSupport => lifePhase == 'SUPPORT';
}

/// Phase 코드 enum
enum PhaseCode {
  preEnlistment,
  training,
  private,
  privateFirstClass,
  corporal,
  sergeant,
}

/// Phase 코드 확장
extension PhaseCodeExtension on PhaseCode {
  String get name {
    switch (this) {
      case PhaseCode.preEnlistment:
        return 'preEnlistment';
      case PhaseCode.training:
        return 'training';
      case PhaseCode.private:
        return 'private';
      case PhaseCode.privateFirstClass:
        return 'privateFirstClass';
      case PhaseCode.corporal:
        return 'corporal';
      case PhaseCode.sergeant:
        return 'sergeant';
    }
  }

  static PhaseCode? fromString(String? value) {
    if (value == null) return null;
    for (final code in PhaseCode.values) {
      if (code.name == value) {
        return code;
      }
    }
    return null;
  }
}

/// LifePhase enum
enum LifePhase {
  militaryLife, // MILITARY_LIFE
  leaveOrPreEnlistment, // LEAVE_OR_PRE_ENLISTMENT
  support, // SUPPORT
}

/// LifePhase 확장
extension LifePhaseExtension on LifePhase {
  String get name {
    switch (this) {
      case LifePhase.militaryLife:
        return 'MILITARY_LIFE';
      case LifePhase.leaveOrPreEnlistment:
        return 'LEAVE_OR_PRE_ENLISTMENT';
      case LifePhase.support:
        return 'SUPPORT';
    }
  }

  static LifePhase? fromString(String? value) {
    if (value == null) return null;
    for (final phase in LifePhase.values) {
      if (phase.name == value) {
        return phase;
      }
    }
    return null;
  }
}
