/// 프로필 피드 Phase 필터
enum ProfileFeedFilter {
  all, // 전체
  preEnlistment, // 입대전
  preEnlistmentMemory, // 입대전 추억 (군인만)
  training, // 훈련소
  private, // 이병
  privateFirstClass, // 일병
  corporal, // 상병
  sergeant, // 병장
  leave, // 휴가 (군인만)
}

/// ProfileFeedFilter 확장 메서드
extension ProfileFeedFilterExtension on ProfileFeedFilter {
  /// 필터 한글명
  String get displayName {
    switch (this) {
      case ProfileFeedFilter.all:
        return '전체';
      case ProfileFeedFilter.preEnlistment:
        return '입대전';
      case ProfileFeedFilter.preEnlistmentMemory:
        return '입대전 추억';
      case ProfileFeedFilter.training:
        return '훈련소';
      case ProfileFeedFilter.private:
        return '이병';
      case ProfileFeedFilter.privateFirstClass:
        return '일병';
      case ProfileFeedFilter.corporal:
        return '상병';
      case ProfileFeedFilter.sergeant:
        return '병장';
      case ProfileFeedFilter.leave:
        return '휴가';
    }
  }

  /// Phase 코드로 변환 (서버 API용)
  String? get phaseCode {
    switch (this) {
      case ProfileFeedFilter.preEnlistment:
      case ProfileFeedFilter.preEnlistmentMemory:
        return 'preEnlistment';
      case ProfileFeedFilter.training:
        return 'training';
      case ProfileFeedFilter.private:
        return 'private';
      case ProfileFeedFilter.privateFirstClass:
        return 'privateFirstClass';
      case ProfileFeedFilter.corporal:
        return 'corporal';
      case ProfileFeedFilter.sergeant:
        return 'sergeant';
      case ProfileFeedFilter.all:
      case ProfileFeedFilter.leave:
        return null;
    }
  }

  /// lifePhase 필터 여부
  bool get isLifePhaseFilter {
    return this == ProfileFeedFilter.leave ||
        this == ProfileFeedFilter.preEnlistmentMemory;
  }

  /// 곰신 모드에서 사용 가능한 필터인지
  bool isAvailableForGirlfriend(bool isGirlfriend) {
    if (!isGirlfriend) return true; // 군인 모드는 모든 필터 사용 가능
    // 곰신 모드는 "입대전 추억"과 "휴가" 필터 제외
    return this != ProfileFeedFilter.preEnlistmentMemory &&
        this != ProfileFeedFilter.leave;
  }
}
