import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/data/services/draft_service.dart';

class DraftListOverlay extends StatefulWidget {
  const DraftListOverlay({
    super.key,
    required this.drafts,
    required this.currentDraftId,
    required this.onLoadDraft,
    required this.onDeleteDraft,
  });

  final Map<String, List<DraftData>> drafts;
  final String? currentDraftId;
  final void Function(String draftId) onLoadDraft;
  final void Function(String draftId) onDeleteDraft;

  @override
  State<DraftListOverlay> createState() => _DraftListOverlayState();
}

class _DraftListOverlayState extends State<DraftListOverlay> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const ui.Color.fromARGB(182, 144, 144, 144),
        elevation: 0,
        title: const Text('임시저장 목록', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // 배경 블러 + 반투명
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: const ui.Color.fromARGB(182, 144, 144, 144),
                ),
              ),
            ),
          ),

          // 임시저장 목록
          Positioned(
            top: 120,
            left: 8,
            right: 8,
            bottom: 100,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child:
                    widget.drafts.isEmpty
                        ? _buildEmptyState()
                        : _buildDraftList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_outlined,
            color: AppColors.darkTextSecondary.withOpacity(0.5),
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            '임시저장된 글이 없습니다',
            style: TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: widget.drafts.length,
      itemBuilder: (context, index) {
        final title = widget.drafts.keys.elementAt(index);
        final drafts = widget.drafts[title]!;
        return _buildDraftGroup(title, drafts);
      },
    );
  }

  Widget _buildDraftGroup(String title, List<DraftData> drafts) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 그룹 헤더
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${drafts.length}개 버전',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.darkTextSecondary,
                  ),
                ),
              ],
            ),
          ),

          // 버전 목록
          ...drafts.map((draft) => _buildDraftItem(draft)).toList(),
        ],
      ),
    );
  }

  Widget _buildDraftItem(DraftData draft) {
    final title = draft.title.isNotEmpty ? draft.title : '무제';

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 16),
      decoration: BoxDecoration(
        color: AppColors.darkBorder.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border:
            widget.currentDraftId == draft.id
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: () {
          widget.onLoadDraft(draft.id);
          Navigator.of(context).pop();
        },
        leading: CircleAvatar(
          radius: 16,
          backgroundColor:
              widget.currentDraftId == draft.id
                  ? AppColors.primary
                  : AppColors.darkTextSecondary,
          child: Text(
            title.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            color:
                widget.currentDraftId == draft.id
                    ? AppColors.primary
                    : AppColors.darkTextPrimary,
            fontWeight:
                widget.currentDraftId == draft.id
                    ? FontWeight.w600
                    : FontWeight.w400,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '저장: ${_formatDateTime(draft.updatedAt)}',
          style: const TextStyle(
            color: AppColors.darkTextSecondary,
            fontSize: 11,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.currentDraftId == draft.id)
              const Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 18,
              ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => widget.onDeleteDraft(draft.id),
              child: const Icon(
                Icons.delete_outline,
                color: Colors.red,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }
}
