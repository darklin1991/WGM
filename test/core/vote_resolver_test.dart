import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/vote_resolver.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/player.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 12 人狼王守衛局（有狼王＝槍牌）。
Preset _preset({Map<String, dynamic>? rules}) => Preset.fromJson(
      {
        'presetId': 'wk',
        'name': '狼王守衛局',
        'playerCount': 12,
        'roles': const [
          {'role': 'wolf', 'count': 3},
          {'role': 'wolfKing', 'count': 1},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'guard', 'count': 1},
          {'role': 'villager', 'count': 4},
        ],
        'nightOrder': const ['guard', 'wolf', 'witch', 'seer'],
        'rules': ?rules,
      },
      sourceName: 'wk.json',
    );

/// 1-3 狼、4 狼王、5 預言家、6 女巫、7 獵人、8 守衛、9-12 平民。
GameState _state({Map<String, dynamic>? rules}) {
  final s = GameState(preset: _preset(rules: rules));
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

/// 把 [voters] 的票投給 [target]。
void _voteFor(ExileVote v, int target, List<int> voters) {
  v.focusTarget(target);
  for (final seat in voters) {
    v.toggleVote(seat);
  }
  v.focusTarget(target); // 取消聚焦
}

Map<int, DeathCause> _deathMap(ExileVote v) => {
      for (final d in v.deaths) d.seat: d.cause,
    };

void main() {
  group('投票權與歸票', () {
    test('所有存活玩家都有票', () {
      expect(ExileVote(state: _state()).eligibleVoters.length, 12);
    });

    test('死人沒票', () {
      final s = _state();
      s.playerAt(9).alive = false;

      expect(ExileVote(state: s).eligibleVoters.contains(9), isFalse);
    });

    test('白痴翻牌後失去投票權', () {
      final s = _state();
      s.playerAt(9).canVote = false;

      expect(ExileVote(state: s).eligibleVoters.contains(9), isFalse);
    });

    test('一人一票 —— 投過的不能再圈給別人', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 3, [9]);

      v.focusTarget(7);
      expect(v.canAssignVote(9), isFalse);
      v.toggleVote(9);
      expect(v.votes[9], 3, reason: '票沒被搶走');
    });

    test('圈錯了可以取消再改投', () {
      final v = ExileVote(state: _state());
      v.focusTarget(3);
      v.toggleVote(9);
      v.toggleVote(9);

      expect(v.votes.containsKey(9), isFalse);
      expect(v.canAssignVote(9), isTrue);
    });

    test('尚未投票的人列得出來', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 3, [1, 2, 4, 5, 6, 7, 8, 9, 10]);

      // 3 號是被投的對象，但他自己照樣有票 —— 放逐投票沒有「候選人不投」。
      expect(v.notYetVoted, {3, 11, 12});
    });

    test('被投的人自己也能投票', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 3, [9]);

      expect(v.eligibleVoters.contains(3), isTrue);
      _voteFor(v, 9, [3]);
      expect(v.votes[3], 9, reason: '3 號被投，但他自己也能投別人');
    });
  });

  group('警長票加權', () {
    test('警長的票算 1.5', () {
      final s = _state()..sheriffSeat = 5;
      final v = ExileVote(state: s);
      _voteFor(v, 3, [5]);

      expect(v.tally[3], 1.5);
    });

    test('1.5 票可以壓過 1 票', () {
      final s = _state()..sheriffSeat = 5;
      final v = ExileVote(state: s);
      _voteFor(v, 3, [5]); // 警長 1.5
      _voteFor(v, 7, [9]); // 平民 1
      v.next();

      expect(v.exiledSeat, 3);
    });

    test('沒有警長時每票都是 1', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 3, [5, 9]);

      expect(v.tally[3], 2.0);
    });
  });

  group('放逐結算', () {
    test('最高票單一 → 放逐並死亡', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 9, [1, 2, 3]);
      _voteFor(v, 10, [4]);
      v.next();

      expect(v.exiledSeat, 9);
      expect(_deathMap(v)[9], DeathCause.exile);
      expect(v.state.playerAt(9).alive, isFalse);
      expect(v.finished, isTrue);
    });

    test('全員棄票 → 無人出局', () {
      final v = ExileVote(state: _state());
      v.next();

      expect(v.exiledSeat, isNull);
      expect(v.deaths, isEmpty);
      expect(v.notes.any((n) => n.contains('無人出局')), isTrue);
    });

    test('被放逐者標記為 exiled', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 9, [1, 2]);
      v.next();

      expect(v.state.playerAt(9).nightFacts, contains(FactTag.exiled));
    });
  });

  // 擔當指定：平票者 PK 再投，平票者本人不投。
  group('平票 PK', () {
    test('平票 → 進入 PK，票數歸零', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 9, [1, 2]);
      _voteFor(v, 10, [3, 4]);
      v.next(); // 算票 → 平票，進入 PK 發言
      v.next(); // PK 發言結束 → 重投

      expect(v.stage, ExileStage.runoffVote);
      expect(v.runoffTargets, {9, 10});
      expect(v.votes, isEmpty);
      expect(v.exiledSeat, isNull);
    });

    test('PK 輪：平票者本人不投', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 9, [1, 2]);
      _voteFor(v, 10, [3, 4]);
      v.next(); // 算票 → 平票，進入 PK 發言
      v.next(); // PK 發言結束 → 重投

      expect(v.eligibleVoters.contains(9), isFalse);
      expect(v.eligibleVoters.contains(10), isFalse);
      expect(v.eligibleVoters.contains(1), isTrue, reason: '其餘人照投');
      expect(v.eligibleVoters.length, 10);
    });

    test('PK 輪只能投平票者', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 9, [1, 2]);
      _voteFor(v, 10, [3, 4]);
      v.next(); // 算票 → 平票，進入 PK 發言
      v.next(); // PK 發言結束 → 重投

      expect(v.votableTargets, {9, 10});
      v.focusTarget(11);
      expect(v.focusedTarget, isNull, reason: '11 號不在 PK 名單裡');
    });

    test('PK 分出勝負 → 放逐', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 9, [1, 2]);
      _voteFor(v, 10, [3, 4]);
      v.next(); // 算票 → 平票，進入 PK 發言
      v.next(); // PK 發言結束 → 重投

      _voteFor(v, 9, [1, 2, 3]);
      _voteFor(v, 10, [4]);
      v.next();

      expect(v.exiledSeat, 9);
      expect(v.finished, isTrue);
    });

    test('PK 再平票 → 無人出局', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 9, [1, 2]);
      _voteFor(v, 10, [3, 4]);
      v.next(); // 算票 → 平票，進入 PK 發言
      v.next(); // PK 發言結束 → 重投

      _voteFor(v, 9, [1]);
      _voteFor(v, 10, [2]);
      v.next();

      expect(v.exiledSeat, isNull);
      expect(v.deaths, isEmpty);
      expect(v.finished, isTrue);
      expect(v.notes.any((n) => n.contains('仍然平票')), isTrue);
    });

    test('tieBreak = none → 平票直接無人出局，不進 PK', () {
      final v = ExileVote(state: _state(rules: const {'tieBreak': 'none'}));
      _voteFor(v, 9, [1, 2]);
      _voteFor(v, 10, [3, 4]);
      v.next(); // 算票 → 平票，進入 PK 發言
      v.next(); // PK 發言結束 → 重投

      expect(v.finished, isTrue);
      expect(v.exiledSeat, isNull);
    });
  });

  group('白痴被放逐', () {
    test('翻牌不死，失去投票權，留在場上', () {
      final s = _state();
      s.playerAt(9).role = Roles.idiot;
      final v = ExileVote(state: s);
      _voteFor(v, 9, [1, 2, 3]);
      v.next();

      expect(v.idiotRevealed, isTrue);
      expect(v.exiledSeat, 9);
      expect(s.playerAt(9).alive, isTrue, reason: '不死');
      expect(s.playerAt(9).canVote, isFalse, reason: '失去投票權');
      expect(v.deaths, isEmpty);
      expect(v.finished, isTrue);
    });

    test('白痴翻牌後，下一次投票他就沒票了', () {
      final s = _state();
      s.playerAt(9).role = Roles.idiot;
      final first = ExileVote(state: s);
      _voteFor(first, 9, [1, 2, 3]);
      first.next();

      expect(ExileVote(state: s).eligibleVoters.contains(9), isFalse);
    });
  });

  // 擔當指定做完整連鎖：放逐 → 殉情 → 開槍 → 開槍目標的殉情
  group('槍牌被放逐 → 開槍', () {
    test('狼王被放逐 → 進入開槍階段', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 4, [1, 2, 3]); // 4 號是狼王
      v.next();

      expect(v.stage, ExileStage.shoot);
      expect(v.shooterSeat, 4);
      expect(v.finished, isFalse);
    });

    test('獵人被放逐 → 也能開槍', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 7, [1, 2, 3]); // 7 號是獵人
      v.next();

      expect(v.shooterSeat, 7);
    });

    test('開槍帶走一人', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 7, [1, 2, 3]);
      v.next();
      v.shoot(10);

      expect(_deathMap(v)[7], DeathCause.exile);
      expect(_deathMap(v)[10], DeathCause.hunterShot);
      expect(v.state.playerAt(10).alive, isFalse);
      expect(v.finished, isTrue);
    });

    test('可以放棄開槍', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 7, [1, 2, 3]);
      v.next();
      v.shoot(null);

      expect(v.deaths.length, 1, reason: '只有被放逐的那位');
      expect(v.notes.any((n) => n.contains('放棄開槍')), isTrue);
      expect(v.finished, isTrue);
    });

    test('平民被放逐不會進開槍階段', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 9, [1, 2, 3]);
      v.next();

      expect(v.shooterSeat, isNull);
      expect(v.finished, isTrue);
    });
  });

  group('狼美人被放逐 → 殉情', () {
    GameState withBeauty() {
      final s = _state();
      s.playerAt(3).role = Roles.wolfBeauty;
      s.charmedSeat = 11;
      return s;
    }

    test('被放逐時，被魅惑者殉情', () {
      final v = ExileVote(state: withBeauty());
      _voteFor(v, 3, [1, 2, 4]);
      v.next();

      expect(_deathMap(v)[3], DeathCause.exile);
      expect(_deathMap(v)[11], DeathCause.loveSuicide);
      expect(v.state.playerAt(11).alive, isFalse);
    });

    test('被魅惑者已經出局 → 不重複殺', () {
      final s = withBeauty();
      s.playerAt(11).alive = false;
      final v = ExileVote(state: s);
      _voteFor(v, 3, [1, 2, 4]);
      v.next();

      expect(v.deaths.length, 1);
      expect(v.notes.any((n) => n.contains('已經出局')), isTrue);
    });

    test('本來就沒魅惑任何人 → 不殉情', () {
      final s = withBeauty()..charmedSeat = null;
      final v = ExileVote(state: s);
      _voteFor(v, 3, [1, 2, 4]);
      v.next();

      expect(v.deaths.length, 1);
    });

    test('開槍打死狼美人 → 也會殉情', () {
      final s = withBeauty();
      final v = ExileVote(state: s);
      _voteFor(v, 7, [1, 2, 4]); // 放逐獵人
      v.next();
      v.shoot(3); // 獵人開槍打狼美人

      expect(_deathMap(v)[7], DeathCause.exile);
      expect(_deathMap(v)[3], DeathCause.hunterShot);
      expect(_deathMap(v)[11], DeathCause.loveSuicide);
      expect(v.deaths.length, 3, reason: '放逐 → 開槍 → 殉情，三條命');
    });
  });

  group('撤銷', () {
    test('剛開始沒有東西可撤', () {
      expect(ExileVote(state: _state()).canUndo, isFalse);
    });

    test('撤銷已結算的放逐 —— 死者要活回來', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 9, [1, 2, 3]);
      v.next();

      expect(v.state.playerAt(9).alive, isFalse);

      expect(v.undo(), isTrue);
      expect(v.stage, ExileStage.vote);
      expect(v.state.playerAt(9).alive, isTrue, reason: '局面還原');
      expect(v.exiledSeat, isNull);
      expect(v.deaths, isEmpty);
      expect(v.votes[1], 9, reason: '投票紀錄還在，可以改一票再算');
    });

    test('撤銷開槍 —— 中槍的人活回來，退回開槍階段', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 7, [1, 2, 3]);
      v.next();
      v.shoot(10);

      expect(v.state.playerAt(10).alive, isFalse);

      expect(v.undo(), isTrue);
      expect(v.stage, ExileStage.shoot);
      expect(v.state.playerAt(10).alive, isTrue);
      expect(v.state.playerAt(7).alive, isFalse, reason: '放逐本身還在');
      expect(v.deaths.length, 1);
    });

    test('撤銷白痴翻牌 —— 投票權要還回去', () {
      final s = _state();
      s.playerAt(9).role = Roles.idiot;
      final v = ExileVote(state: s);
      _voteFor(v, 9, [1, 2, 3]);
      v.next();

      expect(s.playerAt(9).canVote, isFalse);

      expect(v.undo(), isTrue);
      expect(s.playerAt(9).canVote, isTrue);
      expect(v.idiotRevealed, isFalse);
    });

    test('撤銷 PK，退回第一輪的票', () {
      final v = ExileVote(state: _state());
      _voteFor(v, 9, [1, 2]);
      _voteFor(v, 10, [3, 4]);
      v.next(); // 算票 → 平票，進入 PK 發言
      v.next(); // PK 發言結束 → 重投

      expect(v.stage, ExileStage.runoffVote);

      // PK 發言也是一個階段，所以要退兩步才回到第一輪。
      expect(v.undo(), isTrue);
      expect(v.stage, ExileStage.runoffSpeech);

      expect(v.undo(), isTrue);
      expect(v.stage, ExileStage.vote);
      expect(v.votes, {1: 9, 2: 9, 3: 10, 4: 10});
      expect(v.runoffTargets, isEmpty);
    });
  });
}
