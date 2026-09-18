import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/day_controller.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 12 人狼王守衛局。
Preset _preset() => Preset.fromJson(
      const {
        'presetId': 'wk',
        'name': '狼王守衛局',
        'playerCount': 12,
        'roles': [
          {'role': 'wolf', 'count': 3},
          {'role': 'wolfKing', 'count': 1},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'guard', 'count': 1},
          {'role': 'villager', 'count': 4},
        ],
        'nightOrder': ['guard', 'wolf', 'witch', 'seer'],
      },
      sourceName: 'wk.json',
    );

GameState _state() {
  final s = GameState(preset: _preset());
  void set(int seat, Role r) => s.playerAt(seat).role = r;
  for (final seat in [1, 2, 3]) {
    set(seat, Roles.wolf);
  }
  set(4, Roles.wolfKing);
  set(5, Roles.seer);
  set(6, Roles.witch);
  set(7, Roles.hunter);
  set(8, Roles.guard);
  for (var i = 9; i <= 12; i++) {
    set(i, Roles.villager);
  }
  s.dayNumber = 1;
  return s;
}

/// 上警 [nominees]，不退水，直接進投票。
SheriffElection _toVote(List<int> nominees, {GameState? state}) {
  final e = SheriffElection(state: state ?? _state());
  for (final seat in nominees) {
    e.toggleCandidate(seat);
  }
  e.next(); // 上警 → 退水
  e.next(); // 退水 → 投票
  return e;
}

/// 把 [voters] 的票全投給 [candidate]。
void _voteFor(SheriffElection e, int candidate, List<int> voters) {
  e.focusCandidate(candidate);
  for (final v in voters) {
    e.toggleVote(v);
  }
  e.focusCandidate(candidate); // 取消聚焦，避免影響後續判斷
}

void main() {
  group('上警', () {
    test('沒人上警 → 直接無警長', () {
      final e = SheriffElection(state: _state());
      e.next();

      expect(e.finished, isTrue);
      expect(e.noSheriff, isTrue);
      expect(e.sheriffSeat, isNull);
      expect(e.state.sheriffSeat, isNull);
    });

    test('只有一人上警 → 不必投票，直接當選', () {
      final e = SheriffElection(state: _state());
      e.toggleCandidate(3);
      e.next(); // 上警 → 退水
      e.next(); // 退水（沒人退）→ 只剩一人，直接當選

      expect(e.finished, isTrue);
      expect(e.sheriffSeat, 3);
      expect(e.state.sheriffSeat, 3);
    });

    test('死人不能上警', () {
      final s = _state();
      s.playerAt(3).alive = false;
      final e = SheriffElection(state: s);

      e.toggleCandidate(3);
      expect(e.candidates, isEmpty);
    });
  });

  group('退水', () {
    test('全部退水 → 無警長', () {
      final e = SheriffElection(state: _state());
      e
        ..toggleCandidate(3)
        ..toggleCandidate(7)
        ..next(); // → 退水
      e
        ..toggleWithdraw(3)
        ..toggleWithdraw(7)
        ..next();

      expect(e.finished, isTrue);
      expect(e.noSheriff, isTrue);
    });

    test('退到只剩一人 → 那一位直接當選', () {
      final e = SheriffElection(state: _state());
      e
        ..toggleCandidate(3)
        ..toggleCandidate(7)
        ..toggleCandidate(11)
        ..next();
      e
        ..toggleWithdraw(7)
        ..toggleWithdraw(11)
        ..next();

      expect(e.sheriffSeat, 3);
    });

    test('只有候選人能退水', () {
      final e = SheriffElection(state: _state());
      e
        ..toggleCandidate(3)
        ..next();
      e.toggleWithdraw(9); // 9 號沒上警

      expect(e.withdrawn, isEmpty);
    });
  });

  // 擔當選的賽制：候選不投、退水也不投。
  group('投票權', () {
    test('上警的都不投 —— 含退水的', () {
      final e = SheriffElection(state: _state());
      e
        ..toggleCandidate(3)
        ..toggleCandidate(7)
        ..toggleCandidate(11)
        ..next();
      e
        ..toggleWithdraw(11) // 退水
        ..next();

      expect(e.eligibleVoters.contains(3), isFalse);
      expect(e.eligibleVoters.contains(7), isFalse);
      expect(e.eligibleVoters.contains(11), isFalse, reason: '退水也不投');
      expect(e.eligibleVoters.length, 9, reason: '12 人扣掉 3 位上警過的');
    });

    test('死人不能投票', () {
      final s = _state();
      s.playerAt(9).alive = false;
      final e = _toVote([3, 7], state: s);

      expect(e.eligibleVoters.contains(9), isFalse);
    });

    test('一人一票 —— 投過的不能再圈給別人', () {
      final e = _toVote([3, 7]);

      _voteFor(e, 3, [9]);
      expect(e.votes[9], 3);

      // 改歸票給 7 號時，9 號已經投過了。
      e.focusCandidate(7);
      expect(e.canAssignVote(9), isFalse);
      e.toggleVote(9);
      expect(e.votes[9], 3, reason: '票沒有被改掉');
    });

    test('圈錯了可以再點一次取消', () {
      final e = _toVote([3, 7]);

      e.focusCandidate(3);
      e.toggleVote(9);
      expect(e.votes[9], 3);

      e.toggleVote(9);
      expect(e.votes.containsKey(9), isFalse);
      expect(e.canAssignVote(9), isTrue, reason: '取消後可以改投別人');
    });

    test('沒選候選人時圈不了票', () {
      final e = _toVote([3, 7]);

      expect(e.focusedCandidate, isNull);
      e.toggleVote(9);
      expect(e.votes, isEmpty);
    });

    test('尚未投票的人列得出來', () {
      final e = _toVote([3, 7]);
      _voteFor(e, 3, [9, 10]);

      expect(e.notYetVoted, {1, 2, 4, 5, 6, 8, 11, 12});
    });
  });

  group('算票', () {
    test('最高票單一 → 當選', () {
      final e = _toVote([3, 7]);
      _voteFor(e, 3, [9, 10, 11]);
      _voteFor(e, 7, [12, 1]);
      e.next();

      expect(e.tally, {3: 3, 7: 2});
      expect(e.sheriffSeat, 3);
      expect(e.state.sheriffSeat, 3);
    });

    test('沒圈到的就是棄票', () {
      final e = _toVote([3, 7]);
      _voteFor(e, 3, [9]);
      e.next();

      expect(e.sheriffSeat, 3, reason: '1 票也是最高票');
    });

    test('全員棄票 → 無警長', () {
      final e = _toVote([3, 7]);
      e.next();

      expect(e.noSheriff, isTrue);
      expect(e.sheriffSeat, isNull);
    });
  });

  // 擔當選的規則：平票者 PK 再投，再平就沒警長。
  group('平票 PK', () {
    test('平票 → 進入 PK，票數歸零重投', () {
      final e = _toVote([3, 7, 11]);
      _voteFor(e, 3, [9, 10]);
      _voteFor(e, 7, [12, 1]);
      _voteFor(e, 11, [2]);
      e.next();

      expect(e.stage, ElectionStage.runoffVote);
      expect(e.runoffCandidates, {3, 7});
      expect(e.votes, isEmpty, reason: '重投，票數歸零');
      expect(e.sheriffSeat, isNull);
    });

    // PK 輪的投票權：擔當選「第一輪落選的其他候選人恢復投票權」。
    test('PK 輪：落選的候選人恢復投票權，PK 名單本身不投', () {
      final e = _toVote([3, 7, 11]);
      _voteFor(e, 3, [9, 10]);
      _voteFor(e, 7, [12, 1]);
      _voteFor(e, 11, [2]);
      e.next();

      expect(e.eligibleVoters.contains(11), isTrue,
          reason: '11 號落選了，PK 輪可以投');
      expect(e.eligibleVoters.contains(3), isFalse);
      expect(e.eligibleVoters.contains(7), isFalse);
    });

    test('PK 輪：退水的人仍然不投', () {
      final e = SheriffElection(state: _state());
      e
        ..toggleCandidate(3)
        ..toggleCandidate(7)
        ..toggleCandidate(11)
        ..next();
      e
        ..toggleWithdraw(11)
        ..next();
      _voteFor(e, 3, [9]);
      _voteFor(e, 7, [10]);
      e.next();

      expect(e.stage, ElectionStage.runoffVote);
      expect(e.eligibleVoters.contains(11), isFalse,
          reason: '退水是自己退出整場競選');
    });

    test('PK 分出勝負 → 當選', () {
      final e = _toVote([3, 7]);
      _voteFor(e, 3, [9]);
      _voteFor(e, 7, [10]);
      e.next(); // 平票 → PK

      _voteFor(e, 3, [9, 10, 11]);
      _voteFor(e, 7, [12]);
      e.next();

      expect(e.sheriffSeat, 3);
      expect(e.finished, isTrue);
    });

    test('PK 再平票 → 本局無警長', () {
      final e = _toVote([3, 7]);
      _voteFor(e, 3, [9]);
      _voteFor(e, 7, [10]);
      e.next(); // → PK

      _voteFor(e, 3, [9]);
      _voteFor(e, 7, [10]);
      e.next();

      expect(e.finished, isTrue);
      expect(e.noSheriff, isTrue);
      expect(e.state.sheriffSeat, isNull);
    });
  });

  group('撤銷', () {
    test('剛開始沒有東西可撤', () {
      expect(SheriffElection(state: _state()).canUndo, isFalse);
    });

    test('撤銷退回上警階段，名單還在', () {
      final e = SheriffElection(state: _state());
      e
        ..toggleCandidate(3)
        ..toggleCandidate(7)
        ..next();

      expect(e.stage, ElectionStage.withdraw);
      expect(e.undo(), isTrue);
      expect(e.stage, ElectionStage.nominate);
      expect(e.candidates, {3, 7}, reason: '名單保留，法官可以直接改');
    });

    test('撤銷已結算的當選 —— 警長要退回去', () {
      final e = _toVote([3, 7]);
      _voteFor(e, 3, [9, 10]);
      _voteFor(e, 7, [11]);
      e.next();

      expect(e.state.sheriffSeat, 3);

      expect(e.undo(), isTrue);
      expect(e.stage, ElectionStage.vote);
      expect(e.sheriffSeat, isNull);
      expect(e.state.sheriffSeat, isNull, reason: '局面也要還原');
      expect(e.votes[9], 3, reason: '投票紀錄還在，法官可以改一票再結算');
    });

    test('撤銷 PK，退回第一輪的票', () {
      final e = _toVote([3, 7]);
      _voteFor(e, 3, [9]);
      _voteFor(e, 7, [10]);
      e.next(); // → PK

      expect(e.stage, ElectionStage.runoffVote);
      expect(e.undo(), isTrue);
      expect(e.stage, ElectionStage.vote);
      expect(e.votes, {9: 3, 10: 7});
      expect(e.runoffCandidates, isEmpty);
    });
  });
}
