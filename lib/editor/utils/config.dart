import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/nodes/mention_node.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:super_editor/super_editor.dart';

class EditorConfig {
  static const double documentPadding = 0;
  static const double textPadding = 1;
  static const double imagePadding = 0;

  /// 기본 라인 높이 배율 (행간). 텍스트 스타일 전반에 동일 기준으로 적용한다.
  static const double defaultLineHeight = 1.2;

  /// 특수 노드(이미지, 비디오, 링크)와 텍스트 노드 사이의 수직 패딩
  static const double specialNodePaddingWithText = 18.0;

  /// 기본 본문 텍스트 폰트 사이즈
  static const double defaultBodyFontSize = 16.0;

  /// 좌우 수평 패딩 (텍스트 노드 및 center 모드의 이미지/비디오)
  /// 모든 기기에서 동일한 값 사용 (디자인 시스템 일관성)
  static const double horizontalPadding = 20.0;
}

/// 드래그/드롭 UX 임계값(서비스 로직 & UI 표시 로직이 **같은 값**을 쓰도록 중앙화)
class EditorDragConfig {
  /// "정말 드래그했다"로 판단하는 최소 이동 거리
  /// - `PageViewImageComponent`가 삽입 슬롯(좌/우 패딩) 미리보기를 띄우는 기준에도 사용된다.
  static const double dragSignificantDistancePx = 28.0;

  /// PageView 위에서 "병합(내부 삽입)" 모드로 들어갈 수 있는 세로 안전 영역(inset)
  /// - 위/아래 가장자리에서는 reorder(위/아래 드롭라인) 감지가 우선되도록 한다.
  static const double pageViewMergeVerticalInsetMinPx = 36.0;
  static const double pageViewMergeVerticalInsetMaxPx = 96.0;
  static const double pageViewMergeVerticalInsetRatio = 0.18;

  /// PageView 내부 삽입에서 중앙 데드존(가운데 '자기 위치'로 판단하는 구간)
  /// - 이 구간에서는 좌/우 삽입 미리보기가 뜨지 않고 reorder 감지가 가능해진다.
  static const double pageViewMergeCenterDeadZoneMinPx = 36.0;
  static const double pageViewMergeCenterDeadZoneMaxPx = 140.0;
  static const double pageViewMergeCenterDeadZoneRatio = 0.20;

  /// 분리 드래그(split) 중 원래 컨테이너(Row/PageView) 위에서
  /// 위/아래 드롭라인이 너무 좁게 잡히지 않도록 "엣지 감지" 영역을 확장한다.
  static const double splitCancelEdgeYMinPx = 40.0;
  static const double splitCancelEdgeYMaxPx = 120.0;
  static const double splitCancelEdgeYRatio = 0.30;
}

/// 특수 노드인지 확인하는 전역 함수
/// 🎯 멘션 노드도 특수 노드로 처리 (마지막 노드 아래 빈 공간 클릭 시 빈 텍스트 추가 기능을 위해)
bool isSpecialNode(DocumentNode? node) {
  if (node == null) return false;
  return node is ImageNode ||
      node is ImageRowNode ||
      node is PageViewImageNode ||
      node is ClipNode ||
      node is LinkNode ||
      node is MentionNode;
}
