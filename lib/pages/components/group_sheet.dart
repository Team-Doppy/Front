import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/data/models/group_model.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/pages/components/profile_edit_sheet.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

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
                            // 🎯 시스템 그룹(isSystem == true)인 경우 "모든 친구"로 표시
                            widget.group.isSystem == true
                                ? context.tr('all_friends')
                                : widget.group.name,
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

// 🎯 그룹 생성/수정 전체 화면 페이지
class _GroupCreateEditPage extends StatefulWidget {
  final GroupDropDown groupDropDown;
  final List<Group> groups;
  final Group? selectedGroup;
  final Function(Group?) onGroupSelected;
  final Future<void> Function(
    String name,
    String? description,
    String? imageUrl,
  )
  onCreateGroup;
  final bool editMode;
  final VoidCallback? onDeleteGroup;

  const _GroupCreateEditPage({
    required this.groupDropDown,
    required this.groups,
    required this.selectedGroup,
    required this.onGroupSelected,
    required this.onCreateGroup,
    required this.editMode,
    this.onDeleteGroup,
  });

  @override
  State<_GroupCreateEditPage> createState() => _GroupCreateEditPageState();
}

class _GroupCreateEditPageState extends State<_GroupCreateEditPage> {
  @override
  void initState() {
    super.initState();
    // 🎯 페이지 로드 후 키보드 포커스
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.groupDropDown._createGroupFocusNode.canRequestFocus) {
        widget.groupDropDown._createGroupFocusNode.requestFocus();
      }
    });

    // 🎯 텍스트 필드 변경 감지 (변경사항 확인용)
    widget.groupDropDown._createGroupController.addListener(_onFieldChanged);
    widget.groupDropDown._createGroupDescriptionController.addListener(
      _onFieldChanged,
    );
  }

  @override
  void dispose() {
    widget.groupDropDown._createGroupController.removeListener(_onFieldChanged);
    widget.groupDropDown._createGroupDescriptionController.removeListener(
      _onFieldChanged,
    );
    super.dispose();
  }

  void _onFieldChanged() {
    setState(() {}); // 🎯 변경사항 감지 시 rebuild
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // 🎯 수정 모드일 때만 삭제 버튼 표시
          if (widget.editMode && widget.onDeleteGroup != null)
            IconButton(
              icon: SvgPicture.asset(
                'assets/icons/delete.svg',
                width: 24,
                height: 24,
                color: Theme.of(context).colorScheme.error.withOpacity(0.7),
              ),
              onPressed: () async {
                final groupName =
                    widget.groupDropDown._createGroupController.text;
                final confirmed = await DialogUtils.showConfirmDialog(
                  context,
                  title: context.tr('delete'),
                  message:
                      '$groupName 그룹을 삭제하시겠습니까?\n\n그룹에 공유된 포스트는 모두 나만보기로 전환됩니다.',
                  confirmText: context.tr('delete'),
                  cancelText: context.tr('cancel'),
                  isDestructive: true,
                );

                if (confirmed == true && context.mounted) {
                  // 🎯 편집 시트 닫기 (애니메이션 없이)
                  Navigator.of(context).pop();
                  // 🎯 그룹 삭제 콜백 실행 (manage_group_screen에서 처리)
                  widget.onDeleteGroup!();
                }
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: widget.groupDropDown._buildCreateGroupField(
          context,
          widget.onCreateGroup,
          setState,
          widget.groups,
          widget.selectedGroup, // 🎯 selectedGroup 전달
        ),
      ),
    );
  }
}

class GroupDropDown {
  bool _isCreatingLoading = false; // 생성 중 로딩 상태

  // 🎯 이미지 업로드 진행 중인지 확인
  bool get _isImageUploading {
    if (_groupImageUploadTask == null) return false;
    final state = _groupImageUploadTask!.state;
    return state != UploadState.success &&
        state != UploadState.failed &&
        state != UploadState.cancelled;
  }

  final TextEditingController _createGroupController = TextEditingController();
  final TextEditingController _createGroupDescriptionController =
      TextEditingController();
  final FocusNode _createGroupFocusNode = FocusNode();
  final FocusNode _createGroupDescriptionFocusNode = FocusNode();

  // 그룹 프로필 이미지 상태
  String? _selectedGroupImageUrl;
  UploadTask? _groupImageUploadTask;
  VoidCallback? _uploadTaskListener;
  bool _isEditMode = false;

  // 🎯 수정 모드 초기 값 저장 (변경사항 감지용)
  String _initialName = '';
  String _initialDescription = '';
  String? _initialImageUrl;

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

  /// 그룹 생성/수정 페이지 표시 (전체 화면)
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
    _isEditMode = editMode;
    _isCreatingLoading = false;

    // 🎯 수정 모드인 경우 기존 값으로 초기화
    if (editMode) {
      _initialName = initialName ?? '';
      _initialDescription = initialDescription ?? '';
      _initialImageUrl = initialImageUrl;
      _createGroupController.text = _initialName;
      _createGroupDescriptionController.text = _initialDescription;
      _selectedGroupImageUrl = _initialImageUrl;
    } else {
      _initialName = '';
      _initialDescription = '';
      _initialImageUrl = null;
      _createGroupController.clear();
      _createGroupDescriptionController.clear();
      _selectedGroupImageUrl = null;
    }

    // 🎯 전체 화면 페이지로 이동
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return _GroupCreateEditPage(
            groupDropDown: this,
            groups: groups,
            selectedGroup: selectedGroup,
            onGroupSelected: onGroupSelected,
            onCreateGroup: onCreateGroup,
            editMode: editMode,
            onDeleteGroup: onDeleteGroup,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // 아래에서 위로 슬라이드 애니메이션
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  /// 그룹 생성 텍스트 필드 (인라인)
  Widget _buildCreateGroupField(
    BuildContext context,
    Future<void> Function(String name, String? description, String? imageUrl)
    onCreateGroup, // 🎯 시그니처 변경
    StateSetter setModalState,
    List<Group> groups, // 🎯 그룹 목록 (중복 체크용)
    Group? selectedGroup, // 🎯 선택된 그룹 (전체 친구 확인용)
  ) {
    final nameController = _createGroupController; // 🎯 클래스 멤버 사용
    final descriptionController =
        _createGroupDescriptionController; // 🎯 설명 컨트롤러
    final nameFocusNode = _createGroupFocusNode; // 🎯 클래스 멤버 사용
    final descriptionFocusNode = _createGroupDescriptionFocusNode; // 🎯 설명 포커스

    // 🎯 전체 친구 그룹인지 확인 (이름 수정 불가)
    final bool isAllFriendsGroup =
        selectedGroup != null && (selectedGroup.isSystem == true);

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
                _showGroupProfileImagePicker(
                  context,
                  setModalState,
                  selectedGroup: selectedGroup, // 🎯 전체 친구 그룹 확인용 전달
                );
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

          // 그룹 이름 입력 필드 (전체 친구 그룹일 때는 숨김)
          if (!isAllFriendsGroup)
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
          if (!isAllFriendsGroup) const SizedBox(height: 12),

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
                  hintText: context.tr('group_description_optional'),
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
                child: Builder(
                  builder: (context) {
                    // 🎯 전체 친구 그룹 확인
                    final bool isAllFriendsGroup =
                        selectedGroup != null &&
                        (selectedGroup.isSystem == true);

                    // 🎯 수정 모드일 때 변경사항 확인
                    final bool hasChanges =
                        _isEditMode
                            ? _hasChanges()
                            : (nameController.text.trim().isNotEmpty ||
                                isAllFriendsGroup);

                    return TextButton(
                      onPressed:
                          (_isCreatingLoading ||
                                  !hasChanges ||
                                  _isImageUploading)
                              ? null
                              : () async {
                                final groupName = nameController.text.trim();
                                final groupDescription =
                                    descriptionController.text
                                        .trim(); // 🎯 설명 가져오기

                                // 🎯 전체 친구 그룹 확인
                                final bool isAllFriendsGroup =
                                    selectedGroup != null &&
                                    (selectedGroup.isSystem == true);

                                // 🎯 전체 친구 그룹은 이름이 비어있어도 저장 가능
                                if (groupName.isNotEmpty || isAllFriendsGroup) {
                                  // 🎯 그룹 이름 검증
                                  if (!_isEditMode && !isAllFriendsGroup) {
                                    // 🎯 1단계: "모든 친구" / "All Friends" 이름 사용 불가 체크
                                    final allFriendsName = context.tr(
                                      'all_friends',
                                    );
                                    if (groupName.toLowerCase() ==
                                        allFriendsName.toLowerCase()) {
                                      if (context.mounted) {
                                        ErrorHandler.showError(
                                          context,
                                          context.tr('group_name_reserved'),
                                        );
                                      }
                                      return;
                                    }

                                    // 🎯 2단계: 기존 그룹 이름 중복 체크
                                    // (서버는 isSystem 플래그로 구분하므로 시스템 그룹 이름도 일반 그룹 이름으로 사용 가능)
                                    final isDuplicate = groups.any(
                                      (group) =>
                                          group.name.toLowerCase() ==
                                          groupName.toLowerCase(),
                                    );

                                    if (isDuplicate) {
                                      if (context.mounted) {
                                        ErrorHandler.showError(
                                          context,
                                          context.tr('group_name_duplicate'),
                                        );
                                      }
                                      return;
                                    }
                                  }

                                  // 🎯 로딩 시작
                                  setModalState(() {
                                    _isCreatingLoading = true;
                                  });

                                  try {
                                    // 🎯 이미지 업로드 상태 확인 및 대기
                                    String? finalImageUrl;
                                    bool shouldClearImage =
                                        false; // 🎯 기본 이미지로 변경 여부

                                    // 🎯 수정 모드에서 이미지 변경 여부 확인
                                    final bool imageChanged =
                                        _isEditMode
                                            ? _selectedGroupImageUrl !=
                                                _initialImageUrl
                                            : _selectedGroupImageUrl != null;

                                    // 🎯 이미지가 변경되지 않았으면 서버에 보내지 않음 (기본값 유지)
                                    if (!imageChanged) {
                                      finalImageUrl =
                                          null; // 서버에 보내지 않음 (필드 생략)
                                    } else {
                                      // 🎯 이미지가 변경된 경우에만 처리
                                      // 1. 이미지가 선택되었는지 확인
                                      final hasImage =
                                          _selectedGroupImageUrl != null;

                                      if (hasImage) {
                                        // 🎯 전체 친구 그룹은 이미지 업로드 건너뛰기 (로컬 파일 경로 그대로 사용)
                                        if (isAllFriendsGroup) {
                                          // 전체 친구 그룹은 로컬 파일 경로를 그대로 사용
                                          finalImageUrl =
                                              _selectedGroupImageUrl;
                                          debugPrint(
                                            '✅ [GroupSheet] 전체 친구 그룹: 로컬 파일 경로 사용: $finalImageUrl',
                                          );
                                        } else if (_groupImageUploadTask !=
                                            null) {
                                          // 2. 업로드 태스크가 있는지 확인 (일반 그룹만)
                                          // 3. 업로드 상태 확인
                                          final currentState =
                                              _groupImageUploadTask!.state;

                                          if (currentState ==
                                              UploadState.success) {
                                            // 이미 업로드 완료된 경우
                                            finalImageUrl =
                                                _groupImageUploadTask!.url;
                                            // 최신 상태 확인을 위해 _selectedGroupImageUrl도 체크
                                            if (finalImageUrl == null &&
                                                _selectedGroupImageUrl !=
                                                    null &&
                                                _selectedGroupImageUrl!
                                                    .startsWith('http')) {
                                              finalImageUrl =
                                                  _selectedGroupImageUrl;
                                            }
                                            debugPrint(
                                              '✅ [GroupSheet] 이미지 업로드 완료: $finalImageUrl',
                                            );
                                          } else if (currentState ==
                                                  UploadState.failed ||
                                              currentState ==
                                                  UploadState.cancelled) {
                                            // 업로드 실패한 경우
                                            debugPrint(
                                              '❌ [GroupSheet] 이미지 업로드 실패: $currentState',
                                            );
                                            if (context.mounted) {
                                              ErrorHandler.showError(
                                                context,
                                                context.tr(
                                                  'image_upload_failed',
                                                ),
                                              );
                                            }
                                            setModalState(() {
                                              _isCreatingLoading = false;
                                            });
                                            return; // 생성/수정 취소
                                          } else {
                                            // 업로드 진행 중인 경우 - 완료될 때까지 대기
                                            debugPrint(
                                              '🔄 [GroupSheet] 이미지 업로드 진행 중... (상태: $currentState)',
                                            );

                                            // 업로드 완료까지 최대 60초 대기 (더 긴 대기 시간)
                                            int waitCount = 0;
                                            const maxWaitTime = 600; // 60초

                                            while (_groupImageUploadTask !=
                                                    null &&
                                                _groupImageUploadTask!.state !=
                                                    UploadState.success &&
                                                _groupImageUploadTask!.state !=
                                                    UploadState.failed &&
                                                _groupImageUploadTask!.state !=
                                                    UploadState.cancelled &&
                                                waitCount < maxWaitTime) {
                                              await Future.delayed(
                                                const Duration(
                                                  milliseconds: 100,
                                                ),
                                              );
                                              waitCount++;
                                            }

                                            // 최종 상태 확인
                                            if (_groupImageUploadTask != null) {
                                              final finalState =
                                                  _groupImageUploadTask!.state;

                                              if (finalState ==
                                                  UploadState.success) {
                                                finalImageUrl =
                                                    _groupImageUploadTask!.url;

                                                // 리스너가 아직 업데이트하지 않았을 수 있으므로
                                                // _selectedGroupImageUrl도 확인
                                                if (finalImageUrl == null &&
                                                    _selectedGroupImageUrl !=
                                                        null &&
                                                    _selectedGroupImageUrl!
                                                        .startsWith('http')) {
                                                  finalImageUrl =
                                                      _selectedGroupImageUrl;
                                                }

                                                debugPrint(
                                                  '✅ [GroupSheet] 이미지 업로드 완료 (대기 후): $finalImageUrl',
                                                );
                                              } else {
                                                // 업로드 실패 또는 취소
                                                debugPrint(
                                                  '❌ [GroupSheet] 이미지 업로드 실패 또는 취소: $finalState',
                                                );
                                                if (context.mounted) {
                                                  ErrorHandler.showError(
                                                    context,
                                                    context.tr(
                                                      'image_upload_failed',
                                                    ),
                                                  );
                                                }
                                                setModalState(() {
                                                  _isCreatingLoading = false;
                                                });
                                                return; // 생성/수정 취소
                                              }
                                            } else {
                                              // 태스크가 null이 된 경우 (완료된 후 리스너에서 정리됨)
                                              // _selectedGroupImageUrl 확인
                                              if (_selectedGroupImageUrl !=
                                                      null &&
                                                  _selectedGroupImageUrl!
                                                      .startsWith('http')) {
                                                finalImageUrl =
                                                    _selectedGroupImageUrl;
                                                debugPrint(
                                                  '✅ [GroupSheet] 이미지 업로드 완료 (태스크 정리 후): $finalImageUrl',
                                                );
                                              } else {
                                                debugPrint(
                                                  '⚠️ [GroupSheet] 이미지 업로드 타임아웃 또는 실패',
                                                );
                                                if (context.mounted) {
                                                  ErrorHandler.showError(
                                                    context,
                                                    context.tr(
                                                      'image_upload_failed',
                                                    ),
                                                  );
                                                }
                                                setModalState(() {
                                                  _isCreatingLoading = false;
                                                });
                                                return; // 생성/수정 취소
                                              }
                                            }
                                          }
                                        } else {
                                          // 업로드 태스크가 없지만 이미지 URL이 있는 경우
                                          // 이미 서버 URL인지 확인
                                          if (_selectedGroupImageUrl != null) {
                                            if (_selectedGroupImageUrl!
                                                    .startsWith('http://') ||
                                                _selectedGroupImageUrl!
                                                    .startsWith('https://')) {
                                              // 이미 서버 URL인 경우
                                              finalImageUrl =
                                                  _selectedGroupImageUrl;
                                              debugPrint(
                                                '✅ [GroupSheet] 이미 서버 URL 사용: $finalImageUrl',
                                              );
                                            } else {
                                              // 로컬 파일 경로인 경우 - 업로드가 아직 시작되지 않았을 수 있음
                                              debugPrint(
                                                '⚠️ [GroupSheet] 로컬 파일 경로 감지, 업로드 태스크 없음: ${_selectedGroupImageUrl}',
                                              );
                                              // 업로드가 시작되지 않았다면 사용자에게 알림
                                              if (context.mounted) {
                                                ErrorHandler.showError(
                                                  context,
                                                  '이미지 업로드가 아직 시작되지 않았습니다. 잠시 후 다시 시도해주세요.',
                                                );
                                              }
                                              setModalState(() {
                                                _isCreatingLoading = false;
                                              });
                                              return; // 생성/수정 취소
                                            }
                                          }
                                        }
                                      } else {
                                        // 🎯 이미지가 null로 변경된 경우 (기본 이미지로 변경)
                                        // 이미지가 변경되었지만 null이면 서버에 null 명시적 전송
                                        finalImageUrl = null;
                                        shouldClearImage =
                                            true; // 🎯 기본 이미지로 변경 플래그
                                      }
                                    }

                                    // 🎯 최종 검증: 서버 URL만 전달 (로컬 파일 경로는 제외)
                                    // 전체 친구 그룹도 이미지 업로드가 완료되어야 함
                                    if (finalImageUrl != null &&
                                        !finalImageUrl.startsWith('http://') &&
                                        !finalImageUrl.startsWith('https://')) {
                                      debugPrint(
                                        '❌ [GroupSheet] 최종 검증 실패: 서버 URL이 아닌 경로 감지 - $finalImageUrl',
                                      );
                                      if (context.mounted) {
                                        ErrorHandler.showError(
                                          context,
                                          context.tr('image_upload_failed'),
                                        );
                                      }
                                      setModalState(() {
                                        _isCreatingLoading = false;
                                      });
                                      return; // 생성/수정 취소
                                    }

                                    // 🎯 그룹 생성/수정 실행
                                    // 전체 친구 그룹은 이름이 비어있을 수 있으므로 selectedGroup의 이름 사용
                                    // isAllFriendsGroup이 true면 selectedGroup은 null이 아님
                                    final finalGroupName =
                                        isAllFriendsGroup && groupName.isEmpty
                                            ? selectedGroup.name
                                            : groupName;

                                    debugPrint(
                                      '🔵 [GroupSheet] onCreateGroup 호출 시작',
                                    );
                                    debugPrint(
                                      '🔵 [GroupSheet] isAllFriendsGroup: $isAllFriendsGroup',
                                    );
                                    debugPrint(
                                      '🔵 [GroupSheet] groupName: $groupName',
                                    );
                                    debugPrint(
                                      '🔵 [GroupSheet] finalGroupName: $finalGroupName',
                                    );
                                    debugPrint(
                                      '🔵 [GroupSheet] groupDescription: $groupDescription',
                                    );
                                    debugPrint(
                                      '🔵 [GroupSheet] finalImageUrl: $finalImageUrl',
                                    );
                                    debugPrint(
                                      '🔵 [GroupSheet] shouldClearImage: $shouldClearImage',
                                    );
                                    debugPrint(
                                      '🔵 [GroupSheet] selectedGroup: ${selectedGroup?.name} (id: ${selectedGroup?.id}, isSystem: ${selectedGroup?.isSystem})',
                                    );

                                    // 🎯 기본 이미지로 변경하는 경우 빈 문자열로 전송 (서버에서 null로 처리)
                                    final imageUrlToSend =
                                        shouldClearImage
                                            ? '' // 🎯 빈 문자열로 전송하여 서버에서 null로 처리
                                            : finalImageUrl;

                                    await onCreateGroup(
                                      finalGroupName,
                                      groupDescription, // 🎯 설명 전달 (빈 문자열 포함)
                                      imageUrlToSend, // 🎯 서버 URL 또는 빈 문자열 (기본 이미지)
                                    );

                                    debugPrint(
                                      '🔵 [GroupSheet] onCreateGroup 호출 완료',
                                    );

                                    setModalState(() {
                                      _isCreatingLoading = false;
                                      _selectedGroupImageUrl = null;
                                    });

                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  } catch (e) {
                                    // 🎯 에러 발생 시 로딩 해제
                                    setModalState(() {
                                      _isCreatingLoading = false;
                                    });
                                    rethrow;
                                  }
                                }
                              },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child:
                          _isCreatingLoading
                              ? SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              )
                              : Text(
                                _isEditMode
                                    ? context.tr('save_changes')
                                    : context.tr(
                                      'create',
                                    ), // 🎯 수정 모드에 따라 텍스트 변경
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      (hasChanges && !_isImageUploading)
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.onSurface
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.4),
                                ),
                              ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🎯 변경사항 확인 (수정 모드용)
  bool _hasChanges() {
    if (!_isEditMode) return false;

    final currentName = _createGroupController.text.trim();
    final currentDescription = _createGroupDescriptionController.text.trim();
    final currentImageUrl = _selectedGroupImageUrl;

    // 이름 변경 확인
    if (currentName != _initialName) return true;

    // 설명 변경 확인 (null과 빈 문자열을 같게 처리)
    final initialDesc =
        _initialDescription.isEmpty ? null : _initialDescription;
    final currentDesc = currentDescription.isEmpty ? null : currentDescription;
    if (currentDesc != initialDesc) return true;

    // 이미지 변경 확인
    if (currentImageUrl != _initialImageUrl) return true;

    return false;
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
      child: Stack(
        children: [
          ClipOval(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child:
                  _selectedGroupImageUrl != null
                      ? (_selectedGroupImageUrl!.startsWith('http://') ||
                              _selectedGroupImageUrl!.startsWith('https://'))
                          ? CachedNetworkImage(
                            width: double.infinity,
                            height: double.infinity,
                            key: ValueKey('network-${_selectedGroupImageUrl}'),
                            imageUrl: _selectedGroupImageUrl!,
                            fit: BoxFit.cover,
                            placeholder:
                                (context, url) => Container(
                                  color: Theme.of(context).colorScheme.surface,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Theme.of(context).colorScheme.onSurface
                                            .withOpacity(0.3),
                                      ),
                                    ),
                                  ),
                                ),
                            errorWidget:
                                (context, url, error) => Container(
                                  color: Theme.of(context).colorScheme.surface,
                                  child: Center(
                                    child: Icon(
                                      Icons.image_not_supported,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.3),
                                    ),
                                  ),
                                ),
                          )
                          : Stack(
                            key: ValueKey('local-${_selectedGroupImageUrl}'),
                            fit: StackFit.expand,
                            children: [
                              // 🎯 로컬 경로 이미지 (cover로 꽉차게)
                              Image.file(
                                File(_selectedGroupImageUrl!),
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (context, error, stackTrace) => Container(
                                      color:
                                          Theme.of(context).colorScheme.surface,
                                      child: Center(
                                        child: Icon(
                                          Icons.image_not_supported,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.3),
                                        ),
                                      ),
                                    ),
                              ),
                              // 🎯 업로드 중일 때 로딩 표시
                              if (_isImageUploading)
                                Container(
                                  color: Colors.black.withOpacity(0.3),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          )
                      : Container(
                        key: const ValueKey('placeholder'),
                        color:
                            Theme.of(
                              context,
                            ).colorScheme.surface, // 🎯 surface 색상 사용
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
          ),
          // 🎯 카메라 아이콘 (우측 하단)
          Positioned(
            right: 10,
            bottom: 0,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.onSurface,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.camera_alt,
                size: 16,
                color: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 그룹 프로필 이미지 선택 및 업로드
  void _showGroupProfileImagePicker(
    BuildContext context,
    StateSetter setModalState, {
    Group? selectedGroup, // 🎯 전체 친구 그룹 확인용
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext pickerContext) {
        return ProfileEditBottomSheet(
          singleSelect: true,
          onClearProfileImage: () async {
            setModalState(() {
              _selectedGroupImageUrl = null;
            });
          },
          onImagesSelected: (files) async {
            if (files.isEmpty) return;

            final file = files.first;

            // 로컬 파일 경로를 임시로 표시
            setModalState(() {
              _selectedGroupImageUrl = file.path;
            });

            // 🎯 모든 그룹(전체 친구 그룹 포함)에 대해 UploadService를 사용하여 이미지 업로드
            debugPrint('🔄 [GroupSheet] 그룹 이미지 업로드 시작: ${file.path}');

            // UploadService에 태스크 등록
            final uploadService = UploadService();
            final task = uploadService.enqueueFile(
              file,
              kind: UploadKind.group, // 🎯 그룹 이미지 업로드
            );

            _groupImageUploadTask = task;
            _uploadTaskListener = () {
              // 🎯 업로드 상태 변경 시마다 UI 업데이트 (버튼 활성화/비활성화)
              setModalState(() {});

              if (task.state == UploadState.success) {
                final imageUrl = task.url ?? '';
                debugPrint('✅ [GroupSheet] 그룹 이미지 업로드 성공: $imageUrl');

                // 🎯 업로드 완료 후 태스크 정리 및 상태 업데이트
                // 리스너 제거
                if (_uploadTaskListener != null) {
                  task.removeListener(_uploadTaskListener!);
                  _uploadTaskListener = null;
                }
                _groupImageUploadTask = null;

                // 🎯 업로드 완료 후 이미지 URL 업데이트 및 버튼 활성화를 위한 UI 업데이트
                setModalState(() {
                  _selectedGroupImageUrl =
                      imageUrl.isNotEmpty ? imageUrl : null;
                });
              } else if (task.state == UploadState.failed ||
                  task.state == UploadState.cancelled) {
                debugPrint('❌ [GroupSheet] 그룹 이미지 업로드 실패 또는 취소');

                // 🎯 업로드 실패 후 태스크 정리
                // 리스너 제거
                if (_uploadTaskListener != null) {
                  task.removeListener(_uploadTaskListener!);
                  _uploadTaskListener = null;
                }
                _groupImageUploadTask = null;

                setModalState(() {
                  _selectedGroupImageUrl = null;
                });

                if (context.mounted) {
                  ErrorHandler.showError(
                    context,
                    context.tr('image_upload_failed'),
                  );
                }
              }
            };

            task.addListener(_uploadTaskListener!);
          },
        );
      },
    );
  }
}
