import '../models/game_state.dart';
import 'undo_stack.dart';

/// 警長競選的階段。
enum ElectionStage {
  /// 上警：誰要參選。
  nominate,

  /// 退水：警上發言之後，候選人可以退出。
  ///
  /// 發言本身由法官口頭主持，App 不計時也不排序 —— 這一階段只收退水名單。
  withdraw,

  /// 投票：**按候選人歸票**。
  ///
  /// 法官喊「投 N 號的請舉手」，先選定候選人再圈選舉手的人 ——
  /// 這是現場真正的做法，比逐一問每個人投給誰快得多。
  vote,

  /// 平票 PK 後的重投。
  runoffVote,

  /// 已結束：警長選出，或確定無警長。
  done,
}

/// 警長競選狀態機。
///
/// 純 Dart，不依賴 Flutter —— 誰有投票權、票怎麼算、平票怎麼處理都是**規則**，
/// 必須能用單元測試涵蓋。頁面只負責畫出來並把操作轉回來。
///
/// 第一天的競選排在**公布死訊之前** —— 昨晚死的人這時還沒被公布，
/// 照樣可以上警、可以投票。
class SheriffElection {
  SheriffElection({required this.state});

  final GameState state;

  final UndoStack undoStack = UndoStack();

  ElectionStage stage = ElectionStage.nominate;

  /// 上警的座次（**含後來退水的**）。
  final Set<int> candidates = {};

  /// 退水的座次。
  final Set<int> withdrawn = {};

  /// 投票紀錄：投票者座次 → 投給誰。沒出現在這裡的就是棄票。
  final Map<int, int> votes = {};

  /// 平票 PK 的候選人。
  final Set<int> runoffCandidates = {};

  bool get isRunoff => stage == ElectionStage.runoffVote;

  /// 目前正在歸票的候選人 —— 法官喊「投 N 號的請舉手」的那個 N。
  int? focusedCandidate;

  /// 選出的警長；null 且 [stage] 已 done 表示本局無警長。
  int? sheriffSeat;

  /// 是否已確定沒有警長。
  bool noSheriff = false;

  bool get finished => stage == ElectionStage.done;

  // ---- 名單 ----

  Set<int> get _aliveSeats => state.alivePlayers.map((p) => p.seat).toSet();

  /// 這一輪實際在競選的人。
  Set<int> get activeCandidates =>
      isRunoff ? runoffCandidates : candidates.difference(withdrawn);

  /// 有投票權的人。
  ///
  /// - 一般輪：**上警的都不投**（含退水的）—— 擔當選的賽制
  /// - PK 輪：只有 PK 名單裡的不投；第一輪落選的其他候選人**恢復投票權**。
  ///   退水的人是自己退出整場競選，PK 輪仍然不投。
  Set<int> get eligibleVoters {
    if (isRunoff) {
      return _aliveSeats.difference(runoffCandidates).difference(withdrawn);
    }
    return _aliveSeats.difference(candidates);
  }

  /// 還沒投票的人 —— 列出來，法官才不會漏掉某一位。
  Set<int> get notYetVoted => eligibleVoters.difference(votes.keys.toSet());

  /// 目前票數：候選人座次 → 得票。
  ///
  /// 競選時還沒有警長，所以不套用 `sheriffVoteWeight` 加權。
  Map<int, int> get tally {
    final counts = {for (final c in activeCandidates) c: 0};
    for (final target in votes.values) {
      if (counts.containsKey(target)) counts[target] = counts[target]! + 1;
    }
    return counts;
  }

  // ---- 操作 ----

  /// 上警／取消上警。
  void toggleCandidate(int seat) {
    if (stage != ElectionStage.nominate) return;
    if (!state.playerAt(seat).alive) return;
    if (!candidates.remove(seat)) candidates.add(seat);
  }

  /// 退水／取消退水。
  void toggleWithdraw(int seat) {
    if (stage != ElectionStage.withdraw) return;
    if (!candidates.contains(seat)) return;
    if (!withdrawn.remove(seat)) withdrawn.add(seat);
  }

  /// 選定目前要歸票的候選人。
  void focusCandidate(int seat) {
    if (!activeCandidates.contains(seat)) return;
    focusedCandidate = focusedCandidate == seat ? null : seat;
  }

  /// [seat] 這個人現在能不能被圈進目前候選人的票裡。
  ///
  /// **一人一票**：已經投給別人的就不能再圈，免得重複計票。
  bool canAssignVote(int seat) {
    if (stage != ElectionStage.vote && stage != ElectionStage.runoffVote) {
      return false;
    }
    if (focusedCandidate == null) return false;
    if (!eligibleVoters.contains(seat)) return false;
    final existing = votes[seat];
    return existing == null || existing == focusedCandidate;
  }

  /// 圈選／取消一張投給目前候選人的票。
  void toggleVote(int seat) {
    final target = focusedCandidate;
    if (target == null) return;
    if (votes[seat] == target) {
      votes.remove(seat);
      return;
    }
    if (!canAssignVote(seat)) return;
    votes[seat] = target;
  }

  /// 前進到下一階段；投票階段會結算。
  void next() {
    undoStack.push(state, _stageLabel, cursor: _cursor);

    switch (stage) {
      case ElectionStage.nominate:
        if (candidates.isEmpty) {
          // 沒人上警 → 本局無警長，直接結束。
          _finishWithNoSheriff();
          return;
        }
        stage = ElectionStage.withdraw;

      case ElectionStage.withdraw:
        final running = activeCandidates;
        if (running.isEmpty) {
          // 全部退水 → 無警長。
          _finishWithNoSheriff();
          return;
        }
        if (running.length == 1) {
          // 只剩一位候選人，直接當選，不必投票。
          _electSheriff(running.first);
          return;
        }
        stage = ElectionStage.vote;
        focusedCandidate = null;

      case ElectionStage.vote:
      case ElectionStage.runoffVote:
        _resolveVote();

      case ElectionStage.done:
        break;
    }
  }

  void _resolveVote() {
    final counts = tally;
    final highest =
        counts.values.isEmpty ? 0 : counts.values.reduce((a, b) => a > b ? a : b);

    if (highest == 0) {
      // 全員棄票 → 無警長。
      _finishWithNoSheriff();
      return;
    }

    final top = counts.entries
        .where((e) => e.value == highest)
        .map((e) => e.key)
        .toSet();

    if (top.length == 1) {
      _electSheriff(top.first);
      return;
    }

    if (stage == ElectionStage.vote) {
      // 平票 → 平票者 PK 再投。
      runoffCandidates
        ..clear()
        ..addAll(top);
      votes.clear();
      focusedCandidate = null;
      stage = ElectionStage.runoffVote;
      return;
    }

    // PK 之後仍然平票 → 本局無警長。
    _finishWithNoSheriff();
  }

  void _electSheriff(int seat) {
    sheriffSeat = seat;
    state.sheriffSeat = seat;
    stage = ElectionStage.done;
  }

  void _finishWithNoSheriff() {
    noSheriff = true;
    sheriffSeat = null;
    state.sheriffSeat = null;
    stage = ElectionStage.done;
  }

  // ---- 撤銷 ----

  bool get canUndo => undoStack.canUndo;

  String? get undoLabel => undoStack.topLabel;

  String get _stageLabel => switch (stage) {
        ElectionStage.nominate => '上警',
        ElectionStage.withdraw => '退水',
        ElectionStage.vote => '投票',
        ElectionStage.runoffVote => 'PK 重投',
        ElectionStage.done => '結束',
      };

  _ElectionCursor get _cursor => _ElectionCursor(
        stage: stage,
        candidates: {...candidates},
        withdrawn: {...withdrawn},
        votes: {...votes},
        runoffCandidates: {...runoffCandidates},
        focusedCandidate: focusedCandidate,
        sheriffSeat: sheriffSeat,
        noSheriff: noSheriff,
      );

  /// 退回上一次按「下一步」之前。
  bool undo() {
    final snap = undoStack.undo();
    if (snap == null) return false;

    state.restoreFrom(snap.state);
    final c = snap.cursor! as _ElectionCursor;
    stage = c.stage;
    candidates
      ..clear()
      ..addAll(c.candidates);
    withdrawn
      ..clear()
      ..addAll(c.withdrawn);
    votes
      ..clear()
      ..addAll(c.votes);
    runoffCandidates
      ..clear()
      ..addAll(c.runoffCandidates);
    focusedCandidate = c.focusedCandidate;
    sheriffSeat = c.sheriffSeat;
    noSheriff = c.noSheriff;
    return true;
  }
}

/// 競選走到哪裡 —— 撤銷時要連這個一起還原。
class _ElectionCursor {
  const _ElectionCursor({
    required this.stage,
    required this.candidates,
    required this.withdrawn,
    required this.votes,
    required this.runoffCandidates,
    required this.focusedCandidate,
    required this.sheriffSeat,
    required this.noSheriff,
  });

  final ElectionStage stage;
  final Set<int> candidates;
  final Set<int> withdrawn;
  final Map<int, int> votes;
  final Set<int> runoffCandidates;
  final int? focusedCandidate;
  final int? sheriffSeat;
  final bool noSheriff;
}
