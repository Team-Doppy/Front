import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/pages/screens/splash_screen.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/screens/profile_image_view_screen.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'dart:io';

/// 군인 정보 설정 화면 (Cupertino 스타일)
class MilitaryInfoSettingScreen extends StatefulWidget {
  final MilitaryInfo? initialInfo;
  final String? initialAlias; // ✅ 별명 추가
  final Future<bool> Function(String alias, MilitaryInfo militaryInfo)
  onSave; // ✅ async 함수로 변경

  const MilitaryInfoSettingScreen({
    super.key,
    this.initialInfo,
    this.initialAlias,
    required this.onSave,
  });

  @override
  State<MilitaryInfoSettingScreen> createState() =>
      _MilitaryInfoSettingScreenState();
}

class _MilitaryInfoSettingScreenState extends State<MilitaryInfoSettingScreen> {
  late UserType _selectedUserType;
  late MilitaryBranch _selectedBranch;
  late MilitaryStatus _selectedStatus;
  DateTime? _enlistmentDate;
  DateTime? _plannedEnlistmentDate;
  Map<String, DateTime>? _manualPromotionDates;
  List<String> _connectedMilitaryUserIds = []; // 곰신/가족 모드용

  // ✅ 별명 입력 필드
  late TextEditingController _aliasController;

  // ✅ 초기값 저장 (변경 감지용)
  DateTime? _initialEnlistmentDate;
  Map<String, DateTime>? _initialManualPromotionDates;

  // ✅ promotionTimeline (서버 계산값, 읽기 전용)
  Map<String, String>? _promotionTimeline;

  // 피커 컨트롤러
  late FixedExtentScrollController _userTypeController;
  late FixedExtentScrollController _branchController;
  late FixedExtentScrollController _statusController;

  bool _isSaving = false;

  String _getBranchImagePath(MilitaryBranch branch) {
    switch (branch) {
      case MilitaryBranch.army:
        return 'assets/images/army_nobg.png';
      case MilitaryBranch.navy:
        return 'assets/images/navy_nobg.png';
      case MilitaryBranch.airForce:
        return 'assets/images/airforce_nobg.png';
      case MilitaryBranch.marines:
        return 'assets/images/marin_nobg.png';
      default:
        return 'assets/images/army_nobg.png';
    }
  }

  /// 프로필 이미지 뷰 화면 열기
  void _openProfileImageView() {
    final currentUser = context.read<UserProvider>().currentUser;
    if (currentUser == null) return;

    // ✅ 현재 화면을 먼저 pop
    Navigator.of(context).pop();

    // ✅ ProfileImageViewScreen으로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 150),
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  ProfileImageViewScreen(
                    profileImageUrl: currentUser.profileImageUrl,
                    username: currentUser.username,
                    isOwnProfile: true,
                    onShareProfile: () {
                      // TODO: 공유 기능 구현
                    },
                    onCopyProfileLink: () async {
                      // TODO: 링크 복사 기능 구현
                    },
                    onGallerySelected: (file) {
                      _handleImageSelected(file);
                    },
                    onSetDefaultImage: () {
                      _clearProfileImage();
                    },
                    onFollowStatusChanged: null,
                  ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
  }

  /// 선택된 이미지 처리 (원형 크롭된 이미지 업로드)
  Future<void> _handleImageSelected(File file) async {
    try {
      final upload = context.read<UploadService>();
      final task = upload.enqueueFile(file, kind: UploadKind.profile);

      VoidCallback? listener;
      listener = () {
        if (task.state == UploadState.success) {
          final imageUrl = task.url ?? '';
          if (imageUrl.isNotEmpty && context.mounted) {
            context.read<MyProfileFeedProvider>().updateProfileImageAfterUpload(
              imageUrl,
              context,
            );
          }
          if (listener != null) {
            task.removeListener(listener);
          }
        }
      };
      task.addListener(listener);
    } catch (e) {
      debugPrint('[MilitaryInfoSettingScreen] 이미지 업로드 실패: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('프로필 이미지 업로드에 실패했습니다'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// 프로필 이미지 삭제
  Future<void> _clearProfileImage() async {
    try {
      final success = await context
          .read<MyProfileFeedProvider>()
          .deleteProfileImageAndUpdateCache(context);

      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('프로필 이미지 삭제에 실패했습니다'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      debugPrint('[MilitaryInfoSettingScreen] 프로필 이미지 삭제 실패: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('프로필 이미지 삭제에 실패했습니다'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Widget _buildProfileAndBranchHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final currentUser = context.watch<UserProvider>().currentUser;
    final profileImageUrl = currentUser?.profileImageUrl;
    final username = currentUser?.username ?? '';

    final branchImage = _getBranchImagePath(_selectedBranch);

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6, left: 20, right: 20),
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 프로필 아바타 (배경)
            CommonProfileAvatar(
              imageUrl: profileImageUrl,
              username: username,
              size: 150,
              borderWidth: 2,
              borderColor: colorScheme.onSurface.withOpacity(0.12),
              backgroundColor:
                  isDarkMode
                      ? colorScheme.background
                      : colorScheme.surfaceVariant,
              onTap: () => _openProfileImageView(),
            ),
            // 군종 아이콘 (하단 우측 오버레이)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surface,
                  border: Border.all(
                    color: colorScheme.onSurface.withOpacity(0.12),
                    width: 1,
                  ),
                ),
                child: ClipOval(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(branchImage, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final info = widget.initialInfo;

    _selectedUserType = info?.userType ?? UserType.military;
    _selectedBranch = info?.branch ?? MilitaryBranch.army;
    _selectedStatus = info?.status ?? MilitaryStatus.afterEnlistment;
    _enlistmentDate = info?.enlistmentDate;
    _plannedEnlistmentDate = info?.plannedEnlistmentDate;
    _manualPromotionDates =
        info?.manualPromotionDates != null
            ? Map<String, DateTime>.from(info!.manualPromotionDates!)
            : null;
    _connectedMilitaryUserIds =
        info?.connectedMilitaryUserIds != null
            ? List<String>.from(info!.connectedMilitaryUserIds!)
            : [];
    _promotionTimeline = info?.promotionTimeline;

    // ✅ 초기값 저장 (변경 감지용)
    _initialEnlistmentDate = info?.enlistmentDate;
    _initialManualPromotionDates =
        info?.manualPromotionDates != null
            ? Map<String, DateTime>.from(info!.manualPromotionDates!)
            : null;

    // ✅ 별명 컨트롤러 초기화
    _aliasController = TextEditingController(text: widget.initialAlias ?? '');

    _userTypeController = FixedExtentScrollController(
      initialItem: UserType.values.indexOf(_selectedUserType),
    );
    _branchController = FixedExtentScrollController(
      initialItem: MilitaryBranch.values.indexOf(_selectedBranch),
    );
    _statusController = FixedExtentScrollController(
      initialItem: MilitaryStatus.values.indexOf(_selectedStatus),
    );
  }

  @override
  void dispose() {
    _userTypeController.dispose();
    _branchController.dispose();
    _statusController.dispose();
    _aliasController.dispose(); // ✅ 별명 컨트롤러 해제
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    // ✅ 입대일/진급일 변경 감지
    final isEnlistmentDateChanged =
        _selectedStatus == MilitaryStatus.afterEnlistment &&
        _enlistmentDate != _initialEnlistmentDate;

    final isPromotionDatesChanged = _hasPromotionDatesChanged();
    final requiresFullReload =
        isEnlistmentDateChanged || isPromotionDatesChanged;

    // ✅ 입대일/진급일 변경은 "위험 변경" → 확인 2번
    if (requiresFullReload) {
      String title;
      String message;

      if (isEnlistmentDateChanged && isPromotionDatesChanged) {
        // 둘 다 변경된 경우
        title = '입대일 및 진급일 변경';
        message =
            '입대일과 진급일을 변경하면 수동으로 설정한 진급일이 초기화되고, 현재 계급이 자동으로 재계산될 수 있습니다. 계속하시겠습니까?';
      } else if (isEnlistmentDateChanged) {
        // 입대일만 변경된 경우
        title = '입대일 변경';
        message = '입대일을 변경하면 수동으로 설정한 진급일이 초기화될 수 있습니다. 계속하시겠습니까?';
      } else {
        // 진급일만 변경된 경우
        title = '진급일 변경';
        message = '진급일을 변경하면 현재 계급이 자동으로 재계산될 수 있습니다. 계속하시겠습니까?';
      }

      final firstConfirmed = await DialogUtils.showConfirmDialog(
        context,
        title: title,
        message: message,
        confirmText: '변경',
        cancelText: '취소',
        isDestructive: true,
      );

      if (firstConfirmed != true) {
        return; // 사용자가 취소
      }

      // ✅ 2차 확인
      final secondConfirmed = await DialogUtils.showConfirmDialog(
        context,
        title: '마지막 확인',
        message: '정말로 변경할까요?',
        confirmText: '확인',
        cancelText: '취소',
        isDestructive: true,
      );
      if (secondConfirmed != true) {
        return;
      }
    }

    // 곰신/가족 모드일 때는 입대 상태를 기본값으로 설정
    final status =
        _selectedUserType == UserType.military
            ? _selectedStatus
            : MilitaryStatus.afterEnlistment;

    final info = MilitaryInfo(
      userType: _selectedUserType,
      branch: _selectedBranch,
      status: status,
      enlistmentDate: _enlistmentDate,
      // currentRank는 읽기 전용 (서버가 자동 계산) - 요청에 포함하지 않음
      plannedEnlistmentDate: _plannedEnlistmentDate,
      connectedMilitaryUserIds:
          _connectedMilitaryUserIds.isNotEmpty
              ? _connectedMilitaryUserIds
              : null,
      manualPromotionDates: _manualPromotionDates,
    );

    setState(() => _isSaving = true);

    bool success = false;
    try {
      // ✅ 별명과 군 정보 함께 저장 (서버 성공 응답까지 대기)
      success = await widget.onSave(_aliasController.text.trim(), info);
    } catch (e) {
      debugPrint('[MilitaryInfoSettingScreen] onSave failed: $e');
      success = false;
    }

    if (!mounted) return;

    if (!success) {
      setState(() => _isSaving = false);
      await DialogUtils.showInfoDialog(
        context,
        title: '저장 실패',
        message: '잠시 후 다시 시도해주세요.',
      );
      return;
    }

    // ✅ 입대일/진급일 변경 시: 스플래시를 다시 거쳐 앱 상태를 재구성
    if (requiresFullReload) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
      return;
    }

    // ✅ 일반 저장: 화면 닫기
    Navigator.of(context).pop();
  }

  /// 진급일 변경 여부 확인
  bool _hasPromotionDatesChanged() {
    if (_manualPromotionDates == null && _initialManualPromotionDates == null) {
      return false;
    }
    if (_manualPromotionDates == null || _initialManualPromotionDates == null) {
      return true;
    }
    if (_manualPromotionDates!.length != _initialManualPromotionDates!.length) {
      return true;
    }
    for (final entry in _manualPromotionDates!.entries) {
      final initialDate = _initialManualPromotionDates![entry.key];
      if (initialDate == null || initialDate != entry.value) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        backgroundColor: colorScheme.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, color: colorScheme.onSurface),
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          ),
          title: Text(
            '군인 정보 설정',
            style: LocaleTypography.style(
              context: context,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: _isSaving ? null : _handleSave,
              child:
                  _isSaving
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CupertinoActivityIndicator(),
                      )
                      : Text(
                        '저장',
                        style: LocaleTypography.style(
                          context: context,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              // ✅ 프로필 사진 + 군종 아이콘 (원형 Row)
              _buildProfileAndBranchHeader(),

              // ✅ 별명 입력 필드
              _buildAliasSection(),

              // 수동 진급일 조정
              if (_selectedUserType == UserType.military &&
                  _selectedStatus == MilitaryStatus.afterEnlistment &&
                  _enlistmentDate != null)
                _buildManualPromotionSection(),

              // 곰신 모드: 연결된 군인 사용자 검색
              if (_selectedUserType == UserType.girlfriend)
                _buildConnectedUsersSection(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  /// 별명 입력 섹션
  Widget _buildAliasSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return _buildSection(
      title: '별명',
      child: Container(
        padding: const EdgeInsets.only(left: 20, right: 0, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color:
              isDarkMode ? colorScheme.background : colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: TextField(
          controller: _aliasController,
          style: LocaleTypography.style(
            context: context,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            suffixIcon: Icon(
              Icons.chevron_right,
              color: colorScheme.onSurface.withOpacity(0.3),
            ),
            hintText: '별명을 입력하세요',
            hintStyle: LocaleTypography.style(
              context: context,
              fontSize: 16,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: LocaleTypography.style(
              context: context,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// 편집 가능한 날짜 섹션 (클릭 가능한 카드 형태)
  /// 계급별 라벨 반환 (진급일 관리 섹션용)
  String _getRankLabel(MilitaryRank rank) {
    switch (rank) {
      case MilitaryRank.trainee:
        return '입대일';
      case MilitaryRank.private:
        return '수료일';
      case MilitaryRank.privateFirstClass:
        return '일병 진급일';
      case MilitaryRank.corporal:
        return '상병 진급일';
      case MilitaryRank.sergeant:
        return '병장 진급일';
    }
  }

  /// promotionTimeline 키를 MilitaryRank로 변환
  String? _getPromotionTimelineKey(MilitaryRank rank) {
    switch (rank) {
      case MilitaryRank.trainee:
        return 'enlistment';
      case MilitaryRank.private:
        return 'trainingCompletion';
      case MilitaryRank.privateFirstClass:
        return 'privateFirstClass';
      case MilitaryRank.corporal:
        return 'corporal';
      case MilitaryRank.sergeant:
        return 'sergeant';
    }
  }

  /// promotionTimeline에서 날짜 가져오기 (서버 계산값)
  DateTime? _getDateFromPromotionTimeline(MilitaryRank rank) {
    final timelineKey = _getPromotionTimelineKey(rank);
    if (timelineKey == null || _promotionTimeline == null) return null;

    final dateString = _promotionTimeline![timelineKey];
    if (dateString == null || dateString.isEmpty) return null;

    try {
      // yyyy-MM-dd 형식 파싱
      final parts = dateString.split('-');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
    } catch (e) {
      debugPrint('[MilitaryInfoSettingScreen] promotionTimeline 파싱 실패: $e');
    }
    return null;
  }

  Widget _buildManualPromotionSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return _buildSection(
      title: '진급일 관리',
      child: Column(
        children:
            MilitaryRank.values.map((rank) {
              final manualDate = _manualPromotionDates?[rank.name];
              final hasManual = manualDate != null;

              // ✅ promotionTimeline에서 서버 계산값 가져오기 (수동 설정이 없을 때)
              DateTime? serverCalculatedDate;
              if (!hasManual) {
                serverCalculatedDate = _getDateFromPromotionTimeline(rank);
              }

              // ✅ 수동 설정이 있으면 수동값, 없으면 서버 계산값, 둘 다 없으면 자동 계산값
              DateTime? displayDate;
              if (hasManual) {
                displayDate = manualDate;
              } else if (serverCalculatedDate != null) {
                displayDate = serverCalculatedDate;
              } else {
                // fallback: 클라이언트 자동 계산 (promotionTimeline이 없을 때)
                if (_enlistmentDate != null) {
                  displayDate = _calculateAutoPromotionDate(
                    rank,
                    _enlistmentDate!,
                  );
                }
              }

              final dateText =
                  displayDate != null
                      ? '${displayDate.year}.${displayDate.month.toString().padLeft(2, '0')}.${displayDate.day.toString().padLeft(2, '0')}'
                      : '-';

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap:
                      () => _showPromotionDatePicker(
                        rank,
                        displayDate ?? DateTime.now(),
                      ),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isDarkMode
                              ? colorScheme.background
                              : colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getRankLabel(rank),
                                style: LocaleTypography.style(
                                  context: context,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    dateText,
                                    style: LocaleTypography.style(
                                      context: context,
                                      fontSize: 16,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        Icon(
                          Icons.chevron_right,
                          color: colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  /// 자동 진급일 계산 (입대일 기준)
  DateTime? _calculateAutoPromotionDate(
    MilitaryRank rank,
    DateTime enlistmentDate,
  ) {
    // 계급별 진급 주차 (입대일 기준)
    final promotionWeeks = {
      MilitaryRank.trainee: 0, // 훈련병: 입대일
      MilitaryRank.private: 5, // 이병: 입대 후 5주
      MilitaryRank.privateFirstClass: 9, // 일병: 입대 후 9주
      MilitaryRank.corporal: 13, // 상병: 입대 후 13주
      MilitaryRank.sergeant: 17, // 병장: 입대 후 17주
    };

    final weeks = promotionWeeks[rank];
    if (weeks == null) return null;

    return enlistmentDate.add(Duration(days: weeks * 7));
  }

  /// 전역일 계산 (promotionTimeline 우선, 없으면 입대일 + 군종별 복무 개월)
  DateTime? _calculateDischargeDate() {
    // ✅ promotionTimeline에서 전역일 가져오기 (서버 계산값)
    if (_promotionTimeline != null &&
        _promotionTimeline!['discharge'] != null) {
      try {
        final dateString = _promotionTimeline!['discharge']!;
        final parts = dateString.split('-');
        if (parts.length == 3) {
          return DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
        }
      } catch (e) {
        debugPrint('[MilitaryInfoSettingScreen] dischargeDate 파싱 실패: $e');
      }
    }

    // fallback: 클라이언트 계산 (promotionTimeline이 없을 때)
    if (_enlistmentDate == null) return null;
    final serviceMonths = _selectedBranch.serviceMonths;
    return DateTime(
      _enlistmentDate!.year,
      _enlistmentDate!.month + serviceMonths,
      _enlistmentDate!.day,
    );
  }

  /// 특정 계급의 날짜 가져오기 (수동 설정 > promotionTimeline > 자동 계산 순서)
  DateTime? _getRankDate(MilitaryRank rank) {
    // 1. 수동 설정된 날짜가 있으면 우선 사용
    final manualDate = _manualPromotionDates?[rank.name];
    if (manualDate != null) return manualDate;

    // 2. promotionTimeline에서 서버 계산값 가져오기
    final timelineDate = _getDateFromPromotionTimeline(rank);
    if (timelineDate != null) return timelineDate;

    // 3. fallback: 클라이언트 자동 계산 (promotionTimeline이 없을 때)
    if (_enlistmentDate == null) return null;
    return _calculateAutoPromotionDate(rank, _enlistmentDate!);
  }

  /// 진급일 피커의 최소 날짜 계산
  DateTime? _getMinDateForRank(MilitaryRank rank) {
    // ✅ 입대일은 자유롭게 변경 가능 (제한 없음)
    if (rank == MilitaryRank.trainee) {
      return null; // 제한 없음
    }

    if (_enlistmentDate == null) return null;

    switch (rank) {
      case MilitaryRank.trainee:
        return null; // 입대일은 제한 없음
      case MilitaryRank.private:
        // 수료일은 입대일 이후
        return _enlistmentDate!.add(const Duration(days: 1));
      case MilitaryRank.privateFirstClass:
        // 일병 진급일은 수료일 이후
        final privateDate = _getRankDate(MilitaryRank.private);
        return privateDate?.add(const Duration(days: 1));
      case MilitaryRank.corporal:
        // 상병 진급일은 일병 진급일 이후
        final pfcDate = _getRankDate(MilitaryRank.privateFirstClass);
        return pfcDate?.add(const Duration(days: 1));
      case MilitaryRank.sergeant:
        // 병장 진급일은 상병 진급일 이후
        final corporalDate = _getRankDate(MilitaryRank.corporal);
        return corporalDate?.add(const Duration(days: 1));
    }
  }

  /// 진급일 피커의 최대 날짜 계산
  DateTime? _getMaxDateForRank(MilitaryRank rank) {
    // ✅ 입대일은 자유롭게 변경 가능 (제한 없음)
    if (rank == MilitaryRank.trainee) {
      return null; // 제한 없음
    }

    final dischargeDate = _calculateDischargeDate();
    if (dischargeDate == null) return null;

    switch (rank) {
      case MilitaryRank.trainee:
        return null; // 입대일은 제한 없음
      case MilitaryRank.private:
        // 수료일은 일병 진급일 이전
        final pfcDate = _getRankDate(MilitaryRank.privateFirstClass);
        if (pfcDate != null) {
          return pfcDate.subtract(const Duration(days: 1));
        }
        return dischargeDate.subtract(const Duration(days: 1));
      case MilitaryRank.privateFirstClass:
        // 일병 진급일은 상병 진급일 이전
        final corporalDate = _getRankDate(MilitaryRank.corporal);
        if (corporalDate != null) {
          return corporalDate.subtract(const Duration(days: 1));
        }
        return dischargeDate.subtract(const Duration(days: 1));
      case MilitaryRank.corporal:
        // 상병 진급일은 병장 진급일 이전
        final sergeantDate = _getRankDate(MilitaryRank.sergeant);
        if (sergeantDate != null) {
          return sergeantDate.subtract(const Duration(days: 1));
        }
        return dischargeDate.subtract(const Duration(days: 1));
      case MilitaryRank.sergeant:
        // 병장 진급일은 전역일 이전
        return dischargeDate.subtract(const Duration(days: 1));
    }
  }

  /// 진급일 선택 바텀시트 표시
  void _showPromotionDatePicker(MilitaryRank rank, DateTime initialDate) {
    final colorScheme = Theme.of(context).colorScheme;
    DateTime selectedDate = initialDate;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setModalState) => Container(
                  height: MediaQuery.of(context).size.height * 0.6,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // 헤더
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _getRankLabel(rank),
                              style: LocaleTypography.style(
                                context: context,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _manualPromotionDates?.remove(rank.name);
                                      if (_manualPromotionDates?.isEmpty ??
                                          false) {
                                        _manualPromotionDates = null;
                                      }
                                    });
                                    Navigator.of(context).pop();
                                  },
                                  child: Text(
                                    '자동 계산',
                                    style: LocaleTypography.style(
                                      context: context,
                                      fontSize: 14,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _manualPromotionDates ??= {};
                                      _manualPromotionDates![rank.name] =
                                          selectedDate;
                                    });
                                    Navigator.of(context).pop();
                                  },
                                  child: Text(
                                    '저장',
                                    style: LocaleTypography.style(
                                      context: context,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // 날짜 피커 (진급일 순서 보장: 입대일 < 수료일 < 일병 < 상병 < 병장 < 전역일)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final minDate = _getMinDateForRank(rank);
                            final maxDate = _getMaxDateForRank(rank);

                            // 날짜 범위가 유효하지 않으면 경고 표시
                            if (minDate != null &&
                                maxDate != null &&
                                minDate.isAfter(maxDate)) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    '입대일을 먼저 설정해주세요',
                                    style: LocaleTypography.style(
                                      context: context,
                                      fontSize: 14,
                                      color: colorScheme.error,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return CupertinoDatePicker(
                              initialDateTime: initialDate,
                              mode: CupertinoDatePickerMode.date,
                              minimumDate: minDate,
                              maximumDate: maxDate,
                              onDateTimeChanged: (date) {
                                setModalState(() {
                                  selectedDate = date;
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Widget _buildConnectedUsersSection() {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildSection(
      title:
          _selectedUserType == UserType.girlfriend
              ? '연결된 군인 (1명)'
              : '연결된 군인 (여러 명 가능)',
      child: Column(
        children: [
          // 검색 버튼
          ElevatedButton.icon(
            onPressed: () {
              // TODO: 유저 검색 바텀시트 열기
              // showModalBottomSheet로 UserSearchBottomSheet 열고
              // 선택한 유저를 _connectedMilitaryUserIds에 추가
            },
            icon: const Icon(Icons.search),
            label: const Text('군인 검색'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 선택된 유저 목록
          if (_connectedMilitaryUserIds.isNotEmpty)
            ..._connectedMilitaryUserIds.map((username) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      username,
                      style: LocaleTypography.style(
                        context: context,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: colorScheme.error),
                      onPressed: () {
                        setState(() {
                          _connectedMilitaryUserIds.remove(username);
                        });
                      },
                    ),
                  ],
                ),
              );
            }),
          if (_connectedMilitaryUserIds.isEmpty)
            Text(
              '검색하여 연결할 군인을 추가하세요',
              style: LocaleTypography.style(
                context: context,
                fontSize: 14,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
        ],
      ),
    );
  }
}
