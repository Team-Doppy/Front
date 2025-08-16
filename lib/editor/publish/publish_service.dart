import 'dart:convert';
import 'dart:io';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:http/http.dart' as http;
import 'package:super_editor/super_editor.dart';
import 'package:flutter/material.dart'; // Added for BuildContext

enum Visibility { public, private, friends, groups }

enum BlogStatus { DRAFT, PUBLISHED, ARCHIVED }

class PreviewData {
  final String title;
  final String thumbnailUrl;
  final String previewText;
  final List<String> tags;
  PreviewData({
    required this.title,
    required this.thumbnailUrl,
    required this.previewText,
    this.tags = const [],
  });
}

extension PublishServicePreview on PublishService {
  PreviewData extractPreviewData(
    MutableDocument document, {
    String? userThumbnail,
    List<String> tags = const [],
  }) {
    // 제목 추출
    String title = '제목 없음';
    if (document.nodeCount > 0 && document.getNodeAt(0) is ParagraphNode) {
      final t = (document.getNodeAt(0) as ParagraphNode).text.text;
      if (t.isNotEmpty) title = t.length > 30 ? t.substring(0, 30) + '...' : t;
    }
    // 썸네일 추출
    String thumbnailUrl = extractThumbnailUrl(
      document,
      userSelected: userThumbnail,
    );
    // 본문 미리보기(두 번째 문단 등)
    String previewText = '';
    for (int i = 1; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode) {
        previewText = node.text.text;
        if (previewText.isNotEmpty) break;
      }
    }
    if (previewText.isEmpty) previewText = '내용 없음';
    return PreviewData(
      title: title,
      thumbnailUrl: thumbnailUrl,
      previewText: previewText,
      tags: tags,
    );
  }
}

class PublishService {
  static final PublishService _instance = PublishService._internal();
  factory PublishService() => _instance;
  PublishService._internal();

  // API 기본 설정
  static String _baseUrl = ApiServiceBase.baseUrl;

  // 블로그 데이터
  String title = "";
  Map<String, dynamic> content = {};
  String thumbnailImageUrl = "";
  List<String> tags = [];
  List<String> annotations = [];
  Visibility visibility = Visibility.public;
  BlogStatus status = BlogStatus.DRAFT;

  List<int> sharedGroups = [];
  String? password;
  int? thumbnailImageId;

  // 에디터에서 발행 버튼 클릭 시 호출
  Future<Map<String, dynamic>> prepareForPublishing({
    required String title,
    required MutableDocument document,
    String? thumbnailImageUrl, // nullable로 변경
    List<String> tags = const [],
    List<String> annotations = const [],
    Visibility visibility = Visibility.public,
    List<int> sharedGroups = const [],
    String? password,
  }) async {
    try {
      if (title.trim().isEmpty) {
        throw Exception('제목은 필수입니다');
      }
      if (document.nodeCount == 0) {
        throw Exception('내용이 없습니다');
      }
      final documentJson = await _convertDocumentToJson(document);
      this.title = title.trim();
      this.content = documentJson;
      // 썸네일 자동 추출
      this.thumbnailImageUrl = extractThumbnailUrl(
        document,
        userSelected: thumbnailImageUrl,
      );
      this.tags = tags;
      this.annotations = annotations;
      this.visibility = visibility;
      this.sharedGroups = sharedGroups;
      this.password = password;
      _setAccessLevelAndStatus();
      this.thumbnailImageId = _extractImageIdFromUrl(this.thumbnailImageUrl);
      print('✅ 발행 준비 완료: $title');
      print('   상태: ${status.name}');
      print('   태그: ${tags.join(', ')}');
      print('   공유 그룹: ${sharedGroups.join(', ')}');
      return {
        'success': true,
        'title': this.title,
        'status': status.name,
        'tags': this.tags,
        'sharedGroups': this.sharedGroups,
      };
    } catch (e) {
      print('❌ 발행 준비 실패: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 문서를 JSON으로 변환
  Future<Map<String, dynamic>> _convertDocumentToJson(
    MutableDocument document,
  ) async {
    try {
      final blocks = <Map<String, dynamic>>[];

      for (int i = 0; i < document.nodeCount; i++) {
        final node = document.getNodeAt(i);
        if (node == null) continue;

        if (node is ParagraphNode) {
          // 텍스트 노드 처리
          final paragraph = _convertParagraphNode(node);
          blocks.add(paragraph);
        } else if (node is ImageNode) {
          // 이미지 노드 처리
          final image = _convertImageNode(node);
          blocks.add(image);
        }
      }

      return {
        'blocks': blocks,
        'metadata': {
          'totalBlocks': blocks.length,
          'convertedAt': DateTime.now().toIso8601String(),
        },
      };
    } catch (e) {
      print('❌ 문서 JSON 변환 실패: $e');
      rethrow;
    }
  }

  // 텍스트 노드 변환
  Map<String, dynamic> _convertParagraphNode(ParagraphNode node) {
    final textContent = node.text;
    final textSpans = <Map<String, dynamic>>[];

    // 텍스트 스팬 처리 (간단한 버전)
    textSpans.add({
      'text': {'content': textContent.text},
      'annotations': {
        'bold': false,
        'italic': false,
        'underline': false,
        'strikethrough': false,
        'color': '#000000',
        'font_size': 16,
      },
    });

    return {
      'type': 'paragraph',
      'paragraph': {'rich_text': textSpans, 'text_align': 'left'},
    };
  }

  // 이미지 노드 변환
  Map<String, dynamic> _convertImageNode(ImageNode node) {
    final metadata = node.metadata;

    return {
      'type': 'image',
      'image': {'url': node.imageUrl, 'alt': metadata['alt'] ?? '이미지'},
      'layout': {
        'position': {'gridX': metadata['gridX'] ?? 0},
        'size': {
          'gridW': metadata['gridW'] ?? 1,
          'gridH': metadata['gridH'] ?? 1,
          'pxW': metadata['pxW'] ?? 400,
          'pxH': metadata['pxH'] ?? 300,
        },
      },
    };
  }

  // 접근 레벨 및 상태 설정
  void _setAccessLevelAndStatus() {
    switch (visibility) {
      case Visibility.public:
        status = BlogStatus.PUBLISHED;
        break;
      case Visibility.private:
        status = BlogStatus.PUBLISHED;
        break;
      case Visibility.friends:
        status = BlogStatus.PUBLISHED;
        break;
      case Visibility.groups:
        status = BlogStatus.PUBLISHED;
        break;
    }
  }

  // URL에서 이미지 ID 추출
  int? _extractImageIdFromUrl(String url) {
    try {
      if (url.isEmpty) return null;

      // URL 패턴에서 ID 추출 시도
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'images' && i + 1 < pathSegments.length) {
          final id = int.tryParse(pathSegments[i + 1]);
          if (id != null) return id;
        }
      }

      return null;
    } catch (e) {
      print('⚠️ 이미지 ID 추출 실패: $url - $e');
      return null;
    }
  }

  // 썸네일 자동 추출 (없으면 플레이스홀더)
  String extractThumbnailUrl(MutableDocument document, {String? userSelected}) {
    if (userSelected != null && userSelected.isNotEmpty) {
      return userSelected;
    }
    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node is ImageNode && node.imageUrl.isNotEmpty) {
        return node.imageUrl;
      }
    }
    return 'assets/images/sample_image.jpg';
  }

  // 서버에 블로그 발행
  Future<Map<String, dynamic>> publishBlog() async {
    try {
      if (title.isEmpty || content.isEmpty) {
        throw Exception('제목과 내용이 필요합니다');
      }

      final uri = Uri.parse('$_baseUrl/api/posts');

      // 요청 데이터 구성
      final requestData = {
        'title': title,
        'content': content,
        'status': status.name,
        'tags': tags,
        'sharedGroups': sharedGroups,
        if (thumbnailImageId != null) 'thumbnailImageId': thumbnailImageId,
        if (password != null && password!.isNotEmpty) 'password': password,
        'annotations': annotations,
      };

      print('📤 블로그 발행 요청:');
      print('   URL: $uri');
      print('   제목: $title');
      print('   상태: ${status.name}');

      // HTTP 요청 전송
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer user1234', // 실제 토큰으로 변경 필요
            },
            body: json.encode(requestData),
          )
          .timeout(const Duration(seconds: 30));

      final responseBody = response.body;

      print('📡 서버 응답 수신:');
      print('   상태 코드: ${response.statusCode}');
      print('   응답 본문: $responseBody');

      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final result = json.decode(responseBody);
          print('✅ 블로그 발행 성공: ${result['id']}');

          return {
            'success': true,
            'blogId': result['id'],
            'message': '블로그가 성공적으로 발행되었습니다',
            'data': result,
          };
        } catch (parseError) {
          print('❌ JSON 파싱 실패: $parseError');
          throw Exception('서버 응답 파싱 실패');
        }
      } else {
        // 에러 응답 처리
        try {
          final errorResult = json.decode(responseBody);
          final errorMessage = errorResult['message'] ?? '알 수 없는 오류가 발생했습니다';

          print('❌ 블로그 발행 실패: ${response.statusCode} - $errorMessage');

          return {
            'success': false,
            'statusCode': response.statusCode,
            'error': errorMessage,
            'fieldErrors': errorResult['fieldErrors'] ?? [],
            'fileUploadErrors': errorResult['fileUploadErrors'] ?? [],
          };
        } catch (parseError) {
          print('❌ 에러 응답 파싱 실패: $parseError');
          return {
            'success': false,
            'statusCode': response.statusCode,
            'error': '서버 오류가 발생했습니다',
          };
        }
      }
    } on http.ClientException catch (e) {
      print('❌ 네트워크 오류: $e');
      return {'success': false, 'error': '네트워크 연결을 확인해주세요'};
    } catch (e) {
      print('❌ 블로그 발행 중 오류: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 블로그 상태 변경
  Future<Map<String, dynamic>> changeBlogStatus(
    int blogId,
    BlogStatus newStatus,
  ) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/api/posts/$blogId/status?status=${newStatus.name}',
      );

      print('📤 블로그 상태 변경 요청: $blogId → ${newStatus.name}');

      final response = await http
          .put(
            uri,
            headers: {
              'Authorization': 'Bearer user1234', // 실제 토큰으로 변경 필요
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        print('✅ 블로그 상태 변경 성공: ${newStatus.name}');
        return {'success': true, 'message': '블로그 상태가 변경되었습니다'};
      } else {
        print('❌ 블로그 상태 변경 실패: ${response.statusCode}');
        return {'success': false, 'error': '상태 변경에 실패했습니다'};
      }
    } catch (e) {
      print('❌ 블로그 상태 변경 중 오류: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 블로그 수정
  Future<Map<String, dynamic>> updateBlog(int blogId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/posts/$blogId');

      final requestData = {
        'title': title,
        'content': content,
        'status': status.name,
        'tags': tags,
        'sharedGroups': sharedGroups,
        if (thumbnailImageId != null) 'thumbnailImageId': thumbnailImageId,
        if (password != null && password!.isNotEmpty) 'password': password,
        'annotations': annotations,
      };

      print('📤 블로그 수정 요청: $blogId');

      final response = await http
          .put(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer user1234', // 실제 토큰으로 변경 필요
            },
            body: json.encode(requestData),
          )
          .timeout(const Duration(seconds: 30));

      final responseBody = response.body;

      if (response.statusCode == 200) {
        try {
          final result = json.decode(responseBody);
          print('✅ 블로그 수정 성공: $blogId');

          return {'success': true, 'message': '블로그가 수정되었습니다', 'data': result};
        } catch (parseError) {
          print('❌ JSON 파싱 실패: $parseError');
          throw Exception('서버 응답 파싱 실패');
        }
      } else {
        print('❌ 블로그 수정 실패: ${response.statusCode}');
        return {'success': false, 'error': '블로그 수정에 실패했습니다'};
      }
    } catch (e) {
      print('❌ 블로그 수정 중 오류: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 태그 업데이트
  void updateTags(List<String> newTags) {
    this.tags = List<String>.from(newTags);
    print('✅ 태그 업데이트: ${tags.join(', ')}');
  }

  // 에디터에서 바로 발행/피드백/네비게이션까지 처리하는 콜백 메서드
  Future<void> publishFromEditor({
    required BuildContext context,
    required MutableDocument document,
    String? title,
    String? thumbnailImageUrl,
    List<String> tags = const [],
    Visibility visibility = Visibility.public,
    required void Function(Map<String, dynamic> contentJson) onSuccess,
    required void Function(String errorMsg) onError,
  }) async {
    try {
      final resolvedTitle =
          title ??
          ((document.nodeCount > 0 && document.getNodeAt(0) is ParagraphNode)
              ? ((document.getNodeAt(0) as ParagraphNode).text.text.isNotEmpty
                  ? (document.getNodeAt(0) as ParagraphNode).text.text
                  : '제목 없음')
              : '제목 없음');
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      final prepareResult = await prepareForPublishing(
        title: resolvedTitle,
        document: document,
        thumbnailImageUrl: thumbnailImageUrl,
        tags: tags,
        visibility: visibility,
      );
      if (prepareResult['success'] == true) {
        final publishResult = await publishBlog();
        Navigator.of(context).pop(); // 로딩 닫기
        if (publishResult['success'] == true) {
          onSuccess(content);
        } else {
          onError('발행 실패: ${publishResult['error'] ?? '알 수 없는 오류'}');
        }
      } else {
        Navigator.of(context).pop();
        onError('발행 준비 실패: ${prepareResult['error'] ?? '알 수 없는 오류'}');
      }
    } catch (e) {
      Navigator.of(context).pop();
      onError('네트워크 오류 또는 알 수 없는 오류: $e');
    }
  }

  // 서비스 상태 초기화
  void reset() {
    title = "";
    content = {};
    thumbnailImageUrl = "";
    tags = [];
    annotations = [];
    visibility = Visibility.public;
    status = BlogStatus.DRAFT;
    sharedGroups = [];
    password = null;
    thumbnailImageId = null;
  }

  // 현재 상태 정보 출력
  void printCurrentState() {
    print('===============================================');
    print('   제목: $title');
    print('   상태: ${status.name}');

    print('   가시성: ${visibility.name}');
    print('   태그: ${tags.join(', ')}');
    print('   공유 그룹: ${sharedGroups.join(', ')}');
    print('   썸네일 ID: $thumbnailImageId');
    print('   비밀번호: ${password != null ? '설정됨' : '없음'}');
  }
}
