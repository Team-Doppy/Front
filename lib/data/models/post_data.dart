import 'dart:convert';

enum AccessLevel { public, private, groups }

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
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final bool isLiked;

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
    required this.createdAt,
    required this.updatedAt,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.isLiked,
  });

  // 서버 데이터에서 PostData 생성
  factory PostData.fromServer(Map<String, dynamic> data) {
    // accessLevel 문자열을 enum으로 변환
    AccessLevel accessLevel = AccessLevel.public;
    final accessLevelStr = data['accessLevel']?.toString().toUpperCase();
    if (accessLevelStr == 'PRIVATE') {
      accessLevel = AccessLevel.private;
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
            // 제목이 아닌 일반 문단만 추가
            final isTitle = node['isTitle'] == true;
            if (!isTitle) {
              textParts.add(text.trim());
            }
          }
        }
      }

      final result = textParts.join(' ').trim();
      //print('[PostData] Parsed content: "$result"');
      return result;
    } catch (e) {
      print('[PostData] Error parsing content: $e');
      print('[PostData] Raw content: $content');
      // 파싱 실패 시 원본 content 반환
      return content;
    }
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
          print('[PostData] Error parsing content for export: $e');
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
        'likeCount': likeCount,
        'commentCount': commentCount,
        'isLiked': isLiked,
        'stickers': [], // 서버에서 가져온 데이터에는 스티커가 없음
      };
    } catch (e) {
      print('[PostData] Error creating exported data: $e');
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
