import '../models/game_state.dart';
import '../rules/rule_flags.dart';

/// 勝負結果。
enum GameResult {
  /// 還沒分出勝負。
  ongoing('進行中'),

  /// 好人陣營獲勝（狼人全滅）。
  goodWin('好人勝'),

  /// 狼人陣營獲勝。
  wolvesWin('狼人勝');

  const GameResult(this.labelZh);

  final String labelZh;

  bool get isOver => this != GameResult.ongoing;
}

/// 一次勝負檢查的結果。
class WinCheck {
  const WinCheck({required this.result, required this.reason});

  final GameResult result;

  /// 為什麼是這個結果，例如「神職全滅（屠邊）」。現場有爭議時要講得出依據。
  final String reason;

  bool get isOver => result.isOver;

  static const ongoing = WinCheck(result: GameResult.ongoing, reason: '');
}

/// 勝負判定。
///
/// **每次死亡事件後都要呼叫**，不是只在白天結束時 —— 夜晚結算完、放逐完、
/// 開槍帶走人之後，都可能當場分出勝負。
///
/// 兩種賽制由板子的 `winCondition` 旗標決定：
///
/// | 旗標 | 狼人獲勝條件 |
/// |---|---|
/// | `sideElimination`（屠邊） | 神職全滅 **或** 平民全滅 |
/// | `totalElimination`（屠城） | 所有好人全滅 |
///
/// 目前內建的六個板子**都是屠邊**。
abstract final class WinChecker {
  static WinCheck check(GameState state) {
    // 狼人全滅 → 好人勝，兩種賽制都一樣。
    if (state.aliveWolfCount == 0) {
      return const WinCheck(result: GameResult.goodWin, reason: '狼人全數出局');
    }

    // 板子裡本來就沒配置的陣營不算「全滅」—— 否則開局就直接判狼勝。
    final hasGods = state.preset.godCount > 0;
    final hasVillagers = state.preset.villagerCount > 0;

    switch (state.preset.rules.winCondition) {
      case WinCondition.sideElimination:
        if (hasGods && state.aliveGodCount == 0) {
          return const WinCheck(
            result: GameResult.wolvesWin,
            reason: '神職全滅（屠邊）',
          );
        }
        if (hasVillagers && state.aliveVillagerCount == 0) {
          return const WinCheck(
            result: GameResult.wolvesWin,
            reason: '平民全滅（屠邊）',
          );
        }
      case WinCondition.totalElimination:
        if (state.aliveGodCount == 0 && state.aliveVillagerCount == 0) {
          return const WinCheck(
            result: GameResult.wolvesWin,
            reason: '好人全滅（屠城）',
          );
        }
    }

    return WinCheck.ongoing;
  }
}
