import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/engine/night_flow.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 12 人狼美騎士局：3狼 + 狼美人 + 預女守騎 + 4民。
Preset _preset({Map<String, dynamic>? rules}) => Preset.fromJson(
      {
        'presetId': 'langmei_qishi',
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
      sourceName: 'langmei_qishi.json',
    );

/// 固定座位配置，方便測試閱讀：
/// 1-3 狼、4 狼美人、5 預言家、6 女巫、7 守衛、8 騎士、9-12 平民。
GameState _state({Map<String, dynamic>? rules}) {
  final s = GameState(preset: _preset(rules: rules));
  void set(int seat, Role role) => s.playerAt(seat).role = role;
  set(1, Roles.wolf);
  set(2, Roles.wolf);
  set(3, Roles.wolf);
  set(4, Roles.wolfBeauty);
  set(5, Roles.seer);
  set(6, Roles.witch);
  set(7, Roles.guard);
  set(8, Roles.knight);
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
  int? charm,
}) =>
    NightActions(night: night)
      ..guardTarget = guard
      ..wolfTarget = wolf
      ..witchHealTarget = heal
      ..witchPoisonTarget = poison
      ..wolfBeautyCharmTarget = charm;

const _arb = NightArbitrator();

/// 座次 -> 死因，方便斷言。
Map<int, DeathCause> _deathMap(NightOutcome o) => {
      for (final d in o.deaths) d.seat: d.cause,
    };

void main() {
  group('狼美人殉情', () {
    test('狼美人被毒死 → 被魅惑者殉情', () {
      final s = _state();
      final o = _arb.settle(s, _actions(wolf: 9, poison: 4, charm: 10));

      expect(_deathMap(o)[4], DeathCause.poison);
      expect(_deathMap(o)[10], DeathCause.loveSuicide,
          reason: '狼美人出局，被魅惑的 10 號殉情');
      expect(o.charmSuicideSeat, 10);
    });

    test('狼美人存活 → 不殉情', () {
      final s = _state();
      final o = _arb.settle(s, _actions(wolf: 9, charm: 10));

      expect(_deathMap(o).keys, [9]);
      expect(o.charmSuicideSeat, isNull);
    });

    test('本晚未重新魅惑 → 沿用前一晚的魅惑對象', () {
      final s = _state()..charmedSeat = 11;
      final o = _arb.settle(s, _actions(night: 2, wolf: 9, poison: 4));

      expect(_deathMap(o)[11], DeathCause.loveSuicide);
      expect(o.charmSuicideSeat, 11);
    });

    test('被魅惑者本夜已因他故死亡 → 不重複記死因', () {
      final s = _state();
      // 10 號同時被狼刀與被魅惑，狼美人又被毒死。
      final o = _arb.settle(s, _actions(wolf: 10, poison: 4, charm: 10));

      expect(_deathMap(o)[10], DeathCause.wolfKill, reason: '死因維持狼刀，不改記殉情');
      expect(o.charmSuicideSeat, isNull);
      expect(o.notes.any((n) => n.contains('已另因他故死亡')), isTrue);
    });

    test('被魅惑者被守衛守住，但狼美人死了 → 仍然殉情（守衛防不了殉情）', () {
      final s = _state();
      final o = _arb.settle(s, _actions(guard: 10, wolf: 9, poison: 4, charm: 10));

      expect(_deathMap(o)[10], DeathCause.loveSuicide);
    });

    test('殉情者是獵人 → 可以開槍（死因不是毒）', () {
      final s = _state();
      // 把 9 號平民換成獵人，測殉情後的開槍資格。
      s.playerAt(9).role = Roles.hunter;
      final o = _arb.settle(s, _actions(wolf: 11, poison: 4, charm: 9));

      expect(_deathMap(o)[9], DeathCause.loveSuicide);
      expect(o.hunterMayShoot, isTrue);
    });
  });

  group('魅惑的輸入限制', () {
    test('不可連續兩晚魅惑同一人', () {
      final s = _state()..lastCharmTarget = 10;

      expect(_arb.wolfBeautyMayCharm(s, 10), isFalse);
      expect(_arb.wolfBeautyMayCharm(s, 11), isTrue);
    });

    test('charmCannotRepeatTarget = false 時允許連續魅惑', () {
      final s = _state(rules: {'charmCannotRepeatTarget': false})
        ..lastCharmTarget = 10;

      expect(_arb.wolfBeautyMayCharm(s, 10), isTrue);
    });

    test('狼美人不能自刀', () {
      final s = _state();

      expect(_arb.wolfMayKnife(s, 4), isFalse, reason: '4 號是狼美人');
      expect(_arb.wolfMayKnife(s, 1), isTrue, reason: '一般狼可以被自刀');
    });

    test('wolfBeautyCannotSelfKill = false 時可以自刀', () {
      final s = _state(rules: {'wolfBeautyCannotSelfKill': false});

      expect(_arb.wolfMayKnife(s, 4), isTrue);
    });
  });

  group('套用結果到狀態', () {
    test('魅惑對象寫入狀態並沿用到下一夜', () {
      final s = _state();
      final a = _actions(wolf: 9, charm: 10);
      _arb.apply(s, a, _arb.settle(s, a));

      expect(s.charmedSeat, 10);
      expect(s.lastCharmTarget, 10);
    });

    test('本晚沒重新魅惑時，charmedSeat 維持不變', () {
      final s = _state()..charmedSeat = 11;
      final a = _actions(night: 2, wolf: 9);
      _arb.apply(s, a, _arb.settle(s, a));

      expect(s.charmedSeat, 11, reason: '沒指定新對象就沿用');
      expect(s.lastCharmTarget, isNull, reason: '本晚沒魅惑，隔晚就沒有連魅限制');
    });

    test('深拷貝要帶上狼美人的欄位，否則撤銷會壞掉', () {
      final s = _state()
        ..charmedSeat = 10
        ..lastCharmTarget = 10;
      final snapshot = s.copy();
      s.charmedSeat = 11;

      expect(snapshot.charmedSeat, 10);
      expect(snapshot.lastCharmTarget, 10);
    });
  });

  group('夜晚步驟（狼美騎士）', () {
    test('狼美人與狼隊一起登記，之後單獨睜眼魅惑', () {
      final steps = NightFlow.firstNightSteps(_preset());
      final titles = steps.map((s) => s.title).toList();

      expect(titles, ['守衛', '狼人', '狼美人', '女巫', '預言家', '騎士']);

      final wolfStep = steps[1];
      expect(wolfStep.seatCount, 4, reason: '3 狼 + 狼美人一起登記');
      expect(wolfStep.specialPicks.map((r) => r.id), [Roles.wolfBeauty.id],
          reason: '登記完要指認哪一位是狼美人');

      final charmStep = steps[2];
      expect(charmStep.skill, NightSkill.charm);
      expect(charmStep.seatCount, 0, reason: '座次已在狼隊步驟登記過');
    });

    test('騎士只登記，沒有夜間行動', () {
      final steps = NightFlow.firstNightSteps(_preset());
      final knight = steps.firstWhere((s) => s.title == '騎士');

      expect(knight.skill, NightSkill.none);
      expect(knight.seatCount, 1);
    });

    test('第二夜起騎士不再出現，狼美人仍要魅惑', () {
      final s = _state();
      final titles =
          NightFlow.laterNightStepsFor(s, night: 2).map((e) => e.title).toList();

      expect(titles, ['守衛', '狼人', '狼美人', '女巫', '預言家']);
    });
  });
}
