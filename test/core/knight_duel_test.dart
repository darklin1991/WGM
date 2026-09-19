import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/knight_duel.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 12人 狼美騎士：3狼＋狼美人、預女守騎、4民。
Preset _preset({Map<String, dynamic>? rules}) => Preset.fromJson(
      {
        'presetId': 'lmqs',
        'name': '狼美騎士',
        'playerCount': 12,
        'roles': const [
          {'role': 'wolf', 'count': 3},
          {'role': 'wolfBeauty', 'count': 1},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'guard', 'count': 1},
          {'role': 'knight', 'count': 1},
          {'role': 'villager', 'count': 4},
        ],
        'nightOrder': const ['guard', 'wolf', 'wolfBeauty', 'witch', 'seer'],
        'rules': ?rules,
      },
      sourceName: 'lmqs.json',
    );

/// 1-3 狼、4 狼美人、5 預言家、6 女巫、7 守衛、8 騎士、9-12 平民。
GameState _state({Map<String, dynamic>? rules}) {
  final s = GameState(preset: _preset(rules: rules));
  void set(int seat, Role r) => s.playerAt(seat).role = r;
  for (final seat in [1, 2, 3]) {
    set(seat, Roles.wolf);
  }
  set(4, Roles.wolfBeauty);
  set(5, Roles.seer);
  set(6, Roles.witch);
  set(7, Roles.guard);
  set(8, Roles.knight);
  for (var i = 9; i <= 12; i++) {
    set(i, Roles.villager);
  }
  s.dayNumber = 1;
  return s;
}

void main() {
  group('什麼時候能決鬥', () {
    test('騎士還活著且沒用過技能 → 可以', () {
      final s = _state();

      expect(KnightDuel.isAvailable(s), isTrue);
      expect(KnightDuel.aliveKnightSeat(s), 8);
    });

    test('騎士已出局 → 不行', () {
      final s = _state();
      s.playerAt(8).alive = false;

      expect(KnightDuel.isAvailable(s), isFalse);
      expect(KnightDuel.aliveKnightSeat(s), isNull);
    });

    test('整局只能決鬥一次 —— 決鬥到狼活下來也不能再發動', () {
      final s = _state();
      KnightDuel(state: s).duel(1);

      expect(s.playerAt(8).alive, isTrue, reason: '決鬥到狼，騎士活著');
      expect(s.knightDuelUsed, isTrue);
      expect(KnightDuel.isAvailable(s), isFalse);
    });

    test('沒有騎士的板子 → 不行', () {
      final s = _state();
      s.playerAt(8).role = Roles.villager;

      expect(KnightDuel.isAvailable(s), isFalse);
    });

    test('對手名單是除了騎士以外的存活玩家', () {
      final s = _state();
      s.playerAt(9).alive = false;
      final d = KnightDuel(state: s);

      expect(d.opponents.contains(8), isFalse, reason: '不能決鬥自己');
      expect(d.opponents.contains(9), isFalse, reason: '死人不能決鬥');
      expect(d.opponents, {1, 2, 3, 4, 5, 6, 7, 10, 11, 12});
    });
  });

  group('決鬥到狼', () {
    test('對手出局，騎士活著，死因是騎士決鬥', () {
      final s = _state();
      final d = KnightDuel(state: s)..duel(2);

      expect(d.outcome, DuelOutcome.wolfDied);
      expect(s.playerAt(2).alive, isFalse);
      expect(s.playerAt(8).alive, isTrue);
      expect(d.deaths.single.seat, 2);
      expect(d.deaths.single.cause, DeathCause.knightDuel);
    });

    test('白天就此結束，跳過投票直接進夜', () {
      final s = _state();
      final d = KnightDuel(state: s)..duel(2);

      expect(d.endsDay, isTrue);
      expect(d.notes.last, '決鬥出狼，白天就此結束，直接進入黑夜');
    });

    test('板子關掉 knightDuelEndsDay → 白天照常走到投票', () {
      final s = _state(rules: const {'knightDuelEndsDay': false});
      final d = KnightDuel(state: s)..duel(2);

      expect(d.outcome, DuelOutcome.wolfDied);
      expect(d.endsDay, isFalse);
      expect(s.playerAt(2).alive, isFalse);
    });

    test('狼美人也算狼', () {
      final s = _state();
      final d = KnightDuel(state: s)..duel(4);

      expect(d.outcome, DuelOutcome.wolfDied);
      expect(s.playerAt(4).alive, isFalse);
      expect(s.playerAt(8).alive, isTrue);
    });
  });

  group('決鬥到好人', () {
    test('騎士自刎，對手活著', () {
      final s = _state();
      final d = KnightDuel(state: s)..duel(9);

      expect(d.outcome, DuelOutcome.knightDied);
      expect(s.playerAt(8).alive, isFalse);
      expect(s.playerAt(9).alive, isTrue);
      expect(d.deaths.single.seat, 8);
      expect(d.deaths.single.cause, DeathCause.knightDuel);
    });

    test('白天照常繼續，不進夜', () {
      final s = _state();
      final d = KnightDuel(state: s)..duel(9);

      expect(d.endsDay, isFalse);
      expect(d.notes.last, '白天照常繼續，走到放逐投票');
    });

    test('決鬥到神職也是騎士自己死', () {
      final s = _state();
      final d = KnightDuel(state: s)..duel(5);

      expect(d.outcome, DuelOutcome.knightDied);
      expect(s.playerAt(5).alive, isTrue);
      expect(s.playerAt(8).alive, isFalse);
    });
  });

  // 這是騎士唯一能救下殉情者的時機 —— 夜晚結算碰不到這條。
  group('決鬥掉狼美人時的殉情', () {
    test('預設不殉情，被魅惑者活下來', () {
      final s = _state()..charmedSeat = 10;
      final d = KnightDuel(state: s)..duel(4);

      expect(s.playerAt(4).alive, isFalse);
      expect(s.playerAt(10).alive, isTrue, reason: '騎士決鬥致死不觸發殉情');
      expect(d.deaths.length, 1);
      expect(d.notes, contains('狼美人被決鬥致死，10 號不殉情'));
    });

    test('板子關掉 knightDuelBlocksCharmSuicide → 照常殉情', () {
      final s = _state(rules: const {'knightDuelBlocksCharmSuicide': false})
        ..charmedSeat = 10;
      final d = KnightDuel(state: s)..duel(4);

      expect(s.playerAt(10).alive, isFalse);
      expect(d.deaths.map((x) => x.seat), [4, 10]);
      expect(d.deaths.last.cause, DeathCause.loveSuicide);
    });

    test('沒魅惑任何人 → 沒有殉情可談', () {
      final s = _state(); // charmedSeat 為 null
      final d = KnightDuel(state: s)..duel(4);

      expect(d.deaths.length, 1);
      expect(d.notes.any((n) => n.contains('殉情')), isFalse);
    });

    test('決鬥掉的不是狼美人就不談殉情', () {
      final s = _state()..charmedSeat = 10;
      KnightDuel(state: s).duel(2);

      expect(s.playerAt(10).alive, isTrue);
    });
  });

  // 擔當指定：決鬥是騎士的裁決，對手沒有反擊機會。
  group('決鬥致死的對手不能開槍', () {
    test('決鬥到狼王也只是出局，不帶人', () {
      final s = _state();
      s.playerAt(2).role = Roles.wolfKing;
      final d = KnightDuel(state: s)..duel(2);

      expect(s.playerAt(2).alive, isFalse);
      expect(d.deaths.length, 1, reason: '沒有第二個死者');
      expect(s.aliveCount, 11);
    });

    test('死因不是狼刀也不是放逐，所以不會被當成可開槍的死法', () {
      final s = _state();
      s.playerAt(2).role = Roles.wolfKing;
      final d = KnightDuel(state: s)..duel(2);

      expect(d.deaths.single.cause, DeathCause.knightDuel);
    });
  });

  group('防呆', () {
    test('決鬥過就不能再呼叫一次', () {
      final s = _state();
      final d = KnightDuel(state: s)
        ..duel(1)
        ..duel(2);

      expect(s.playerAt(2).alive, isTrue);
      expect(d.deaths.length, 1);
    });

    test('對手不在名單裡就不動作', () {
      final s = _state();
      s.playerAt(9).alive = false;
      final d = KnightDuel(state: s)
        ..duel(9) // 死人
        ..duel(8); // 自己

      expect(d.finished, isFalse);
      expect(s.knightDuelUsed, isFalse);
    });
  });

  group('撤銷', () {
    test('一開始沒有東西可撤銷', () {
      expect(KnightDuel(state: _state()).canUndo, isFalse);
    });

    test('撤銷決鬥 → 人活回來，技能也還沒用掉', () {
      final s = _state();
      final d = KnightDuel(state: s)..duel(2);

      expect(d.undoLabel, '騎士決鬥');
      expect(d.undo(), isTrue);

      expect(s.playerAt(2).alive, isTrue);
      expect(s.knightDuelUsed, isFalse);
      expect(d.finished, isFalse);
      expect(d.deaths, isEmpty);
      expect(d.notes, isEmpty);

      // 撤銷之後可以改決鬥別人。
      d.duel(9);
      expect(s.playerAt(8).alive, isFalse, reason: '改決鬥好人，騎士自刎');
      expect(s.playerAt(2).alive, isTrue);
    });

    test('撤銷殉情那一串也要一起退回來', () {
      final s = _state(rules: const {'knightDuelBlocksCharmSuicide': false})
        ..charmedSeat = 10;
      final d = KnightDuel(state: s)..duel(4);
      expect(s.playerAt(10).alive, isFalse);

      d.undo();
      expect(s.playerAt(4).alive, isTrue);
      expect(s.playerAt(10).alive, isTrue);
    });
  });
}
