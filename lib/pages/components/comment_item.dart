import 'package:doppy/pages/components/comment_image_full_viewer.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/comment_reaction_users_bottom_sheet.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver/image_gallery_saver.dart';
// NOTE: 댓글 이미지는 editor처럼 단순 NetworkImage + cacheWidth로만 처리 (CachedNetworkImage 사용 금지)
import 'dart:io';
import 'dart:ui';

/// 개별 댓글 아이템 위젯
class CommentItem extends StatelessWidget {
  const CommentItem({
    super.key,
    required this.comment,
    required this.commentService,
    required this.currentUser,
    required this.isMe,
    required this.showProfile,
    required this.showAuthorInfo,
    required this.onReactionToggle,
    required this.onLongPress,
    required this.bounceAnimationValue,
    required this.isAnimating,
    required this.onTapTargetComment,
    required this.targetComment,
    required this.globalKey,
    required this.onSwipeReply,
    required this.dragOffset,
    this.onProfileTap,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.postAuthorUsername,
    this.enableImageHero = true,
    this.customBottomPadding,
    this.onImageTap, // 🎯 이미지 클릭 콜백 (프리뷰에서 댓글 시트로 이동용)
  });

  final Comment comment;
  final CommentService commentService;
  final User? currentUser;
  final bool isMe;
  final bool showProfile;
  final bool showAuthorInfo;
  final Function(String commentId, String emoji) onReactionToggle;
  final Function(Offset globalPosition, Comment comment) onLongPress;
  final double bounceAnimationValue;
  final bool isAnimating;
  final Function(String commentId) onTapTargetComment;
  final Comment? targetComment;
  final GlobalKey? globalKey;
  final VoidCallback onSwipeReply;
  final Function(String username)? onProfileTap; // 🎯 프로필 탭 콜백 (선택적)
  final double dragOffset; // 🎯 드래그 오프셋 (부모에서 관리)
  final Function(DragUpdateDetails)? onHorizontalDragUpdate; // 🎯 드래그 업데이트 핸들러
  final Function(DragEndDetails)? onHorizontalDragEnd; // 🎯 드래그 종료 핸들러
  final String? postAuthorUsername; // 🎯 포스트 작성자 username (비밀댓글 권한 체크용)
  final bool enableImageHero; // ✅ 라우트 전환 시 Hero flight 방지용 (프리뷰에서는 false)
  final double? customBottomPadding; // 🎯 외부에서 지정하는 하단 패딩 (다른 작성자 간 간격 조절용)
  final VoidCallback? onImageTap; // 🎯 이미지 클릭 콜백 (프리뷰에서 댓글 시트로 이동용)

  /// 🎯 비밀댓글에 대한 권한 체크
  /// 작성자이거나 포스트 작성자인 경우에만 true 반환
  bool _canInteractWithPrivateComment() {
    // 공개 댓글이면 항상 true
    if (comment.visibility != 'PRIVATE' && !comment.isSecret) {
      return true;
    }

    // 비밀댓글이면 작성자이거나 포스트 작성자만 true
    final currentUsername = currentUser?.username;
    if (currentUsername == null) {
      return false;
    }

    // 작성자 확인
    if (comment.author == currentUsername) {
      return true;
    }

    // 포스트 작성자 확인
    if (postAuthorUsername != null && postAuthorUsername == currentUsername) {
      return true;
    }

    return false;
  }

  BorderRadius _getBorderRadius() {
    // 첫 번째 버블 (꼬리 있음)
    if (showProfile && showAuthorInfo) {
      return BorderRadius.only(
        topLeft: Radius.circular(isMe ? 20 : 20),
        topRight: Radius.circular(isMe ? 20 : 20),
        bottomLeft: Radius.circular(isMe ? 20 : 4),
        bottomRight: Radius.circular(isMe ? 4 : 20),
      );
    }

    // 마지막 버블 (꼬리 있음, 꼬리 반대편을 더 둥글게)
    if (!showProfile && showAuthorInfo) {
      return BorderRadius.only(
        topLeft: Radius.circular(isMe ? 20 : 4),
        topRight: Radius.circular(isMe ? 6 : 20),
        bottomLeft: Radius.circular(isMe ? 20 : 20), // ← 더 둥글게
        bottomRight: Radius.circular(isMe ? 20 : 20), // ← 더 둥글게
      );
    }

    // 첫 번째이지만 마지막 아님 (위를 더 둥글게)
    if (showProfile && !showAuthorInfo) {
      return BorderRadius.only(
        topLeft: Radius.circular(isMe ? 24 : 24), // ← 더 둥글게
        topRight: Radius.circular(isMe ? 24 : 24), // ← 더 둥글게
        bottomLeft: Radius.circular(isMe ? 20 : 6),
        bottomRight: Radius.circular(isMe ? 6 : 20),
      );
    }

    // 가운데 버블 (양쪽 모서리만 약간 둥글게)
    return BorderRadius.only(
      topLeft: Radius.circular(isMe ? 20 : 6),
      topRight: Radius.circular(isMe ? 6 : 20),
      bottomLeft: Radius.circular(isMe ? 20 : 6),
      bottomRight: Radius.circular(isMe ? 6 : 20),
    );
  }

  String _formatRelativeTime(BuildContext context, String isoString) {
    try {
      return TimeUtils.formatRelativeTimeFromUtc(context, isoString);
    } catch (e) {
      final loc = AppLocalizations.of(context);
      return loc.translate('just_now');
    }
  }

  /// 🎯 @username 언급이 포함된 텍스트를 파싱하여 RichText로 변환
  Widget _buildTextWithMentions(BuildContext context, bool isMe) {
    final text = comment.content;
    final baseStyle = TextStyle(
      color: isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
      fontSize: 15,
      height: 1.35,
    );
    final mentionStyle = TextStyle(
      color: isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
      fontSize: 15,
      height: 1.35,
      decoration: TextDecoration.underline,
      decorationColor:
          isMe
              ? Colors.white.withOpacity(0.8)
              : Theme.of(context).colorScheme.primary.withOpacity(0.8),
    );

    // @username 패턴 찾기 (정규식: @ 다음에 공백이나 줄바꿈 전까지의 문자)
    final mentionRegex = RegExp(r'@(\w+)');
    final matches = mentionRegex.allMatches(text);

    if (matches.isEmpty) {
      // 언급이 없으면 일반 텍스트
      return Text(text, style: baseStyle);
    }

    // TextSpan 리스트 생성
    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      // 언급 전의 일반 텍스트
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: baseStyle,
          ),
        );
      }

      // 언급 텍스트 (@username)
      final username = match.group(1)!;
      final mentionText = match.group(0)!; // @username 전체

      spans.add(
        TextSpan(
          text: mentionText,
          style: mentionStyle,
          recognizer:
              TapGestureRecognizer()
                ..onTap = () {
                  // 프로필 화면으로 이동
                  if (onProfileTap != null) {
                    onProfileTap!(username);
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (context) => UserProfileScreen(
                              otherUser: User(
                                username: username,
                                profileImageUrl: '', // 프로필 이미지는 서버에서 가져올 수 있음
                              ),
                            ),
                      ),
                    );
                  }
                },
        ),
      );

      lastEnd = match.end;
    }

    // 마지막 일반 텍스트
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
    }

    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final canInteract = _canInteractWithPrivateComment();
    // 🎯 비밀댓글에 권한이 없으면 이모지 반응도 숨김
    final hasReactions =
        comment.emotionCounts.isNotEmpty &&
        (canInteract || !(comment.isSecret || comment.visibility == 'PRIVATE'));

    return GestureDetector(
      // 🎯 비밀댓글에 권한이 없으면 스와이프 답장 비활성화
      onHorizontalDragUpdate:
          (canInteract && onHorizontalDragUpdate != null)
              ? (details) => onHorizontalDragUpdate!(details)
              : null,
      onHorizontalDragEnd:
          (canInteract && onHorizontalDragEnd != null)
              ? (details) => onHorizontalDragEnd!(details)
              : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(dragOffset, 0, 0),
        child: Padding(
          key: globalKey,
          padding: EdgeInsets.only(
            top: showProfile ? 8 : 2,
            bottom: customBottomPadding ?? (showAuthorInfo ? 8 : 2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe) ...[
                if (showProfile)
                  _buildProfileImage(context)
                else
                  const SizedBox(width: 34),
                const SizedBox(width: 4),
              ],

              Expanded(
                child: Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment:
                        isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                    children: [
                      // 댓글 버블 (답글인 경우 타겟도 포함)
                      _buildCommentBubble(context, hasReactions),

                      // 반응 표시
                      if (hasReactions) _buildReactions(context),
                      // 시간 표시
                      if (showAuthorInfo) _buildTimeStamp(context),
                    ],
                  ),
                ),
              ),

              if (isMe) ...[
                const SizedBox(width: 4),
                // 🎯 내 채팅일 때는 프로필 이미지 표시 안 함
                const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 🎯 이미지 URL 추출 (content에서 파싱 또는 imageUrl 필드 사용) - 단일 이미지만 반환
  String? _extractImageUrl() {
    // 🎯 1순위: imageUrl 필드 사용 (서버에서 직접 제공)
    if (comment.imageUrl != null &&
        comment.imageUrl!.isNotEmpty &&
        !comment.imageUrl!.startsWith('pending://')) {
      return comment.imageUrl!;
    }

    // 🎯 2순위: [IMAGES:url1,url2,url3] 형식 파싱 (첫 번째만)
    if (comment.content.contains('[IMAGES:')) {
      final regex = RegExp(r'\[IMAGES:(.+?)\]');
      final match = regex.firstMatch(comment.content);
      if (match != null) {
        final urlsString = match.group(1);
        if (urlsString != null) {
          final urls =
              urlsString
                  .split(',')
                  .map((url) => url.trim())
                  .where((url) => url.isNotEmpty)
                  .toList();
          if (urls.isNotEmpty) {
            return urls.first; // 🎯 첫 번째만 반환
          }
        }
      }
    }
    // 🎯 3순위: [IMAGE] url 형식 파싱
    else if (comment.content.contains('[IMAGE] ')) {
      final parts = comment.content.split('[IMAGE] ');
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        return parts[1].trim();
      }
    }

    return null;
  }

  /// 🎯 이미지 위젯 빌드 (로컬 이미지 우선, 없으면 네트워크 이미지) - 단일 이미지
  Widget _buildImageWidget(BuildContext context) {
    final imageUrl = _extractImageUrl();
    final hasLocalImage =
        comment.localImagePath != null && comment.localImagePath!.isNotEmpty;
    final hasNetworkImage = imageUrl != null;

    if (!hasLocalImage && !hasNetworkImage) {
      return const SizedBox.shrink();
    }

    // 🎯 로컬 이미지가 있으면 계속 로컬 이미지 사용 (전환 없음)
    // 로컬 이미지가 한 번 로드되면 네트워크 이미지로 바꾸지 않음
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child:
            hasLocalImage
                ? _buildLocalImageWidget(context)
                : (imageUrl != null
                    ? _buildNetworkImageWidget(context, imageUrl)
                    : const SizedBox.shrink()),
      ),
    );
  }

  /// 🎯 로컬 이미지 위젯 빌드
  Widget _buildLocalImageWidget(BuildContext context) {
    final imageProvider = FileImage(File(comment.localImagePath!));
    return Stack(
      key: ValueKey('local_${comment.id}_${comment.localImagePath}'),
      children: [
        GestureDetector(
          onTap: () {
            // 🎯 onImageTap 콜백이 있으면 호출 (프리뷰에서 댓글 시트로 이동)
            if (onImageTap != null) {
              onImageTap!();
            } else {
              // 기본 동작: 전체화면 뷰어 열기
              _showImageFullscreen(
                context,
                imageProvider,
                null,
                comment.localImagePath!,
              );
            }
          },
          child:
              enableImageHero
                  ? Hero(
                    tag: 'comment_image_${comment.id}', // 🎯 Hero 태그
                    child: Image(
                      image: imageProvider,
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 200,
                          height: 200,
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.5),
                          child: Icon(
                            Icons.broken_image,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.5),
                          ),
                        );
                      },
                    ),
                  )
                  : Image(
                    image: imageProvider,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 200,
                        height: 200,
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withOpacity(0.5),
                        child: Icon(
                          Icons.broken_image,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                        ),
                      );
                    },
                  ),
        ),
        // 🎯 실패 시에만 작은 X, 새로고침 버튼 표시 (하단)
        if (comment.isFailed)
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      commentService.removeFailedComment(comment.id);
                    },
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      commentService.retryComment(comment.id);
                    },
                    child: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 🎯 네트워크 이미지 위젯 빌드
  Widget _buildNetworkImageWidget(BuildContext context, String imageUrl) {
    return Stack(
      key: ValueKey('network_${comment.id}_$imageUrl'),
      children: [
        (enableImageHero
            ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Hero(
                tag: 'comment_image_${comment.id}', // 🎯 Hero 태그
                child: GestureDetector(
                  onTap: () {
                    // 🎯 onImageTap 콜백이 있으면 호출 (프리뷰에서 댓글 시트로 이동)
                    if (onImageTap != null) {
                      onImageTap!();
                    } else {
                      // 기본 동작: 전체화면 뷰어 열기
                      _showImageFullscreen(
                        context,
                        NetworkImage(imageUrl),
                        imageUrl,
                        null,
                      );
                    }
                  },
                  child: RepaintBoundary(
                    child: _CommentNetworkImageCore(
                      imageUrl: imageUrl,
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            )
            : ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: GestureDetector(
                onTap: () {
                  // 🎯 onImageTap 콜백이 있으면 호출 (프리뷰에서 댓글 시트로 이동)
                  if (onImageTap != null) {
                    onImageTap!();
                  } else {
                    // 기본 동작: 전체화면 뷰어 열기
                    _showImageFullscreen(
                      context,
                      NetworkImage(imageUrl),
                      imageUrl,
                      null,
                    );
                  }
                },
                child: RepaintBoundary(
                  child: _CommentNetworkImageCore(
                    imageUrl: imageUrl,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            )),
        // 🎯 실패 시에만 작은 X, 새로고침 버튼 표시 (하단)
        if (comment.isFailed)
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      commentService.removeFailedComment(comment.id);
                    },
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      commentService.retryComment(comment.id);
                    },
                    child: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProfileImage(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 🎯 프로필 탭 콜백이 있으면 사용, 없으면 기본 동작 (프로필 화면으로 이동)
        if (onProfileTap != null) {
          onProfileTap!(comment.author);
        } else {
          // 기본 동작: 프로필 화면으로 이동
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (context) => UserProfileScreen(
                    otherUser: User(
                      username: comment.author,
                      profileImageUrl: comment.authorProfileImageUrl,
                    ),
                  ),
            ),
          );
        }
      },
      child: CommonProfileAvatar(
        backgroundColor: Colors.transparent,
        imageUrl: comment.authorProfileImageUrl,
        username: comment.author,
        size: 34,
        borderWidth: 0,
      ),
    );
  }

  Widget _buildCommentBubble(BuildContext context, bool hasReactions) {
    final canInteract = _canInteractWithPrivateComment();

    // 🎯 이미지 URL 추출
    final imageUrl = _extractImageUrl();

    // 🎯 이미지만 있는지 확인
    final hasImage =
        (comment.localImagePath != null &&
            comment.localImagePath!.isNotEmpty) ||
        imageUrl != null;
    final isImageOnly =
        hasImage &&
        (comment.content == '[IMAGE]' ||
            comment.content.startsWith('[IMAGE] ') ||
            comment.content.contains('[IMAGES:'));

    return GestureDetector(
      onDoubleTap:
          canInteract
              ? () {
                HapticFeedback.lightImpact();
                // 어떤 이모지든 있으면 취소, 없으면 ❤️ 추가
                if (comment.myEmotions.isNotEmpty) {
                  // 기존 이모지 취소
                  final currentEmoji = comment.myEmotions.keys.first;
                  onReactionToggle(comment.id, currentEmoji);
                } else {
                  // ❤️ 추가
                  onReactionToggle(comment.id, '❤️');
                }
              }
              : null, // 비밀댓글에 권한 없으면 더블탭 비활성화
      onLongPressStart:
          canInteract
              ? (details) {
                HapticFeedback.mediumImpact();
                onLongPress(details.globalPosition, comment);
              }
              : null, // 비밀댓글에 권한 없으면 롱프레스 비활성화
      child: Transform.scale(
        scale: isAnimating ? bounceAnimationValue : 1.0,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.55,
          ),
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            // 🎯 이미지만 있는 댓글은 배경색과 테두리 없음 (완전 투명)
            color:
                (hasImage && isImageOnly)
                    ? Colors.transparent
                    : (hasImage
                        ? Colors.transparent
                        : (isMe
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                              context,
                            ).colorScheme.surfaceVariant.withOpacity(0.9))),
            borderRadius: (hasImage && isImageOnly) ? null : _getBorderRadius(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 타겟 댓글이 있으면 표시
              if (targetComment != null) ...[
                GestureDetector(
                  onTap: () => onTapTargetComment(targetComment!.id),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${targetComment!.author}',
                          style: TextStyle(
                            color:
                                isMe
                                    ? Colors.white.withOpacity(0.8)
                                    : Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        // 🎯 [IMAGE] 마커가 아닐 때만 텍스트 표시
                        if (targetComment!.content.isNotEmpty &&
                            targetComment!.content != '[IMAGE]')
                          Text(
                            targetComment!.content,
                            style: TextStyle(
                              color:
                                  isMe
                                      ? Colors.white.withOpacity(0.7)
                                      : Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.6),
                              fontSize: 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(
                    height: 1,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.2),
                  ),
                ),
              ],
              // 내 답글 내용
              // 🎯 이미지만 있는 경우: 패딩 없이 정렬 (내 댓글: 오른쪽, 타인 댓글: 왼쪽)
              if (hasImage && isImageOnly) ...[
                // 🎯 이미지만 있는 경우: 내 댓글이면 오른쪽, 타인 댓글이면 왼쪽 정렬
                Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: _buildImageWidget(context),
                ),
              ] else ...[
                // 🎯 이미지 + 텍스트 또는 텍스트만 있는 경우
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    targetComment != null ? 8 : 8,
                    12,
                    8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 🎯 이미지 표시 (있으면)
                      if (hasImage) ...[
                        _buildImageWidget(context),
                        // 🎯 텍스트가 있으면 간격 추가
                        if (comment.content.isNotEmpty && !isImageOnly)
                          const SizedBox(height: 8),
                      ],
                      // 🎯 텍스트 내용 (있으면, [IMAGE] 마커 제외)
                      if (comment.content.isNotEmpty && !isImageOnly)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: _buildTextWithMentions(context, isMe),
                            ),
                            // 🎯 비밀댓글 자물쇠 아이콘
                            if (comment.isSecret ||
                                comment.visibility == 'PRIVATE') ...[
                              const SizedBox(width: 4),
                              SvgPicture.asset(
                                'assets/icons/lock.svg',
                                width: 10,
                                height: 10,
                                colorFilter: ColorFilter.mode(
                                  isMe
                                      ? Colors.white.withOpacity(0.7)
                                      : Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.6),
                                  BlendMode.srcIn,
                                ),
                              ),
                            ],
                          ],
                        ),
                      // 전송 실패 시 재시도/삭제 버튼
                      if (comment.isFailed) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () {
                                commentService.retryComment(comment.id);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),

                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.refresh,
                                      size: 20,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                commentService.removeFailedComment(comment.id);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  size: 20,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactions(BuildContext context) {
    final canInteract = _canInteractWithPrivateComment();

    // 🎯 비밀댓글에 권한이 없으면 이모지 반응 버튼 숨김
    if (!canInteract && (comment.isSecret || comment.visibility == 'PRIVATE')) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in comment.emotionCounts.entries)
            if (entry.value != '0')
              GestureDetector(
                onTap:
                    canInteract
                        ? () {
                          // 🎯 모든 이모지와 사용자 정보를 하나의 바텀시트에 표시
                          final emotionData = <String, dynamic>{};
                          for (final emojiEntry
                              in comment.emotionCounts.entries) {
                            final emoji = emojiEntry.key;
                            final count =
                                int.tryParse(emojiEntry.value.toString()) ?? 0;
                            if (count > 0) {
                              final users = comment.emotionUsers[emoji] ?? [];
                              emotionData[emoji] = {
                                'count': count,
                                'users': users,
                              };
                            }
                          }

                          if (emotionData.isNotEmpty) {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              isScrollControlled: true,
                              builder:
                                  (context) => CommentReactionUsersBottomSheet(
                                    emotionData: emotionData,
                                    commentId: comment.id,
                                    onReactionToggle: onReactionToggle,
                                  ),
                            );
                          }
                        }
                        : null, // 비밀댓글에 권한 없으면 탭 비활성화
                child: Container(
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  child: Row(
                    children: [
                      Text(
                        '${entry.key}${entry.value}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildTimeStamp(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        _formatRelativeTime(context, comment.createdAt),
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
      ),
    );
  }

  /// 🎯 이미지 전체화면 보기 (Hero 애니메이션으로 인스타그램 느낌)
  void _showImageFullscreen(
    BuildContext context,
    ImageProvider imageProvider, // 🎯 이미지 객체 전달 (재로드 방지)
    String? imageUrl, // 🎯 다운로드용 URL
    String? localImagePath, // 🎯 로컬 이미지 경로
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        // ✅ opaque=false면 아래 화면이 비치면서 "깜빡임/배경색 변화"가 더 잘 보임
        // 댓글 이미지 뷰어는 배경색을 안정적으로 유지하기 위해 opaque=true로 고정
        opaque: true,
        barrierColor: Colors.transparent, // ✅ Hero 애니메이션 시 어두워지는 효과 제거
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return CommentImageFullscreenDialog(
            imageProvider: imageProvider,
            imageUrl: imageUrl,
            localImagePath: localImagePath,
            heroTag: 'comment_image_${comment.id}', // 🎯 Hero 태그
            comment: comment, // 🎯 댓글 정보 전달
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

/// ✅ 완전 기본형(캐시/리사이즈/keepAlive 없이) 댓글 네트워크 이미지
/// - Image.network만 사용
/// - 쉬머는 frameBuilder로 "첫 프레임" 뜰 때까지 표시
/// - 이미지가 한 번 로드되면 이후에는 쉬머가 뜨지 않음 (상태 유지)
class _CommentNetworkImageCore extends StatefulWidget {
  const _CommentNetworkImageCore({
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  State<_CommentNetworkImageCore> createState() =>
      _CommentNetworkImageCoreState();
}

class _CommentNetworkImageCoreState extends State<_CommentNetworkImageCore> {
  bool _didLoadOnce = false; // 🎯 이미지가 한 번 로드되었는지 추적

  @override
  Widget build(BuildContext context) {
    final br = widget.borderRadius ?? BorderRadius.zero;
    return ClipRRect(
      borderRadius: br,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Image.network(
          widget.imageUrl,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            // 🎯 이미지가 한 번 로드되었으면 쉬머 표시하지 않음
            if (_didLoadOnce) {
              return child;
            }

            // 🎯 첫 프레임이 로드되면 플래그 설정
            if (wasSynchronouslyLoaded || frame != null) {
              // 다음 프레임에 플래그 설정 (setState 최소화)
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_didLoadOnce) {
                  setState(() {
                    _didLoadOnce = true;
                  });
                }
              });
              return child;
            }

            // 🎯 첫 로드 시에만 쉬머 표시
            return ShimmerBox(
              width: widget.width ?? 200,
              height: widget.height ?? 200,
              borderRadius: br,
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: widget.width ?? 200,
              height: widget.height ?? 200,
              color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
              child: Icon(
                Icons.broken_image,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            );
          },
        ),
      ),
    );
  }
}
