/// 숫자를 K, M 형식으로 포맷 (1000 → 1K, 1000000 → 1M)
/// 99 초과 시 99+로 표시
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
