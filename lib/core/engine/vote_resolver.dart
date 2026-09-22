import '../models/game_state.dart';
import '../models/log_entry.dart';
import '../models/night_action.dart';
import '../models/player.dart';
import '../models/role.dart';
import '../rules/rule_flags.dart';
import 'undo_stack.dart';

/// 放逐投票的階段。
enum ExileStage {
  /// 投票：按對象歸票（與警長競選同一套操作）。
  vote,

  /// 平票 PK 發言：平票者依序再講一次，逐人計時。
  ///
  /// 只是計時，不動任何狀態。
  runoffSpeech,

  /// 平票 PK 後的重投。
  runoffVote,

  /// 被放逐者是槍牌 → 選一個帶走。
  shoot,

  /// 被放逐的是河豚 → 問他要不要翻牌帶走投他的人。
  ///
  /// **主動技能**，法官要問過本人；不發動就直接結束。
  pufferfishReveal,

  /// 結束。
  done,
}

/// 放逐投票與其後的死亡連鎖。
///
/// 純 Dart。誰有票、警長加權、平票怎麼處理、放逐後誰死誰翻牌 —— 全是規則。
///
/// 死亡連鎖（擔當指定做完整版）：
/// 放逐 → 白痴翻牌不死／其餘死亡 → 狼美人殉情 → 槍牌開槍 → 開槍目標的殉情
class ExileVote {
  ExileVote({required this.state});

  final GameState state;

  final UndoStack undoStack = UndoStack();

  ExileStage stage = ExileStage.vote;

  /// 投票紀錄：投票者座次 → 投給誰。沒出現在這裡的就是棄票。
  final Map<int, int> votes = {};

  /// 平票 PK 的名單。
  final Set<int> runoffTargets = {};

  /// 目前正在歸票的對象 —— 法官喊「投 N 號的請舉手」的那個 N。
  int? focusedTarget;

  /// 被放逐的座次；null 表示無人出局。
  int? exiledSeat;

  /// 被放逐的是白痴，翻牌不死。
  bool idiotRevealed = false;

  /// 可以開槍的座次（獵人或狼王被放逐）。
  int? shooterSeat;

  /// 白天產生的所有死亡，依發生順序。
  final List<Death> deaths = [];

  /// 給法官看的說明，例如「3 號是白痴，翻牌不死」。
  final List<String> notes = [];

  bool get finished => stage == ExileStage.done;

  bool get isRunoff => stage == ExileStage.runoffVote;

  // ---- 名單 ----

  Set<int> get _aliveSeats => state.alivePlayers.map((p) => p.seat).toSet();

  /// 有投票權的人。
  ///
  /// 白痴翻牌後失去投票權（`canVote`）。PK 輪時**平票者本人不投**
  /// （擔當指定，與警長競選的「候選不投」一致）。
  Set<int> get eligibleVoters {
    final base = state.alivePlayers
        .where((p) => p.canVote)
        .map((p) => p.seat)
        .toSet();
    return isRunoff ? base.difference(runoffTargets) : base;
  }

  /// 可以被投的人 —— PK 輪只剩平票者。
  Set<int> get votableTargets => isRunoff ? runoffTargets : _aliveSeats;

  /// PK 發言的順序：平票者依**座號遞增**排。
  ///
  /// 跟警上發言同樣的理由 —— 桌上實際從誰先講各家不同，計時頁點號碼就能跳。
  List<int> get runoffSpeechOrder => runoffTargets.toList()..sort();

  /// 還沒投票的人。
  Set<int> get notYetVoted => eligibleVoters.difference(votes.keys.toSet());

  /// 目前票數。警長票依 `sheriffVoteWeight` 加權，所以是小數。
  Map<int, double> get tally {
    final counts = <int, double>{};
    for (final entry in votes.entries) {
      final weight = entry.key == state.sheriffSeat
          ? state.preset.rules.sheriffVoteWeight
          : 1.0;
      counts[entry.value] = (counts[entry.value] ?? 0) + weight;
    }
    return counts;
  }

  // ---- 操作 ----

  void focusTarget(int seat) {
    if (!votableTargets.contains(seat)) return;
    focusedTarget = focusedTarget == seat ? null : seat;
  }

  /// [seat] 現在能不能被圈進目前對象的票裡。**一人一票**。
  bool canAssignVote(int seat) {
    if (stage != ExileStage.vote && stage != ExileStage.runoffVote) {
      return false;
    }
    if (focusedTarget == null) return false;
    if (!eligibleVoters.contains(seat)) return false;
    final existing = votes[seat];
    return existing == null || existing == focusedTarget;
  }

  void toggleVote(int seat) {
    final target = focusedTarget;
    if (target == null) return;
    if (votes[seat] == target) {
      votes.remove(seat);
      return;
    }
    if (!canAssignVote(seat)) return;
    votes[seat] = target;
  }

  /// 開槍帶走 [seat]。只在 [ExileStage.shoot] 有效；[seat] 為 null 表示不開。
  void shoot(int? seat) {
    if (stage != ExileStage.shoot) return;
    final shooter = shooterSeat;
    if (shooter == null) return;

    undoStack.push(state, '開槍', cursor: _cursor);

    if (seat != null && state.playerAt(seat).alive) {
      _kill(seat, DeathCause.hunterShot);
      _note('$shooter 號開槍帶走 $seat 號');
      _resolveCharmSuicide(seat);
    } else {
      _note('$shooter 號放棄開槍');
    }
    _finishStage();
  }

  /// 前進：投票階段會算票並跑完放逐連鎖。
  void next() {
    switch (stage) {
      case ExileStage.vote:
      case ExileStage.runoffVote:
        undoStack.push(state, isRunoff ? 'PK 重投' : '投票', cursor: _cursor);
        _resolveVote();

      case ExileStage.runoffSpeech:
        undoStack.push(state, 'PK 發言', cursor: _cursor);
        stage = ExileStage.runoffVote;
      case ExileStage.shoot:
        // 用 shoot() 結束，next() 視為放棄開槍。
        shoot(null);
      case ExileStage.pufferfishReveal:
        // 同上 —— next() 視為不發動。要帶走人得明確按翻牌。
        revealPufferfish(activate: false);
      case ExileStage.done:
        break;
    }
  }

  /// 記一句宣布稿，同時寫進復盤日誌。
  ///
  /// 兩件事綁在一起做 —— 分開寫遲早會有一邊漏掉。
  void _note(String text) {
    notes.add(text);
    state.log.add(
      round: state.dayNumber,
      isNight: false,
      kind: LogKind.vote,
      text: text,
    );
  }

  /// 把票型寫進日誌。復盤最常翻的就是這個。
  void _logTally(Map<int, double> counts) {
    if (counts.isEmpty) return;
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final detail = entries.map((e) {
      final voters = votes.entries
          .where((v) => v.value == e.key)
          .map((v) => v.key)
          .toList()
        ..sort();
      return '${e.key} 號 ${_fmt(e.value)} 票（${voters.join('、')}）';
    }).join('；');

    final abstained = notYetVoted.toList()..sort();
    state.log.add(
      round: state.dayNumber,
      isNight: false,
      kind: LogKind.vote,
      text: '${isRunoff ? "PK 重投" : "放逐投票"}票型：$detail'
          '${abstained.isEmpty ? "" : "；棄票 ${abstained.join('、')}"}',
    );
  }

  /// 1.5 顯示成 1.5，2.0 顯示成 2。
  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _resolveVote() {
    final counts = tally;
    _logTally(counts);
    final highest = counts.values.isEmpty
        ? 0.0
        : counts.values.reduce((a, b) => a > b ? a : b);

    if (highest == 0) {
      _note('全員棄票，無人出局');
      _finishStage();
      return;
    }

    final top = counts.entries
        .where((e) => e.value == highest)
        .map((e) => e.key)
        .toSet();

    if (top.length == 1) {
      _exile(top.first);
      return;
    }

    // 平票。
    final tie = top.toList()..sort();
    switch (state.preset.rules.tieBreak) {
      case TieBreak.none:
        _note('${tie.join('、')} 號平票，依本局規則直接無人出局');
        _finishStage();
      case TieBreak.pkThenNone:
      case TieBreak.pkThenRevote:
        if (isRunoff) {
          _note('PK 後仍然平票，無人出局');
          _finishStage();
          return;
        }
        runoffTargets
          ..clear()
          ..addAll(tie);
        votes.clear();
        focusedTarget = null;
        // 平票者要先各講一輪，講完才重投。
        stage = ExileStage.runoffSpeech;
        _note('${tie.join('、')} 號平票，先 PK 發言再重投');
    }
  }

  void _exile(int seat) {
    exiledSeat = seat;
    final role = state.playerAt(seat).role;

    // 白痴被放逐：翻牌不死，失去投票權，留在場上。
    if (role?.id == Roles.idiot.id) {
      idiotRevealed = true;
      state.playerAt(seat).canVote = false;
      state.playerAt(seat).infoTags.add(InfoTag.silenced);
      _note('$seat 號是白痴，翻牌不死，失去投票權但留在場上');
      _finishStage();
      return;
    }

    _kill(seat, DeathCause.exile);
    _note('$seat 號被放逐出局');

    _resolveCharmSuicide(seat);

    // 槍牌被放逐 → 可以開槍。獵人與狼王被推出去都能開。
    if (role != null && Roles.gunRoleIds.contains(role.id)) {
      shooterSeat = seat;
      _note('${role.nameZh}（$seat 號）被放逐，可以開槍');
      stage = ExileStage.shoot;
      return;
    }

    // 河豚被放逐 → 問他要不要翻牌帶走投他的人。
    // 只有河豚**自己被放逐**時才有這一步（擔當 2026-09-23 指定）。
    if (role?.id == Roles.pufferfish.id) {
      if (pufferfishVoters.isEmpty) {
        _note('河豚（$seat 號）被放逐，但沒有人投他，技能無從發動');
      } else {
        _note('河豚（$seat 號）被放逐，可以翻牌帶走投他的人');
        stage = ExileStage.pufferfishReveal;
        return;
      }
    }

    _finishStage();
  }

  /// 這一輪投給河豚的人 —— 也就是翻牌會帶走的名單。
  ///
  /// 取的是**被放逐的那一次**投票紀錄：平票 PK 時 [votes] 已經在重投前清空，
  /// 所以這裡拿到的正是決定放逐的那一輪，符合「投給河豚的玩家」。
  ///
  /// 河豚自己不在名單裡（投自己也不算），死者也排除掉 —— 連鎖前面的
  /// 殉情可能已經帶走某些人。
  Set<int> get pufferfishVoters {
    final seat = exiledSeat;
    if (seat == null) return const {};
    if (state.playerAt(seat).role?.id != Roles.pufferfish.id) return const {};
    return votes.entries
        .where((e) => e.value == seat && e.key != seat)
        .map((e) => e.key)
        .where((voter) => state.playerAt(voter).alive)
        .toSet();
  }

  /// 河豚翻牌，帶走所有投他的人。
  ///
  /// 被帶走的人**不能開槍**（擔當 2026-09-23 指定）—— 死因是
  /// [DeathCause.pufferfishRevenge]，不在「可以開槍的死法」裡，
  /// 所以這裡不會進入 [ExileStage.shoot]。
  void revealPufferfish({required bool activate}) {
    if (stage != ExileStage.pufferfishReveal) return;

    undoStack.push(state, '河豚翻牌', cursor: _cursor);

    if (!activate) {
      _note('河豚放棄翻牌，沒有人被帶走');
      _finishStage();
      return;
    }

    final taken = pufferfishVoters.toList()..sort();
    for (final voter in taken) {
      _kill(voter, DeathCause.pufferfishRevenge);
      // 帶走的若是狼美人，殉情照樣成立 —— 只有騎士決鬥有免疫的例外。
      _resolveCharmSuicide(voter);
    }
    _note('河豚翻牌，帶走投他的 ${taken.join("、")} 號');
    _finishStage();
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
    state.playerAt(seat).nightFacts.add(
          cause == DeathCause.exile ? FactTag.exiled : FactTag.shot,
        );
    deaths.add(Death(seat: seat, cause: cause));

    // 白貓翻牌但不當場離場 —— 白天被判死的話要到**隔天**的放逐投票
    // 結束才真正出局，這段期間他照樣有票、照樣算活著。
    if (state.deferWhiteCatDeath(seat, cause)) {
      _note('白貓（$seat 號）翻牌，但要到隔天的放逐投票結束才真正出局');
      return;
    }
    state.playerAt(seat).alive = false;
  }

  /// 放逐投票結束時結清白貓延後的死亡。
  ///
  /// 所有走到 [ExileStage.done] 的路徑都要經過這裡 —— 漏掉一條，
  /// 白貓就會永遠不死。
  void _finishStage() {
    stage = ExileStage.done;

    if (!state.whiteCatDeathIsDue) return;
    final seat = state.seatOfRole(Roles.whiteCat.id);
    final cause = state.whiteCatPendingCause;
    if (seat == null || cause == null) return;
    if (!state.playerAt(seat).alive) return;

    state.playerAt(seat).alive = false;
    deaths.add(Death(seat: seat, cause: cause));
    _note('白貓（$seat 號）延後的離場生效，正式出局（死因：${cause.labelZh}）');
  }

  // ---- 撤銷 ----

  bool get canUndo => undoStack.canUndo;

  String? get undoLabel => undoStack.topLabel;

  _ExileCursor get _cursor => _ExileCursor(
        stage: stage,
        votes: {...votes},
        runoffTargets: {...runoffTargets},
        focusedTarget: focusedTarget,
        exiledSeat: exiledSeat,
        idiotRevealed: idiotRevealed,
        shooterSeat: shooterSeat,
        deaths: [...deaths],
        notes: [...notes],
      );

  bool undo() {
    final snap = undoStack.undo();
    if (snap == null) return false;

    state.restoreFrom(snap.state);
    final c = snap.cursor! as _ExileCursor;
    stage = c.stage;
    votes
      ..clear()
      ..addAll(c.votes);
    runoffTargets
      ..clear()
      ..addAll(c.runoffTargets);
    focusedTarget = c.focusedTarget;
    exiledSeat = c.exiledSeat;
    idiotRevealed = c.idiotRevealed;
    shooterSeat = c.shooterSeat;
    deaths
      ..clear()
      ..addAll(c.deaths);
    notes
      ..clear()
      ..addAll(c.notes);
    return true;
  }
}

/// 放逐流程走到哪裡 —— 撤銷時要連這個一起還原。
class _ExileCursor {
  const _ExileCursor({
    required this.stage,
    required this.votes,
    required this.runoffTargets,
    required this.focusedTarget,
    required this.exiledSeat,
    required this.idiotRevealed,
    required this.shooterSeat,
    required this.deaths,
    required this.notes,
  });

  final ExileStage stage;
  final Map<int, int> votes;
  final Set<int> runoffTargets;
  final int? focusedTarget;
  final int? exiledSeat;
  final bool idiotRevealed;
  final int? shooterSeat;
  final List<Death> deaths;
  final List<String> notes;
}
