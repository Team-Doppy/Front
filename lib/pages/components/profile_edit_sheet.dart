import 'dart:io';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/editor/overlay/link_overlay.dart';
import 'package:flutter/material.dart';
import '../../image/native_image_picker.dart';

class ProfileEditBottomSheet extends StatelessWidget {
  final Future<void> Function() onClearProfileImage;
  final Function(List<File>) onImagesSelected;
  final bool singleSelect;

  const ProfileEditBottomSheet({
    Key? key,
    required this.onClearProfileImage,
    required this.onImagesSelected,
    this.singleSelect = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        padding: const EdgeInsets.only(bottom: 28),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  AppLocalizations.of(context).translate('select_from_gallery'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ),
              onTap: () async {
                // 현재 시트 닫기
                Navigator.pop(context);

                // 네이티브 이미지 선택기 사용
                final picker = NativeImagePicker();
                final files =
                    singleSelect
                        ? await picker.pickSingleImage().then(
                          (f) => f != null ? [f] : <File>[],
                        )
                        : await picker.pickMultipleImages();

                if (files.isNotEmpty) {
                  onImagesSelected(files);
                }
              },
            ),
            ListTile(
              title: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  AppLocalizations.of(context).translate('change_to_default'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ),
              onTap: () async {
                try {
                  await onClearProfileImage();
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${AppLocalizations.of(context).translate('change_failed')}: $e',
                        ),
                        backgroundColor: theme.colorScheme.error,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class ProfileInfoEditBottomSheet extends StatefulWidget {
  final User? user;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final Future<void> Function()? onClearProfileImage;
  final Function(List<File>)? onImagesSelected;
  final Future<void> Function({
    required String alias,
    required String description,
    List<String>? links, // 🎯 프로필 링크 목록 (최대 3개)
    Map<String, String>? linkTitles, // 🎯 링크 타이틀 (URL -> 타이틀)
  })?
  onSave;

  const ProfileInfoEditBottomSheet({
    super.key,
    required this.user,
    required this.nameController,
    required this.descriptionController,
    this.onClearProfileImage,
    this.onImagesSelected,
    this.onSave,
  });

  @override
  State<ProfileInfoEditBottomSheet> createState() =>
      _ProfileInfoEditBottomSheetState();
}

class _ProfileInfoEditBottomSheetState
    extends State<ProfileInfoEditBottomSheet> {
  bool _saving = false;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();

  late String _initialName;
  late String _initialDescription;
  late List<String> _initialLinks; // 🎯 초기 링크 목록 (URL만)
  List<String> _links = []; // 🎯 현재 링크 목록 (URL만, 저장용)
  Map<String, String> _linkTitles = {}; // 🎯 링크 타이틀 저장 (URL -> 타이틀)

  @override
  void initState() {
    super.initState();
    // trim()된 값으로 초기값 저장
    _initialName = widget.nameController.text.trim();
    _initialDescription = widget.descriptionController.text.trim();

    // 🎯 초기 링크 목록 설정
    _initialLinks = List<String>.from(widget.user?.links ?? []);
    _links = List<String>.from(_initialLinks);

    // 🎯 초기 링크 타이틀 설정 (서버에서 받아온 linkTitles 초기화)
    if (widget.user?.linkTitles != null &&
        widget.user!.linkTitles!.isNotEmpty) {
      _linkTitles = Map<String, String>.from(widget.user!.linkTitles!);
    } else {
      _linkTitles = {};
    }

    print(
      '[ProfileEdit] 초기값 저장 - 이름: "$_initialName", 소개: "$_initialDescription", 링크: ${_initialLinks.length}개, 타이틀: ${_linkTitles.length}개',
    );
    print('[ProfileEdit] 초기 링크 타이틀: $_linkTitles');

    // Bottom Sheet 열릴 때 자동으로 별명란에 포커스
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _nameFocus.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    final currentName = widget.nameController.text.trim();
    final currentDescription = widget.descriptionController.text.trim();

    final hasNameChange = currentName != _initialName;
    final hasDescChange = currentDescription != _initialDescription;
    // 🎯 링크 변경 체크 (순서 무관 비교)
    final hasLinksChange = !_listEquals(_links, _initialLinks);

    // 🎯 링크 타이틀 변경 체크
    final initialLinkTitles = widget.user?.linkTitles ?? {};
    final hasLinkTitlesChange = !_mapEquals(_linkTitles, initialLinkTitles);

    print(
      '[ProfileEdit] 변경 체크 - 이름: "$currentName" vs "$_initialName" = $hasNameChange',
    );
    print(
      '[ProfileEdit] 변경 체크 - 소개: "$currentDescription" vs "$_initialDescription" = $hasDescChange',
    );
    print(
      '[ProfileEdit] 변경 체크 - 링크: ${_links.length}개 vs ${_initialLinks.length}개 = $hasLinksChange',
    );
    print(
      '[ProfileEdit] 변경 체크 - 링크 타이틀: ${_linkTitles.length}개 vs ${initialLinkTitles.length}개 = $hasLinkTitlesChange',
    );

    // 별명이 비어있으면 변경사항이 있어도 저장 불가
    if (currentName.isEmpty) {
      return false;
    }

    return hasNameChange ||
        hasDescChange ||
        hasLinksChange ||
        hasLinkTitlesChange;
  }

  // 🎯 리스트 비교 헬퍼 (순서 무관)
  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final aSet = a.toSet();
    final bSet = b.toSet();
    return aSet.length == bSet.length &&
        aSet.every((item) => bSet.contains(item));
  }

  // 🎯 맵 비교 헬퍼
  bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      // 기본 높이 고정: 화면의 85%
      initialChildSize: 0.85,
      minChildSize: 0.6, // 🎯 자동 닫힘 역치 높임 (0.4 -> 0.6)
      maxChildSize: 0.95,
      snap: true, // 🎯 스냅 기능 활성화 (더 많이 드래그해야 닫힘)
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 원형 프로필 + 액션 버튼]
                /*
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          showModalBottomSheet(
                            context: context,
                            builder:
                                (context) => ProfileImageBottomSheet(
                                  onClearProfileImage: () async {
                                    await widget.onClearProfileImage!();
                                  },
                                  onImagesSelected: (files) {
                                    widget.onImagesSelected!(files);
                                  },
                                ),
                          );
                        },
                        child: CommonProfileAvatar(
                          imageUrl: widget.user?.profileImageUrl ?? '',
                          username: widget.user?.username ?? '',
                          size: 150,
                          borderWidth: 2,
                          borderColor: theme.colorScheme.onSurface,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 4,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.photo_camera,
                            color: theme.colorScheme.surface,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),*/
                Text(
                  AppLocalizations.of(context).translate('nickname'),
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                // 별명 텍스트필드
                TextField(
                  controller: widget.nameController,
                  focusNode: _nameFocus,
                  textAlign: TextAlign.center,
                  onChanged: (value) => setState(() {}),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(
                      context,
                    ).translate('nickname_hint'),
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    errorText:
                        widget.nameController.text.trim().isEmpty
                            ? AppLocalizations.of(
                              context,
                            ).translate('nickname_required')
                            : null,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).translate('introduction'),
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                // 소개글 텍스트필드
                TextField(
                  controller: widget.descriptionController,
                  focusNode: _descriptionFocus,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  onChanged: (value) => setState(() {}),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(
                      context,
                    ).translate('introduction_hint'),
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 🎯 링크 섹션
                Row(
                  children: [
                    Text(
                      '링크',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const Spacer(),
                    if (_links.length < 3)
                      GestureDetector(
                        onTap: () => _showLinkOverlay(context),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onSurface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.add,
                            color: Theme.of(context).colorScheme.surface,
                            size: 20,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // 🎯 링크 목록 표시 (Column 내에서 직접 빌드)
                if (_links.isNotEmpty) ...[
                  ...List.generate(_links.length, (index) {
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index < _links.length - 1 ? 8 : 0,
                      ),
                      child: _buildLinkItem(context, _links[index], index),
                    );
                  }),
                  const SizedBox(height: 8),
                ],

                if (_links.isEmpty) ...[
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        '링크가 없습니다',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                const SizedBox(height: 16),

                // 저장 버튼 (별명이 있고 변경사항이 있을 때만)
                if (widget.onSave != null &&
                    _hasChanges &&
                    widget.nameController.text.trim().isNotEmpty)
                  _buildActionButton(
                    context: context,
                    icon: Icons.save,
                    label: AppLocalizations.of(
                      context,
                    ).translate('save_profile'),
                    onTap: () async {
                      final hasChanges = _hasChanges;
                      if (!hasChanges) return;

                      setState(() => _saving = true);

                      try {
                        await widget.onSave!(
                          alias: widget.nameController.text.trim(),
                          description: widget.descriptionController.text.trim(),
                          links: _links.isEmpty ? null : _links,
                          linkTitles: _linkTitles.isEmpty ? null : _linkTitles,
                        );

                        // 저장 완료 후 잠시 대기
                        await Future.delayed(const Duration(milliseconds: 500));

                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        // 에러 처리
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLocalizations.of(
                                  context,
                                ).translate('save_error'),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onError,
                                ),
                              ),
                              backgroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
                  ),
                // 키보드가 올라올 때 하단 여백 추가
                SizedBox(height: keyboardHeight > 0 ? keyboardHeight : 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final hasChanges = _hasChanges;

    return Container(
      height: 55,
      decoration: BoxDecoration(
        color:
            hasChanges
                ? theme.colorScheme.onSurface
                : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _saving ? null : onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_saving) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.surface,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                _saving ? '' : label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.surface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🎯 링크 오버레이 표시 (LinkOverlay 사용)
  void _showLinkOverlay(BuildContext context) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder:
            (_, __, ___) => LinkOverlay(
              autoSubmit: true, // 🎯 링크 추가 시 즉시 제출 (LinkOverlay는 닫지 않음)
              onSubmit: ({
                required String url,
                String? title,
                String? description,
                String? thumbnailUrl,
              }) {
                // 🎯 링크 추가 (최대 3개, 즉시 추가)
                if (mounted) {
                  // 중복 링크 체크
                  if (_links.contains(url)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('이미 추가된 링크입니다'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                    return;
                  }

                  if (_links.length < 3) {
                    setState(() {
                      _links.add(url);
                      // 🎯 타이틀 저장 (직접 작성한 타이틀이 있으면 저장)
                      if (title != null && title.isNotEmpty) {
                        _linkTitles[url] = title;
                      }
                    });
                    // 🎯 LinkOverlay는 닫지 않고 계속 열어둠 (바텀시트도 열어둠)
                  } else {
                    // 이미 3개가 있으면 에러 메시지
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('링크는 최대 3개까지 추가할 수 있습니다'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              },
            ),
      ),
    );
  }

  // 🎯 링크 아이템 빌드
  Widget _buildLinkItem(BuildContext context, String link, int index) {
    // URL 정규화 (표시용)
    String displayUrl = link;
    if (!link.startsWith('http://') && !link.startsWith('https://')) {
      displayUrl = 'https://$link';
    }

    // 도메인 추출 (표시용)
    String domain = link;
    try {
      final uri = Uri.parse(displayUrl);
      domain = uri.host.replaceFirst('www.', '');
    } catch (_) {
      // 파싱 실패 시 원본 link 사용
      domain = link;
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // 🎯 링크 썸네일 또는 아이콘 (나중에 인터넷에서 가져옴)
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Builder(
              builder: (context) {
                // 도메인에서 썸네일 URL 생성 (Google Favicon API)
                String? thumbnailUrl;
                try {
                  final uri = Uri.parse(displayUrl);
                  final domain = uri.host.replaceFirst('www.', '');
                  thumbnailUrl =
                      'https://www.google.com/s2/favicons?domain=$domain&sz=64';
                } catch (_) {
                  thumbnailUrl = null;
                }

                return thumbnailUrl != null
                    ? Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.link,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          size: 20,
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          return child;
                        }
                        return Icon(
                          Icons.link,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                          size: 20,
                        );
                      },
                    )
                    : Icon(
                      Icons.link,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      size: 20,
                    );
              },
            ),
          ),
          const SizedBox(width: 12),
          // 링크 정보
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // 🎯 직접 작성한 타이틀이 있으면 표시, 없으면 도메인 표시
                  _linkTitles.containsKey(link) && _linkTitles[link]!.isNotEmpty
                      ? _linkTitles[link]!
                      : domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  link,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // 삭제 버튼
          GestureDetector(
            onTap: () {
              setState(() {
                final removedUrl = _links.removeAt(index);
                // 🎯 타이틀도 함께 삭제
                _linkTitles.remove(removedUrl);
              });
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.close,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
