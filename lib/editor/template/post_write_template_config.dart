import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/data/models/military_info_model.dart';

/// 글쓰기 모드별 템플릿 정의
class PostWriteTemplateConfig {
  PostWriteTemplateConfig._();

  /// 모드별 템플릿 텍스트 반환
  static List<String>? getTemplateTexts(
    PostWriteMode mode, {
    UserType? userType,
  }) {
    switch (mode) {
      case PostWriteMode.militaryLife:
        return [
          '이번 주 기분은?',
          '지난주보다 나아진 점 하나만?',
          '이번 주에 기억 남는 상황은?',
          '별로였던 일은?',
          '이번 주에 한 고민은?',
        ];
      case PostWriteMode.leaveOrPreEnlistment:
        return null; // ✅ 휴가 모드는 템플릿 없음
      case PostWriteMode.public:
        return null; // ✅ GENERAL 모드는 템플릿 없음
      case PostWriteMode.letter:
        return null; // ✅ 편지 모드는 템플릿 없음
      case PostWriteMode.promise:
        // ✅ 통일된 promise 템플릿 (모든 사용자 타입에 동일)
        return [
          '전역할 때 나는 어떤 사람이 되어 있고 싶어?',
          '이 군생활에서 꼭 얻고 싶은 한 가지는 뭐야?',
          '지금의 나랑 뭐가 제일 달라졌으면 좋겠어?',
        ];
    }
  }

  /// 모드에 템플릿이 있는지 확인
  static bool hasTemplate(PostWriteMode mode) {
    return getTemplateTexts(mode) != null;
  }
}
