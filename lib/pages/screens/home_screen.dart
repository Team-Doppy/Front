import 'package:doppy/pages/components/military_cell_long_press_preview.dart';
import 'package:doppy/pages/home/common/home_app_bar.dart';
import 'package:doppy/pages/home/pre_enlistment_home_content.dart';
import 'package:doppy/pages/home/military_home_content.dart';
import 'package:doppy/pages/home/girlfriend_home_content.dart';
import 'package:doppy/pages/screens/week_post_list_screen.dart';
import 'package:doppy/providers/military_grid_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/letter_provider.dart';
import 'package:doppy/data/models/military_grid_model.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/utils/week_utils.dart';
import 'package:doppy/pages/screens/post_mode_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  final bool isActive; // 현재 탭이 활성 상태인지

  const HomeScreen({super.key, this.isActive = true});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  // 🎯 포그라운드 복귀 시 새로고침을 위한 GlobalKey
  static final GlobalKey<HomeScreenState> globalKey =
      GlobalKey<HomeScreenState>();

  // Military Grid 관련 상태
  Cell? _selectedCell; // 선택된 Cell (로컬 상태만 유지, Phase는 프로바이더에서 관리)

  // 길게 누르기 미리보기(블러 없이) 오버레이
  OverlayEntry? _cellPreviewEntry;
  Offset _cellPreviewPosition = Offset.zero;
  Phase? _previewPhase;
  Cell? _previewCell;
  bool _isDraggingPreview = false; // 🎯 드래그 중인지 여부
  late AnimationController _previewAnimationController;
  late Animation<double> _previewScaleAnimation;

  @override
  void initState() {
    super.initState();

    // 미리보기 애니메이션 컨트롤러 초기화
    _previewAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _previewScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _previewAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    // ✅ 초기 Military Grid 로드: 무조건 현재 상태(현재 계급 phase)로 로드
    // phase 파라미터를 전달하지 않으면 서버가 현재 계급 phase를 반환
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final gridProvider = context.read<MilitaryGridProvider>();
      if (gridProvider.gridResponse == null) {
        // ✅ phase를 명시적으로 null로 전달하여 현재 상태로 로드
        await gridProvider.loadGrid(phase: null);
      }

      // ✅ 내 프로필 피드 로드 (여친 홈 화면에서 곰신 포스트 섹션에 사용)
      final myFeedProvider = context.read<MyProfileFeedProvider>();
      if (myFeedProvider.posts.isEmpty && !myFeedProvider.isLoading) {
        await myFeedProvider.loadInitial();
      }

      // ✅ 최근 받은 편지 로드 (SupportPostsSection에 사용)
      final letterProvider = context.read<LetterProvider>();
      if (letterProvider.recentLetters.isEmpty && !letterProvider.isLoading) {
        await letterProvider.loadRecentLetters();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // ✅ 프리뷰 제거를 먼저 수행 (컨트롤러 dispose 전)
    _removeCellPreview();
    _previewAnimationController.dispose();
    super.dispose();
  }

  void _removeCellPreview() {
    // ✅ 컨트롤러가 이미 dispose되었거나 mounted가 아니면 바로 제거
    if (!mounted || !_previewAnimationController.isAnimating) {
      _cellPreviewEntry?.remove();
      _cellPreviewEntry = null;
      _previewPhase = null;
      _previewCell = null;
      return;
    }

    try {
      _previewAnimationController
          .reverse()
          .then((_) {
            if (mounted) {
              _cellPreviewEntry?.remove();
              _cellPreviewEntry = null;
              _previewPhase = null;
              _previewCell = null;
            }
          })
          .catchError((_) {
            // reverse 실패 시 바로 제거
            _cellPreviewEntry?.remove();
            _cellPreviewEntry = null;
            _previewPhase = null;
            _previewCell = null;
          });
    } catch (e) {
      // 컨트롤러가 이미 dispose된 경우 바로 제거
      _cellPreviewEntry?.remove();
      _cellPreviewEntry = null;
      _previewPhase = null;
      _previewCell = null;
    }
  }

  void _showOrMoveCellPreview({
    required Phase phase,
    required Cell cell,
    required Offset globalPosition,
    bool isDragging = false, // 🎯 드래그 중인지 여부
  }) {
    _previewPhase = phase;
    _previewCell = cell;
    _cellPreviewPosition = globalPosition;
    _isDraggingPreview = isDragging;

    if (_cellPreviewEntry == null) {
      final overlay = Overlay.of(context, rootOverlay: true);

      _cellPreviewEntry = OverlayEntry(
        builder: (context) {
          final media = MediaQuery.of(context);
          final size = media.size;
          final safeTop = media.padding.top;
          final safeBottom = media.padding.bottom;

          // 프리뷰 카드 크기
          const cardW = 250.0;
          const cardH = 200.0;

          // 손가락 근처에 표시(약간 위로, 아래로 보정)
          double left = _cellPreviewPosition.dx - (cardW / 2);
          double top =
              _cellPreviewPosition.dy - cardH + 20; // 16 -> 8로 조정하여 아래로 보정

          // 화면 밖으로 나가지 않도록 clamp
          left = left.clamp(12.0, size.width - cardW - 12.0);
          top = top.clamp(
            safeTop + 12.0,
            size.height - safeBottom - cardH - 12.0,
          );

          return Stack(
            children: [
              // 빈 곳 탭하면 닫기
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _removeCellPreview,
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: IgnorePointer(
                  child:
                      _isDraggingPreview
                          ? MilitaryCellLongPressPreview(
                            key: ValueKey(
                              'preview-${_previewPhase?.phase}-${_previewCell?.slotIndex}',
                            ),
                            phase: _previewPhase!,
                            cell: _previewCell!,
                          )
                          : ScaleTransition(
                            scale: _previewScaleAnimation,
                            alignment: Alignment.center,
                            child: MilitaryCellLongPressPreview(
                              key: ValueKey(
                                'preview-${_previewPhase?.phase}-${_previewCell?.slotIndex}',
                              ), // 🎯 위젯 교체 시 애니메이션 재시작
                              phase: _previewPhase!,
                              cell: _previewCell!,
                            ),
                          ),
                ),
              ),
            ],
          );
        },
      );
      overlay.insert(_cellPreviewEntry!);
      // 애니메이션 시작 (드래그 중이 아닐 때만)
      if (!_isDraggingPreview) {
        _previewAnimationController.reset();
        _previewAnimationController.forward();
      } else {
        // 드래그 중이면 애니메이션을 완료 상태로 설정 (스케일 1.0)
        _previewAnimationController.value = 1.0;
      }
    } else {
      // 기존 오버레이가 있을 때
      // 🎯 위치는 항상 업데이트해야 하므로 markNeedsBuild 호출
      // 단, 같은 셀을 드래그하는 경우에는 위젯 교체 없이 위치만 업데이트
      final isSameCell =
          _previewPhase?.phase == phase.phase &&
          _previewCell?.slotIndex == cell.slotIndex;
      _cellPreviewEntry?.markNeedsBuild();

      if (!_isDraggingPreview) {
        // 드래그 중이 아니면 애니메이션 재시작 (위젯이 변경된 경우)
        if (!isSameCell) {
          _previewAnimationController.reset();
          _previewAnimationController.forward();
        }
      } else {
        // 드래그 중이면 애니메이션을 완료 상태로 유지 (스케일 1.0)
        _previewAnimationController.value = 1.0;
      }
    }
  }

  /// 셀 길게 누르기 핸들러
  void _handleCellLongPress(
    Phase phase,
    Cell cell,
    Offset? position,
    Offset? cellCenter,
  ) {
    // slotIndex가 0이면 종료 신호
    if (cell.slotIndex == 0) {
      _removeCellPreview();
      return;
    }

    if (position == null) return;

    // 🎯 onLongPressMoveUpdate에서 호출된 경우 (드래그 중)
    // - 기존 오버레이가 있고, 같은 셀을 드래그하는 경우
    final isDragging =
        _cellPreviewEntry != null &&
        _previewPhase?.phase == phase.phase &&
        _previewCell?.slotIndex == cell.slotIndex;

    _showOrMoveCellPreview(
      phase: phase,
      cell: cell,
      globalPosition: position,
      isDragging: isDragging,
    );
  }

  /// 셀 선택 핸들러
  void _handleCellTap(Phase phase, Cell cell) {
    debugPrint(
      '[HomeScreen] _handleCellTap 호출: ${phase.phase} ${cell.slotIndex}주차',
    );

    // ✅ 프로바이더에 phase 선택 저장
    final gridProvider = context.read<MilitaryGridProvider>();
    gridProvider.selectPhase(phase);

    setState(() {
      _selectedCell = cell;
    });

    // ✅ 1. 색깔이 없으면 문구만 보여주고 종료
    final hasPosts = cell.postCount > 0;
    if (!hasPosts) {
      // 포스트가 없는 경우: 문구만 표시
      debugPrint('[HomeScreen] 포스트 없는 셀 클릭 → 문구 표시');

      // 과거/현재/미래 판단
      final isCurrentWeek = cell.currentWeek;
      final currentYearWeek = WeekUtils.getCurrentYearAndWeek();
      final currentYear = currentYearWeek.year;
      final currentWeek = currentYearWeek.weekNumber;
      final cellYear = cell.year;
      final cellWeek = cell.week;

      bool isPast = false;
      bool isFuture = false;

      if (cellYear > 0 && cellWeek > 0) {
        if (cellYear < currentYear) {
          isPast = true;
        } else if (cellYear > currentYear) {
          isFuture = true;
        } else {
          if (cellWeek < currentWeek) {
            isPast = true;
          } else if (cellWeek > currentWeek) {
            isFuture = true;
          }
        }
      } else {
        if (!isCurrentWeek) {
          isPast = true;
        }
      }

      String message = '';
      if (isFuture) {
        message = '아직 기록할 수 없는 주차예요';
      } else if (isPast) {
        if (phase.phase == 'preEnlistment') {
          message = '입대 전 추억을 기록해보세요';
        } else {
          message = '이미 지나간 주차예요';
        }
      } else if (isCurrentWeek) {
        message = '이번 주 기록을 남겨보세요';
      } else {
        message = '기록이 없는 주차예요';
      }

      return;
    }

    // 롱프레스 프리뷰가 떠있으면 닫고 이동
    _removeCellPreview();

    // ✅ 2-4. 셀 상태에 따른 처리
    final isCurrentWeek = cell.currentWeek;

    // 현재 주차 정보 가져오기
    final currentYearWeek = WeekUtils.getCurrentYearAndWeek();
    final currentYear = currentYearWeek.year;
    final currentWeek = currentYearWeek.weekNumber;

    // 셀의 주차 정보
    final cellYear = cell.year;
    final cellWeek = cell.week;

    // 과거/현재/미래 판단
    bool isPast = false;
    bool isFuture = false;

    if (cellYear > 0 && cellWeek > 0) {
      // 연도와 주차가 모두 있는 경우
      if (cellYear < currentYear) {
        isPast = true;
      } else if (cellYear > currentYear) {
        isFuture = true;
      } else {
        // 같은 연도
        if (cellWeek < currentWeek) {
          isPast = true;
        } else if (cellWeek > currentWeek) {
          isFuture = true;
        }
      }
    } else {
      // 연도/주차 정보가 없는 경우 slotIndex로 판단 (대략적)
      // 이번 주가 아닌 경우 과거로 간주
      if (!isCurrentWeek) {
        isPast = true;
      }
    }

    // ✅ 3. 미래 주차 클릭하면 아무일도 안 일어나게
    if (isFuture) {
      debugPrint('[HomeScreen] 미래 주차 클릭 - 무시');
      return;
    }

    // ✅ 4. 이번주 것을 누르면
    if (isCurrentWeek) {
      if (hasPosts) {
        // 비어있지 않은 경우: 기록보기
        debugPrint(
          '[HomeScreen] 이번주 셀(포스트 있음) 클릭 → MilitaryPostListScreen으로 이동',
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (context) => MilitaryPostListScreen(
                  phase: phase.phase,
                  slotIndex: cell.slotIndex,
                ),
          ),
        );
      } else {
        // 비어있는 경우: 글쓰기
        debugPrint('[HomeScreen] 이번주 셀(비어있음) 클릭 → 글쓰기 모드 선택');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const PostModeSelectionScreen(),
          ),
        );
      }
      return;
    }

    // ✅ 2. 지난 그리드(비어있는)를 클릭하면
    if (isPast && !hasPosts) {
      // 오직 입대전일 때만 글쓰기 가능
      if (phase.phase == 'preEnlistment') {
        debugPrint('[HomeScreen] 지난 주차(입대전, 비어있음) 클릭 → 글쓰기 모드 선택');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const PostModeSelectionScreen(),
          ),
        );
      } else {
        // 나머지는 못쓰게 (아무일도 안 일어남)
        debugPrint('[HomeScreen] 지난 주차(입대전 아님, 비어있음) 클릭 - 무시');
      }
      return;
    }

    // ✅ 포스트가 있는 경우: 기록보기
    if (hasPosts) {
      debugPrint('[HomeScreen] 셀(포스트 있음) 클릭 → MilitaryPostListScreen으로 이동');
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (context) => MilitaryPostListScreen(
                phase: phase.phase,
                slotIndex: cell.slotIndex,
              ),
        ),
      );
    }
  }

  /// Phase 선택 UI 표시
  void _showPhasePicker(BuildContext context) {
    final gridProvider = context.read<MilitaryGridProvider>();
    final gridResponse = gridProvider.gridResponse;

    if (gridResponse == null) return;

    // ✅ 모든 가능한 Phase 목록 생성
    final allPhaseCodes = [
      'preEnlistment',
      'training',
      'private',
      'privateFirstClass',
      'corporal',
      'sergeant',
    ];

    // ✅ 서버에서 받은 Phase와 매칭하여 모든 Phase 목록 생성
    final allPhases =
        allPhaseCodes.map((phaseCode) {
          // 서버에서 받은 Phase 중에서 찾기
          final existingPhase = gridResponse.phases.firstWhere(
            (p) => p.phase == phaseCode,
            orElse:
                () => Phase(
                  phase: phaseCode,
                  labelKey: 'phase.$phaseCode',
                  slotCount: 0,
                  cells: [],
                ),
          );
          return existingPhase;
        }).toList();

    // ✅ 프로바이더의 선택된 phase 또는 기본 phase 사용
    final currentUser = context.read<UserProvider>().currentUser;
    // ✅ 곰신의 경우 연결된 남친의 militaryInfo 사용
    final militaryInfo =
        currentUser?.connectedMilitaryUser?.militaryInfo ??
        currentUser?.militaryInfo;
    final userStatus = militaryInfo?.status;
    final currentRank = militaryInfo?.currentRank;

    final defaultPhase = gridProvider.determineDefaultPhase(
      allPhases: allPhases,
      userStatus: userStatus,
      currentRank: currentRank,
    );

    final selectedPhase =
        gridProvider.selectedPhase ?? defaultPhase ?? allPhases.first;

    // ✅ 서버에서 반환된 availablePhases 사용 (없으면 전체 phase 목록 사용)
    // ✅ 지나간 phase도 모두 활성화되어야 하므로, availablePhases가 비어있으면 모든 phase 사용
    final availablePhasesFromServer = gridResponse.availablePhases;
    final phasesForPicker =
        availablePhasesFromServer.isNotEmpty
            ? availablePhasesFromServer.map((phaseCode) {
              return allPhases.firstWhere(
                (p) => p.phase == phaseCode,
                orElse:
                    () => Phase(
                      phase: phaseCode,
                      labelKey: 'phase.$phaseCode',
                      slotCount: 0,
                      cells: [],
                    ),
              );
            }).toList()
            : allPhases; // ✅ availablePhases가 비어있으면 모든 phase 활성화

    // Provider에 Phase 선택 UI 표시 요청
    gridProvider.showPhasePicker(
      selectedPhase: selectedPhase,
      phases: phasesForPicker,
      onConfirm: (phase) async {
        debugPrint('[HomeScreen] Phase 선택 다이얼로그 onConfirm: ${phase.phase}');
        // ✅ UX: "적용" 누르는 즉시 오버레이를 닫고, 뒤에서 쉬머 로딩이 보이게 한다.
        gridProvider.closePhasePicker();

        if (mounted) {
          setState(() {
            _selectedCell = null; // Phase 변경 시 셀 선택 초기화
          });
        }

        // ✅ 프로바이더에 phase 선택 저장 (서버에서 해당 phase 데이터 재로드)
        debugPrint('[HomeScreen] gridProvider.selectPhase 호출 (unawaited)');
        // ignore: unawaited_futures
        gridProvider.selectPhase(phase);
        debugPrint('[HomeScreen] Phase 선택 완료(오버레이 닫힘)');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          // ✅ 공통 AppBar (Phase 선택 버튼 포함)
          HomeAppBar(onPhasePickerTap: () => _showPhasePicker(context)),

          // ✅ 사용자 타입별 콘텐츠
          SliverToBoxAdapter(
            child: Consumer<UserProvider>(
              builder: (context, userProvider, _) {
                final currentUser = userProvider.currentUser;
                final militaryInfo = currentUser?.militaryInfo;
                final userType = militaryInfo?.userType;
                final userStatus = militaryInfo?.status;

                // ✅ 곰신 모드 (militaryInfo가 null이어도 role로 판단 가능)
                if (userType == UserType.girlfriend ||
                    currentUser?.role == 'girlfriend') {
                  return GirlfriendHomeContent(
                    onCellTap: _handleCellTap,
                    onCellLongPress: _handleCellLongPress,
                    selectedCell: _selectedCell,
                  );
                }

                // ✅ 입대 예정자 모드
                if (userStatus == MilitaryStatus.beforeEnlistment ||
                    currentUser?.role == 'plannedEnlistment') {
                  return PreEnlistmentHomeContent(
                    onCellTap: _handleCellTap,
                    onCellLongPress: _handleCellLongPress,
                    selectedCell: _selectedCell,
                  );
                }

                // ✅ 입대 후 (군인) 모드
                return MilitaryHomeContent(
                  onCellTap: _handleCellTap,
                  onCellLongPress: _handleCellLongPress,
                  selectedCell: _selectedCell,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
