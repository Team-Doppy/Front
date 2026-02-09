import 'package:doppy/data/models/military_grid_model.dart';
import 'package:doppy/l10n/military_grid_messages.dart';
import 'package:doppy/providers/military_grid_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 홈 화면 공통 AppBar
class HomeAppBar extends StatelessWidget {
  final VoidCallback onPhasePickerTap;

  const HomeAppBar({super.key, required this.onPhasePickerTap});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      pinned: false,
      floating: true,
      snap: false,
      title: Container(
        padding: const EdgeInsets.only(bottom: 6, left: 6),
        child: Text(
          '',
          style: GoogleFonts.notoSansKr(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      centerTitle: false,
      actions: [
        // Phase 선택 버튼
        Consumer2<MilitaryGridProvider, UserProvider>(
          builder: (context, gridProvider, userProvider, _) {
            final gridResponse = gridProvider.gridResponse;
            if (gridResponse == null) return const SizedBox.shrink();

            final allPhaseCodes = [
              'preEnlistment',
              'training',
              'private',
              'privateFirstClass',
              'corporal',
              'sergeant',
            ];

            final allPhases =
                allPhaseCodes.map((phaseCode) {
                  return gridResponse.phases.firstWhere(
                    (p) => p.phase == phaseCode,
                    orElse:
                        () => Phase(
                          phase: phaseCode,
                          labelKey: 'phase.$phaseCode',
                          slotCount: 0,
                          cells: const [],
                        ),
                  );
                }).toList();

            final militaryInfo = userProvider.currentUser?.militaryInfo;
            final userStatus = militaryInfo?.status;
            final currentRank = militaryInfo?.currentRank;

            final defaultPhase = gridProvider.determineDefaultPhase(
              allPhases: allPhases,
              userStatus: userStatus,
              currentRank: currentRank,
            );

            if (gridProvider.selectedPhase == null && defaultPhase != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                gridProvider.selectPhase(defaultPhase);
              });
            }

            final currentPhase =
                gridProvider.selectedPhase ?? defaultPhase ?? allPhases.first;
            final phaseLabel =
                MilitaryGridMessages.getPhaseLabel(currentPhase.labelKey) ??
                currentPhase.phase;

            return Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 6),
              child: GestureDetector(
                onTap: onPhasePickerTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        phaseLabel,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
