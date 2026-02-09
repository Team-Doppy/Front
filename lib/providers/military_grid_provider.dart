import 'dart:async';
import 'package:doppy/data/models/military_grid_model.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show GlobalKey;
import 'package:doppy/data/services/user_service.dart';
import 'package:doppy/data/services/auth_service.dart';

/// Military Grid 프로바이더 (새로운 시스템)
class MilitaryGridProvider extends ChangeNotifier {
  final UserService _userService = UserService();

  /// ✅ 클라이언트 기본 phase별 slotCount (서버 로드 전/실패 시 스켈레톤 렌더용)
  /// - 값은 "대충"이며, 서버가 없을 때 UI 뼈대를 먼저 잡기 위한 용도
  static const Map<String, int> _clientPhaseSlotCounts = {
    'preEnlistment': 7,
    'training': 5,
    'private': 13,
    'privateFirstClass': 13,
    'corporal': 13,
    'sergeant': 13,
  };

  // ✅ 계정 변경 감지를 위한 현재 사용자명 추적
  String? _currentUsername;

  // Military Grid 데이터 캐싱
  MilitaryGridResponse? _gridResponse;
  bool _isLoading = false;

  // 블러 레이어 표시 여부 (Phase 선택 시 사용)
  bool _showBlurOverlay = false;

  // Phase 선택 관련 상태
  Phase? _phasePickerSelectedPhase;
  List<Phase>? _phasePickerPhases;
  Function(Phase)? _phasePickerOnConfirm;

  // phase -> slotIndex -> GlobalKey
  final Map<String, Map<int, GlobalKey>> _cellKeys = {};

  // ✅ 선택된 Phase 상태 관리
  Phase? _selectedPhase;

  /// Military Grid 데이터 가져오기
  MilitaryGridResponse? get gridResponse => _gridResponse;

  /// 선택된 Phase 가져오기
  Phase? get selectedPhase => _selectedPhase;

  /// ✅ 서버 로드 전/실패 시 사용할 phase 목록(스켈레톤용)
  List<Phase> buildClientPhases() {
    return _clientPhaseSlotCounts.entries
        .map(
          (e) => Phase(
            phase: e.key,
            labelKey: 'phase.${e.key}',
            slotCount: e.value,
            cells: const [],
          ),
        )
        .toList();
  }

  /// ✅ 서버 로드 전/실패 시 사용할 스켈레톤 그리드 응답
  MilitaryGridResponse buildPlaceholderResponse({required Phase phase}) {
    return MilitaryGridResponse(
      phases: [phase], // phase 객체를 그대로 사용
      greetingKey: '', // 로딩 중에는 문구를 숨김
      availablePhases: const [],
      currentPhase: phase.phase,
    );
  }

  /// 로딩 상태
  bool get isLoading => _isLoading;

  /// 블러 레이어 표시 여부
  bool get showBlurOverlay => _showBlurOverlay;

  /// Phase 선택 관련 getter
  Phase? get phasePickerSelectedPhase => _phasePickerSelectedPhase;
  List<Phase>? get phasePickerPhases => _phasePickerPhases;
  Function(Phase)? get phasePickerOnConfirm => _phasePickerOnConfirm;

  /// ✅ 계정 변경 감지 및 캐시 초기화
  void _checkAndClearCacheIfUserChanged() {
    final currentUsername = AuthService().currentUsernameSync;
    if (_currentUsername != null &&
        currentUsername != null &&
        _currentUsername != currentUsername) {
      debugPrint(
        '[MilitaryGridProvider] 계정 변경 감지: $_currentUsername -> $currentUsername, 캐시 초기화',
      );
      clearAllCache();
      _cellKeys.clear();
    }
    _currentUsername = currentUsername;
  }

  /// Military Grid 데이터 로드
  /// - phase: 미지정 시 현재 계급 phase 반환 (부팅 시 기본), 지정 시 해당 phase만 반환
  /// - ✅ 초기 로드 시 무조건 현재 상태(현재 계급 phase)로 로드
  Future<void> loadGrid({String? region, String? phase}) async {
    _checkAndClearCacheIfUserChanged();

    if (_isLoading || _gridResponse != null) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // ✅ 초기 로드 시 phase를 명시적으로 null로 전달하여 현재 상태로 로드
      final response = await _userService.getMilitaryGrid(
        region: region,
        phase: phase, // phase가 null이면 서버가 현재 계급 phase 반환
      );
      _gridResponse = response;

      // ✅ 초기 로드 시 무조건 서버에서 반환된 currentPhase로 선택된 phase 설정
      // (기존 _selectedPhase 무시)
      _syncSelectedPhaseFromServerResponse(response, force: true);

      debugPrint(
        '[MilitaryGridProvider] Military Grid 초기 로드 완료: phase=${response.currentPhase}, '
        'availablePhases=${response.availablePhases}',
      );
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[MilitaryGridProvider] Military Grid 로드 실패: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Military Grid 데이터 재로드
  /// - phase: 미지정 시 현재 계급 phase 반환, 지정 시 해당 phase만 반환
  Future<void> reloadGrid({String? region, String? phase}) async {
    _checkAndClearCacheIfUserChanged();

    if (_isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      final response = await _userService.getMilitaryGrid(
        region: region,
        phase: phase,
      );
      _gridResponse = response;

      // ✅ 서버에서 반환된 currentPhase로 선택된 phase 업데이트
      _syncSelectedPhaseFromServerResponse(response);

      debugPrint(
        '[MilitaryGridProvider] Military Grid 재로드 완료: phase=${response.currentPhase}, '
        'availablePhases=${response.availablePhases}',
      );
    } catch (e) {
      debugPrint('[MilitaryGridProvider] Military Grid 재로드 실패: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 서버 응답에서 선택된 phase 동기화
  /// [force]: true면 기존 _selectedPhase를 무시하고 무조건 서버 응답으로 설정
  void _syncSelectedPhaseFromServerResponse(
    MilitaryGridResponse response, {
    bool force = false,
  }) {
    final currentPhaseCode = response.currentPhase;
    if (currentPhaseCode != null && response.phases.isNotEmpty) {
      Phase? matched;
      for (final p in response.phases) {
        if (p.phase == currentPhaseCode) {
          matched = p;
          break;
        }
      }
      // ✅ force가 true이거나 기존 선택이 없으면 무조건 서버 응답으로 설정
      if (force || _selectedPhase == null) {
        _selectedPhase = matched ?? response.phases.first;
        debugPrint(
          '[MilitaryGridProvider] _selectedPhase를 서버 응답으로 설정: ${_selectedPhase?.phase}',
        );
      }
      return;
    }

    // currentPhase가 없으면, 기존 선택 유지. 다만 처음 로드라면 첫 phase를 선택.
    if (force || (_selectedPhase == null && response.phases.isNotEmpty)) {
      _selectedPhase = response.phases.first;
      debugPrint(
        '[MilitaryGridProvider] _selectedPhase를 첫 phase로 설정: ${_selectedPhase?.phase}',
      );
    }
  }

  /// 셀 키 등록
  void registerCellKey(Phase phase, Cell cell, GlobalKey key) {
    final phaseKey = phase.phase;
    _cellKeys.putIfAbsent(phaseKey, () => {})[cell.slotIndex] = key;
  }

  /// 셀 키 가져오기
  GlobalKey? getCellKey(Phase phase, Cell cell) {
    return _cellKeys[phase.phase]?[cell.slotIndex];
  }

  /// Phase별 셀 키들 가져오기
  Map<int, GlobalKey> getCellKeysForPhase(Phase phase) {
    return Map<int, GlobalKey>.unmodifiable(_cellKeys[phase.phase] ?? const {});
  }

  /// Phase 선택 UI 표시
  void showPhasePicker({
    required Phase selectedPhase,
    required List<Phase> phases,
    required Function(Phase) onConfirm,
  }) {
    _phasePickerSelectedPhase = selectedPhase;
    _phasePickerPhases = phases;
    _phasePickerOnConfirm = onConfirm;
    _showBlurOverlay = true;
    notifyListeners();
  }

  /// Phase 선택 UI 닫기
  void closePhasePicker() {
    _showBlurOverlay = false;
    _phasePickerSelectedPhase = null;
    _phasePickerPhases = null;
    _phasePickerOnConfirm = null;
    notifyListeners();
  }

  /// ✅ Phase 선택 (홈 화면에서 사용)
  /// - phase 선택 시 서버에서 해당 phase 데이터를 다시 로드
  Future<void> selectPhase(Phase phase) async {
    final previousPhase = _selectedPhase?.phase;
    if (previousPhase != phase.phase) {
      _selectedPhase = phase;
      debugPrint(
        '[MilitaryGridProvider] Phase 선택: $previousPhase → ${phase.phase}',
      );

      // ✅ phase 전환 시 서버에서 해당 phase 데이터 재로드
      try {
        await reloadGrid(phase: phase.phase);
      } catch (e) {
        debugPrint('[MilitaryGridProvider] Phase 선택 후 재로드 실패: $e');
        // 에러가 발생해도 선택된 phase는 유지
      }
    } else {
      debugPrint('[MilitaryGridProvider] Phase 선택 스킵: 이미 ${phase.phase} 선택됨');
    }
  }

  /// ✅ Phase 선택 해제 (모든 phase 표시)
  void clearPhaseSelection() {
    if (_selectedPhase != null) {
      _selectedPhase = null;
      debugPrint('[MilitaryGridProvider] Phase 선택 해제');
      notifyListeners();
    }
  }

  /// ✅ 사용자 상태에 따라 기본 Phase 결정
  Phase? determineDefaultPhase({
    required List<Phase> allPhases,
    MilitaryStatus? userStatus,
    MilitaryRank? currentRank,
  }) {
    String? defaultPhaseCode;

    if (userStatus == MilitaryStatus.beforeEnlistment) {
      defaultPhaseCode = 'preEnlistment';
    } else if (userStatus == MilitaryStatus.afterEnlistment &&
        currentRank != null) {
      // 계급에 따라 phase 결정
      switch (currentRank) {
        case MilitaryRank.trainee:
          defaultPhaseCode = 'training';
          break;
        case MilitaryRank.private:
          defaultPhaseCode = 'private';
          break;
        case MilitaryRank.privateFirstClass:
          defaultPhaseCode = 'privateFirstClass';
          break;
        case MilitaryRank.corporal:
          defaultPhaseCode = 'corporal';
          break;
        case MilitaryRank.sergeant:
          defaultPhaseCode = 'sergeant';
          break;
      }
    }

    if (defaultPhaseCode != null) {
      return allPhases.firstWhere(
        (p) =>
            p.phase == defaultPhaseCode &&
            (p.slotCount > 0 || p.cells.isNotEmpty),
        orElse:
            () => allPhases.firstWhere(
              (p) => p.slotCount > 0 || p.cells.isNotEmpty,
              orElse: () => allPhases.first,
            ),
      );
    }

    return allPhases.firstWhere(
      (p) => p.slotCount > 0 || p.cells.isNotEmpty,
      orElse: () => allPhases.first,
    );
  }

  /// 블러 레이어 표시 설정
  void setBlurOverlay(bool show) {
    if (_showBlurOverlay != show) {
      _showBlurOverlay = show;
      if (!show) {
        // 블러가 닫힐 때 Phase 선택 상태 초기화
        _phasePickerSelectedPhase = null;
        _phasePickerPhases = null;
        _phasePickerOnConfirm = null;
      }
      notifyListeners();
    }
  }

  /// 모든 캐시 삭제
  void clearAllCache() {
    _gridResponse = null;
    _selectedPhase = null;
    _cellKeys.clear();
    notifyListeners();
  }

  /// ✅ 로그아웃/계정 변경 시 명시적으로 호출
  void logout() {
    clearAllCache();
    _currentUsername = null;
    debugPrint('[MilitaryGridProvider] 로그아웃 - 모든 캐시 초기화됨');
  }
}
