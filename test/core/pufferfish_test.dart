import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/vote_resolver.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 河豚（擔當 2026-09-23 指定）：
///
/// - **只有河豚自己被放逐時**才能翻牌
/// - 翻牌帶走所有這一輪投他的人
/// - 被帶走的人**不能開槍**
/// - 河豚自己照樣死（他本來就是被放逐的）
///
/// 翻牌是**主動技能** —— 法官要問過本人，不發動就直接結束。

/// 12 人測試板：3狼 + 預女獵豚 + 5民。
Preset _preset() => Preset.fromJson(
      const {
        'presetId': 'pf',
        'name': '河豚測試板',
        'playerCount': 12,
        'roles': [
          {'role': 'wolf', 'count': 3},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'pufferfish', 'count': 1},
          {'role': 'villager', 'count': 5},
        ],
        'nightOrder': ['wolf', 'witch', 'seer'],
      },
      sourceName: 'pf.json',
    );

/// 1-3 狼、4 預言家、5 女巫、6 獵人、7 河豚、8-12 平民。
GameState _state() {
  final s = GameState(preset: _preset());
  void set(int seat, Role role) => s.playerAt(seat).role = role;
  for (final seat in [1, 2, 3]) {
    set(seat, Roles.wolf);
  }
  set(4, Roles.seer);
  set(5, Roles.witch);
  set(6, Roles.hunter);
  set(7, Roles.pufferfish);
  for (var i = 8; i <= 12; i++) {
    set(i, Roles.villager);
  }
  s.dayNumber = 2;
  return s;
}

/// 讓 [voters] 投給 [target]，然後算票。
ExileVote _voteOut(GameState s, {required int target, required List<int> voters}) {
  final v = ExileVote(state: s);
  v.focusTarget(target);
  for (final voter in voters) {
    v.toggleVote(voter);
  }
  v.next(); // 算票並跑放逐連鎖
  return v;
}

void main() {
  group('觸發時機', () {
    test('河豚被放逐 → 停在翻牌那一步', () {
      final s = _state();
      final v = _voteOut(s, target: 7, voters: [1, 2, 8]);

      expect(v.exiledSeat, 7);
      expect(v.stage, ExileStage.pufferfishReveal);
      expect(v.pufferfishVoters, {1, 2, 8});
    });

    test('被放逐的是別人 → 沒有翻牌這一步', () {
      final s = _state();
      final v = _voteOut(s, target: 8, voters: [1, 2, 7]);

      expect(v.exiledSeat, 8);
      expect(v.stage, ExileStage.done);
      expect(v.pufferfishVoters, isEmpty);
    });

    test('帶走名單只算還活著的投票者', () {
      // 連鎖前面可能已經帶走人（殉情之類），死者不該再被帶走一次。
      final s = _state();
      final v = _voteOut(s, target: 7, voters: [2, 8]);
      expect(v.pufferfishVoters, {2, 8});

      s.playerAt(8).alive = false; // 8 號在翻牌前就出局了
      expect(v.pufferfishVoters, {2});
    });
  });

  group('翻牌', () {
    test('帶走所有投他的人', () {
      final s = _state();
      final v = _voteOut(s, target: 7, voters: [1, 2, 8]);
      v.revealPufferfish(activate: true);

      expect(s.playerAt(1).alive, isFalse);
      expect(s.playerAt(2).alive, isFalse);
      expect(s.playerAt(8).alive, isFalse);
      expect(v.stage, ExileStage.done);
    });

    test('死因是河豚帶走，不是放逐也不是開槍', () {
      final s = _state();
      final v = _voteOut(s, target: 7, voters: [1]);
      v.revealPufferfish(activate: true);

      final taken = v.deaths.where((d) => d.seat == 1).single;
      expect(taken.cause, DeathCause.pufferfishRevenge);
    });

    test('沒投他的人不受影響', () {
      final s = _state();
      final v = _voteOut(s, target: 7, voters: [1, 2]);
      v.revealPufferfish(activate: true);

      expect(s.playerAt(8).alive, isTrue, reason: '8 號沒投河豚');
      expect(s.playerAt(9).alive, isTrue);
    });

    test('河豚自己照樣死 —— 他是被放逐的', () {
      final s = _state();
      final v = _voteOut(s, target: 7, voters: [1]);
      v.revealPufferfish(activate: true);

      expect(s.playerAt(7).alive, isFalse);
      expect(
        v.deaths.where((d) => d.seat == 7).single.cause,
        DeathCause.exile,
      );
    });

    test('不發動就沒有人被帶走', () {
      final s = _state();
      final v = _voteOut(s, target: 7, voters: [1, 2, 8]);
      v.revealPufferfish(activate: false);

      expect(s.playerAt(1).alive, isTrue);
      expect(s.playerAt(2).alive, isTrue);
      expect(s.playerAt(8).alive, isTrue);
      expect(v.stage, ExileStage.done);
    });

    test('next() 視為不發動', () {
      final s = _state();
      final v = _voteOut(s, target: 7, voters: [1]);
      v.next();

      expect(s.playerAt(1).alive, isTrue);
      expect(v.stage, ExileStage.done);
    });
  });

  group('被帶走的人不能開槍', () {
    test('帶走獵人也不會進入開槍階段', () {
      final s = _state();
      final v = _voteOut(s, target: 7, voters: [6]); // 6 號是獵人
      v.revealPufferfish(activate: true);

      expect(s.playerAt(6).alive, isFalse);
      expect(v.stage, ExileStage.done, reason: '不能開槍，直接結束');
      expect(v.shooterSeat, isNull);
    });

    test('對照：獵人被放逐時可以開槍', () {
      final s = _state();
      final v = _voteOut(s, target: 6, voters: [1, 2]);

      expect(v.stage, ExileStage.shoot);
      expect(v.shooterSeat, 6);
    });
  });

  test('撤銷可以退回翻牌之前', () {
    final s = _state();
    final v = _voteOut(s, target: 7, voters: [1, 2]);
    v.revealPufferfish(activate: true);
    expect(s.playerAt(1).alive, isFalse);

    expect(v.undo(), isTrue);
    expect(v.stage, ExileStage.pufferfishReveal);
    expect(s.playerAt(1).alive, isTrue, reason: '被帶走的人要活回來');
    expect(s.playerAt(2).alive, isTrue);
  });
}
