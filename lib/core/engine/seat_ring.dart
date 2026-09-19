import '../models/game_state.dart';

/// 環狀座次走訪。
///
/// 座次是**環狀**的：12 號的下一位是 1 號。走訪時要跳過死亡玩家並繞回。
///
/// **方向以座號表示**，不用「左／右」：
/// - 順時鐘 = 座號**遞增**（5 → 6 → 7…）
/// - 逆時鐘 = 座號**遞減**（5 → 4 → 3…）
///
/// 桌上說的「警左／警右」對應哪個方向，各家習慣不同 —— 所以 App 不自己定義，
/// 畫面直接把實際的號碼順序列出來，法官照警長講的挑。
abstract final class SeatRing {
  /// 從 [from] 出發、依 [clockwise] 方向走一圈，回傳**經過的所有座次**。
  ///
  /// 不含 [from] 本身，最後一個是繞回來的前一位。死人也含在內 ——
  /// 要只取存活的請用 [aliveFrom]。
  static List<int> walkFrom(
    GameState state, {
    required int from,
    required bool clockwise,
  }) {
    final n = state.players.length;
    final seats = <int>[];
    for (var step = 1; step < n; step++) {
      final offset = clockwise ? step : -step;
      seats.add(((from - 1 + offset) % n + n) % n + 1);
    }
    return seats;
  }

  /// 從 [from] 出發走一圈，只回傳**存活**的座次（不含 [from]）。
  static List<int> aliveFrom(
    GameState state, {
    required int from,
    required bool clockwise,
  }) =>
      walkFrom(state, from: from, clockwise: clockwise)
          .where((seat) => state.playerAt(seat).alive)
          .toList();
}
