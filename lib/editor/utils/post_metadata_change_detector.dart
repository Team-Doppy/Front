/// 포스트 메타데이터 변경 감지 결과
class PostMetadataChangeResult {
  final bool titleChanged;
  final bool summaryChanged;
  final bool thumbnailChanged;
  final bool categoryChanged;
  final bool accessLevelChanged;
  final bool sharedGroupIdsChanged;

  PostMetadataChangeResult({
    required this.titleChanged,
    required this.summaryChanged,
    required this.thumbnailChanged,
    required this.categoryChanged,
    required this.accessLevelChanged,
    required this.sharedGroupIdsChanged,
  });

  /// 변경사항이 있는지 확인
  bool get hasChanges =>
      titleChanged ||
      summaryChanged ||
      thumbnailChanged ||
      categoryChanged ||
      accessLevelChanged ||
      sharedGroupIdsChanged;

  /// 제목/요약/썸네일 변경 여부 (more_horiz 아이콘 색상용)
  bool get hasMetadataChanges =>
      titleChanged || summaryChanged || thumbnailChanged;

  /// 공개범위 관련 변경 여부
  bool get hasAccessLevelChanges => accessLevelChanged || sharedGroupIdsChanged;
}

/// 그룹 ID 리스트 비교 헬퍼
bool areGroupIdsEqual(List<int>? list1, List<int>? list2) {
  if (list1 == null && list2 == null) return true;
  if (list1 == null || list2 == null) return false;
  if (list1.length != list2.length) return false;
  final set1 = list1.toSet();
  final set2 = list2.toSet();
  return set1.length == set2.length && set1.containsAll(set2);
}

/// 포스트 메타데이터 변경사항 감지
PostMetadataChangeResult detectPostMetadataChanges({
  required String currentTitle,
  required String originalTitle,
  required String currentSummary,
  required String originalSummary,
  required String currentThumbnailUrl,
  required String originalThumbnailUrl,
  int? currentCategoryId,
  int? originalCategoryId,
  String? currentAccessLevel,
  String? originalAccessLevel,
  List<int>? currentSharedGroupIds,
  List<int>? originalSharedGroupIds,
}) {
  final titleChanged = currentTitle.trim() != originalTitle.trim();
  final summaryChanged = currentSummary.trim() != originalSummary.trim();
  final thumbnailChanged =
      currentThumbnailUrl.trim() != originalThumbnailUrl.trim();

  // 🎯 카테고리 변경 감지:
  // - 둘 다 null이면 변경 없음
  // - 둘 다 실제 값이면 값 비교
  // - 하나만 null이고 다른 하나가 실제 값이면 변경 있음 (카테고리 추가/제거)
  final categoryChanged = currentCategoryId != originalCategoryId;

  // 🎯 공개범위 변경 감지: 빈 문자열과 null을 동일하게 취급
  final normalizedCurrentAccessLevel =
      (currentAccessLevel?.trim().isEmpty ?? true)
          ? null
          : currentAccessLevel?.trim();
  final normalizedOriginalAccessLevel =
      (originalAccessLevel?.trim().isEmpty ?? true)
          ? null
          : originalAccessLevel?.trim();
  final accessLevelChanged =
      normalizedCurrentAccessLevel != normalizedOriginalAccessLevel;

  // 🎯 그룹 ID 변경 감지
  final sharedGroupIdsChanged =
      !areGroupIdsEqual(currentSharedGroupIds, originalSharedGroupIds);

  return PostMetadataChangeResult(
    titleChanged: titleChanged,
    summaryChanged: summaryChanged,
    thumbnailChanged: thumbnailChanged,
    categoryChanged: categoryChanged,
    accessLevelChanged: accessLevelChanged,
    sharedGroupIdsChanged: sharedGroupIdsChanged,
  );
}
