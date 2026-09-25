import '../models/game_state.dart';
import '../models/log_entry.dart';
import '../models/night_action.dart';
import '../models/player.dart';
import '../models/role.dart';
import 'seat_block_reason.dart';
import 'undo_stack.dart';

/// 夜裡出局的槍牌，天亮後開槍。
///
/// 純 Dart。誰能開、能打誰、打完誰死 —— 全是規則。誰有開槍資格由夜晚結算
/// 決定（`NightOutcome.shooterSeats`），這裡只負責把開槍目標記下來。
///
/// 擔當 2026-09-24 指定的位置：**公布死訊之後、警徽流之前**。
/// 排在警徽流前面是因為獵人可能帶走的就是警長 —— 得先開完槍，
/// 才知道警徽要不要移交。第一天有警長競選時，完整順序是：
///
/// 競選 → 公布死訊 → 開槍 → 警徽流 → 發言順序
///
/// 連鎖與放逐時的開槍相同（見 `ExileVote.shoot`）：開槍目標死亡 →
/// 目標若是狼美人，被魅惑者殉情。被帶走的人**不會再開槍** ——
/// 死因是 [DeathCause.hunterShot]，不是刀也不是推。
class NightDeathShot {
  NightDeathShot({required this.state, required List<int> shooters})
      : shooters = List.unmodifiable(shooters);

  final GameState state;

  /// 依序要開槍的座次。同一夜可能不只一位（例如獵人與狼王都被刀）。
  final List<int> shooters;

  final UndoStack undoStack = UndoStack();

  int _index = 0;

  /// 被帶走的人（含殉情與延後離場的白貓）。發言順序的「單死／雙死」用。
  final List<Death> deaths = [];

  /// 可以給遺言的人 —— 真的出局的。延後離場的白貓還在場上、今天照常發言，不算。
  List<int> get lastWordsSeats => [
        for (final d in deaths)
          if (!state.playerAt(d.seat).alive) d.seat,
      ];

  /// 給法官看的說明，宣布時照著念。
  final List<String> notes = [];

  bool get finished => _index >= shooters.length;

  /// 輪到開槍的座次；都開完了是 null。
  int? get currentShooter => finished ? null : shooters[_index];

  /// 不能選的座次與原因（見 [dayBlockedSeats]）。
  Map<int, SeatBlockReason> get blockedSeats => dayBlockedSeats(state);

  /// 開槍可以選的對象：存活、而且不在 [blockedSeats] 裡。
  Set<int> get targets {
    final blocked = blockedSeats;
    return {
      for (final p in state.alivePlayers)
        if (!blocked.containsKey(p.seat)) p.seat,
    };
  }

  /// 目前的開槍者開槍帶走 [seat]；[seat] 為 null 表示放棄開槍。
  void shoot(int? seat) {
    final shooter = currentShooter;
    if (shooter == null) return;
    if (seat != null && !targets.contains(seat)) return;

    undoStack.push(state, '$shooter 號開槍', cursor: _cursor);

    if (seat == null) {
      _note('$shooter 號放棄開槍');
    } else {
      // 宣布稿不寫開槍者的身分 —— 機械狼學到獵人時，寫出來就露餡了。
      _note('$shooter 號開槍帶走 $seat 號');
      _kill(seat, DeathCause.hunterShot);
      _resolveCharmSuicide(seat);
    }
    _index++;
  }

  /// [seat] 若是狼美人，處理殉情。
  void _resolveCharmSuicide(int seat) {
    if (state.playerAt(seat).role?.id != Roles.wolfBeauty.id) return;
    final charmed = state.charmedSeat;
    if (charmed == null) return;
    if (!state.playerAt(charmed).alive) {
      _note('$charmed 號被魅惑，但已經出局了');
      return;
    }
    _kill(charmed, DeathCause.loveSuicide);
    _note('狼美人（$seat 號）出局，$charmed 號殉情');
  }

  void _kill(int seat, DeathCause cause) {
    state.playerAt(seat).nightFacts.add(FactTag.shot);
    deaths.add(Death(seat: seat, cause: cause));

    // 白貓翻牌但不當場離場 —— 這時已經是白天，要到**隔天**的放逐投票
    // 結束才真正出局。
    if (state.deferWhiteCatDeath(seat, cause)) {
      _note('白貓（$seat 號）翻牌，但要到隔天的放逐投票結束才真正出局');
      return;
    }
    state.playerAt(seat).alive = false;
  }

  /// 記一句宣布稿，同時寫進復盤日誌 —— 兩件事綁在一起做才不會漏。
  void _note(String text) {
    notes.add(text);
    state.log.add(
      round: state.dayNumber,
      isNight: false,
      kind: LogKind.death,
      text: text,
    );
  }

  // ---- 撤銷 ----

  bool get canUndo => undoStack.canUndo;

  String? get undoLabel => undoStack.topLabel;

  _ShotCursor get _cursor =>
      _ShotCursor(index: _index, deaths: [...deaths], notes: [...notes]);

  bool undo() {
    final snap = undoStack.undo();
    if (snap == null) return false;

    state.restoreFrom(snap.state);
    final c = snap.cursor! as _ShotCursor;
    _index = c.index;
    deaths
      ..clear()
      ..addAll(c.deaths);
    notes
      ..clear()
      ..addAll(c.notes);
    return true;
  }
}

class _ShotCursor {
  const _ShotCursor({
    required this.index,
    required this.deaths,
    required this.notes,
  });

  final int index;
  final List<Death> deaths;
  final List<String> notes;
}
