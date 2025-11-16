/// 숫자를 K, M 형식으로 포맷 (1000 → 1K, 1000000 → 1M)
/// 99 초과 시 99+로 표시 (좋아요/댓글 등용)
String formatCount(int count) {
  if (count >= 1000000) {
    final millions = count / 1000000;
    return millions == millions.floor()
        ? '${millions.toInt()}M'
        : '${millions.toStringAsFixed(1)}M';
  } else if (count >= 1000) {
    final thousands = count / 1000;
    return thousands == thousands.floor()
        ? '${thousands.toInt()}K'
        : '${thousands.toStringAsFixed(1)}K';
  } else if (count > 99) {
    return '99+';
  } else {
    return count.toString();
  }
}

/// 조회수 전용 포맷터
/// - 0 ~ 999: 원본 숫자 그대로
/// - 1,000 ~ 999,999: 소문자 k 사용 (예: 1.5k)
/// - 1,000,000 이상: 소문자 m 사용 (예: 1.2m)
String formatViewCount(int count) {
  if (count >= 1000000) {
    final millions = count / 1000000;
    return millions == millions.floor()
        ? '${millions.toInt()}m'
        : '${millions.toStringAsFixed(1)}m';
  } else if (count >= 1000) {
    final thousands = count / 1000;
    return thousands == thousands.floor()
        ? '${thousands.toInt()}k'
        : '${thousands.toStringAsFixed(1)}k';
  } else {
    return count.toString();
  }
}
