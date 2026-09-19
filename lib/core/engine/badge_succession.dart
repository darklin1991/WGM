import '../models/game_state.dart';
import '../models/log_entry.dart';
import 'undo_stack.dart';

/// 警徽的去向。
enum BadgeOutcome {
  /// 還沒決定。
  pending,

  /// 移交給新警長。
  passed,

  /// 撕毀，本局之後無警長。
  destroyed,
}

/// 警徽流：警長出局後的移交。
///
/// 純 Dart。什麼時候要走、可以交給誰、交完誰是警長 —— 全是規則。
///
/// 擔當指定的賽制（2026-09-19）：
///
/// | 項目 | 規則 |
/// |---|---|
/// | 移交對象 | **任一存活玩家**，不必事先宣告警徽流名單 |
/// | 撕警徽 | **可以**，此後本局無警長（票權加權與警左警右都跟著消失） |
/// | 警長被毒死 | **照常可以移交** —— 毒藥只擋獵人開槍，不擋警徽 |
///
/// 沒有「移交順序名單」這種東西，所以也沒有對應的宣告步驟；警長口頭指定
/// 誰接任，法官當場點下去就好。
class BadgeSuccession {
  BadgeSuccession({required this.state}) : formerSheriff = state.sheriffSeat! {
    assert(
      !state.playerAt(formerSheriff).alive,
      '警長還活著就不該走警徽流',
    );
  }

  final GameState state;

  /// 交出警徽的那位 —— 已經出局的警長。移交之後 `state.sheriffSeat` 就改了，
  /// 所以要在建構時先記下來。
  final int formerSheriff;

  final UndoStack undoStack = UndoStack();

  BadgeOutcome outcome = BadgeOutcome.pending;

  /// 接任的座次；撕毀或還沒決定時為 null。
  int? newSheriff;

  /// 給法官看的說明，宣布時照著念。
  final List<String> notes = [];

  /// 這一刻該不該走警徽流。
  ///
  /// 條件只有一條：**有警長，而且那位已經出局**。不看是這一輪死的還是更早死的
  /// —— 第一天的競選排在公布死訊之前，昨晚死掉的人照樣可以上警當選，
  /// 那種情況一公布死訊就要馬上移交。
  static bool isDue(GameState state) {
    final seat = state.sheriffSeat;
    return seat != null && !state.playerAt(seat).alive;
  }

  /// 可以接任的座次：所有還活著的人。
  Set<int> get candidates => state.alivePlayers.map((p) => p.seat).toSet();

  /// 全場只剩死人 —— 只能撕。實務上這時勝負早就分完了，純粹防呆。
  bool get mustDestroy => candidates.isEmpty;

  bool get finished => outcome != BadgeOutcome.pending;

  /// 移交給 [seat]。
  void passTo(int seat) {
    if (finished) return;
    if (!candidates.contains(seat)) return;

    undoStack.push(state, '移交警徽', cursor: _cursor);

    state.sheriffSeat = seat;
    newSheriff = seat;
    outcome = BadgeOutcome.passed;
    _note('$formerSheriff 號的警徽移交給 $seat 號，$seat 號成為新警長');
  }

  /// 撕毀警徽。此後本局沒有警長 —— 票權不再加權，發言順序改走隨機。
  void destroy() {
    if (finished) return;

    undoStack.push(state, '撕毀警徽', cursor: _cursor);

    state.sheriffSeat = null;
    newSheriff = null;
    outcome = BadgeOutcome.destroyed;
    _note('$formerSheriff 號撕毀警徽，本局之後沒有警長');
  }

  /// 記一句宣布稿，同時寫進復盤日誌 —— 兩件事綁在一起做才不會漏。
  void _note(String text) {
    notes.add(text);
    state.log.add(
      round: state.dayNumber,
      isNight: false,
      kind: LogKind.badge,
      text: text,
    );
  }

  // ---- 撤銷 ----

  bool get canUndo => undoStack.canUndo;

  String? get undoLabel => undoStack.topLabel;

  _BadgeCursor get _cursor =>
      _BadgeCursor(outcome: outcome, newSheriff: newSheriff, notes: [...notes]);

  bool undo() {
    final snap = undoStack.undo();
    if (snap == null) return false;

    state.restoreFrom(snap.state);
    final c = snap.cursor! as _BadgeCursor;
    outcome = c.outcome;
    newSheriff = c.newSheriff;
    notes
      ..clear()
      ..addAll(c.notes);
    return true;
  }
}

class _BadgeCursor {
  const _BadgeCursor({
    required this.outcome,
    required this.newSheriff,
    required this.notes,
  });

  final BadgeOutcome outcome;
  final int? newSheriff;
  final List<String> notes;
}
