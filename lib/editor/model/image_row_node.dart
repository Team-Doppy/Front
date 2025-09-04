import 'package:super_editor/super_editor.dart';

/// 여러 이미지를 가로로 배치하는 커스텀 노드
class ImageRowNode extends DocumentNode {
  ImageRowNode({required this.id, required this.imageUrls, this.spacing = 8.0});

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
      imageUrls: imageUrls ?? this.imageUrls,
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
  NodePosition get beginningPosition => throw UnimplementedError();

  @override
  NodeSelection computeSelection({
    required NodePosition base,
    required NodePosition extent,
  }) {
    // TODO: implement computeSelection
    throw UnimplementedError();
  }

  @override
  bool containsPosition(Object position) {
    // TODO: implement containsPosition
    throw UnimplementedError();
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    // TODO: implement copyAndReplaceMetadata
    throw UnimplementedError();
  }

  @override
  String? copyContent(NodeSelection selection) {
    // TODO: implement copyContent
    throw UnimplementedError();
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    // TODO: implement copyWithAddedMetadata
    throw UnimplementedError();
  }

  @override
  // TODO: implement endPosition
  NodePosition get endPosition => throw UnimplementedError();

  @override
  NodePosition selectDownstreamPosition(
    NodePosition position1,
    NodePosition position2,
  ) {
    // TODO: implement selectDownstreamPosition
    throw UnimplementedError();
  }

  @override
  NodePosition selectUpstreamPosition(
    NodePosition position1,
    NodePosition position2,
  ) {
    // TODO: implement selectUpstreamPosition
    throw UnimplementedError();
  }
}
