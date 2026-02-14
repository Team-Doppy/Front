import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../editor/data/draft.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/utils/dialog_util.dart';
import '../utils/editor_localization.dart';
import '../../editor/config/editor_config.dart';
import '../../editor/config/emum_config.dart';
import '../../editor/service/post_export_service.dart';
import '../../editor/component/clip_component.dart';
import '../../editor/service/node_component_service.dart';
import 'undo_redo_buttons.dart';

/// 발행 시 호출하는 콜백 - context는 Navigator 접근용(PostwriteAppBar의 context 전달)
/// [isEditMode] true면 수정 모드에서 나온 페이로드 → 업데이트 API 호출, false면 생성 API 호출
/// [currentDraftId] 발행 성공 시 해당 임시저장 삭제용 (있으면 전달)
typedef OnPublishCallback =
    Future<void> Function(
      BuildContext context, {
      required String title,
      required String? thumbnailImageUrl,
      required String accessLevel,
      required String exportedJson,
      bool isEditMode,
      String? existingPostId,
      String? currentDraftId,
    });

class PostwriteAppBar extends StatefulWidget implements PreferredSizeWidget {
  final DraftData? draftData;
  final VoidCallback? onLoadDraft;
  final EditorService editorService;
  final Future<bool> Function()? onSaveDraft;
  final bool networkMode;
  final OnPublishCallback? onPublish;
  final bool isEditMode;
  final String? existingPostId;

  /// 발행 성공 시 이 드래프트를 임시저장 목록에서 삭제 (자동저장·수동 임시저장 모두)
  final String? currentDraftId;

  const PostwriteAppBar({
    super.key,
    required this.editorService,
    required this.networkMode,
    this.draftData,
    this.onSaveDraft,
    this.onLoadDraft,
    this.onPublish,
    this.isEditMode = false,
    this.existingPostId,
    this.currentDraftId,
  });

  @override
  State<PostwriteAppBar> createState() => _PostwriteAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _PostwriteAppBarState extends State<PostwriteAppBar> {
  bool _isNextLoading = false;

  Future<void> _onNextButtonTapped(BuildContext context) async {
    // 업로드 중인 미디어가 있으면 진행 차단
    if (widget.networkMode && widget.editorService.hasUnuploadedMedia()) {
      await DialogUtils.showInfoDialog(
        context,
        title: context.tr('editor_wait_for_media_upload'),
        message: context.tr('editor_media_still_uploading'),
      );
      return;
    }

    // 본문 검증
    if (!widget.editorService.hasNonEmptyBody(context: context)) {
      await DialogUtils.showInfoDialog(
        context,
        title: context.tr('editor_content_required'),
        message: context.tr('editor_body_required'),
      );
      return;
    }

    // 제목 검증
    final doc = widget.editorService.document;
    final titleStatus = PostExporter.getTitleNodeStatus(doc);
    String? userEnteredTitle;
    if (titleStatus.hasTitleNode && titleStatus.titleNodeEmpty) {
      await DialogUtils.showInfoDialog(
        context,
        title: context.tr('editor_title_required'),
        message: context.tr('editor_title_required'),
      );
      return;
    }
    if (!titleStatus.hasTitleNode) {
      final entered = await DialogUtils.showTextInputDialog(
        context,
        title: context.tr('editor_title_required'),
        hintText: context.tr('editor_title_required'),
        confirmText: context.tr('editor_next'),
        cancelText: context.tr('editor_cancel'),
      );
      if (entered == null || entered.trim().isEmpty) {
        return;
      }
      userEnteredTitle = entered.trim();
    }

    muteAllVideos();
    NodeComponentService().selectNode(null);

    // 문서 내보내기
    String json;
    try {
      json = PostExporter.exportToJsonString(
        pretty: true,
        forPublishing: widget.networkMode,
        // 로컬 모드에서는 "업로드 없음"이 정상 플로우이므로 로컬 경로를 그대로 페이로드에 포함한다.
        allowPartialUpload: !widget.networkMode,
        editorService: widget.editorService,
      );
    } catch (e) {
      final detailMessage =
          e is StateError
              ? e.message
              : (e is Exception ? e.toString() : e.toString());
      final message =
          detailMessage == PostExporter.kUploadWaitKey
              ? context.tr(PostExporter.kUploadWaitKey)
              : (detailMessage.isNotEmpty
                  ? detailMessage
                  : context.tr('editor_error_occurred'));
      await DialogUtils.showInfoDialog(
        context,
        title: context.tr('editor_error'),
        message: message,
      );

      return;
    }

    // 발행 파라미터 명시적 결정 (폴백 ?? 사용 금지)
    final map = jsonDecode(json) as Map<String, dynamic>;

    String title;
    if (userEnteredTitle != null && userEnteredTitle.isNotEmpty) {
      title = userEnteredTitle.trim();
    } else if (widget.draftData != null &&
        widget.draftData!.title.isNotEmpty &&
        widget.draftData!.title.trim().isNotEmpty) {
      title = widget.draftData!.title.trim();
    } else {
      final fromExport = map['title'] as Object?;
      if (fromExport != null && fromExport.toString().trim().isNotEmpty) {
        title = fromExport.toString().trim();
      } else {
        title = '';
      }
    }

    AccessLevel accessLevel;
    if (widget.draftData != null && widget.draftData!.visibility != null) {
      accessLevel = widget.draftData!.visibility!;
    } else {
      accessLevel = EditorConfig.defaultPublishAccessLevel;
    }

    // thumbnailImageUrl: draftData에 없으면 본문 첫 이미지(대표이미지)로 채움
    String? thumbnailImageUrl;
    if (widget.draftData != null &&
        widget.draftData!.thumbnailUrl != null &&
        widget.draftData!.thumbnailUrl!.trim().isNotEmpty) {
      thumbnailImageUrl = widget.draftData!.thumbnailUrl!.trim();
    } else {
      final firstBodyImage = PostContentUtils.findFirstBodyImageUrl(map);
      thumbnailImageUrl = firstBodyImage.isNotEmpty ? firstBodyImage : null;
    }

    map['title'] = title;
    map['thumbnailImageUrl'] = thumbnailImageUrl;
    map['accessLevel'] = accessLevel.name;
    json = jsonEncode(map);

    if (widget.onPublish != null) {
      if (!mounted) return;
      setState(() => _isNextLoading = true);

      try {
        if (!mounted) return;
        await widget.onPublish!(
          context,
          title: title,
          thumbnailImageUrl: thumbnailImageUrl,
          accessLevel: accessLevel.name,
          exportedJson: json,
          isEditMode: widget.isEditMode,
          existingPostId: widget.existingPostId,
          currentDraftId: widget.currentDraftId,
        );
      } catch (e) {
        if (!mounted) return;
        await DialogUtils.showInfoDialog(
          context,
          title: context.tr('editor_error'),
          message:
              e is Exception
                  ? e.toString().replaceFirst('Exception: ', '')
                  : e.toString(),
        );
      } finally {
        if (mounted) {
          setState(() => _isNextLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 상태바 배경도 앱바 자체에서 칠한다(외부 TopPadding 의존 제거).
    final bgColor = Theme.of(context).colorScheme.surface;
    return Container(
      color: bgColor,
      child: SafeArea(
        bottom: false,
        child: ClipRRect(
          child: Container(
            decoration: BoxDecoration(color: bgColor),
            height: kToolbarHeight,
            width: MediaQuery.of(context).size.width,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 왼쪽 버튼들 (뒤로가기 + 언두/리두)
                Row(
                  children: [
                    SizedBox(width: 4),
                    // 뒤로가기 버튼
                    IconButton(
                      onPressed: () async {
                        Navigator.of(context).maybePop();
                      },
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 22,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.75),
                      ),
                    ),

                    UndoRedoButtons(
                      editorService: widget.editorService,
                      defaultPadding: EdgeInsets.only(bottom: 2),
                      // androidPadding: ...,  // 필요 시 플랫폼별 조절
                      // iosPadding: ...,
                    ),
                  ],
                ),

                // 오른쪽 버튼들
                Row(
                  children: [
                    // 더보기 메뉴
                    _isNextLoading
                        ? const SizedBox.shrink()
                        : PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                            size: 20,
                          ),
                          elevation: 0,

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceVariant.withOpacity(0.9),
                          offset: const Offset(45, 45),
                          onSelected: (value) {
                            if (value == 'load') {
                              widget.onLoadDraft?.call();
                            } else if (value == 'save') {
                              widget.onSaveDraft?.call();
                            }
                          },
                          itemBuilder:
                              (context) => [
                                PopupMenuItem(
                                  value: 'load',
                                  child: Text(
                                    context.tr('editor_load_draft'),
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'save',
                                  child: Text(
                                    context.tr('editor_save_draft'),
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                        ),

                    // 다음 버튼 (로딩 중에는 스피너)
                    _isNextLoading
                        ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        )
                        : TextButton(
                          onPressed: () => _onNextButtonTapped(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            widget.isEditMode
                                ? context.tr('editor_finish_edit')
                                : context.tr('editor_next'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                    const SizedBox(width: 10),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
