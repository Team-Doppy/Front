import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/user_provider.dart';

/// 🎯 링크 리스트 바텀시트
class LinkBottomSheet extends StatelessWidget {
  final List<String> links;
  final Map<String, String>? linkTitles;
  final Map<String, String>? linkThumbnails;
  final User? otherUser; // 다른 사용자의 링크인 경우

  const LinkBottomSheet({
    Key? key,
    required this.links,
    this.linkTitles,
    this.linkThumbnails,
    this.otherUser,
  }) : super(key: key);

  static void show(
    BuildContext context, {
    required List<String> links,
    Map<String, String>? linkTitles,
    Map<String, String>? linkThumbnails,
    User? otherUser,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isDismissible: true,
      builder: (BuildContext context) {
        return LinkBottomSheet(
          links: links,
          linkTitles: linkTitles,
          linkThumbnails: linkThumbnails,
          otherUser: otherUser,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.transparent),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 제목
                    Text(
                      '${l10n.t('link')} (${links.length})',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // 링크 리스트
                    if (links.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          l10n.t('no_links'),
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: links.length,
                          itemBuilder: (context, index) {
                            final isOther = otherUser != null;
                            final userProvider = context.read<UserProvider>();
                            final me = userProvider.currentUser;
                            final linkThumbnailsForItem =
                                isOther
                                    ? (otherUser?.linkThumbnails)
                                    : (me?.linkThumbnails);
                            return _LinkTile(
                              url: links[index],
                              linkTitles: linkTitles,
                              linkThumbnails:
                                  linkThumbnailsForItem ?? linkThumbnails,
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 24),
                    // 취소 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.onSurface
                              .withOpacity(0.03),
                          foregroundColor: theme.colorScheme.onSurface,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          l10n.t('cancel'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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

/// 🎯 링크 타일 위젯
class _LinkTile extends StatelessWidget {
  final String url;
  final Map<String, String>? linkTitles;
  final Map<String, String>? linkThumbnails;

  const _LinkTile({required this.url, this.linkTitles, this.linkThumbnails});

  @override
  Widget build(BuildContext context) {
    // URL 정규화
    String displayUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      displayUrl = 'https://$url';
    }

    // 도메인 추출
    String domain = url;
    String? thumbnailUrl;

    // 🎯 저장된 썸네일 우선 사용 (서버에서 받아온 linkThumbnails)
    // 원본 URL과 정규화된 URL 모두 확인 (URL 정규화 차이 대응)
    if (linkThumbnails != null) {
      // 원본 URL로 먼저 확인
      thumbnailUrl = linkThumbnails![url];
      // 정규화된 URL로도 확인
      if ((thumbnailUrl == null || thumbnailUrl.isEmpty) &&
          linkThumbnails!.containsKey(displayUrl)) {
        thumbnailUrl = linkThumbnails![displayUrl];
      }
      // 역방향도 확인 (정규화된 URL이 키인 경우)
      // Uri.parse를 사용하여 query parameter를 제외하고 비교
      if ((thumbnailUrl == null || thumbnailUrl.isEmpty)) {
        try {
          final urlUri = Uri.parse(displayUrl);
          final urlBase = '${urlUri.scheme}://${urlUri.host}${urlUri.path}';
          for (final entry in linkThumbnails!.entries) {
            final keyUrl = entry.key;
            try {
              final keyUri = Uri.parse(
                keyUrl.startsWith('http://') || keyUrl.startsWith('https://')
                    ? keyUrl
                    : 'https://$keyUrl',
              );
              final keyBase = '${keyUri.scheme}://${keyUri.host}${keyUri.path}';
              // 기본 URL이 일치하면 (query parameter 무시)
              if (urlBase == keyBase || keyUrl == url || keyUrl == displayUrl) {
                thumbnailUrl = entry.value;
                break;
              }
            } catch (_) {
              // 파싱 실패 시 문자열 비교
              if (keyUrl == url || keyUrl == displayUrl) {
                thumbnailUrl = entry.value;
                break;
              }
            }
          }
        } catch (_) {
          // 파싱 실패 시 문자열 비교
          for (final entry in linkThumbnails!.entries) {
            if (entry.key == url || entry.key == displayUrl) {
              thumbnailUrl = entry.value;
              break;
            }
          }
        }
      }
    }

    // 저장된 썸네일이 없으면 Google Favicon API 사용
    if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
      try {
        final uri = Uri.parse(displayUrl);
        domain = uri.host.replaceFirst('www.', '');
        // 🎯 썸네일 URL 생성 (Google Favicon API 또는 도메인 기반)
        thumbnailUrl =
            'https://www.google.com/s2/favicons?domain=$domain&sz=64';
      } catch (_) {
        domain = url;
      }
    } else {
      // 썸네일이 있으면 도메인만 추출 (표시용)
      try {
        final uri = Uri.parse(displayUrl);
        domain = uri.host.replaceFirst('www.', '');
      } catch (_) {
        domain = url;
      }
    }

    // 🎯 사용자가 설정한 커스텀 타이틀 가져오기
    final customTitle = linkTitles?[url];
    final displayTitle = customTitle ?? domain; // 커스텀 타이틀이 있으면 사용, 없으면 도메인

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: InkWell(
        onTap: () async {
          try {
            final uri = Uri.parse(displayUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            // 바텀시트 닫기
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          } catch (e) {
            if (context.mounted) {
              ErrorHandler.showError(context, '링크를 열 수 없습니다: $url');
            }
          }
        },
        child: Row(
          children: [
            // 🎯 링크 썸네일
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child:
                  thumbnailUrl != null
                      ? CachedNetworkImage(
                        imageUrl: thumbnailUrl,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        memCacheWidth: 80,
                        maxWidthDiskCache: 200,
                        errorWidget: (context, url, error) {
                          return Icon(
                            Icons.link,
                            size: 20,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          );
                        },
                        placeholder: (context, url) {
                          return Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.3,
                                ),
                              ),
                            ),
                          );
                        },
                      )
                      : Icon(
                        Icons.link,
                        size: 20,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
            ),
            const SizedBox(width: 12),
            // 링크 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🎯 커스텀 타이틀 또는 도메인 표시
                  Text(
                    displayTitle,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // URL 표시
                  Text(
                    url,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
