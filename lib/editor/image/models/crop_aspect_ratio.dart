/// 자르기 비율 타입
enum CropAspectRatio { free, square, ratio3_4, ratio4_3, ratio9_16, ratio16_9 }

/// 자르기 비율 유틸리티
class CropAspectRatioUtils {
  /// 비율 타입을 숫자 값으로 변환
  static double getValue(CropAspectRatio ratio) {
    switch (ratio) {
      case CropAspectRatio.square:
        return 1.0;
      case CropAspectRatio.ratio3_4:
        return 3 / 4;
      case CropAspectRatio.ratio4_3:
        return 4 / 3;
      case CropAspectRatio.ratio9_16:
        return 9 / 16;
      case CropAspectRatio.ratio16_9:
        return 16 / 9;
      case CropAspectRatio.free:
        return 1.0;
    }
  }

  /// 비율 타입의 표시 이름
  static String getLabel(CropAspectRatio ratio) {
    switch (ratio) {
      case CropAspectRatio.free:
        return '자유';
      case CropAspectRatio.square:
        return '1:1';
      case CropAspectRatio.ratio3_4:
        return '3:4';
      case CropAspectRatio.ratio4_3:
        return '4:3';
      case CropAspectRatio.ratio9_16:
        return '9:16';
      case CropAspectRatio.ratio16_9:
        return '16:9';
    }
  }

  /// 모든 비율 목록
  static const List<CropAspectRatio> allRatios = [
    CropAspectRatio.free,
    CropAspectRatio.square,
    CropAspectRatio.ratio3_4,
    CropAspectRatio.ratio4_3,
    CropAspectRatio.ratio9_16,
    CropAspectRatio.ratio16_9,
  ];
}
