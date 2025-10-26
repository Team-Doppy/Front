import 'package:doppy/data/models/post_data.dart';

/// 공개 섹션 메타 (feed.dart의 `_FeedSectionMeta` 대체 용)
class CategoryMetaData {
  const CategoryMetaData({
    required this.title,
    required this.posts,
    this.categoryId,
    this.isReadOnly = false,
  });

  final String title;
  final List<PostData> posts;
  final String? categoryId;
  final bool isReadOnly;
}
