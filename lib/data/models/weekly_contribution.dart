import 'package:doppy/data/models/weekly_contribution_greeting.dart';
import 'package:doppy/providers/weekly_contribution_provider.dart';

/// 주차 기여도 데이터 모델 (서버 응답)
class WeeklyContributionResponse {
  final int year;
  final int weeksInYear;
  final List<WeeklyContributionWeekData> weeks;
  final WeeklyContributionGreeting? greeting;

  WeeklyContributionResponse({
    required this.year,
    required this.weeksInYear,
    required this.weeks,
    this.greeting,
  });

  factory WeeklyContributionResponse.fromJson(Map<String, dynamic> json) {
    final weeks =
        (json['weeks'] as List? ?? [])
            .map(
              (w) => WeeklyContributionWeekData.fromJson(
                w as Map<String, dynamic>,
              ),
            )
            .toList();

    return WeeklyContributionResponse(
      year: json['year'] as int? ?? 0,
      weeksInYear: json['weeksInYear'] as int? ?? 0,
      weeks: weeks,
      greeting:
          json['greeting'] != null
              ? WeeklyContributionGreeting.fromJson(
                json['greeting'] as Map<String, dynamic>,
              )
              : null,
    );
  }
}

/// 주차별 데이터
class WeeklyContributionWeekData {
  final int weekNumber;
  final List<Map<String, dynamic>> myPosts;

  WeeklyContributionWeekData({required this.weekNumber, required this.myPosts});

  factory WeeklyContributionWeekData.fromJson(Map<String, dynamic> json) {
    return WeeklyContributionWeekData(
      weekNumber: json['weekNumber'] as int? ?? 0,
      myPosts:
          (json['myPosts'] as List? ?? [])
              .map((p) => p as Map<String, dynamic>)
              .toList(),
    );
  }
}
