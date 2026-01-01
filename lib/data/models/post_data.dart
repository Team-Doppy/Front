import 'dart:convert';
import 'package:doppy/utils/access_level_parser.dart';
import 'package:flutter/material.dart';

enum AccessLevel { public, private, friends, groups }

class PostData {
  final String id;
  final String thumbnailImageUrl;
  final String title;
  final String summary;
  final String author;
  final int? authorId;
  final String authorProfileImageUrl;
  final String content;
  final String createdAt;
  final String updatedAt;
  final AccessLevel accessLevel;
  final List<int>? sharedGroupIds; // 🎯 그룹 공유 시 그룹 ID 목록
  final List<String>? sharedGroupNames; // 🎯 서버에서 제공하는 그룹 이름 목록
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final bool isLiked;

  // 🎯 성능 최적화: feed에서 parsedContent가 여러 번 호출되면 json.decode가 반복되어 버벅임 유발
  // - summary가 있으면 파싱을 아예 하지 않음
  // - summary가 없을 때만 1회 파싱 후 캐시
  String? _parsedContentCache;

  /// ✅ 썸네일이 "같은 URL인데 내용이 바뀌는" 경우 캐시가 구버전으로 남을 수 있으므로
  /// updatedAt을 섞은 cacheKey를 제공한다.
  ///
  /// - URL이 바뀌는(버전이 포함된) 구조라면 사실상 영향 없음
  /// - URL이 고정이고 내용만 바뀌는 구조라면 이 키로 즉시 최신 이미지 사용
  String? get thumbnailCacheKey {
    final url = thumbnailImageUrl.trim();
    if (!(url.startsWith('http://') || url.startsWith('https://'))) return null;
    final version = (updatedAt.isNotEmpty ? updatedAt : createdAt).trim();
    if (version.isEmpty) return url;
    return '$url::$version';
  }

  /// ✅ 썸네일이 "같은 URL인데 내용만 바뀌는" 경우를 위해 URL에 버전 파라미터(v)를 붙인다.
  /// - NetworkImage에서도 캐시가 안전하게 분리됨
  /// - updatedAt/createdAt을 epoch(ms)로 변환해 사용
  String get thumbnailUrlForCache {
    final raw = thumbnailImageUrl.trim();
    if (!(raw.startsWith('http://') || raw.startsWith('https://'))) {
      return raw;
    }

    final vSource = (updatedAt.isNotEmpty ? updatedAt : createdAt).trim();
    int? v;
    final dt = DateTime.tryParse(vSource);
    if (dt != null) {
      v = dt.millisecondsSinceEpoch;
    } else if (vSource.isNotEmpty) {
      v = vSource.hashCode;
    }
    if (v == null) return raw;

    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['v'] = '$v';
    return uri.replace(queryParameters: qp).toString();
  }

  PostData({
    required this.id,
    required this.thumbnailImageUrl,
    required this.title,
    required this.summary,
    required this.author,
    this.authorId,
    required this.authorProfileImageUrl,
    required this.content,
    required this.accessLevel,
    this.sharedGroupIds, // 🎯 그룹 공유 시 그룹 ID 목록
    this.sharedGroupNames, // 🎯 서버에서 제공하는 그룹 이름 목록
    required this.createdAt,
    required this.updatedAt,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.isLiked,
  });

  /// 피드(목록)에서만 쓰는 경량 파서: content(JSON)를 무겁게 문자열화/파싱하지 않는다.
  /// - summary가 있으면 summary로 미리보기 사용
  /// - content는 Map일 때 비우고, String일 때만 보존(서버가 이미 짧은 문자열을 내려주는 경우)
  factory PostData.fromServerMeta(Map<String, dynamic> data) {
    final accessLevelStr = AccessLevelParser.parseAccessLevelString(
      data['accessLevel'],
    );
    AccessLevel accessLevel = AccessLevel.public;
    if (accessLevelStr == 'PRIVATE') {
      accessLevel = AccessLevel.private;
    } else if (accessLevelStr == 'FRIENDS') {
      accessLevel = AccessLevel.friends;
    } else if (accessLevelStr == 'GROUPS') {
      accessLevel = AccessLevel.groups;
    }

    final author =
        data['author']?.toString() ??
        data['username']?.toString() ??
        data['authorUsername']?.toString() ??
        '';

    int? authorId;
    if (data['authorId'] != null) {
      authorId =
          (data['authorId'] is int)
              ? (data['authorId'] as int)
              : int.tryParse('${data['authorId']}');
    }

    String content = '';
    final contentData = data['content'];
    if (contentData is String) {
      content = contentData;
    }

    return PostData(
      id: data['id']?.toString() ?? '',
      thumbnailImageUrl:
          data['thumbnailUrl'] ??
          data['thumbnailImageUrl'] ??
          'assets/images/feed2.png',
      title: data['title'] ?? '',
      author: author,
      authorId: authorId,
      authorProfileImageUrl: data['authorProfileImageUrl'] ?? '',
      content: content,
      summary: data['summary'] ?? '',
      accessLevel: accessLevel,
      sharedGroupIds: null,
      sharedGroupNames: null,
      createdAt: data['createdAt'] ?? DateTime.now().toIso8601String(),
      updatedAt:
          data['updatedAt'] ??
          data['createdAt'] ??
          DateTime.now().toIso8601String(),
      viewCount:
          (data['viewCount'] is int)
              ? (data['viewCount'] as int)
              : int.tryParse('${data['viewCount'] ?? 0}') ?? 0,
      likeCount:
          (data['likeCount'] is int)
              ? (data['likeCount'] as int)
              : int.tryParse('${data['likeCount'] ?? 0}') ?? 0,
      commentCount:
          (data['commentCount'] is int)
              ? (data['commentCount'] as int)
              : int.tryParse('${data['commentCount'] ?? 0}') ?? 0,
      isLiked: data['isLiked'] == true,
    );
  }

  // 서버 데이터에서 PostData 생성
  factory PostData.fromServer(Map<String, dynamic> data) {
    // 🎯 공통 파싱 유틸리티 사용
    final accessLevelStr = AccessLevelParser.parseAccessLevelString(
      data['accessLevel'],
    );
    AccessLevel accessLevel = AccessLevel.public;
    if (accessLevelStr == 'PRIVATE') {
      accessLevel = AccessLevel.private;
    } else if (accessLevelStr == 'FRIENDS') {
      accessLevel = AccessLevel.friends;
    } else if (accessLevelStr == 'GROUPS') {
      accessLevel = AccessLevel.groups;
    }

    // content가 Map인 경우 JSON 문자열로 변환
    String content = '';
    final contentData = data['content'];
    if (contentData is String) {
      content = contentData;
    } else if (contentData is Map<String, dynamic>) {
      content = json.encode(contentData);
    } else {
      content = contentData?.toString() ?? '';
    }

    // author 필드 우선순위: author > username > authorUsername > ''
    final author =
        data['author']?.toString() ??
        data['username']?.toString() ??
        data['authorUsername']?.toString() ??
        '';

    // authorId 파싱 (없을 수 있음)
    int? authorId;
    if (data['authorId'] != null) {
      authorId =
          (data['authorId'] is int)
              ? (data['authorId'] as int)
              : int.tryParse('${data['authorId']}');
    }

    // 🎯 메타데이터 레벨에서는 sharedGroupIds/Names 없음
    // content 포함 응답은 content.accessLevelInfo에서 파싱해야 함
    // 여기서는 null로 설정 (메타데이터만 파싱하는 경우)
    final List<int>? sharedGroupIds = null;
    final List<String>? sharedGroupNames = null;

    return PostData(
      id: data['id']?.toString() ?? '',
      thumbnailImageUrl:
          data['thumbnailUrl'] ??
          data['thumbnailImageUrl'] ??
          'assets/images/feed2.png',
      title: data['title'] ?? '',
      author: author,
      authorId: authorId,
      authorProfileImageUrl: data['authorProfileImageUrl'] ?? '',
      content: content,
      summary: data['summary'] ?? '',
      accessLevel: accessLevel,
      sharedGroupIds: sharedGroupIds,
      sharedGroupNames: sharedGroupNames,
      createdAt: data['createdAt'] ?? DateTime.now().toIso8601String(),
      updatedAt:
          data['updatedAt'] ??
          data['createdAt'] ??
          DateTime.now().toIso8601String(),
      viewCount:
          (data['viewCount'] is int)
              ? (data['viewCount'] as int)
              : int.tryParse('${data['viewCount'] ?? 0}') ?? 0,
      likeCount:
          (data['likeCount'] is int)
              ? (data['likeCount'] as int)
              : int.tryParse('${data['likeCount'] ?? 0}') ?? 0,
      commentCount:
          (data['commentCount'] is int)
              ? (data['commentCount'] as int)
              : int.tryParse('${data['commentCount'] ?? 0}') ?? 0,
      isLiked: data['isLiked'] == true,
    );
  }

  // PostData를 서버 형식으로 변환
  Map<String, dynamic> toServer() {
    return {
      'id': id,
      'title': title,
      'summary': summary,
      'author': author,
      'authorProfileImageUrl': authorProfileImageUrl,
      'content': content,
      'thumbnailImageUrl': thumbnailImageUrl,
      // 서버 전송 시 accessLevel은 문자열로 전달하는 편이 안전
      'accessLevel': accessLevel.name.toUpperCase(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'viewCount': viewCount,
      'likeCount': likeCount,
    };
  }

  /// content JSON을 파싱해서 실제 텍스트 내용만 추출
  String get parsedContent {
    try {
      if (summary.isNotEmpty) return summary;

      if (content.isEmpty) return '';

      // 이미 계산된 값이 있으면 그대로 사용
      final cached = _parsedContentCache;
      if (cached != null) return cached;

      // content가 JSON 문자열인지 확인
      final parsed = json.decode(content);

      List<dynamic> nodes = [];

      // content가 Map이고 nodes 키가 있는 경우
      if (parsed is Map<String, dynamic> && parsed.containsKey('nodes')) {
        nodes = parsed['nodes'] as List? ?? [];
      }
      // content가 직접 배열인 경우
      else if (parsed is List) {
        nodes = parsed;
      }

      if (nodes.isEmpty) return '';

      final textParts = <String>[];
      for (final node in nodes) {
        if (node is Map<String, dynamic>) {
          final nodeType = node['type'] as String?;
          final text = node['text'] as String?;

          if (nodeType == 'paragraph' && text != null && text.isNotEmpty) {
            // 모든 문단 추가
            textParts.add(text.trim());
          }
        }
      }

      final result = textParts.join(' ').trim();
      //debugPrint('[PostData] Parsed content: "$result"');
      _parsedContentCache = result;
      return result;
    } catch (e) {
      debugPrint('[PostData] Error parsing content: $e');
      debugPrint('[PostData] Raw content: $content');
      // 파싱 실패 시 원본 content 반환
      return content;
    }
  }

  /// isolate/compute 결과를 다시 PostData로 복원하기 위한 경량 맵
  /// (enum 등 비전달 타입을 문자열로 변환)
  Map<String, dynamic> toPrimitiveMap() {
    return {
      'id': id,
      'thumbnailImageUrl': thumbnailImageUrl,
      'title': title,
      'summary': summary,
      'author': author,
      'authorId': authorId,
      'authorProfileImageUrl': authorProfileImageUrl,
      'content': content,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'accessLevel': accessLevel.name, // public/private/friends/groups
      'sharedGroupIds': sharedGroupIds,
      'sharedGroupNames': sharedGroupNames,
      'viewCount': viewCount,
      'likeCount': likeCount,
      'commentCount': commentCount,
      'isLiked': isLiked,
    };
  }

  factory PostData.fromPrimitiveMap(Map<String, dynamic> data) {
    final accessLevelName = data['accessLevel']?.toString() ?? 'public';
    final accessLevel = AccessLevel.values.firstWhere(
      (e) => e.name == accessLevelName,
      orElse: () => AccessLevel.public,
    );

    return PostData(
      id: data['id']?.toString() ?? '',
      thumbnailImageUrl: data['thumbnailImageUrl']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      summary: data['summary']?.toString() ?? '',
      author: data['author']?.toString() ?? '',
      authorId:
          (data['authorId'] is int)
              ? data['authorId'] as int
              : int.tryParse('${data['authorId'] ?? ''}'),
      authorProfileImageUrl: data['authorProfileImageUrl']?.toString() ?? '',
      content: data['content']?.toString() ?? '',
      accessLevel: accessLevel,
      sharedGroupIds: (data['sharedGroupIds'] as List?)?.cast<int>(),
      sharedGroupNames: (data['sharedGroupNames'] as List?)?.cast<String>(),
      createdAt:
          data['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt:
          data['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
      viewCount:
          (data['viewCount'] is int)
              ? data['viewCount'] as int
              : int.tryParse('${data['viewCount'] ?? 0}') ?? 0,
      likeCount:
          (data['likeCount'] is int)
              ? data['likeCount'] as int
              : int.tryParse('${data['likeCount'] ?? 0}') ?? 0,
      commentCount:
          (data['commentCount'] is int)
              ? data['commentCount'] as int
              : int.tryParse('${data['commentCount'] ?? 0}') ?? 0,
      isLiked: data['isLiked'] == true,
    );
  }

  /// PostReaderScreen에 필요한 exported 데이터 생성
  Map<String, dynamic> toExportedData() {
    try {
      // content가 JSON 문자열인지 확인하고 파싱
      Map<String, dynamic> contentData = {};
      if (content.isNotEmpty) {
        try {
          final parsed = json.decode(content);
          if (parsed is Map<String, dynamic>) {
            contentData = parsed;
          } else if (parsed is List) {
            contentData = {'nodes': parsed};
          }
        } catch (e) {
          debugPrint('[PostData] Error parsing content for export: $e');
          // 파싱 실패 시 빈 문서로 생성
          contentData = {'nodes': []};
        }
      }

      return {
        'id': id,
        'thumbnailImageUrl': thumbnailImageUrl,
        'title': title,
        'summary': summary, // 🎯 summary 추가
        'author': author,
        'authorId': authorId,
        'authorProfileImageUrl': authorProfileImageUrl,
        'content': contentData,
        'accessLevel': accessLevel.name.toUpperCase(), // 🎯 accessLevel 추가
        'sharedGroupIds': sharedGroupIds, // 🎯 sharedGroupIds 추가
        'sharedGroupNames': sharedGroupNames, // 🎯 sharedGroupNames 추가
        'viewCount': viewCount, // 🎯 viewCount 추가
        'likeCount': likeCount,
        'commentCount': commentCount,
        'isLiked': isLiked,
        'stickers': [], // 서버에서 가져온 데이터에는 스티커가 없음
      };
    } catch (e) {
      debugPrint('[PostData] Error creating exported data: $e');
      // 에러 시 기본 데이터 반환
      return {
        'id': id,
        'thumbnailImageUrl': thumbnailImageUrl,
        'title': title,
        'summary': summary, // 🎯 summary 추가
        'author': author,
        'authorId': authorId,
        'authorProfileImageUrl': authorProfileImageUrl,
        'content': {'nodes': []},
        'accessLevel': accessLevel.name.toUpperCase(), // 🎯 accessLevel 추가
        'sharedGroupIds': sharedGroupIds, // 🎯 sharedGroupIds 추가
        'sharedGroupNames': sharedGroupNames, // 🎯 sharedGroupNames 추가
        'viewCount': viewCount, // 🎯 viewCount 추가
        'likeCount': likeCount,
        'commentCount': commentCount,
        'isLiked': isLiked,
        'stickers': [],
      };
    }
  }

  /// 서버 DTO(BlogResponse)와 동일한 키로 디버깅 출력용 맵 생성
  Map<String, dynamic> toServerLikeMap() {
    dynamic contentJson;
    try {
      contentJson = content.isNotEmpty ? json.decode(content) : null;
    } catch (_) {
      contentJson = {'raw': content};
    }
    return {
      'title': title,
      'thumbnailImageUrl': thumbnailImageUrl,
      'content': contentJson ?? const {'nodes': []},
      'author': author,
      'authorProfileImageUrl': authorProfileImageUrl,
      'accessLevel': accessLevel.name.toUpperCase(),
      'viewCount': viewCount,
      'likeCount': likeCount,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
