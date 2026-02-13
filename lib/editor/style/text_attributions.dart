import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 형광펜 효과 Attribution 정의
///
/// ⚠️ 주의:
/// - 툴바/편집 UI에 종속되지 않는 "순수 모델" 성격의 정의만 둔다.
/// - PostReader(읽기) / Exporter / Stylesheet 등에서 공통으로 사용한다.
class HighlightAttribution extends ColorAttribution {
  const HighlightAttribution(Color color) : super(color);

  @override
  String get id => 'highlight';
}

/// 스포일러(가림) 텍스트 Attribution (JSON 직렬화용 id만 사용)
/// NamedAttribution을 사용하면 export/import 시 그대로 보존된다.
const NamedAttribution spoilerAttribution = NamedAttribution('spoiler');

/// 기본 형광펜 색상들 (연한 톤)
const Color highlightYellow = Color(0xFFFFF59D);
const Color highlightGreen = Color(0xFFA5D6A7);
const Color highlightBlue = Color(0xFF90CAF9);
const Color highlightPink = Color(0xFFF8BBD9);
const Color highlightOrange = Color(0xFFFFCC80);
const Color highlightPurple = Color(0xFFCE93D8);
