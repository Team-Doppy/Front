import 'package:super_editor/super_editor.dart';
import 'dart:ui';

/// 여러 이미지를 가로로 배치하는 커스텀 노드 (최대 3개)
class ImageRowNode extends BlockNode {
  ImageRowNode({
    required this.id,
    required List<String> imageUrls,
    this.spacing = 8.0,
  }) : imageUrls = imageUrls.take(3).toList(); // 최대 3개로 제한

  @override
  final String id;
  final List<String> imageUrls;
  final double spacing;

  String get nodeType => 'imageRow';

  bool get hasContent => imageUrls.isNotEmpty;

  ImageRowNode copyWith({
    String? id,
    List<String>? imageUrls,
    double? spacing,
  }) {
    return ImageRowNode(
      id: id ?? this.id,
      imageUrls: imageUrls?.take(3).toList() ?? this.imageUrls,
      spacing: spacing ?? this.spacing,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nodeType': nodeType,
      'imageUrls': imageUrls,
      'spacing': spacing,
    };
  }

  static ImageRowNode fromJson(Map<String, dynamic> json) {
    return ImageRowNode(
      id: json['id'] as String,
      imageUrls: List<String>.from(json['imageUrls'] as List),
      spacing: (json['spacing'] as num?)?.toDouble() ?? 8.0,
    );
  }

  @override
  bool containsPosition(Object position) {
    // 블록 노드는 Upstream/Downstream 포지션만 가진다고 가정
    return position is UpstreamDownstreamNodePosition;
  }

  Rect getRectForPosition(NodePosition nodePosition) {
    // 기본 구현 - 실제로는 컴포넌트에서 계산됨
    return const Rect.fromLTWH(0, 0, 0, 0);
  }

  NodeSelection getSelectionOfEverything() {
    return UpstreamDownstreamNodeSelection(
      base: const UpstreamDownstreamNodePosition.upstream(),
      extent: const UpstreamDownstreamNodePosition.downstream(),
    );
  }

  bool isVisualSelectionSupported() {
    // 이미지 행은 드래그 선택 불필요
    return false;
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    // 메타데이터 사용 안 하면 동일 복제 반환
    return ImageRowNode(
      id: id,
      imageUrls: List<String>.from(imageUrls),
      spacing: spacing,
    );
  }

  @override
  String? copyContent(NodeSelection selection) {
    // 이미지 행은 텍스트 복사 없음
    return null;
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    // 동일
    return ImageRowNode(
      id: id,
      imageUrls: List<String>.from(imageUrls),
      spacing: spacing,
    );
  }

  @override
  UpstreamDownstreamNodeSelection computeSelection({
    required NodePosition base,
    required NodePosition extent,
  }) {
    return UpstreamDownstreamNodeSelection(
      base: base as UpstreamDownstreamNodePosition,
      extent: extent as UpstreamDownstreamNodePosition,
    );
  }

  @override
  UpstreamDownstreamNodePosition selectDownstreamPosition(
    NodePosition base,
    NodePosition extent,
  ) => UpstreamDownstreamNodePosition.downstream();

  @override
  UpstreamDownstreamNodePosition selectUpstreamPosition(
    NodePosition base,
    NodePosition extent,
  ) => UpstreamDownstreamNodePosition.upstream();
}
