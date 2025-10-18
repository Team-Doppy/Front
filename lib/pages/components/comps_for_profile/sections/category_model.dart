import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';

/// 공개 섹션 메타 (feed.dart의 `_FeedSectionMeta` 대체 용)
class CategoryMetaData {
  const CategoryMetaData({
    required this.title,
    required this.posts,
    this.categoryId,
  });

  final String title;
  final List<PostData> posts;
  final String? categoryId;
}
