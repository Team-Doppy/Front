import 'dart:io';
import 'dart:ui';

import 'package:doppy/data/models/group_model.dart';
import 'package:doppy/data/services/upload_service.dart'; // 🎯 UploadService 추가
import 'package:doppy/image/profile_image_bottom_sheet.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart'; // 🎯 ErrorHandler 추가
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

// 그룹 아이템 (스와이프 액션 포함)
class _GroupItemWithActions extends StatefulWidget {
  final Group group;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GroupItemWithActions({
    required this.group,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_GroupItemWithActions> createState() => _GroupItemWithActionsState();
}

class _GroupItemWithActionsState extends State<_GroupItemWithActions> {
  double _dragOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          // 왼쪽으로만 밀기 지원 (primaryDelta가 음수)
          _dragOffset += details.primaryDelta!;
          // 오른쪽으로 밀리는 것 방지 및 왼쪽으로 제한
          if (_dragOffset > 0) _dragOffset = 0;
          if (_dragOffset < -200) _dragOffset = -200;
        });
      },
      onHorizontalDragEnd: (details) {
        // 스냅: 일정 이상 밀리면 고정(-140), 아니면 원위치(0)
        const double openThreshold = -30.0;
        setState(() {
          _dragOffset = (_dragOffset <= openThreshold) ? -140.0 : 0.0;
        });
      },
      onTap: () {
        // 탭은 항목 선택으로 처리
        if (_dragOffset != 0) {
          // 드래그 상태면 먼저 닫기
          setState(() {
            _dragOffset = 0.0;
          });
          // no-op
        } else {
          widget.onTap();
        }
      },
      child: Stack(
        children: [
          // 수정 버튼 (드래그된 부분의 왼쪽, 파란색)
          if (_dragOffset < 0)
            Positioned(
              left: MediaQuery.of(context).size.width + _dragOffset,
              top: 0,
              bottom: 0,
              width: 70,
              child: GestureDetector(
                onTap: () async {
                  // 먼저 원위치로 복귀
                  setState(() => _dragOffset = 0.0);
                  // 공통 입력 다이얼로그 사용
                  widget.onEdit();
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.2),
                  ),
                  child: Icon(
                    Icons.edit,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
              ),
            ),

          // 삭제 버튼 (오른쪽, 빨간색)
          if (_dragOffset < -40)
            Positioned(
              left: MediaQuery.of(context).size.width + _dragOffset + 70,
              top: 0,
              bottom: 0,
              width: 70,
              child: GestureDetector(
                onTap: () async {
                  setState(() => _dragOffset = 0.0);
                  widget.onDelete();
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withOpacity(0.12),
                  ),
                  child: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                ),
              ),
            ),

          // 메인 컨텐츠
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color:
                    widget.isSelected
                        ? Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.8)
                        : Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (_dragOffset != 0) {
                      // 드래그 상태면 먼저 닫기
                      setState(() {
                        _dragOffset = 0.0;
                      });
                      // no-op
                    } else {
                      widget.onTap();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.group.name,
                            style: TextStyle(
                              fontWeight:
                                  widget.isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                              fontSize: 16,
                              color:
                                  widget.isSelected && isDarkMode
                                      ? AppColors.darkSurface
                                      : widget.isSelected && !isDarkMode
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            '${widget.group.members.length}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color:
                                  widget.isSelected && isDarkMode
                                      ? AppColors.darkSurface
                                      : widget.isSelected && !isDarkMode
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GroupDropDown {
  VoidCallback? _onGroupChanged;
  bool _isCreatingGroup = false;
  final TextEditingController _createGroupController = TextEditingController();
  final TextEditingController _createGroupDescriptionController =
      TextEditingController(); // 🎯 그룹 설명
  final FocusNode _createGroupFocusNode = FocusNode();
  final FocusNode _createGroupDescriptionFocusNode =
      FocusNode(); // 🎯 그룹 설명 포커스

  // 그룹 프로필 이미지 상태
  String? _selectedGroupImageUrl;
  UploadTask? _groupImageUploadTask; // 🎯 업로드 태스크
  VoidCallback? _uploadTaskListener; // 🎯 업로드 리스너
  bool _isEditMode = false; // 🎯 수정 모드 플래그

  /// 그룹 변경 콜백 설정
  void setOnGroupChanged(VoidCallback? callback) {
    _onGroupChanged = callback;
  }

  /// 리소스 정리
  void dispose() {
    _createGroupController.dispose();
    _createGroupDescriptionController.dispose();
    _createGroupFocusNode.dispose();
    _createGroupDescriptionFocusNode.dispose();

    // 🎯 업로드 태스크 정리
    if (_uploadTaskListener != null && _groupImageUploadTask != null) {
      _groupImageUploadTask!.removeListener(_uploadTaskListener!);
    }
  }

  /// 그룹 드롭다운 표시 (BottomSheet)
  void showGroupDropdown(
    BuildContext context,
    GlobalKey buttonKey,
    List<Group> groups,
    Group? selectedGroup,
    Function(Group?) onGroupSelected,
    Future<void> Function(String name, String? description, String? imageUrl)
    onCreateGroup, { // 🎯 description 추가
    bool startWithCreate = false, // 🎯 그룹 생성 UI로 바로 시작
    bool editMode = false, // 🎯 수정 모드
    String? initialName, // 🎯 초기 이름 (수정 모드)
    String? initialDescription, // 🎯 초기 설명 (수정 모드)
    String? initialImageUrl, // 🎯 초기 이미지 URL (수정 모드)
    VoidCallback? onDeleteGroup, // 🎯 그룹 삭제 콜백 (수정 모드)
  }) async {
    // 상태 초기화
    _isCreatingGroup = startWithCreate; // 🎯 파라미터에 따라 초기 상태 설정
    _isEditMode = editMode; // 🎯 수정 모드 플래그 저장

    // 🎯 수정 모드인 경우 기존 값으로 초기화
    if (editMode) {
      _createGroupController.text = initialName ?? '';
      _createGroupDescriptionController.text = initialDescription ?? '';
      _selectedGroupImageUrl = initialImageUrl;
    } else {
      _createGroupController.clear();
      _createGroupDescriptionController.clear();
      _selectedGroupImageUrl = null;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.5), // 🎯 surfaceColor로 변경
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Stack(
              children: [
                // 배경 영역 (바깥 부분) - 탭하면 닫힘
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ),
                // 바텀시트 컨텐츠
                DraggableScrollableSheet(
                  initialChildSize: 0.85, // 🎯 85%로 더 높게
                  minChildSize: 0.6,
                  maxChildSize: 0.95,
                  builder: (context, scrollController) {
                    return GestureDetector(
                      onTap: () {
                        // 바텀시트 내부를 탭해도 닫히지 않도록 이벤트 소비
                      },
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.background.withOpacity(0.95),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.1),
                                width: 0.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                // 핸들 바 + 삭제 버튼 (수정 모드일 때만)
                                SizedBox(
                                  height: 56, // 🎯 충분한 높이 확보
                                  child: Stack(
                                    clipBehavior: Clip.none, // 🎯 클리핑 방지
                                    children: [
                                      // 중앙 핸들 바
                                      Center(
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            top: 12,
                                            bottom: 8,
                                          ),
                                          width: 38,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withOpacity(0.8),
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // 🎯 오른쪽 상단 삭제 버튼 (수정 모드일 때만)
                                      if (editMode && onDeleteGroup != null)
                                        Positioned(
                                          top: 12, // 🎯 8 → 12로 조정
                                          right: 8, // 🎯 12 → 8로 조정
                                          child: IconButton(
                                            icon: SvgPicture.asset(
                                              'assets/icons/delete.svg',
                                              width: 24,
                                              height: 24,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error
                                                  .withOpacity(0.7),
                                            ),
                                            onPressed: () async {
                                              // 🎯 삭제 확인 다이얼로그
                                              final confirmed =
                                                  await DialogUtils.showConfirmDialog(
                                                    context,
                                                    title: context.tr('delete'),
                                                    message:
                                                        '${_createGroupController.text} 그룹을 삭제하시겠습니까?',
                                                    confirmText: context.tr(
                                                      'delete',
                                                    ),
                                                    cancelText: context.tr(
                                                      'cancel',
                                                    ),
                                                  );

                                              if (confirmed == true &&
                                                  context.mounted) {
                                                Navigator.of(
                                                  context,
                                                ).pop(); // 바텀시트 닫기
                                                onDeleteGroup(); // 삭제 콜백 실행
                                              }
                                            },
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 44,
                                              minHeight: 44,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: scrollController,
                                    child: _buildGroupContent(
                                      context,
                                      sheetContext,
                                      groups,
                                      selectedGroup,
                                      onGroupSelected,
                                      onCreateGroup,
                                      setModalState,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 그룹 드롭다운 내용 빌드 (생성/수정만)
  Widget _buildGroupContent(
    BuildContext context,
    BuildContext sheetContext,
    List<Group> groups,
    Group? selectedGroup,
    Function(Group?) onGroupSelected,
    Future<void> Function(String name, String? description, String? imageUrl)
    onCreateGroup, // 🎯 시그니처 변경
    StateSetter setModalState,
  ) {
    // 🎯 그룹 생성/수정 UI만 반환 (리스트 제거)
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCreateGroupField(context, onCreateGroup, setModalState),
        const SizedBox(height: 20),
      ],
    );
  }

  /// 🎯 미사용 (이제 필요 없음)
  Widget _buildGroupContentOld(
    BuildContext context,
    BuildContext sheetContext,
    List<Group> groups,
    Group? selectedGroup,
    Function(Group?) onGroupSelected,
    Future<void> Function(String name, String? description, String? imageUrl)
    onCreateGroup,
    StateSetter setModalState,
  ) {
    final groupProvider = context.read<GroupProvider>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 그룹 생성/수정 필드
        if (_isCreatingGroup)
          _buildCreateGroupField(context, onCreateGroup, setModalState),

        // 🎯 그룹 목록은 생성/수정 모드가 아니고, 수정 모드가 아닐 때만 표시
        if (!_isCreatingGroup && !_isEditMode) ...[
          // 그룹 생성 버튼
          _buildCreateGroupButton(context, setModalState),

          // 전체 그룹 아이템
          _buildGroupItem(
            title: context.tr('all_groups'),
            count: groups.length,
            isSelected: selectedGroup == null,
            context: context,
            onTap: () {
              onGroupSelected(null);
              Navigator.of(context).pop();
              _onGroupChanged?.call();
            },
          ),

          // 사용자가 만든 그룹들
          ...groups.map(
            (group) => _GroupItemWithActions(
              group: group,
              isSelected: selectedGroup?.id == group.id,
              onTap: () {
                onGroupSelected(group);
                Navigator.of(context).pop();
                _onGroupChanged?.call();
              },
              onEdit: () async {
                final newName = await _showEditGroupNameDialog(
                  context,
                  group.name,
                );
                if (newName != null && newName.trim().isNotEmpty) {
                  try {
                    // TODO: GroupProvider에 updateGroupName 메서드 추가 필요
                    // await groupProvider.updateGroupName(group.id, newName.trim());
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('group_name_updated')),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('group_update_failed')),
                        ),
                      );
                    }
                  }
                }
              },
              onDelete: () async {
                final confirmed = await _showDeleteConfirmDialog(
                  context,
                  group.name,
                );
                if (confirmed == true) {
                  // 🎯 바텀시트를 먼저 닫음
                  if (Navigator.of(sheetContext).canPop()) {
                    Navigator.of(sheetContext).pop();
                  }

                  try {
                    await groupProvider.deleteGroup(group.id);
                    if (selectedGroup?.id == group.id) {
                      onGroupSelected(null);
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.tr('group_deleted'))),
                      );
                    }
                    _onGroupChanged?.call();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('group_delete_failed')),
                        ),
                      );
                    }
                  }
                }
              },
            ),
          ),
        ],

        // BottomSheet 하단 여백
        const SizedBox(height: 20),
      ],
    );
  }

  /// 그룹 아이템 빌드 (일반)
  Widget _buildGroupItem({
    required String title,
    required int count,
    required bool isSelected,
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      child: Material(
        borderRadius: BorderRadius.circular(12),
        color:
            isSelected
                ? Theme.of(context).colorScheme.onSurface.withOpacity(0.9)
                : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
                      fontSize: 16,
                      color:
                          isSelected && isDarkMode
                              ? Theme.of(context).colorScheme.surface
                              : isSelected && !isDarkMode
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color:
                          isSelected && isDarkMode
                              ? Theme.of(context).colorScheme.surface
                              : isSelected && !isDarkMode
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 그룹 생성 버튼
  Widget _buildCreateGroupButton(
    BuildContext context,
    StateSetter setModalState,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setModalState(() {
            _isCreatingGroup = true;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('create_new_group'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 그룹 생성 텍스트 필드 (인라인)
  Widget _buildCreateGroupField(
    BuildContext context,
    Future<void> Function(String name, String? description, String? imageUrl)
    onCreateGroup, // 🎯 시그니처 변경
    StateSetter setModalState,
  ) {
    final nameController = _createGroupController; // 🎯 클래스 멤버 사용
    final descriptionController =
        _createGroupDescriptionController; // 🎯 설명 컨트롤러
    final nameFocusNode = _createGroupFocusNode; // 🎯 클래스 멤버 사용
    final descriptionFocusNode = _createGroupDescriptionFocusNode; // 🎯 설명 포커스

    // 🎯 자동 포커스 제거 (이미지 선택 시 키보드가 다시 올라오는 문제 해결)

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min, // 🎯 최소 크기로
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 그룹 프로필 사진
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () async {
              // 🎯 키보드 내리기
              nameFocusNode.unfocus();
              descriptionFocusNode.unfocus();

              // 잠시 대기 (키보드가 내려갈 시간)
              await Future.delayed(const Duration(milliseconds: 100));

              // 이미지 선택 및 업로드
              if (context.mounted) {
                _showGroupProfileImagePicker(context, setModalState);
              }
            },
            child: _buildGroupProfileAvatar(
              context,
              nameController.text.isEmpty
                  ? 'G'
                  : nameController.text[0].toUpperCase(),
            ),
          ),
          const SizedBox(height: 20),

          // 그룹 이름 입력 필드
          Container(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                cursorColor: Theme.of(context).colorScheme.onSurface,
                controller: nameController,
                focusNode: nameFocusNode,
                autofocus: false, // 🎯 자동 포커스 끄기 (이미지 선택 방해)
                textInputAction: TextInputAction.next, // 🎯 다음으로 이동
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: context.tr('enter_group_name'),
                  hintStyle: TextStyle(
                    fontSize: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.04),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                ),
                onSubmitted: (value) {
                  // 🎯 Enter 시 설명 필드로 이동
                  descriptionFocusNode.requestFocus();
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 🎯 그룹 설명 입력 필드 (새로 추가)
          Container(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                cursorColor: Theme.of(context).colorScheme.onSurface,
                controller: descriptionController,
                focusNode: descriptionFocusNode,
                maxLines: 3,
                minLines: 2,
                textInputAction: TextInputAction.done,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: '그룹 설명 (선택)',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.04),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    // 🎯 바로 바텀시트 닫기
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    context.tr('cancel'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final groupName = nameController.text.trim();
                    final groupDescription =
                        descriptionController.text.trim(); // 🎯 설명 가져오기
                    if (groupName.isNotEmpty) {
                      await onCreateGroup(
                        groupName,
                        groupDescription.isEmpty
                            ? null
                            : groupDescription, // 🎯 설명 전달
                        _selectedGroupImageUrl, // 🎯 이미지 URL 전달
                      );
                      setModalState(() {
                        _isCreatingGroup = false;
                        _selectedGroupImageUrl = null;
                      });
                      Navigator.of(context).pop();
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    _isEditMode
                        ? '수정완료'
                        : context.tr('create'), // 🎯 수정 모드에 따라 텍스트 변경
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 그룹 프로필 아바타 빌드
  Widget _buildGroupProfileAvatar(BuildContext context, String initialLetter) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade400,
          width: 1,
        ),
      ),
      child: ClipOval(
        child:
            _selectedGroupImageUrl != null
                ? (_selectedGroupImageUrl!.startsWith('http')
                    ? Image.network(_selectedGroupImageUrl!, fit: BoxFit.cover)
                    : Image.file(
                      File(_selectedGroupImageUrl!),
                      fit: BoxFit.cover,
                    ))
                : Container(
                  color:
                      Theme.of(context).colorScheme.surface, // 🎯 surface 색상 사용
                  child: Center(
                    child: Icon(
                      Icons.photo, // 🎯 사진 추가 아이콘
                      size: 30,
                      color:
                          isDarkMode
                              ? Colors.grey.shade800
                              : Colors.grey.shade400, // 🎯 onSurface 색상
                    ),
                  ),
                ),
      ),
    );
  }

  /// 그룹 프로필 이미지 선택 및 업로드
  void _showGroupProfileImagePicker(
    BuildContext context,
    StateSetter setModalState,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext pickerContext) {
        return ProfileImageBottomSheet(
          singleSelect: true,
          onClearProfileImage: () async {
            setModalState(() {
              _selectedGroupImageUrl = null;
            });
          },
          onImagesSelected: (files) async {
            if (files.isEmpty) return;

            // 🎯 UploadService를 사용하여 이미지 업로드
            final file = files.first;
            print('🔄 [GroupSheet] 그룹 이미지 업로드 시작: ${file.path}');

            // 로컬 파일 경로를 임시로 표시
            setModalState(() {
              _selectedGroupImageUrl = file.path;
            });

            // UploadService에 태스크 등록
            final uploadService = UploadService();
            final task = uploadService.enqueueFile(
              file,
              kind: UploadKind.profile, // 프로필 이미지 업로드와 동일
            );

            _groupImageUploadTask = task;
            _uploadTaskListener = () {
              if (task.state == UploadState.success) {
                final imageUrl = task.url ?? '';
                print('✅ [GroupSheet] 그룹 이미지 업로드 성공: $imageUrl');

                setModalState(() {
                  _selectedGroupImageUrl =
                      imageUrl.isNotEmpty ? imageUrl : null;
                });

                // 리스너 제거
                if (_uploadTaskListener != null) {
                  task.removeListener(_uploadTaskListener!);
                  _uploadTaskListener = null;
                }
                _groupImageUploadTask = null;
              } else if (task.state == UploadState.failed ||
                  task.state == UploadState.cancelled) {
                print('❌ [GroupSheet] 그룹 이미지 업로드 실패 또는 취소');

                setModalState(() {
                  _selectedGroupImageUrl = null;
                });

                if (context.mounted) {
                  ErrorHandler.showError(
                    context,
                    context.tr('image_upload_failed'),
                  );
                }

                // 리스너 제거
                if (_uploadTaskListener != null) {
                  task.removeListener(_uploadTaskListener!);
                  _uploadTaskListener = null;
                }
                _groupImageUploadTask = null;
              }
            };

            task.addListener(_uploadTaskListener!);
          },
        );
      },
    );
  }

  /// 그룹 이름 수정 다이얼로그
  Future<String?> _showEditGroupNameDialog(
    BuildContext context,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    String? result;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(context.tr('edit_group_name')),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: context.tr('enter_group_name'),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.tr('cancel')),
            ),
            TextButton(
              onPressed: () {
                result = controller.text;
                Navigator.of(dialogContext).pop();
              },
              child: Text(context.tr('save')),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }

  /// 그룹 삭제 확인 다이얼로그
  Future<bool?> _showDeleteConfirmDialog(
    BuildContext context,
    String groupName,
  ) async {
    return await DialogUtils.showConfirmDialog(
      context,
      title: context.tr('delete_group'),
      message: context.tr('group_delete_confirmation'),
      confirmText: context.tr('delete'),
      cancelText: context.tr('cancel'),
      isDestructive: true,
    );
  }
}
