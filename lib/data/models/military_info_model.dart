import 'package:flutter/foundation.dart';

/// 군인 정보 모델
///
/// **서버 중심 구조**: 모든 데이터는 서버에서 관리되며, 클라이언트는 서버에서 받은 데이터를 그대로 사용합니다.
/// - 입대일, 진급일, 휴가 정보는 모두 서버에서 관리
/// - 클라이언트는 서버 응답을 그대로 표시하고, 변경 시 서버에 전송
class MilitaryInfo {
  /// 사용자 타입 (군인, 곰신, 가족)
  /// 서버에서 관리
  final UserType userType;

  /// 군종
  /// 서버에서 관리
  final MilitaryBranch branch;

  /// 입대 상태 (입대 전/입대 후)
  /// 서버에서 관리
  final MilitaryStatus status;

  /// 입대일 (입대 후인 경우 필수)
  /// 서버에서 관리 - 클라이언트는 서버에서 받은 값을 그대로 사용
  final DateTime? enlistmentDate;

  /// 현재 계급 (입대 후인 경우 필수)
  /// 서버에서 관리 - 클라이언트는 서버에서 받은 값을 그대로 사용
  final MilitaryRank? currentRank;

  /// 예정 입대일 (입대 전인 경우 필수)
  /// 서버에서 관리
  final DateTime? plannedEnlistmentDate;

  /// 연결된 군인 사용자 ID 목록
  /// - 곰신 모드: 1명만 (List.length == 1)
  /// - 가족 모드: 여러 명 가능 (List.length >= 1)
  /// 서버에서 관리
  final List<String>? connectedMilitaryUserIds;

  /// 수동 조정된 진급일 (계급별)
  /// key: 계급 이름, value: 진급일
  /// 서버에서 관리 - 클라이언트는 서버에서 받은 값을 그대로 사용
  final Map<String, DateTime>? manualPromotionDates;

  /// 전역일 (서버 계산값, 읽기 전용)
  /// 서버에서 입대일 + 군종별 복무 개월로 자동 계산
  final DateTime? dischargeDate;

  /// 다음 진급 예상일 (서버 계산값, 읽기 전용)
  /// 서버에서 입대일 및 수동 진급일 기준으로 자동 계산
  final DateTime? nextPromotionDate;

  /// 진급일 타임라인 (서버 계산값, 읽기 전용)
  /// 진급일 관리 UI용. military + afterEnlistment일 때만 채움
  /// 키: enlistment, trainingCompletion, privateFirstClass, corporal, sergeant, discharge
  /// 값: yyyy-MM-dd 형식의 날짜 문자열
  final Map<String, String>? promotionTimeline;

  MilitaryInfo({
    required this.userType,
    required this.branch,
    required this.status,
    this.enlistmentDate,
    this.currentRank,
    this.plannedEnlistmentDate,
    this.connectedMilitaryUserIds,
    this.manualPromotionDates,
    this.dischargeDate,
    this.nextPromotionDate,
    this.promotionTimeline,
  }) : assert(
         userType == UserType.military
             ? (status == MilitaryStatus.beforeEnlistment
                 ? plannedEnlistmentDate != null
                 : enlistmentDate != null) // 입대 후: 입대일만 필수 (계급은 서버에서 계산)
             : userType == UserType.plannedEnlistment
             ? plannedEnlistmentDate != null
             : (userType == UserType.girlfriend
                 ? (connectedMilitaryUserIds == null ||
                     connectedMilitaryUserIds.isEmpty ||
                     connectedMilitaryUserIds.length ==
                         1) // ✅ 곰신 모드: 빈 배열 또는 1명 연결 허용 (요청 보낸 직후 빈 배열 가능)
                 : true),
         '군인 모드일 때만 입대 전이면 예정 입대일이, 입대 후면 입대일이 필요합니다. '
         '곰신 모드는 0명(요청 대기) 또는 1명 연결되어야 합니다.',
       );

  /// JSON으로 변환 (서버 전송용)
  /// 주의: 휴가는 별도 API로 관리하므로 여기서는 포함하지 않음
  /// currentRank는 읽기 전용이므로 요청에 포함하지 않음
  Map<String, dynamic> toJson() {
    return {
      'userType': userType.name,
      'branch': branch.name,
      'status': status.name,
      'enlistmentDate': enlistmentDate?.toIso8601String(),
      // currentRank는 읽기 전용 (서버가 자동 계산) - 요청에 포함하지 않음
      'plannedEnlistmentDate': plannedEnlistmentDate?.toIso8601String(),
      'connectedMilitaryUserIds': connectedMilitaryUserIds,
      'manualPromotionDates': manualPromotionDates?.map(
        (key, value) => MapEntry(key, value.toIso8601String()),
      ),
      // dischargeDate, nextPromotionDate, promotionTimeline은 읽기 전용 - 요청에 포함하지 않음
      // vacations는 서버에서 별도로 관리하므로 toJson에는 포함하지 않음
    };
  }

  /// JSON에서 생성 (서버 응답용)
  /// 서버에서 받은 데이터를 그대로 사용합니다.
  factory MilitaryInfo.fromJson(Map<String, dynamic> json) {
    // ✅ 서버 응답에 nextPromotionDate와 dischargeDate가 포함되어 있는지 확인
    debugPrint(
      '[MilitaryInfo.fromJson] 서버 응답 확인: '
      'nextPromotionDate=${json['nextPromotionDate']}, '
      'dischargeDate=${json['dischargeDate']}, '
      '전체 키: ${json.keys.toList()}',
    );

    return MilitaryInfo(
      userType: UserType.values.firstWhere(
        (e) => e.name == json['userType'],
        orElse: () => UserType.military,
      ),
      branch: MilitaryBranch.values.firstWhere(
        (e) => e.name == json['branch'],
        orElse: () => MilitaryBranch.army,
      ),
      status: MilitaryStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MilitaryStatus.beforeEnlistment,
      ),
      enlistmentDate:
          json['enlistmentDate'] != null
              ? DateTime.parse(json['enlistmentDate'])
              : null,
      currentRank:
          json['currentRank'] != null
              ? MilitaryRank.values.firstWhere(
                (e) => e.name == json['currentRank'],
                orElse: () => MilitaryRank.trainee,
              )
              : null,
      plannedEnlistmentDate:
          json['plannedEnlistmentDate'] != null
              ? DateTime.parse(json['plannedEnlistmentDate'])
              : null,
      connectedMilitaryUserIds:
          json['connectedMilitaryUserIds'] != null
              ? List<String>.from(
                (json['connectedMilitaryUserIds'] as List).map(
                  (e) => e.toString(),
                ),
              )
              : (json['connectedMilitaryUserId'] != null
                  ? [json['connectedMilitaryUserId'] as String]
                  : null), // 하위 호환성: 단일 ID도 리스트로 변환
      manualPromotionDates:
          json['manualPromotionDates'] != null
              ? Map<String, DateTime>.from(
                (json['manualPromotionDates'] as Map).map(
                  (key, value) => MapEntry(
                    key.toString(),
                    DateTime.parse(value.toString()),
                  ),
                ),
              )
              : null,
      dischargeDate:
          json['dischargeDate'] != null
              ? DateTime.parse(json['dischargeDate'].toString())
              : null,
      nextPromotionDate:
          json['nextPromotionDate'] != null
              ? DateTime.parse(json['nextPromotionDate'].toString())
              : null,
      promotionTimeline:
          json['promotionTimeline'] != null
              ? Map<String, String>.from(
                (json['promotionTimeline'] as Map).map(
                  (key, value) => MapEntry(key.toString(), value.toString()),
                ),
              )
              : null,
    );
  }

  /// 복사 생성
  MilitaryInfo copyWith({
    UserType? userType,
    MilitaryBranch? branch,
    MilitaryStatus? status,
    DateTime? enlistmentDate,
    MilitaryRank? currentRank,
    DateTime? plannedEnlistmentDate,
    List<String>? connectedMilitaryUserIds,
    Map<String, DateTime>? manualPromotionDates,
    DateTime? dischargeDate,
    DateTime? nextPromotionDate,
    Map<String, String>? promotionTimeline,
  }) {
    return MilitaryInfo(
      userType: userType ?? this.userType,
      branch: branch ?? this.branch,
      status: status ?? this.status,
      enlistmentDate: enlistmentDate ?? this.enlistmentDate,
      currentRank: currentRank ?? this.currentRank,
      plannedEnlistmentDate:
          plannedEnlistmentDate ?? this.plannedEnlistmentDate,
      connectedMilitaryUserIds:
          connectedMilitaryUserIds ?? this.connectedMilitaryUserIds,
      manualPromotionDates: manualPromotionDates ?? this.manualPromotionDates,
      dischargeDate: dischargeDate ?? this.dischargeDate,
      nextPromotionDate: nextPromotionDate ?? this.nextPromotionDate,
      promotionTimeline: promotionTimeline ?? this.promotionTimeline,
    );
  }

  /// 특정 계급의 수동 조정된 진급일 가져오기
  DateTime? getManualPromotionDate(MilitaryRank rank) {
    return manualPromotionDates?[rank.name];
  }

  /// 특정 계급의 진급일 설정 (수동 조정)
  MilitaryInfo setManualPromotionDate(
    MilitaryRank rank,
    DateTime promotionDate,
  ) {
    final updated = Map<String, DateTime>.from(manualPromotionDates ?? {});
    updated[rank.name] = promotionDate;
    return copyWith(manualPromotionDates: updated);
  }

  /// 특정 계급의 수동 조정 제거
  MilitaryInfo removeManualPromotionDate(MilitaryRank rank) {
    final updated = Map<String, DateTime>.from(manualPromotionDates ?? {});
    updated.remove(rank.name);
    return copyWith(manualPromotionDates: updated.isEmpty ? null : updated);
  }

  /// 연결된 군인 사용자 ID 추가
  MilitaryInfo addConnectedMilitaryUserId(String userId) {
    final updated = List<String>.from(connectedMilitaryUserIds ?? []);
    if (!updated.contains(userId)) {
      updated.add(userId);
    }
    return copyWith(connectedMilitaryUserIds: updated);
  }

  /// 연결된 군인 사용자 ID 제거
  MilitaryInfo removeConnectedMilitaryUserId(String userId) {
    final updated = List<String>.from(connectedMilitaryUserIds ?? []);
    updated.remove(userId);
    return copyWith(connectedMilitaryUserIds: updated.isEmpty ? null : updated);
  }

  /// 연결된 군인 사용자 ID 목록 가져오기
  List<String> get connectedMilitaryUserIdsList =>
      connectedMilitaryUserIds ?? [];
}

/// 사용자 타입
enum UserType {
  military, // 군인 (입대 후, 전역 전)
  plannedEnlistment, // 입대 예정자
  girlfriend, // 곰신 (military_user_type = girlfriend)
  discharged, // 전역 후 (연결된 곰신 없음)
  dischargedWithPartner, // 꽃신 (전역 후 + 연결된 곰신 있음)
}

/// 사용자 타입 확장 메서드
extension UserTypeExtension on UserType {
  /// 사용자 타입 한글명
  String get displayName {
    switch (this) {
      case UserType.military:
        return '군인';
      case UserType.plannedEnlistment:
        return '입대 예정';
      case UserType.girlfriend:
        return '곰신';
      case UserType.discharged:
        return '전역';
      case UserType.dischargedWithPartner:
        return '꽃신';
    }
  }

  /// 서버 role 문자열로부터 UserType 생성
  ///
  /// 서버 role 값:
  /// - girlfriend: 곰신
  /// - plannedEnlistment: 입대예정
  /// - military: 군인
  /// - discharged: 전역 후
  /// - discharged_with_partner: 꽃신
  /// - null: 군 관련 정보 미입력 → null 반환
  static UserType? fromServerRole(String? role) {
    if (role == null || role.isEmpty) return null;

    switch (role.toLowerCase()) {
      case 'girlfriend':
        return UserType.girlfriend;
      case 'plannedenlistment':
        return UserType.plannedEnlistment;
      case 'military':
        return UserType.military;
      case 'discharged':
        return UserType.discharged;
      case 'discharged_with_partner':
        return UserType.dischargedWithPartner;
      default:
        return null;
    }
  }
}

/// 군종
enum MilitaryBranch {
  army, // 육군
  navy, // 해군
  airForce, // 공군
  marines, // 해병대
  other, // 기타
}

/// 입대 상태
enum MilitaryStatus {
  beforeEnlistment, // 입대 전
  afterEnlistment, // 입대 후
}

/// 계급
enum MilitaryRank {
  trainee, // 훈련병
  private, // 이병
  privateFirstClass, // 일병
  corporal, // 상병
  sergeant, // 병장
}

/// 계급 확장 메서드
extension MilitaryRankExtension on MilitaryRank {
  /// 계급 한글명
  String get displayName {
    switch (this) {
      case MilitaryRank.trainee:
        return '훈련병';
      case MilitaryRank.private:
        return '이병';
      case MilitaryRank.privateFirstClass:
        return '일병';
      case MilitaryRank.corporal:
        return '상병';
      case MilitaryRank.sergeant:
        return '병장';
    }
  }

  /// 다음 계급
  MilitaryRank? get nextRank {
    switch (this) {
      case MilitaryRank.trainee:
        return MilitaryRank.private;
      case MilitaryRank.private:
        return MilitaryRank.privateFirstClass;
      case MilitaryRank.privateFirstClass:
        return MilitaryRank.corporal;
      case MilitaryRank.corporal:
        return MilitaryRank.sergeant;
      case MilitaryRank.sergeant:
        return null; // 최고 계급
    }
  }
}

/// 군종 확장 메서드
extension MilitaryBranchExtension on MilitaryBranch {
  /// 군종 한글명
  String get displayName {
    switch (this) {
      case MilitaryBranch.army:
        return '육군';
      case MilitaryBranch.navy:
        return '해군';
      case MilitaryBranch.airForce:
        return '공군';
      case MilitaryBranch.marines:
        return '해병대';
      case MilitaryBranch.other:
        return '기타';
    }
  }

  /// 복무 기간 (개월)
  /// 기타의 경우 기본값 18개월 반환
  int get serviceMonths {
    switch (this) {
      case MilitaryBranch.army:
      case MilitaryBranch.marines:
        return 18;
      case MilitaryBranch.navy:
        return 20;
      case MilitaryBranch.airForce:
        return 21;
      case MilitaryBranch.other:
        return 18; // 기본값
    }
  }
}
