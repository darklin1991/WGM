import 'package:flutter/material.dart';

import '../../core/engine/seat_block_reason.dart';
import '../../core/models/game_state.dart';
import '../../shared/theme.dart';

/// 禁選原因的顯示文字。原因由引擎判定（[SeatBlockReason]），這裡只負責措辭 ——
/// 夜晚與白天的頁面共用這一份，同一個原因不會在不同頁面講成不同的話。
String seatBlockReasonZh(SeatBlockReason reason) => switch (reason) {
      SeatBlockReason.guardedLastNight => '昨晚已守',
      SeatBlockReason.charmedLastNight => '昨晚已魅惑',
      SeatBlockReason.wolfBeautySelfKill => '狼美人不能自刀',
      SeatBlockReason.secretAdmirerSelf => '不能暗戀自己',
      SeatBlockReason.whiteCatPending => '白貓已翻牌，離場前不能被指定',
      SeatBlockReason.mechanicSelfLearn => '不能學自己',
      SeatBlockReason.witchDualUse => '本局不可同夜雙藥',
      SeatBlockReason.convertGargoyle => '石像鬼自己人，不能轉換',
      SeatBlockReason.alreadyConverted => '另一隻已轉換他',
      SeatBlockReason.duelSelf => '騎士本人',
    };

/// 把引擎給的禁選原因整份換成顯示文字，直接餵給 [SeatPicker.disabledReason]。
Map<int, String> seatBlockReasonsZh(Map<int, SeatBlockReason> blocked) => {
      for (final e in blocked.entries) e.key: seatBlockReasonZh(e.value),
    };

/// 座次選擇格線。
///
/// 法官在昏暗環境快速點選，因此格子放大、選中狀態要一眼看得出來。
class SeatPicker extends StatelessWidget {
  const SeatPicker({
    super.key,
    required this.state,
    required this.selected,
    required this.onTap,
    this.selectableSeats,
    this.disabledReason,
    this.showRoleName = false,
  });

  final GameState state;
  final Set<int> selected;
  final ValueChanged<int> onTap;

  /// 可選座次；null 表示所有存活座次都可選。
  final Set<int>? selectableSeats;

  /// 不可選座次的原因，顯示在格子下方（例如「昨晚已守」）。
  final Map<int, String>? disabledReason;

  /// 是否顯示已登記的身分名稱。
  final bool showRoleName;

  bool _selectable(int seat) {
    if (!state.playerAt(seat).alive) return false;
    final allow = selectableSeats;
    return allow == null || allow.contains(seat);
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 92,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.95,
      ),
      itemCount: state.players.length,
      itemBuilder: (context, i) {
        final player = state.players[i];
        final seat = player.seat;
        final isSelected = selected.contains(seat);
        final canPick = _selectable(seat);
        final reason = disabledReason?[seat];
        final scheme = Theme.of(context).colorScheme;

        final color = isSelected
            ? scheme.primary
            : canPick
                ? WgmTheme.colorOf(player.role)
                : WgmTheme.deadColor;

        return InkWell(
          onTap: canPick ? () => onTap(seat) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? scheme.primary.withValues(alpha: 0.28)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? scheme.primary
                    : color.withValues(alpha: canPick ? 0.45 : 0.18),
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$seat',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: canPick || isSelected
                        ? color
                        : color.withValues(alpha: 0.5),
                  ),
                ),
                // 禁選原因優先於身分名稱 —— 法官看到格子變灰時，
                // 最需要知道的是「為什麼不能選」，身分可以事後再查。
                if (reason != null)
                  Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      color: WgmTheme.deadColor,
                    ),
                  )
                else if (showRoleName && player.role != null)
                  Text(
                    player.role!.nameZh,
                    style: TextStyle(
                      fontSize: 10,
                      color: WgmTheme.colorOf(player.role),
                    ),
                  )
                else if (!player.alive)
                  const Text(
                    '已死亡',
                    style: TextStyle(fontSize: 9, color: WgmTheme.deadColor),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
