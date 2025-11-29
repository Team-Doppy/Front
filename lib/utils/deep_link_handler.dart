import 'package:flutter/material.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/deep_link_service.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/data/services/like_service.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/pages/screens/group_selection_screen.dart';
import 'package:doppy/pages/components/liked_users_bottom_sheet.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/utils/access_level_parser.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/editor/service/post_reader_service.dart';
import 'package:provider/provider.dart';
import 'package:doppy/providers/friend_provider.dart';

/// 🎯 딥링크 처리 헬퍼
class DeepLinkHandler {
  /// 딥링크 처리 및 네비게이션
  static Future<void> handleDeepLink(
    BuildContext context,
    DeepLinkResult result,
  ) async {
    try {
      switch (result.type) {
        case DeepLinkType.post:
        case DeepLinkType.postWithComment:
        case DeepLinkType.postWithLikes:
        case DeepLinkType.postWithChat:
          if (result.postId != null && result.postId!.isNotEmpty) {
            await _handlePostDeepLink(context, result);
          } else {
            debugPrint('[DeepLinkHandler] postId가 없습니다');
            ErrorHandler.showError(context, '포스트를 찾을 수 없습니다.');
          }
          break;

        case DeepLinkType.profile:
          if (result.username != null && result.username!.isNotEmpty) {
            _handleProfileDeepLink(context, result.username!);
          } else {
            debugPrint('[DeepLinkHandler] username이 없습니다');
            ErrorHandler.showError(context, '프로필을 찾을 수 없습니다.');
          }
          break;

        case DeepLinkType.friendRequest:
          await _handleFriendRequestDeepLink(context);
          break;

        case DeepLinkType.unknown:
          debugPrint('[DeepLinkHandler] 알 수 없는 딥링크 타입');
          break;
      }
    } catch (e) {
      debugPrint('[DeepLinkHandler] 딥링크 처리 오류: $e');
      if (context.mounted) {
        ErrorHandler.showError(context, '링크를 처리할 수 없습니다.');
      }
    }
  }

  /// 포스트 딥링크 처리
  /// 🎯 필요한 데이터를 순서대로 로드한 후 화면으로 이동
  static Future<void> _handlePostDeepLink(
    BuildContext context,
    DeepLinkResult result,
  ) async {
    final postId = result.postId!;
    final blogService = BlogService();
    final postReaderService = PostReaderService();
    final commentService = CommentService();
    final likeService = LikeService();

    try {
      // 1️⃣ 포스트 데이터 로드 (메타데이터 + 컨텐츠 병렬)
      debugPrint('[DeepLinkHandler] 1/5 포스트 데이터 로드 중...');
      final futures = await Future.wait([
        blogService.getPostMetadata(postId),
        blogService.getPostContent(postId),
      ]);

      final postMetadata = futures[0];
      final postContent = futures[1];

      // 🎯 메타데이터와 컨텐츠를 병합
      final postData = <String, dynamic>{
        ...postMetadata,
        ...postContent, // content, isLiked, likeCount, commentCount 포함
      };

      if (postData.isEmpty) {
        debugPrint('[DeepLinkHandler] 포스트 데이터가 비어있습니다');
        if (context.mounted) {
          ErrorHandler.showError(context, '포스트를 찾을 수 없습니다.');
        }
        return;
      }

      // 🎯 디버깅: content에 mediaId가 있는지 확인
      final content = postData['content'] as Map<String, dynamic>? ?? {};
      if (content.containsKey('nodes')) {
        final nodes = content['nodes'] as List?;
        if (nodes != null) {
          for (final node in nodes) {
            if (node is Map && node['type'] == 'video') {
              final data = node['data'] as Map?;
              debugPrint(
                '[DeepLinkHandler] 🎬 video 노드 - node.mediaId: ${node['mediaId']}, data.mediaId: ${data?['mediaId']}',
              );
            } else if (node is Map && node['type'] == 'image') {
              final data = node['data'] as Map?;
              debugPrint(
                '[DeepLinkHandler] 🖼️ image 노드 - node.mediaId: ${node['mediaId']}, data.mediaId: ${data?['mediaId']}',
              );
            }
          }
        }
      }

      // PostData 형식으로 변환
      final exported = _convertToExportedData(postData);

      // 2️⃣ 좋아요/댓글 데이터 초기화
      debugPrint('[DeepLinkHandler] 2/5 좋아요/댓글 데이터 초기화 중...');
      likeService.setInitialLikeData(
        postId,
        postData['isLiked'] == true,
        postData['likeCount'] as int? ?? 0,
      );
      commentService.setPostId(postId);
      commentService.setInitialCommentCount(
        postData['commentCount'] as int? ?? 0,
      );

      // 3️⃣ 댓글/좋아요 미리 로드 (병렬)
      debugPrint('[DeepLinkHandler] 3/5 댓글/좋아요 미리 로드 중...');
      await Future.wait([
        commentService.loadComments(), // 🎯 기본 크기(100개)로 로드
        LikedUsersBottomSheet.preloadLikedUsers(postId).catchError((_) {}),
      ]);

      debugPrint('[DeepLinkHandler] ✅ 필수 데이터 로딩 완료!');

      // 4️⃣ 이미지/비디오 프리로드 (백그라운드)
      if (context.mounted) {
        Future.microtask(() async {
          try {
            final imageUrls = postReaderService.extractImageUrls(content);
            if (imageUrls.isNotEmpty) {
              postReaderService.preloadImages(context, imageUrls, maxCount: 6);
            }
          } catch (_) {}
        });
      }

      // 5️⃣ 네비게이션 준비
      PostReaderInitialAction? initialAction;
      String? scrollToCommentId;
      if (result.type == DeepLinkType.postWithComment &&
          result.commentId != null) {
        initialAction = PostReaderInitialAction.showComments;
        scrollToCommentId = result.commentId;
      } else if (result.type == DeepLinkType.postWithLikes) {
        initialAction = PostReaderInitialAction.showLikes;
      } else if (result.type == DeepLinkType.postWithChat) {
        // 🎯 채팅 딥링크: 댓글창 열기
        initialAction = PostReaderInitialAction.showComments;
      }

      // PostReaderScreen으로 네비게이션 (이미 로드된 content 전달)
      if (context.mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder:
                (context, animation, secondaryAnimation) => PostReaderScreen(
                  exported: exported,
                  heroTag: 'deep-link-post-$postId',
                  initialAction: initialAction,
                  scrollToCommentId: scrollToCommentId,
                  preloadedContent: content, // 🎯 이미 로드된 content 전달
                ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 100),
          ),
        );
      }
    } catch (e) {
      debugPrint('[DeepLinkHandler] 포스트 딥링크 처리 오류: $e');
      if (context.mounted) {
        ErrorHandler.showError(context, '포스트를 불러올 수 없습니다.');
      }
    }
  }

  /// 프로필 딥링크 처리
  static void _handleProfileDeepLink(BuildContext context, String username) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(otherUser: User(username: username)),
      ),
    );
  }

  /// 친구 요청 딥링크 처리
  /// 🎯 필요한 데이터를 순서대로 로드한 후 화면으로 이동
  static Future<void> _handleFriendRequestDeepLink(BuildContext context) async {
    try {
      // 1️⃣ 친구 데이터 로드 (받은 요청 포함)
      debugPrint('[DeepLinkHandler] 1/2 친구 데이터 로드 중...');
      final friendProvider = Provider.of<FriendProvider>(
        context,
        listen: false,
      );
      await friendProvider.fetchAllFriendData(forceRefresh: true);

      if (!context.mounted) return;

      debugPrint('[DeepLinkHandler] ✅ 친구 데이터 로딩 완료!');

      // 2️⃣ 내 그룹 화면으로 이동 (딥링크 플래그 전달)
      debugPrint('[DeepLinkHandler] 2/2 내 그룹 화면으로 이동 중...');
      await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  const GroupSelectionScreen(showReceivedRequests: true),
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (e) {
      debugPrint('[DeepLinkHandler] 친구 요청 딥링크 처리 오류: $e');
      if (context.mounted) {
        ErrorHandler.showError(context, '친구 요청을 불러올 수 없습니다.');
      }
    }
  }

  /// 서버 응답을 exported 데이터 형식으로 변환
  static Map<String, dynamic> _convertToExportedData(
    Map<String, dynamic> postData,
  ) {
    final content = postData['content'] as Map<String, dynamic>? ?? {};
    final parsed = AccessLevelParser.parseAccessLevelFromContent(postData);

    // 🎯 authorId 파싱
    int? authorId;
    if (postData['authorId'] != null) {
      authorId =
          (postData['authorId'] is int)
              ? (postData['authorId'] as int)
              : int.tryParse('${postData['authorId']}');
    }

    return {
      'id': postData['postId']?.toString() ?? postData['id']?.toString() ?? '',
      'thumbnailImageUrl': postData['thumbnailImageUrl']?.toString() ?? '',
      'title': postData['title']?.toString() ?? '',
      'summary': postData['summary']?.toString() ?? '',
      'author': postData['author']?.toString() ?? '',
      'authorId': authorId,
      'authorProfileImageUrl':
          postData['authorProfileImageUrl']?.toString() ?? '',
      'content': content,
      'accessLevel': parsed['accessLevel'] as String? ?? 'PUBLIC',
      'sharedGroupIds': parsed['sharedGroupIds'] as List<int>?,
      'sharedGroupNames': parsed['sharedGroupNames'] as List<String>?,
      'likeCount': postData['likeCount'] as int? ?? 0,
      'commentCount': postData['commentCount'] as int? ?? 0,
      'isLiked': postData['isLiked'] == true,
      'stickers': [],
    };
  }
}
