import '../models/game_state.dart';
import '../models/log_entry.dart';
import '../models/night_action.dart';
import '../models/player.dart';
import '../models/role.dart';
import 'undo_stack.dart';

/// 決鬥的結果。
enum DuelOutcome {
  /// 對手是狼人 —— 對手死亡。
  wolfDied('決鬥到狼'),

  /// 對手是好人 —— 騎士自刎。
  knightDied('決鬥到好人');

  const DuelOutcome(this.labelZh);

  final String labelZh;
}

/// 騎士決鬥。
///
/// 純 Dart。時機、能選誰、誰死、白天要不要就此結束 —— 全是規則。
///
/// 規則（CLAUDE.md「騎士決鬥的時機」，細節由擔當 2026-09-19 補齊）：
///
/// | 項目 | 規則 | 旗標 |
/// |---|---|---|
/// | 時機 | 警長競選結束後、放逐投票開始前（白天的發言階段） | — |
/// | 對手是狼人 | 對手死亡，**立即進入黑夜**，跳過當天投票 | `knightDuelEndsDay` |
/// | 對手是好人 | **騎士自己出局**，白天照常走到投票 | — |
/// | 決鬥次數 | **整局只有一次**，決鬥到狼活下來也不能再發動 | — |
/// | 對手是槍牌 | **不能開槍** —— 決鬥是騎士的裁決，對手沒有反擊機會 | — |
/// | 對手是狼美人 | 被魅惑者**不殉情** —— 騎士唯一能救下殉情者的時機 | `knightDuelBlocksCharmSuicide` |
///
/// 死因一律是 [DeathCause.knightDuel]。
class KnightDuel {
  KnightDuel({required this.state}) : knightSeat = aliveKnightSeat(state)! {
    assert(!state.knightDuelUsed, '整局只能決鬥一次');
  }

  final GameState state;

  /// 翻牌的騎士。
  final int knightSeat;

  final UndoStack undoStack = UndoStack();

  DuelOutcome? outcome;

  /// 決鬥的對象。
  int? opponentSeat;

  /// 這場決鬥造成的死亡，依發生順序。
  final List<Death> deaths = [];

  /// 給法官看的說明，宣布時照著念。
  final List<String> notes = [];

  bool get finished => outcome != null;

  /// 場上還活著的騎士；沒有就是 null。
  ///
  /// 板子驗證保證騎士至多一位，所以取第一個就好。
  static int? aliveKnightSeat(GameState state) {
    for (final p in state.players) {
      if (p.alive && p.role?.id == Roles.knight.id) return p.seat;
    }
    return null;
  }

  /// 現在能不能決鬥。
  ///
  /// 時機（發言階段）由呼叫端負責 —— 這裡只管騎士還在不在、技能用掉了沒。
  static bool isAvailable(GameState state) =>
      !state.knightDuelUsed && aliveKnightSeat(state) != null;

  /// 可以指定的對手：除了騎士自己以外的存活玩家。
  Set<int> get opponents =>
      state.alivePlayers.map((p) => p.seat).toSet()..remove(knightSeat);

  /// 白天是否就此結束（決鬥到狼，且本局採「決鬥出狼立即進夜」）。
  ///
  /// 走的是和狼人自爆相同的路徑：跳過當天投票直接進黑夜。
  bool get endsDay =>
      outcome == DuelOutcome.wolfDied && state.preset.rules.knightDuelEndsDay;

  /// 騎士翻牌，與 [opponent] 決鬥。
  void duel(int opponent) {
    if (finished) return;
    if (!opponents.contains(opponent)) return;

    undoStack.push(state, '騎士決鬥', cursor: _cursor);

    state.knightDuelUsed = true;
    opponentSeat = opponent;

    final isWolf = state.playerAt(opponent).role?.camp == Camp.wolf;
    if (isWolf) {
      _kill(opponent);
      _note('騎士（$knightSeat 號）決鬥 $opponent 號 —— 是狼人，$opponent 號出局');
      _resolveCharmSuicide(opponent);
      outcome = DuelOutcome.wolfDied;
      if (endsDay) _note('決鬥出狼，白天就此結束，直接進入黑夜');
    } else {
      _kill(knightSeat);
      _note('騎士（$knightSeat 號）決鬥 $opponent 號 —— 是好人，騎士自刎出局');
      outcome = DuelOutcome.knightDied;
      _note('白天照常繼續，走到放逐投票');
    }
  }

  /// 決鬥掉的若是狼美人，依旗標決定殉情發不發動。
  ///
  /// `knightDuelBlocksCharmSuicide` 為 true 時不殉情 —— 這是騎士唯一能救下
  /// 殉情者的時機，夜晚結算碰不到這條。
  void _resolveCharmSuicide(int seat) {
    if (state.playerAt(seat).role?.id != Roles.wolfBeauty.id) return;
    final charmed = state.charmedSeat;
    if (charmed == null) return;

    if (state.preset.rules.knightDuelBlocksCharmSuicide) {
      _note('狼美人被決鬥致死，$charmed 號不殉情');
      return;
    }
    if (!state.playerAt(charmed).alive) {
      _note('$charmed 號被魅惑，但已經出局了');
      return;
    }
    state.playerAt(charmed).alive = false;
    state.playerAt(charmed).nightFacts.add(FactTag.shot);
    deaths.add(Death(seat: charmed, cause: DeathCause.loveSuicide));
    _note('狼美人出局，$charmed 號殉情');
  }

  void _kill(int seat) {
    state.playerAt(seat).nightFacts.add(FactTag.shot);
    deaths.add(Death(seat: seat, cause: DeathCause.knightDuel));

    // 白貓翻牌但不當場離場 —— 決鬥掉的也一樣走延後那條路。
    if (state.deferWhiteCatDeath(seat, DeathCause.knightDuel)) {
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
      kind: LogKind.duel,
      text: text,
    );
  }

  // ---- 撤銷 ----

  bool get canUndo => undoStack.canUndo;

  String? get undoLabel => undoStack.topLabel;

  _DuelCursor get _cursor => _DuelCursor(
        outcome: outcome,
        opponentSeat: opponentSeat,
        deaths: [...deaths],
        notes: [...notes],
      );

  bool undo() {
    final snap = undoStack.undo();
    if (snap == null) return false;

    state.restoreFrom(snap.state);
    final c = snap.cursor! as _DuelCursor;
    outcome = c.outcome;
    opponentSeat = c.opponentSeat;
    deaths
      ..clear()
      ..addAll(c.deaths);
    notes
      ..clear()
      ..addAll(c.notes);
    return true;
  }
}

class _DuelCursor {
  const _DuelCursor({
    required this.outcome,
    required this.opponentSeat,
    required this.deaths,
    required this.notes,
  });

  final DuelOutcome? outcome;
  final int? opponentSeat;
  final List<Death> deaths;
  final List<String> notes;
}
