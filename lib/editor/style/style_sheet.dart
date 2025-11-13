import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/config.dart';
import 'package:doppy/editor/style/defualt_toolbar.dart'; // HighlightAttribution import
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:super_editor/super_editor.dart';

// 전역 폰트 접근용
TextStylingService? _globalTextStylingService;

void setGlobalTextStylingService(TextStylingService? service) {
  _globalTextStylingService = service;
}

/// 커스텀 스타일시트 (테마에 따라 텍스트/타이틀 색을 적용)
Stylesheet buildCustomStylesheet(BuildContext context) {
  final bool isDark =
      context.watch<ThemeProvider>().themeMode == ThemeMode.dark;
  final Color titleColor =
      isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  final Color bodyColor =
      isDark
          ? const Color.fromARGB(230, 255, 255, 255)
          : AppColors.lightTextPrimary;

  return defaultStylesheet.copyWith(
    documentPadding: EdgeInsets.all(EditorConfig.documentPadding),
    addRulesAfter: [
      // 텍스트 노드 스타일
      StyleRule(BlockSelector.all, (doc, docNode) {
        if (docNode is ParagraphNode) {
          // 제목 문단 스타일
          final isTitle = (docNode.metadata['isTitle'] == true);

          // 제목 스타일은 문서의 0번째 문단에만 적용
          if (isTitle && doc.getNodeIndexById(docNode.id) == 0) {
            // 메타데이터에서 폰트 정보 읽기
            final fontFamily = docNode.metadata['fontFamily'] as String?;

            TextStyle titleStyle = TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: titleColor,
              height: 0,
            );

            // 구글 폰트 적용
            if (fontFamily != null && fontFamily.isNotEmpty) {
              try {
                titleStyle = GoogleFonts.getFont(
                  fontFamily,
                  textStyle: titleStyle,
                );
              } catch (e) {
                print('[FontDebug] 제목 폰트 적용 실패: $fontFamily (오류: $e)');
                titleStyle = titleStyle.copyWith(fontFamily: fontFamily);
              }
            }

            return {
              Styles.textStyle: titleStyle,
              Styles.padding: CascadingPadding.only(
                top: 120,
                bottom: 20,
                left: 20,
                right: 20,
              ),
            };
          }

          // 멘션 노드 스타일 (metadata['mention'] == true)
          final isMention = docNode.metadata['mention'] == true;
          if (isMention) {
            // 메타데이터에서 폰트 정보 읽기
            final fontFamily = docNode.metadata['fontFamily'] as String?;

            TextStyle mentionStyle = TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: bodyColor,
              height: 1,
            );

            // 구글 폰트 적용
            if (fontFamily != null && fontFamily.isNotEmpty) {
              try {
                mentionStyle = GoogleFonts.getFont(
                  fontFamily,
                  textStyle: mentionStyle,
                );
              } catch (e) {
                print('[FontDebug] 멘션 폰트 적용 실패: $fontFamily (오류: $e)');
                mentionStyle = mentionStyle.copyWith(fontFamily: fontFamily);
              }
            }

            return {
              Styles.textStyle: mentionStyle,
              Styles.padding: CascadingPadding.only(
                top: 0,
                bottom: 0,
                left: 20,
                right: 20,
              ),
            };
          }

          // 메타데이터에서 폰트 정보 읽기
          final fontFamily = docNode.metadata['fontFamily'] as String?;

          TextStyle bodyStyle = TextStyle(
            fontSize: 16,
            color: bodyColor,
            height: 1.4,
          );

          // 구글 폰트 적용
          if (fontFamily != null && fontFamily.isNotEmpty) {
            try {
              bodyStyle = GoogleFonts.getFont(fontFamily, textStyle: bodyStyle);
            } catch (e) {
              print('[FontDebug] 본문 폰트 적용 실패: $fontFamily (오류: $e)');
              bodyStyle = bodyStyle.copyWith(fontFamily: fontFamily);
            }
          }

          return {
            Styles.textStyle: bodyStyle,
            Styles.padding: CascadingPadding.only(
              top: 0,
              bottom: 0,
              left: 20,
              right: 20,
            ),
          };
        }
        if (docNode is ImageNode) {
          // 메타데이터에서 패딩 모드 확인
          final paddingMode =
              docNode.metadata['padding'] as String? ?? 'center';

          // 'full' 모드면 좌우 패딩 없음, 'center' 모드면 기본 패딩
          final horizontalPadding = paddingMode == 'full' ? 0.0 : 20.0;

          return {
            Styles.padding: CascadingPadding.only(
              top: EditorConfig.imagePadding,
              bottom: EditorConfig.imagePadding,
              left: horizontalPadding,
              right: horizontalPadding,
            ),
          };
        }
        if (docNode is ImageRowNode) {
          return {
            Styles.padding: CascadingPadding.symmetric(
              vertical: EditorConfig.imagePadding,
              horizontal: 0,
            ),
          };
        }

        if (docNode is ClipNode) {
          return {
            Styles.padding: CascadingPadding.symmetric(
              vertical: 0,
              horizontal: 0,
            ),
          };
        }

        return {};
      }),
    ],
    inlineTextStyler: (attributions, existingStyle) {
      TextStyle style = existingStyle;
      bool isBold = false;
      bool isItalic = false;
      bool hasUnderline = false;
      bool hasStrikethrough = false;
      // 형광펜은 별도 오버레이로 렌더링하므로 스타일에서 사용하지 않음
      bool isSpoiler = false;
      String? fontFamily;

      for (final attribution in attributions) {
        if (attribution == boldAttribution) {
          isBold = true;
        } else if (attribution == italicsAttribution) {
          isItalic = true;
        } else if (attribution == underlineAttribution) {
          hasUnderline = true;
        } else if (attribution == strikethroughAttribution) {
          hasStrikethrough = true;
        } else if (attribution is HighlightAttribution) {
          // no-op: overlay painter handles highlight visuals
        } else if (attribution is NamedAttribution &&
            attribution.id == 'spoiler') {
          isSpoiler = true;
        } else if (attribution is ColorAttribution &&
            attribution is! HighlightAttribution) {
          // ✅ 글자색 (형광펜은 제외!)
          style = style.copyWith(color: attribution.color);
        } else if (attribution is FontSizeAttribution) {
          style = style.copyWith(
            fontSize: attribution.fontSize,
            height: 1.2, // 커서가 텍스트에 맞도록 line height 조정
          );
        } else if (attribution is FontFamilyAttribution) {
          fontFamily = attribution.fontFamily;
        }
      }

      style = style.copyWith(
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
        decoration: _buildTextDecoration(hasUnderline, hasStrikethrough),
        // 형광펜은 별도 오버레이로 렌더링하므로 배경색은 사용하지 않음
      );

      // 🙈 스포일러 스타일: 텍스트 색상은 유지, 마스크로만 가림
      if (isSpoiler) {
        // 스포일러 텍스트도 색상 유지
        // paragraph_component의 마스크가 시각적으로 가림
        style = style.copyWith(decoration: TextDecoration.none);
        // ColorAttribution이 없으면 기본 bodyColor 유지
      }

      // 🎨 폰트 패밀리 적용 (Google Fonts 로더 통해 동적 로드)
      // Attribution이 없으면 전역 폰트 사용
      if (fontFamily == null || fontFamily.isEmpty) {
        fontFamily = _globalTextStylingService?.globalFontFamily;
        if (fontFamily != null) {
          print('[FontDebug] 전역 폰트 사용: $fontFamily');
        }
      }

      if (fontFamily != null && fontFamily.isNotEmpty) {
        print('[FontDebug] inlineTextStyler 폰트 감지: $fontFamily');
        try {
          style = GoogleFonts.getFont(fontFamily, textStyle: style);
          print('[FontDebug] GoogleFonts.getFont 성공: $fontFamily');
        } catch (e) {
          print('[FontDebug] GoogleFonts.getFont 실패: $fontFamily (오류: $e)');
          // 폰트명이 GoogleFonts에 없을 경우 fallback으로 family만 지정
          style = style.copyWith(fontFamily: fontFamily);
        }
      }
      // 본문/타이틀 기본 색을 테마에 맞춰 적용 (인라인 컬러 지정이 없는 경우)
      if (style.color == null) {
        style = style.copyWith(color: bodyColor);
      }
      // 제목의 경우 위에서 const TextStyle로 생성했으므로 색상을 후처리로 주입
      // ParagraphNode의 metadata를 직접 접근할 수 없어서, 기본적으로 bodyColor를 주고
      // 실제 렌더링에서 첫 문단(isTitle=true)은 아래 규칙으로 타이틀 색을 덮어씀
      // (SuperEditor는 상위 규칙 → 인라인 규칙 순 적용)
      return style;
    },
    addRulesBefore: [
      // 타이틀 문단에 색상을 강제로 덮어씌우기 (테마 반영)
      StyleRule(BlockSelector.all, (doc, node) {
        if (node is ParagraphNode) {
          final isTitle = (node.metadata['isTitle'] == true);
          if (isTitle && doc.getNodeIndexById(node.id) == 0) {
            return {Styles.textStyle: TextStyle(color: titleColor)};
          }
        }
        return {};
      }),
    ],
  );
}

/// 텍스트 장식 빌드 (밑줄, 취소선)
TextDecoration _buildTextDecoration(bool hasUnderline, bool hasStrikethrough) {
  if (hasUnderline && hasStrikethrough) {
    return TextDecoration.combine([
      TextDecoration.underline,
      TextDecoration.lineThrough,
    ]);
  } else if (hasUnderline) {
    return TextDecoration.underline;
  } else if (hasStrikethrough) {
    return TextDecoration.lineThrough;
  } else {
    return TextDecoration.none;
  }
}
