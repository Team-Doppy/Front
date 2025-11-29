import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/comment_reaction_users_bottom_sheet.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/services/comment_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver/image_gallery_saver.dart';
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

  String _formatRelativeTime(String isoString) {
    try {
      // UTC 시간을 로컬 시간으로 변환
      final dateTime = TimeUtils.toLocalTime(isoString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return '방금';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}분 전';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}시간 전';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}일 전';
      } else {
        return '${(difference.inDays / 7).floor()}주 전';
      }
    } catch (e) {
      return '방금';
    }
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
            bottom: showAuthorInfo ? 8 : 2,
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

  /// 🎯 이미지 위젯 빌드 (로컬 이미지 또는 네트워크 이미지)
  Widget _buildImageWidget(BuildContext context) {
    if (comment.localImagePath != null && comment.localImagePath!.isNotEmpty) {
      // 🎯 로컬 이미지 표시 (업로드 중)
      final imageProvider = FileImage(File(comment.localImagePath!));
      return RepaintBoundary(
        child: ClipRRect(
          key: ValueKey(
            'image_widget_local_${comment.id}_${comment.localImagePath}',
          ),
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              GestureDetector(
                onTap: () {
                  _showImageFullscreen(
                    context,
                    imageProvider,
                    null,
                    comment.localImagePath!,
                  );
                },
                child: Image(
                  image: imageProvider,
                  key: ValueKey(
                    'local_image_${comment.id}_${comment.localImagePath}',
                  ),
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
              // 🎯 업로드 중 로딩 인디케이터
              if (comment.isPending)
                Container(
                  width: 200,
                  height: 200,
                  color: Colors.black.withOpacity(0.3),
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      // 🎯 네트워크 이미지 표시
      String? imageUrlToDisplay;
      if (comment.content.startsWith('[IMAGE] ')) {
        final parts = comment.content.split('[IMAGE] ');
        if (parts.length > 1 && parts[1].trim().isNotEmpty) {
          imageUrlToDisplay = parts[1].trim();
        }
      } else if (comment.imageUrl != null &&
          comment.imageUrl!.isNotEmpty &&
          !comment.imageUrl!.startsWith('pending://')) {
        imageUrlToDisplay = comment.imageUrl;
      }

      if (imageUrlToDisplay == null) {
        return const SizedBox.shrink();
      }

      final imageUrl = imageUrlToDisplay; // 🎯 null 체크 후 non-null로 사용

      return RepaintBoundary(
        child: ClipRRect(
          key: ValueKey('image_widget_network_${comment.id}_$imageUrl'),
          borderRadius: BorderRadius.circular(8),
          child: _CachedNetworkImageWidget(
            imageUrl: imageUrl,
            commentId: comment.id,
            onImageTap: (imageProvider) {
              _showImageFullscreen(context, imageProvider, imageUrl, null);
            },
          ),
        ),
      );
    }
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
    String? imageUrlToDisplay;
    if (comment.localImagePath != null && comment.localImagePath!.isNotEmpty) {
      // 로컬 이미지가 있으면 로컬 이미지 표시
      imageUrlToDisplay = null; // 로컬 이미지 사용
    } else if (comment.content.startsWith('[IMAGE] ')) {
      // content에서 URL 추출: "[IMAGE] https://..."
      final parts = comment.content.split('[IMAGE] ');
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        imageUrlToDisplay = parts[1].trim();
      }
    } else if (comment.imageUrl != null &&
        comment.imageUrl!.isNotEmpty &&
        !comment.imageUrl!.startsWith('pending://')) {
      imageUrlToDisplay = comment.imageUrl;
    }

    // 🎯 이미지만 있는지 확인
    final hasImage =
        (comment.localImagePath != null &&
            comment.localImagePath!.isNotEmpty) ||
        imageUrlToDisplay != null;
    final isImageOnly =
        comment.content == '[IMAGE]' || comment.content.startsWith('[IMAGE] ');

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
                              child: Text(
                                comment.content,
                                style: TextStyle(
                                  color:
                                      isMe
                                          ? Colors.white
                                          : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                  fontSize: 15,
                                  height: 1.35,
                                ),
                              ),
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
        _formatRelativeTime(comment.createdAt),
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
      ),
    );
  }

  /// 🎯 이미지 전체화면 보기 (배경 블러 + 가운데 이미지 + 다운로드 버튼)
  void _showImageFullscreen(
    BuildContext context,
    ImageProvider imageProvider, // 🎯 이미지 객체 전달 (재로드 방지)
    String? imageUrl, // 🎯 다운로드용 URL
    String? localImagePath, // 🎯 로컬 이미지 경로
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder:
          (context) => _CommentImageFullscreenDialog(
            imageProvider: imageProvider, // 🎯 이미지 객체 전달
            imageUrl: imageUrl,
            localImagePath: localImagePath,
          ),
    );
  }
}

/// 🎯 캐시된 네트워크 이미지 위젯 (스크롤 시 Shimmer 재표시 방지)
class _CachedNetworkImageWidget extends StatefulWidget {
  final String imageUrl;
  final String commentId;
  final Function(ImageProvider) onImageTap; // 🎯 이미지 탭 콜백 (ImageProvider 전달)

  const _CachedNetworkImageWidget({
    required this.imageUrl,
    required this.commentId,
    required this.onImageTap,
  });

  @override
  State<_CachedNetworkImageWidget> createState() =>
      _CachedNetworkImageWidgetState();
}

class _CachedNetworkImageWidgetState extends State<_CachedNetworkImageWidget> {
  // 🎯 Image 위젯에서 사용하는 NetworkImage (풀뷰와 동일한 인스턴스로 캐시 공유)
  late final NetworkImage _imageProvider;

  @override
  void initState() {
    super.initState();
    // 🎯 NetworkImage 인스턴스 생성 (Image 위젯과 풀뷰에서 동일한 인스턴스 사용)
    _imageProvider = NetworkImage(widget.imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 🎯 이미지 위젯에서 사용하는 ImageProvider 전달 (캐시된 이미지 재사용)
        widget.onImageTap(_imageProvider);
      },
      child: Image(
        image:
            _imageProvider, // 🎯 Image.network 대신 Image 위젯에 직접 전달 (같은 인스턴스 사용)
        key: ValueKey('network_image_${widget.commentId}_${widget.imageUrl}'),
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 200,
            height: 200,
            color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
            child: Icon(
              Icons.broken_image,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          );
        },
      ),
    );
  }
}

/// 🎯 댓글 이미지 전체화면 다이얼로그
class _CommentImageFullscreenDialog extends StatefulWidget {
  final ImageProvider imageProvider; // 🎯 이미지 객체 (재로드 방지)
  final String? imageUrl; // 🎯 다운로드용 URL
  final String? localImagePath; // 🎯 로컬 이미지 경로

  const _CommentImageFullscreenDialog({
    required this.imageProvider,
    required this.imageUrl,
    required this.localImagePath,
  });

  @override
  State<_CommentImageFullscreenDialog> createState() =>
      _CommentImageFullscreenDialogState();
}

class _CommentImageFullscreenDialogState
    extends State<_CommentImageFullscreenDialog> {
  bool _isDownloading = false;
  bool _isDownloaded = false;

  Future<void> _downloadImage() async {
    if (_isDownloading || _isDownloaded) return;

    // 로컬 이미지는 다운로드 불가
    if (widget.localImagePath != null) {
      return;
    }

    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _isDownloaded = false;
    });

    try {
      final response = await http.get(Uri.parse(widget.imageUrl!));

      if (response.statusCode == 200) {
        final result = await ImageGallerySaver.saveImage(
          response.bodyBytes,
          quality: 100,
          name: 'doppy_image_${DateTime.now().millisecondsSinceEpoch}',
        );

        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isDownloaded = result != null && result['isSuccess'] == true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isDownloaded = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[CommentImageFullscreen] 다운로드 실패: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isDownloaded = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // 🎯 배경 투명 (블러 제거)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.transparent),
            ),
          ),
          // 🎯 가운데 이미지
          Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: Stack(
                  children: [
                    // 🎯 이미지 (전달받은 ImageProvider 사용, 재로드 없음)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image(
                        image: widget.imageProvider, // 🎯 전달받은 이미지 객체 사용
                        fit: BoxFit.contain,
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
                    // 🎯 닫기 X 버튼 (우측 상단)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    // 🎯 다운로드 버튼 (이미지 하단, 흰색 배경)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child:
                            widget.localImagePath == null &&
                                    widget.imageUrl != null
                                ? ElevatedButton.icon(
                                  onPressed:
                                      (_isDownloading || _isDownloaded)
                                          ? null
                                          : _downloadImage,
                                  icon:
                                      _isDownloading
                                          ? SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.black87,
                                                  ),
                                            ),
                                          )
                                          : _isDownloaded
                                          ? Icon(
                                            Icons.check,
                                            color: Colors.black87,
                                          )
                                          : Icon(
                                            Icons.download,
                                            color: Colors.black87,
                                          ),
                                  label: Text(
                                    _isDownloading
                                        ? '다운로드 중...'
                                        : _isDownloaded
                                        ? AppLocalizations.of(
                                          context,
                                        ).translate('done')
                                        : '다운로드',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black87,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    elevation: 2,
                                  ),
                                )
                                : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 댓글 메뉴를 여는 helper 함수
Future<String?> openCommentMenu(
  BuildContext context, {
  required Offset anchor,
  required Comment comment,
  required bool isMyComment, // 내 댓글인지 여부
  String? postAuthorUsername, // 🎯 포스트 작성자 username (비밀댓글 권한 체크용)
}) async {
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      anchor.dx - 140,
      anchor.dy + 20,
      anchor.dx,
      anchor.dy,
    ),
    constraints: BoxConstraints(minWidth: 180, maxWidth: 180),

    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    elevation: 8,

    items: [
      // 이모지 반응 (가로 배치)
      PopupMenuItem<String>(
        enabled: false, // 부모 아이템은 클릭 불가
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final emoji in ['❤️', '👍', '😆', '😮', '😭'])
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop(emoji);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    emoji,
                    style: TextStyle(
                      fontSize: 24,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),

      // 답글 (비밀댓글일 때는 호출하는 쪽에서 권한 체크 후 메뉴를 열므로, 여기서는 항상 표시)
      PopupMenuItem<String>(
        value: 'reply',
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Text(
            AppLocalizations.of(context).translate('reply'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      // 수정 (내 댓글만)
      if (isMyComment)
        PopupMenuItem<String>(
          value: 'edit',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Text(
              AppLocalizations.of(context).translate('edit'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      // 삭제 (내 댓글만)
      if (isMyComment)
        PopupMenuItem<String>(
          value: 'delete',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Text(
              AppLocalizations.of(context).translate('delete'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      // 복사
      PopupMenuItem<String>(
        value: 'copy',
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Text(
            AppLocalizations.of(context).translate('copy'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ],
  );
}
