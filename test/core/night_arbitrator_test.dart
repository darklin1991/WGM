import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/player.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 12 人狼王守衛局：3狼 + 狼王 + 預女獵守 + 4民。
Preset _preset({Map<String, dynamic>? rules}) => Preset.fromJson(
      {
        'presetId': 'wk_guard',
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
      sourceName: 'wk_guard.json',
    );

/// 固定座位配置，方便測試閱讀：
/// 1-3 狼、4 狼王、5 預言家、6 女巫、7 獵人、8 守衛、9-12 平民。
GameState _state({Map<String, dynamic>? rules}) {
  final s = GameState(preset: _preset(rules: rules));
  void set(int seat, Role role) => s.playerAt(seat).role = role;
  set(1, Roles.wolf);
  set(2, Roles.wolf);
  set(3, Roles.wolf);
  set(4, Roles.wolfKing);
  set(5, Roles.seer);
  set(6, Roles.witch);
  set(7, Roles.hunter);
  set(8, Roles.guard);
  for (var i = 9; i <= 12; i++) {
    set(i, Roles.villager);
  }
  return s;
}

NightActions _actions({
  int night = 1,
  int? guard,
  int? wolf,
  int? heal,
  int? poison,
  int? seer,
}) =>
    NightActions(night: night)
      ..guardTarget = guard
      ..wolfTarget = wolf
      ..witchHealTarget = heal
      ..witchPoisonTarget = poison
      ..seerTarget = seer;

Map<int, DeathCause> _deathMap(NightOutcome o) =>
    { for (final d in o.deaths) d.seat: d.cause };

void main() {
  const arb = NightArbitrator();

  group('衝突裁決表', () {
    test('狼刀 ＋ 守衛守（同一目標）→ 存活', () {
      final out = arb.settle(_state(), _actions(guard: 9, wolf: 9));
      expect(out.deadSeats, isEmpty);
      expect(out.isPeacefulNight, isTrue);
    });

    test('狼刀 ＋ 解藥（同一目標）→ 存活', () {
      final out = arb.settle(_state(), _actions(wolf: 9, heal: 9));
      expect(out.deadSeats, isEmpty);
    });

    test('狼刀 ＋ 守衛守 ＋ 解藥（同守同救／奶穿）→ 死亡', () {
      final out = arb.settle(_state(), _actions(guard: 9, wolf: 9, heal: 9));
      expect(out.deadSeats, [9]);
      expect(out.deaths.single.cause, DeathCause.guardHealConflict);
      expect(out.notes.any((n) => n.contains('奶穿')), isTrue);
    });

    test('同守同救 — guardHealKills = false 時改為存活', () {
      final out = arb.settle(
        _state(rules: const {'guardHealKills': false}),
        _actions(guard: 9, wolf: 9, heal: 9),
      );
      expect(out.deadSeats, isEmpty);
    });

    test('毒 ＋ 守衛守（同一目標）→ 死亡（守衛防不了毒）', () {
      final out = arb.settle(_state(), _actions(guard: 9, poison: 9));
      expect(out.deadSeats, [9]);
      expect(out.deaths.single.cause, DeathCause.poison);
      expect(out.notes.any((n) => n.contains('守衛防不了毒')), isTrue);
    });

    test('狼刀 ＋ 毒（同一目標）→ 死亡', () {
      final out = arb.settle(_state(), _actions(wolf: 9, poison: 9));
      expect(out.deadSeats, [9]);
    });

    test('狼刀 ＋ 毒（不同目標）→ 兩人皆死', () {
      final out = arb.settle(_state(), _actions(wolf: 9, poison: 10));
      expect(out.deadSeats, [9, 10]);
    });

    test('解藥救回刀口、同時毒別人 → 只有被毒者死', () {
      final out = arb.settle(_state(), _actions(wolf: 9, heal: 9, poison: 10));
      expect(out.deadSeats, [10]);
    });

    test('空刀且未用藥 → 平安夜', () {
      final out = arb.settle(_state(), _actions(guard: 9));
      expect(out.isPeacefulNight, isTrue);
      expect(out.notes.any((n) => n.contains('空刀')), isTrue);
    });
  });

  group('獵人開槍資格', () {
    test('獵人被狼刀死 → 可開槍', () {
      final out = arb.settle(_state(), _actions(wolf: 7));
      expect(out.deadSeats, [7]);
      expect(out.hunterMayShoot, isTrue);
    });

    test('獵人被毒死 → 不可開槍', () {
      final out = arb.settle(_state(), _actions(poison: 7));
      expect(out.deadSeats, [7]);
      expect(out.hunterMayShoot, isFalse);
      expect(out.notes.any((n) => n.contains('不可開槍')), isTrue);
    });

    test('獵人被毒死 — poisonedHunterCannotShoot = false 時可開槍', () {
      final out = arb.settle(
        _state(rules: const {'poisonedHunterCannotShoot': false}),
        _actions(poison: 7),
      );
      expect(out.hunterMayShoot, isTrue);
    });

    test('獵人被刀但被守住 → 沒死，不能開槍', () {
      final out = arb.settle(_state(), _actions(guard: 7, wolf: 7));
      expect(out.deadSeats, isEmpty);
      expect(out.hunterMayShoot, isFalse);
    });

    test('獵人同守同救而死 → 可開槍（死因不是毒）', () {
      final out = arb.settle(_state(), _actions(guard: 7, wolf: 7, heal: 7));
      expect(out.deadSeats, [7]);
      expect(out.hunterMayShoot, isTrue);
    });
  });

  group('獵人開槍手勢（每晚叫起來確認）', () {
    test('未被毒 → 拇指向上（可開槍）', () {
      final s = _state();
      expect(arb.hunterCanShootTonight(s, _actions(wolf: 9)), isTrue);
    });

    test('今晚被毒 → 拇指向下（不可開槍）', () {
      final s = _state();
      expect(arb.hunterCanShootTonight(s, _actions(poison: 7)), isFalse);
    });

    test('別人被毒不影響獵人 → 仍可開槍', () {
      final s = _state();
      expect(arb.hunterCanShootTonight(s, _actions(poison: 9)), isTrue);
    });

    test('被狼刀但沒被毒 → 仍是可開槍（刀不影響技能）', () {
      final s = _state();
      expect(arb.hunterCanShootTonight(s, _actions(wolf: 7)), isTrue);
    });

    test('poisonedHunterCannotShoot = false → 被毒也可開槍', () {
      final s = _state(rules: const {'poisonedHunterCannotShoot': false});
      expect(arb.hunterCanShootTonight(s, _actions(poison: 7)), isTrue);
    });

    test('獵人已出局 → 不再需要手勢', () {
      final s = _state();
      s.playerAt(7).alive = false;
      expect(arb.hunterCanShootTonight(s, _actions()), isFalse);
    });

    test('手勢是預告狀態，與結算後的 hunterMayShoot 不同', () {
      final s = _state();
      final a = _actions(wolf: 9); // 獵人沒事
      // 手勢：獵人活著且沒被毒 → 給可開槍手勢
      expect(arb.hunterCanShootTonight(s, a), isTrue);
      // 結算：獵人沒死 → 不會真的開槍
      expect(arb.settle(s, a).hunterMayShoot, isFalse);
    });
  });

  // 狼王的槍與獵人不同：看的是**有沒有被自刀**，不是死因。
  // 狼隊自己知道有沒有自刀，所以狼王不需要每晚給手勢，白天起來直接發動。
  group('狼王開槍', () {
    test('被自刀出局 → 可以開槍', () {
      final s = _state();
      final o = arb.settle(s, _actions(wolf: 4)); // 4 號是狼王

      expect(o.wolfKingMayShoot, isTrue);
    });

    test('被自刀同時又被毒 → 仍可開槍', () {
      final s = _state();
      final o = arb.settle(s, _actions(wolf: 4, poison: 4));

      expect(_deathMap(o)[4], DeathCause.poison, reason: '死因記為毒');
      expect(o.wolfKingMayShoot, isTrue, reason: '但有被自刀，槍還在');
    });

    test('沒被自刀、只被毒死 → 不可開槍', () {
      final s = _state();
      final o = arb.settle(s, _actions(wolf: 9, poison: 4));

      expect(_deathMap(o)[4], DeathCause.poison);
      expect(o.wolfKingMayShoot, isFalse);
    });

    test('被自刀但被守衛守住 → 沒死，不能開槍', () {
      final s = _state();
      final o = arb.settle(s, _actions(guard: 4, wolf: 4));

      expect(o.wolfKingMayShoot, isFalse);
    });

    test('同守同救而死也算被自刀 → 可以開槍', () {
      final s = _state();
      final o = arb.settle(s, _actions(guard: 4, wolf: 4, heal: 4));

      expect(_deathMap(o)[4], DeathCause.guardHealConflict);
      expect(o.wolfKingMayShoot, isTrue);
    });

    test('狼王沒出局 → 不可開槍', () {
      final s = _state();

      expect(arb.settle(s, _actions(wolf: 9)).wolfKingMayShoot, isFalse);
    });

    test('狼王的槍與獵人的槍各自獨立', () {
      final s = _state();
      // 自刀狼王、毒獵人：狼王有槍，獵人被毒沒槍。
      final o = arb.settle(s, _actions(wolf: 4, poison: 7));

      expect(o.wolfKingMayShoot, isTrue);
      expect(o.hunterMayShoot, isFalse);
    });
  });

  // 白天要記開槍目標，得知道是誰開的 —— 獵人本人與學到槍牌的機械狼
  // 共用 hunterMayShoot，光看布林值分不出來。
  group('可以開槍的座次', () {
    test('獵人被刀 → 他自己', () {
      expect(arb.settle(_state(), _actions(wolf: 7)).shooterSeats, [7]);
    });

    test('獵人被毒 → 沒有人', () {
      expect(arb.settle(_state(), _actions(poison: 7)).shooterSeats, isEmpty);
    });

    test('狼王被自刀、獵人被毒 → 只有狼王', () {
      final o = arb.settle(_state(), _actions(wolf: 4, poison: 7));
      expect(o.shooterSeats, [4]);
    });

    test('兩位都能開 → 依座次排好', () {
      final o = arb.settle(
        _state(rules: const {'poisonedHunterCannotShoot': false}),
        _actions(wolf: 4, poison: 7),
      );
      expect(o.shooterSeats, [4, 7]);
    });
  });

  group('預言家查驗', () {
    test('查到狼人 → 查殺', () {
      final out = arb.settle(_state(), _actions(seer: 1));
      expect(out.seerSawWolf, isTrue);
    });

    test('查到狼王 → 也是查殺', () {
      final out = arb.settle(_state(), _actions(seer: 4));
      expect(out.seerSawWolf, isTrue);
    });

    test('查到平民 → 金水', () {
      final out = arb.settle(_state(), _actions(seer: 9));
      expect(out.seerSawWolf, isFalse);
    });

    test('查到神職 → 金水', () {
      final out = arb.settle(_state(), _actions(seer: 6));
      expect(out.seerSawWolf, isFalse);
    });
  });

  group('套用結果到狀態', () {
    test('死者標記為死亡、藥水消耗、守衛目標記錄', () {
      final s = _state();
      final a = _actions(guard: 10, wolf: 9, poison: 11, seer: 1);
      final out = arb.settle(s, a);
      arb.apply(s, a, out);

      expect(s.playerAt(9).alive, isFalse);
      expect(s.playerAt(11).alive, isFalse);
      expect(s.playerAt(10).alive, isTrue);
      expect(s.aliveCount, 10);
      expect(s.witchPoisonAvailable, isFalse);
      expect(s.witchAntidoteAvailable, isTrue, reason: '本夜未用解藥');
      expect(s.lastGuardTarget, 10);
    });

    test('查驗結果寫成資訊標記', () {
      final s = _state();
      final a = _actions(seer: 1);
      arb.apply(s, a, arb.settle(s, a));
      expect(s.playerAt(1).infoTags, contains(InfoTag.verifiedWolf));

      final a2 = _actions(seer: 9);
      arb.apply(s, a2, arb.settle(s, a2));
      expect(s.playerAt(9).infoTags, contains(InfoTag.verifiedGood));
    });

    test('事實標記每晚重算，不會累積到下一夜', () {
      final s = _state();
      final a1 = _actions(wolf: 9);
      arb.apply(s, a1, arb.settle(s, a1));
      expect(s.playerAt(9).nightFacts, contains(FactTag.knifed));

      final a2 = _actions(night: 2, wolf: 10);
      arb.apply(s, a2, arb.settle(s, a2));
      expect(s.playerAt(9).nightFacts, isEmpty, reason: '前一夜的標記應已清除');
      expect(s.playerAt(10).nightFacts, contains(FactTag.knifed));
    });
  });

  group('守衛不可連守同一人', () {
    test('前一晚守過的人，本晚不可再守', () {
      final s = _state();
      final a = _actions(guard: 9, wolf: 10);
      arb.apply(s, a, arb.settle(s, a));

      expect(arb.guardMayProtect(s, 9), isFalse);
      expect(arb.guardMayProtect(s, 11), isTrue);
    });

    test('guardCannotRepeatTarget = false 時允許連守', () {
      final s = _state(rules: const {'guardCannotRepeatTarget': false});
      final a = _actions(guard: 9);
      arb.apply(s, a, arb.settle(s, a));
      expect(arb.guardMayProtect(s, 9), isTrue);
    });
  });
}
