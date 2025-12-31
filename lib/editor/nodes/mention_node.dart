import 'package:super_editor/super_editor.dart';

/// 멘션 블록 노드 (문서 모델)
///
/// UI 레이어(`mention_component.dart`)와 분리하여,
/// 드래그/드롭, 타입 체크, exporter 등에서 순환 import 없이 사용할 수 있다.
class MentionNode extends BlockNode {
  MentionNode({
    required this.id,
    required this.usernames,
    Map<String, dynamic>? metadata,
  }) : _metadata = metadata ?? const {};

  @override
  final String id;

  final List<String> usernames;
  final Map<String, dynamic> _metadata;

  @override
  Map<String, dynamic> get metadata => _metadata;

  @override
  bool get isDeletable => true;

  @override
  bool containsPosition(Object position) =>
      position is UpstreamDownstreamNodePosition;

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
  ) => const UpstreamDownstreamNodePosition.downstream();

  @override
  UpstreamDownstreamNodePosition selectUpstreamPosition(
    NodePosition base,
    NodePosition extent,
  ) => const UpstreamDownstreamNodePosition.upstream();

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) =>
      MentionNode(id: id, usernames: usernames, metadata: newMetadata);

  @override
  String? copyContent(NodeSelection selection) => null;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) =>
      MentionNode(
        id: id,
        usernames: usernames,
        metadata: {...metadata, ...newProperties},
      );
}
