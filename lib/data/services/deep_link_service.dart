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
  bool _hasInitialFcmMessage = false; // FCM 초기 메시지가 있는지 추적
  String? _lastProcessedUrl; // ✅ 최근 처리한 URL 캐싱 (중복 방지)
  DateTime? _lastProcessedAt; // ✅ 마지막 처리 시간

  /// FCM 초기 메시지가 있음을 표시 (main()에서 호출)
  void setHasInitialFcmMessage() {
    _hasInitialFcmMessage = true;
  }

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
  /// - /{postId} (경로만, 예: /334)
  /// - /profile/{username} (경로만)
  static DeepLinkResult? parseDeepLink(String? url) {
    if (url == null || url.isEmpty) return null;

    try {
      // ✅ 경로만 들어온 경우 (예: /334, /profile/username) 전체 URL로 보정
      String normalizedUrl = url;
      if (url.startsWith('/') &&
          !url.startsWith('//') &&
          !url.contains('://')) {
        normalizedUrl = 'https://${AppConstants.webDomain}$url';
      }

      final uri = Uri.parse(normalizedUrl);
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
        bool _isNumericId(String s) => RegExp(r'^\d+$').hasMatch(s);

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
        // ✅ path-only(/334, /username) 케이스 처리:
        // - 요구사항: /334 같은 숫자 경로는 포스트로 인식
        // - 반면 /sojulover 같은 문자는 프로필로 인식 (기존 로직은 포스트로 오인해 400 발생 가능)
        if (pathSegments.isNotEmpty && pathSegments.first != 'profile') {
          final first = pathSegments.first;
          final commentId = uri.queryParameters['commentId'];
          final action = uri.queryParameters['action'];

          // ✅ 숫자면 포스트 ID
          if (!_isNumericId(first)) {
            // ✅ 문자는 username으로 간주
            return DeepLinkResult(
              type: DeepLinkType.profile,
              username: _cleanUsername(first),
            );
          }

          final postId = first;
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

    // ✅ unknown 타입 반환 시 URL 로그 (디버깅용)
    debugPrint('[DeepLinkService] 알 수 없는 딥링크 형식: $url');
    return DeepLinkResult(type: DeepLinkType.unknown);
  }

  /// 딥링크 스트림 리스너 등록
  /// [skipInitialLink]가 true이면 getInitialLink()를 호출하지 않음 (FCM 초기 메시지와 중복 방지)
  void listenToDeepLinks(
    Function(DeepLinkResult) onDeepLink, {
    bool skipInitialLink = false,
  }) {
    // 현재 앱이 실행 중일 때 딥링크 받기
    _linkSubscription?.cancel();
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        final uriString = uri.toString();
        debugPrint('[DeepLinkService] 딥링크 수신: $uriString');

        // ✅ URL 레벨 중복 방지 (DeepLinkCoordinator의 결과 레벨 중복 방지와 별개)
        // 짧은 시간(1초) 내 동일 URL은 중복으로 간주
        final now = DateTime.now();
        if (_lastProcessedUrl == uriString &&
            _lastProcessedAt != null &&
            now.difference(_lastProcessedAt!).inMilliseconds < 1000) {
          debugPrint('[DeepLinkService] 🔁 중복 URL 무시: $uriString');
          return;
        }
        _lastProcessedUrl = uriString;
        _lastProcessedAt = now;

        final result = parseDeepLink(uriString);
        if (result != null && result.type != DeepLinkType.unknown) {
          onDeepLink(result);
        } else if (result != null) {
          // unknown 타입도 로그는 남김 (디버깅용)
          debugPrint('[DeepLinkService] 알 수 없는 딥링크 타입: $uriString');
        }
      },
      onError: (err) {
        debugPrint('[DeepLinkService] 딥링크 스트림 오류: $err');
      },
    );

    // 앱이 종료된 상태에서 딥링크로 열린 경우
    // FCM 초기 메시지가 있으면 getInitialLink()를 호출하지 않음 (중복 방지)
    // ✅ 500ms 딜레이 제거: DeepLinkCoordinator가 큐잉 및 타이밍 제어를 담당
    if (!skipInitialLink && !_hasInitialFcmMessage) {
      _appLinks.getInitialLink().then((Uri? uri) {
        if (uri != null) {
          final uriString = uri.toString();
          debugPrint('[DeepLinkService] 초기 딥링크: $uriString');

          // ✅ URL 레벨 중복 방지
          // 짧은 시간(1초) 내 동일 URL은 중복으로 간주
          final now = DateTime.now();
          if (_lastProcessedUrl == uriString &&
              _lastProcessedAt != null &&
              now.difference(_lastProcessedAt!).inMilliseconds < 1000) {
            debugPrint('[DeepLinkService] 🔁 중복 초기 링크 무시: $uriString');
            return;
          }
          _lastProcessedUrl = uriString;
          _lastProcessedAt = now;

          final result = parseDeepLink(uriString);
          if (result != null && result.type != DeepLinkType.unknown) {
            // DeepLinkCoordinator가 앱 준비 상태를 확인하고 큐잉하므로 딜레이 불필요
            onDeepLink(result);
          } else if (result != null) {
            // unknown 타입도 로그는 남김 (디버깅용)
            debugPrint('[DeepLinkService] 알 수 없는 딥링크 타입: $uriString');
          }
        }
      });
    }

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
