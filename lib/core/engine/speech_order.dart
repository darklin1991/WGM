import 'dart:math';

import '../models/game_state.dart';
import 'seat_ring.dart';

/// 發言順序用什麼當起點。
enum SpeechOrderBasis {
  /// **單死**：從死者算起（桌上說的「死左／死右」）。方向由警長選。
  deceased,

  /// **其餘**（平安夜、或雙死以上）：從警長算起（「警左／警右」）。方向由警長選。
  sheriff,

  /// **沒有警長**：起點與方向都由上帝隨機決定。
  random,
}

/// 一份定好的發言順序。
class SpeechOrderPlan {
  const SpeechOrderPlan({
    required this.basis,
    required this.referenceSeat,
    required this.clockwise,
    required this.order,
  });

  final SpeechOrderBasis basis;

  /// 起點的參考座次：死者、警長，或隨機抽到的那位。
  final int referenceSeat;

  /// true = 順時鐘（座號遞增）；false = 逆時鐘（座號遞減）。
  final bool clockwise;

  /// 實際發言順序（只含存活玩家）。
  final List<int> order;

  /// 參考座次本人是否也要發言 —— 警長要（排最後），死者不用。
  bool get referenceSpeaks => order.isNotEmpty && order.last == referenceSeat;
}

/// 白天發言順序。
///
/// 規則（擔當指定）：
///
/// | 情況 | 起點 | 方向 |
/// |---|---|---|
/// | 單死 | 死者 | 警長選 |
/// | 平安夜、雙死以上 | 警長 | 警長選 |
/// | **沒有警長** | 隨機抽存活玩家 | 隨機 |
///
/// 沒有警長時整組都隨機 —— 沒人有權決定，就由上帝抽。
abstract final class SpeechOrder {
  /// 這一天該用哪種方式決定起點。
  ///
  /// [deceased] 是昨晚公布的死者。沒有警長一律走 [SpeechOrderBasis.random]，
  /// 就算只死一個也一樣 —— 死左死右的方向本來就該由警長決定。
  static SpeechOrderBasis basisFor(GameState state, List<int> deceased) {
    if (state.sheriffSeat == null) return SpeechOrderBasis.random;
    return deceased.length == 1
        ? SpeechOrderBasis.deceased
        : SpeechOrderBasis.sheriff;
  }

  /// 依起點與方向算出發言順序。
  ///
  /// 從 [referenceSeat] 往 [clockwise] 方向的**第一位存活玩家**開始，繞一圈。
  /// [referenceSeat] 本人若還活著（警長），會排在**最後**發言；
  /// 死者則不在名單裡。
  static List<int> resolve(
    GameState state, {
    required int referenceSeat,
    required bool clockwise,
  }) {
    final order =
        SeatRing.aliveFrom(state, from: referenceSeat, clockwise: clockwise);
    if (state.playerAt(referenceSeat).alive) order.add(referenceSeat);
    return order;
  }

  /// 組出一份順序。[referenceSeat] 與 [clockwise] 由呼叫端依 [basisFor] 決定。
  static SpeechOrderPlan plan(
    GameState state, {
    required SpeechOrderBasis basis,
    required int referenceSeat,
    required bool clockwise,
  }) =>
      SpeechOrderPlan(
        basis: basis,
        referenceSeat: referenceSeat,
        clockwise: clockwise,
        order: resolve(
          state,
          referenceSeat: referenceSeat,
          clockwise: clockwise,
        ),
      );

  /// 沒有警長時，由上帝抽起點與方向。
  ///
  /// [random] 可注入以便測試；正式使用傳 null 即可。
  static SpeechOrderPlan randomPlan(GameState state, {Random? random}) {
    final rng = random ?? Random();
    final alive = state.alivePlayers.map((p) => p.seat).toList()..sort();
    if (alive.isEmpty) {
      return const SpeechOrderPlan(
        basis: SpeechOrderBasis.random,
        referenceSeat: 0,
        clockwise: true,
        order: [],
      );
    }

    final start = alive[rng.nextInt(alive.length)];
    final clockwise = rng.nextBool();

    // 抽到的那位自己先發言，所以從他的前一位起算，讓他排在最前面。
    final order = <int>[
      start,
      ...SeatRing.aliveFrom(state, from: start, clockwise: clockwise),
    ];

    return SpeechOrderPlan(
      basis: SpeechOrderBasis.random,
      referenceSeat: start,
      clockwise: clockwise,
      order: order,
    );
  }
}
