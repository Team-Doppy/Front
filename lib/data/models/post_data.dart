import 'dart:convert';

enum AccessLevel { public, private, groups }

class PostData {
  final String id;
  final String thumbnailImageUrl;
  final String title;
  final String author;
  final String content;
  final List<String>? mentionedFriends; // 언급된 친구들
  final String createdAt;
  final AccessLevel accessLevel;

  PostData({
    required this.id,
    required this.thumbnailImageUrl,
    required this.title,
    required this.author,
    required this.content,
    this.mentionedFriends,
    required this.accessLevel,
    required this.createdAt,
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

    print('[PostData] content: ${data['thumbnailImageUrl']}');

    return PostData(
      id: data['id']?.toString() ?? '',
      thumbnailImageUrl: data['thumbnailImageUrl'] ?? 'assets/images/feed2.png',
      title: data['title'] ?? '',
      author: data['author'] ?? '',
      content: content,
      mentionedFriends: (data['mentionedFriends'] as List?)?.cast<String>(),
      accessLevel: accessLevel,
      createdAt: data['createdAt'] ?? DateTime.now().toIso8601String(),
    );
  }

  // PostData를 서버 형식으로 변환
  Map<String, dynamic> toServer() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'content': content,
      'mentionedFriends': mentionedFriends,
      'thumbnailImageUrl': thumbnailImageUrl,
      'accessLevel': accessLevel,
      'createdAt': createdAt,
    };
  }

  /// content JSON을 파싱해서 실제 텍스트 내용만 추출
  String get parsedContent {
    try {
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
}
