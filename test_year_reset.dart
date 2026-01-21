void main() {
  // 2024년 12월 31일
  final dec31_2024 = DateTime(2024, 12, 31);
  print('2024년 12월 31일: ${getWeekNumber(dec31_2024)}주차');

  // 2025년 1월 1일
  final jan1_2025 = DateTime(2025, 1, 1);
  print('2025년 1월 1일: ${getWeekNumber(jan1_2025)}주차');

  // 2025년 1월 7일
  final jan7_2025 = DateTime(2025, 1, 7);
  print('2025년 1월 7일: ${getWeekNumber(jan7_2025)}주차');

  // 2025년 1월 8일
  final jan8_2025 = DateTime(2025, 1, 8);
  print('2025년 1월 8일: ${getWeekNumber(jan8_2025)}주차');

  // 2025년 12월 31일
  final dec31_2025 = DateTime(2025, 12, 31);
  print('2025년 12월 31일: ${getWeekNumber(dec31_2025)}주차');

  // 2026년 1월 1일
  final jan1_2026 = DateTime(2026, 1, 1);
  print('2026년 1월 1일: ${getWeekNumber(jan1_2026)}주차');

  print('\n--- 주차 시작일 확인 ---');
  print('2025년 1주차 시작일: ${getWeekStartDate(2025, 1)}');
  print('2026년 1주차 시작일: ${getWeekStartDate(2026, 1)}');
}

int getWeekNumber(DateTime date) {
  // 1월 1일부터 7일씩 나누는 방식
  final jan1 = DateTime(date.year, 1, 1);
  final daysSinceJan1 = date.difference(jan1).inDays;
  final weekNumber = (daysSinceJan1 ~/ 7) + 1;

  if (date.year < jan1.year) {
    final prevYear = date.year;
    final prevJan1 = DateTime(prevYear, 1, 1);
    final prevDec31 = DateTime(prevYear, 12, 31);
    final prevDaysSinceJan1 = prevDec31.difference(prevJan1).inDays;
    return (prevDaysSinceJan1 ~/ 7) + 1;
  }

  if (date.year > jan1.year) {
    return 1;
  }

  return weekNumber;
}

DateTime getWeekStartDate(int year, int weekNumber) {
  final jan1 = DateTime(year, 1, 1);
  return jan1.add(Duration(days: (weekNumber - 1) * 7));
}
