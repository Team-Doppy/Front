import 'dart:io';

import 'package:doppy/data/models/group_model.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/image/profile_image_bottom_sheet.dart';
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
                final confirmed = await DialogUtils.showConfirmDialog(
                  context,
                  title: context.tr('delete'),
                  message:
                      '${widget.groupDropDown._createGroupController.text} 그룹을 삭제하시겠습니까?',
                  confirmText: context.tr('delete'),
                  cancelText: context.tr('cancel'),
                );

                if (confirmed == true && context.mounted) {
                  Navigator.of(context).pop();
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
        ),
      ),
    );
  }
}

class GroupDropDown {
  bool _isCreatingLoading = false; // 생성 중 로딩 상태
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
      _createGroupController.text = initialName ?? '';
      _createGroupDescriptionController.text = initialDescription ?? '';
      _selectedGroupImageUrl = initialImageUrl;
    } else {
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
                child: TextButton(
                  onPressed:
                      _isCreatingLoading
                          ? null
                          : () async {
                            final groupName = nameController.text.trim();
                            final groupDescription =
                                descriptionController.text.trim(); // 🎯 설명 가져오기
                            if (groupName.isNotEmpty) {
                              // 🎯 로딩 시작
                              setModalState(() {
                                _isCreatingLoading = true;
                              });

                              try {
                                // 🎯 이미지 업로드가 진행 중이면 완료될 때까지 대기
                                String? finalImageUrl = _selectedGroupImageUrl;
                                if (_groupImageUploadTask != null &&
                                    _groupImageUploadTask!.state !=
                                        UploadState.success) {
                                  // 업로드 완료까지 최대 30초 대기
                                  int waitCount = 0;
                                  while (_groupImageUploadTask != null &&
                                      _groupImageUploadTask!.state !=
                                          UploadState.success &&
                                      _groupImageUploadTask!.state !=
                                          UploadState.failed &&
                                      waitCount < 300) {
                                    await Future.delayed(
                                      const Duration(milliseconds: 100),
                                    );
                                    waitCount++;
                                  }

                                  if (_groupImageUploadTask != null &&
                                      _groupImageUploadTask!.state ==
                                          UploadState.success) {
                                    finalImageUrl = _groupImageUploadTask!.url;
                                    print(
                                      '✅ [GroupSheet] 이미지 업로드 완료: $finalImageUrl',
                                    );
                                  } else {
                                    print('⚠️ [GroupSheet] 이미지 업로드 실패 또는 타임아웃');
                                    finalImageUrl = null; // 업로드 실패 시 null로 설정
                                  }
                                }

                                // 🎯 로컬 파일 경로인 경우 제외 (서버 URL만 전달)
                                if (finalImageUrl != null &&
                                    (finalImageUrl.startsWith('file://') ||
                                        (!finalImageUrl.startsWith('http://') &&
                                            !finalImageUrl.startsWith(
                                              'https://',
                                            )))) {
                                  print(
                                    '⚠️ [GroupSheet] 로컬 파일 경로는 전달하지 않음: $finalImageUrl',
                                  );
                                  finalImageUrl = null;
                                }

                                await onCreateGroup(
                                  groupName,
                                  groupDescription.isEmpty
                                      ? null
                                      : groupDescription, // 🎯 설명 전달
                                  finalImageUrl, // 🎯 서버 URL만 전달
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
              kind: UploadKind.group, // 🎯 그룹 이미지 업로드
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
}
