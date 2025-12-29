import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doppy/main.dart';

/// 🎯 딥링크 타입
enum DeepLinkType {
  post, // 포스트
  postWithComment, // 포스트 + 댓글
  postWithLikes, // 포스트 + 좋아요
  postWithChat, // 포스트 + 채팅
  profile, // 프로필
  friendRequest, // 친구 요청
  unknown, // 알 수 없음
}

/// 🎯 딥링크 URL 파싱 결과
class DeepLinkResult {
  final DeepLinkType type;
  final String? postId;
  final String? commentId;
  final String? username;

  DeepLinkResult({
    required this.type,
    this.postId,
    this.commentId,
    this.username,
  });
}

/// 🎯 딥링크 처리 서비스
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<Uri>? _uriLinkSubscription;

  /// 딥링크 URL 파싱
  /// 지원 형식:
  /// - doppy://post/{postId}?commentId={commentId}
  /// - doppy://post/{postId}?action=likes
  /// - doppy://post/{postId}
  /// - https://${AppConstants.webDomain}/{postId}/{slug}?commentId={commentId}
  /// - https://${AppConstants.webDomain}/{postId}/{slug}?action=likes
  /// - https://${AppConstants.webDomain}/{postId}/{slug}
  /// - https://${AppConstants.webDomain}/profile/{username}
  /// - https://doppy.app/{postId}/{slug} (리다이렉트되지만 파싱은 지원)
  static DeepLinkResult? parseDeepLink(String? url) {
    if (url == null || url.isEmpty) return null;

    try {
      final uri = Uri.parse(url);
      String _cleanUsername(String raw) {
        final trimmed = raw.trim();
        return trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
      }

      // URL 스킴이 doppy://인 경우
      if (uri.scheme == 'doppy') {
        // doppy://app/post/{postId}, doppy://app/profile/{username} 같은 라우팅 변형 지원
        // (웹 "앱에서 열기" 버튼 구현에서 종종 이런 형태를 사용)
        if (uri.host == 'app' && uri.pathSegments.isNotEmpty) {
          final first = uri.pathSegments.first;
          if (first == 'post') {
            final postId =
                uri.pathSegments.length >= 2
                    ? uri.pathSegments[1]
                    : (uri.queryParameters['postId'] ??
                        uri.queryParameters['id'] ??
                        '');
            if (postId.isNotEmpty) {
              final commentId = uri.queryParameters['commentId'];
              final action = uri.queryParameters['action'];
              if (commentId != null && commentId.isNotEmpty) {
                return DeepLinkResult(
                  type: DeepLinkType.postWithComment,
                  postId: postId,
                  commentId: commentId,
                );
              } else if (action == 'likes') {
                return DeepLinkResult(
                  type: DeepLinkType.postWithLikes,
                  postId: postId,
                );
              } else if (action == 'chat') {
                return DeepLinkResult(
                  type: DeepLinkType.postWithChat,
                  postId: postId,
                );
              } else {
                return DeepLinkResult(type: DeepLinkType.post, postId: postId);
              }
            }
          } else if (first == 'profile') {
            final usernameRaw =
                uri.pathSegments.length >= 2
                    ? uri.pathSegments[1]
                    : (uri.queryParameters['username'] ??
                        uri.queryParameters['user'] ??
                        '');
            if (usernameRaw.isNotEmpty) {
              return DeepLinkResult(
                type: DeepLinkType.profile,
                username: _cleanUsername(usernameRaw),
              );
            }
          } else if (first == 'friends' &&
              uri.pathSegments.length >= 2 &&
              uri.pathSegments[1] == 'requests') {
            return DeepLinkResult(type: DeepLinkType.friendRequest);
          }
        }

        // doppy://post/{postId}?commentId={commentId}
        if (uri.host == 'post') {
          final pathSegments = uri.pathSegments;
          final postId =
              pathSegments.isNotEmpty
                  ? pathSegments.first
                  : (uri.queryParameters['postId'] ??
                      uri.queryParameters['id'] ??
                      '');
          if (postId.isNotEmpty) {
            final commentId = uri.queryParameters['commentId'];
            final action =
                uri.queryParameters['action']; // 'likes', 'comments', 'chat'

            if (commentId != null && commentId.isNotEmpty) {
              return DeepLinkResult(
                type: DeepLinkType.postWithComment,
                postId: postId,
                commentId: commentId,
              );
            } else if (action == 'likes') {
              return DeepLinkResult(
                type: DeepLinkType.postWithLikes,
                postId: postId,
              );
            } else if (action == 'chat') {
              return DeepLinkResult(
                type: DeepLinkType.postWithChat,
                postId: postId,
              );
            } else {
              return DeepLinkResult(type: DeepLinkType.post, postId: postId);
            }
          }
        }

        // doppy://profile/{username}
        if (uri.host == 'profile') {
          final pathSegments = uri.pathSegments;
          final usernameRaw =
              pathSegments.isNotEmpty
                  ? pathSegments.first
                  : (uri.queryParameters['username'] ??
                      uri.queryParameters['user'] ??
                      '');
          if (usernameRaw.isNotEmpty) {
            final username = _cleanUsername(usernameRaw);
            return DeepLinkResult(
              type: DeepLinkType.profile,
              username: username,
            );
          }
        }

        // doppy://friends/requests
        if (uri.host == 'friends' && uri.pathSegments.isNotEmpty) {
          if (uri.pathSegments.first == 'requests') {
            return DeepLinkResult(type: DeepLinkType.friendRequest);
          }
        }
      }

      // HTTPS URL인 경우 (Universal Links / App Links)
      // www.doppy.app과 doppy.app 모두 지원 (doppy.app은 리다이렉트되지만 파싱은 지원)
      if (uri.scheme == 'https' &&
          (uri.host == AppConstants.webDomain || uri.host == 'doppy.app')) {
        final pathSegments = uri.pathSegments;

        // www.doppy.app/profile/{username} 또는 https://doppy.app/profile/{username}
        if (pathSegments.isNotEmpty && pathSegments.first == 'profile') {
          if (pathSegments.length >= 2) {
            final username = _cleanUsername(pathSegments[1]);
            return DeepLinkResult(
              type: DeepLinkType.profile,
              username: username,
            );
          }
        }

        // https://{domain}/post/{postId}/... (웹 라우팅 변형 지원)
        if (pathSegments.isNotEmpty && pathSegments.first == 'post') {
          if (pathSegments.length >= 2) {
            final postId = pathSegments[1];
            final commentId = uri.queryParameters['commentId'];
            final action = uri.queryParameters['action'];
            if (commentId != null && commentId.isNotEmpty) {
              return DeepLinkResult(
                type: DeepLinkType.postWithComment,
                postId: postId,
                commentId: commentId,
              );
            } else if (action == 'likes') {
              return DeepLinkResult(
                type: DeepLinkType.postWithLikes,
                postId: postId,
              );
            } else if (action == 'chat') {
              return DeepLinkResult(
                type: DeepLinkType.postWithChat,
                postId: postId,
              );
            } else {
              return DeepLinkResult(type: DeepLinkType.post, postId: postId);
            }
          }
        }

        // www.doppy.app/{postId}/{slug}?commentId={commentId} 또는 https://doppy.app/{postId}/{slug}?commentId={commentId}
        // 첫 번째 path segment가 'profile'이 아니면 포스트로 간주
        if (pathSegments.isNotEmpty && pathSegments.first != 'profile') {
          final postId = pathSegments.first;
          final commentId = uri.queryParameters['commentId'];
          final action = uri.queryParameters['action'];

          if (commentId != null && commentId.isNotEmpty) {
            return DeepLinkResult(
              type: DeepLinkType.postWithComment,
              postId: postId,
              commentId: commentId,
            );
          } else if (action == 'likes') {
            return DeepLinkResult(
              type: DeepLinkType.postWithLikes,
              postId: postId,
            );
          } else if (action == 'chat') {
            return DeepLinkResult(
              type: DeepLinkType.postWithChat,
              postId: postId,
            );
          } else {
            return DeepLinkResult(type: DeepLinkType.post, postId: postId);
          }
        }
      }
    } catch (e) {
      debugPrint('[DeepLinkService] URL 파싱 오류: $e');
    }

    return DeepLinkResult(type: DeepLinkType.unknown);
  }

  /// 딥링크 스트림 리스너 등록
  void listenToDeepLinks(Function(DeepLinkResult) onDeepLink) {
    // 현재 앱이 실행 중일 때 딥링크 받기
    _linkSubscription?.cancel();
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('[DeepLinkService] 딥링크 수신: $uri');
        final result = parseDeepLink(uri.toString());
        if (result != null && result.type != DeepLinkType.unknown) {
          onDeepLink(result);
        }
      },
      onError: (err) {
        debugPrint('[DeepLinkService] 딥링크 스트림 오류: $err');
      },
    );

    // 앱이 종료된 상태에서 딥링크로 열린 경우
    _appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        debugPrint('[DeepLinkService] 초기 딥링크: $uri');
        final result = parseDeepLink(uri.toString());
        if (result != null && result.type != DeepLinkType.unknown) {
          // 약간의 딜레이를 주어 앱 초기화 완료 후 처리
          Future.delayed(const Duration(milliseconds: 500), () {
            onDeepLink(result);
          });
        }
      }
    });

    debugPrint('[DeepLinkService] 딥링크 리스너 등록 완료');
  }

  /// 딥링크 리스너 해제
  void dispose() {
    _linkSubscription?.cancel();
    _uriLinkSubscription?.cancel();
    _linkSubscription = null;
    _uriLinkSubscription = null;
  }
}
