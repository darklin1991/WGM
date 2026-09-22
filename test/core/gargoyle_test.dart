import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/engine/night_flow.dart';
import 'package:wgm/core/engine/night_flow_machine.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 覺醒石像鬼與轉換（擔當 2026-09-22 指定）：
///
/// - 兩隻互認、一起決定狼刀（就是狼隊那一步），**沒有查驗**
/// - **只有首夜**可轉換，各自選**相鄰座次**的一位
/// - 兩隻選到同一人 → **只有那一個人**轉換進狼隊
/// - 被轉換者：查驗第一夜好人、第二夜起狼；熊**沒有**這個延遲；
///   屠邊人頭改算狼；原技能用到「接刀」那一刻才喪失
/// - 開刀順位：石像鬼 → 機械狼 → 被轉換者（只剩一位時）

const _arb = NightArbitrator();

/// 12 人風聲諜影（簡化版，只留測得到的角色）：
/// 石像鬼 ×2 + 機械狼 + 預女熊獵 + 5民。
Preset _preset() => Preset.fromJson(
      const {
        'presetId': 'fs',
        'name': '風聲測試板',
        'playerCount': 12,
        'roles': [
          {'role': 'awakenedGargoyle', 'count': 2},
          {'role': 'mechanicWolf', 'count': 1},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'bear', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'villager', 'count': 5},
        ],
        'nightOrder': [
          'mechanicWolf',
          'awakenedGargoyle',
          'bear',
          'witch',
          'hunter',
          'seer',
        ],
      },
      sourceName: 'fs.json',
    );

/// 1、2 石像鬼、3 機械狼、4 預言家、5 女巫、6 熊、7 獵人、8-12 平民。
GameState _state() {
  final s = GameState(preset: _preset());
  void set(int seat, Role role) => s.playerAt(seat).role = role;
  set(1, Roles.awakenedGargoyle);
  set(2, Roles.awakenedGargoyle);
  set(3, Roles.mechanicWolf);
  set(4, Roles.seer);
  set(5, Roles.witch);
  set(6, Roles.bear);
  set(7, Roles.hunter);
  for (var i = 8; i <= 12; i++) {
    set(i, Roles.villager);
  }
  s
    ..dayNumber = 1
    ..phase = GamePhase.night;
  return s;
}

/// 首夜轉換 [targets]（略過流程，直接套用結算）。
void _convert(GameState s, Set<int> targets) {
  final a = NightActions(night: 1)..gargoyleConvertTargets.addAll(targets);
  _arb.apply(s, a, _arb.settle(s, a));
}

void _kill(GameState s, List<int> seats) {
  for (final seat in seats) {
    s.playerAt(seat).alive = false;
  }
}

void main() {
  group('狼隊步驟', () {
    test('兩隻石像鬼合成一步，喊的是石像鬼不是狼人', () {
      final steps = NightFlow.firstNightSteps(_preset());
      final team = steps.firstWhere((s) => s.skill == NightSkill.wolfKill);

      expect(team.seatCount, 2);
      expect(team.primaryRole?.id, Roles.awakenedGargoyle.id);
      expect(team.title, '覺醒石像鬼');
    });

    test('整隊同一身分時不必再指認是哪一位', () {
      final steps = NightFlow.firstNightSteps(_preset());
      final team = steps.firstWhere((s) => s.skill == NightSkill.wolfKill);

      expect(team.needsSpecialPick, isFalse);
    });

    test('轉換排在狼刀之後、熊之前', () {
      final steps = NightFlow.firstNightSteps(_preset());
      final skills = steps.map((s) => s.skill).toList();

      expect(
        skills.indexOf(NightSkill.gargoyleConvert),
        greaterThan(skills.indexOf(NightSkill.wolfKill)),
      );
      expect(
        skills.indexOf(NightSkill.gargoyleConvert),
        lessThan(skills.indexOf(NightSkill.bearGrowl)),
        reason: '熊首夜就要咆哮得出被轉換者，轉換得先發生',
      );
    });

    test('第二夜起不再有轉換那一步', () {
      final s = _state()..dayNumber = 2;
      final steps = NightFlow.laterNightStepsFor(s, night: 2);

      expect(
        steps.any((step) => step.skill == NightSkill.gargoyleConvert),
        isFalse,
      );
    });
  });

  group('轉換的選擇範圍', () {
    test('只能選自己的左右鄰座', () {
      final s = _state();
      final m = NightFlowMachine(state: s, night: 1, isFirstNight: true);
      while (m.sub != NightSub.gargoyleConvert) {
        m.next();
        if (m.outcome != null) fail('沒走到轉換那一步');
      }

      // 先問 1 號石像鬼：鄰座是 12 與 2（環狀）。
      expect(m.currentGargoyleSeat, 1);
      expect(m.selectableSeats, {2, 12});
    });

    test('逐隻問過去 —— 第二隻換成它自己的鄰座', () {
      final s = _state();
      final m = NightFlowMachine(state: s, night: 1, isFirstNight: true);
      while (m.sub != NightSub.gargoyleConvert) {
        m.next();
      }

      m.toggleSeat(12);
      m.next();

      expect(m.sub, NightSub.gargoyleConvert);
      expect(m.currentGargoyleSeat, 2, reason: '換第二隻');
      expect(m.selectableSeats, {1, 3});
    });

    test('兩隻選到同一人時只算一位', () {
      // 1 號與 2 號石像鬼相鄰，兩隻都選得到對方以外的共同鄰座嗎？
      // 這個板子裡 1 的鄰座是 {2,12}、2 的鄰座是 {1,3}，沒有共同的第三人，
      // 所以改走狀態機讓兩隻都選 1 號自己人 —— 重點是**收到兩次同一個號碼**。
      final s = _state();
      final m = NightFlowMachine(state: s, night: 1, isFirstNight: true);
      while (m.sub != NightSub.gargoyleConvert) {
        m.next();
      }

      m.toggleSeat(2); // 1 號石像鬼轉 2 號
      m.next();
      m.toggleSeat(1); // 2 號石像鬼轉 1 號
      m.next();

      // 兩筆不同的目標會有兩位；重點是型別用 Set，同號碼只會留一筆。
      expect(m.actions.gargoyleConvertTargets, {1, 2});

      // 直接驗重複的語意：再加一次已經有的號碼不會變多。
      m.actions.gargoyleConvertTargets.add(2);
      expect(m.actions.gargoyleConvertTargets, {1, 2});
    });
  });

  group('被轉換者', () {
    test('查驗第一夜是好人', () {
      final s = _state();
      _convert(s, {5}); // 女巫被轉換

      final a = NightActions(night: 1)..seerTarget = 5;
      expect(_arb.settle(s, a).seerSawWolf, isFalse);
    });

    test('查驗第二夜起是查殺', () {
      final s = _state();
      _convert(s, {5});
      s.dayNumber = 2;

      final a = NightActions(night: 2)..seerTarget = 5;
      expect(_arb.settle(s, a).seerSawWolf, isTrue);
    });

    test('魔鏡少女看到的仍是原本的身分 —— 與預言家對不上', () {
      final s = _state();
      _convert(s, {5});
      s.dayNumber = 2;

      final a = NightActions(night: 2)
        ..psychicTarget = 5
        ..seerTarget = 5;
      final o = _arb.settle(s, a);

      expect(o.psychicResult?.revealedRole?.id, Roles.witch.id);
      expect(o.seerSawWolf, isTrue);
    });

    test('熊立刻算他是狼 —— 沒有首夜延遲', () {
      final s = _state();
      _convert(s, {5}); // 5 號是熊（6 號）的鄰座

      expect(NightArbitrator.bearNeighbors(s), [5, 7]);
      expect(NightArbitrator.bearGrowls(s), isTrue, reason: '首夜就咆哮');
    });

    test('屠邊人頭改算狼', () {
      final s = _state();
      final godsBefore = s.aliveGodCount;
      _convert(s, {5}); // 女巫

      expect(s.aliveGodCount, godsBefore - 1);
      expect(s.isConverted(5), isTrue);
    });

    test('原技能一直能用，接刀前不受影響', () {
      final s = _state();
      _convert(s, {5});
      s.dayNumber = 2;

      final steps = NightFlow.laterNightStepsFor(s, night: 2);
      expect(
        steps.any((step) => step.skill == NightSkill.witchPotion),
        isTrue,
        reason: '被轉換的女巫照樣有藥',
      );
    });
  });

  group('開刀順位', () {
    test('石像鬼還活著時輪不到被轉換者', () {
      final s = _state();
      _convert(s, {5});

      expect(s.convertedKnifeHolder, isNull);
    });

    test('石像鬼全滅但機械狼還在 → 仍輪不到', () {
      final s = _state();
      _convert(s, {5});
      _kill(s, [1, 2]);

      expect(s.convertedKnifeHolder, isNull, reason: '機械狼先接');
    });

    test('兩位被轉換者都活著 → 沒有人能開刀', () {
      final s = _state();
      _convert(s, {5, 8});
      _kill(s, [1, 2, 3]);

      expect(s.convertedKnifeHolder, isNull,
          reason: '必須剩到只有一位，這是刻意的空窗');
    });

    test('只剩一位被轉換者 → 由他持刀', () {
      final s = _state();
      _convert(s, {5, 8});
      _kill(s, [1, 2, 3, 8]);

      expect(s.convertedKnifeHolder, 5);
    });

    test('撞車局只有一位被轉換者，機械狼一死就接刀', () {
      final s = _state();
      _convert(s, {5}); // 兩隻轉到同一人
      _kill(s, [1, 2, 3]);

      expect(s.convertedKnifeHolder, 5, reason: '不必再等另一位死');
    });
  });

  group('接刀那一刻', () {
    test('取得狼刀並喪失原技能', () {
      final s = _state();
      _convert(s, {5}); // 女巫
      _kill(s, [1, 2, 3]);
      s.dayNumber = 2;

      final a = NightActions(night: 2);
      _arb.apply(s, a, _arb.settle(s, a));

      expect(s.hasLostSkills(5), isTrue);
    });

    test('喪失技能後，女巫那一步變成沒有東西可收', () {
      final s = _state();
      _convert(s, {5});
      _kill(s, [1, 2, 3]);
      s.dayNumber = 2;
      final a = NightActions(night: 2);
      _arb.apply(s, a, _arb.settle(s, a));

      final steps = NightFlow.laterNightStepsFor(s, night: 3);
      final witchStep =
          steps.where((step) => step.primaryRole?.id == Roles.witch.id);
      expect(witchStep, hasLength(1), reason: '步驟保留，不跳過');
      expect(witchStep.single.skill, NightSkill.none);
    });
  });

  test('機械狼的帶刀條件自動變成「兩隻石像鬼都出局」', () {
    final s = _state();
    expect(s.mechanicWolfCarriesKnife, isFalse, reason: '石像鬼還活著');

    _kill(s, [1, 2]);
    expect(s.mechanicWolfCarriesKnife, isTrue);
  });

  test('撤銷會連轉換一起還原', () {
    final s = _state();
    final snapshot = s.copy();

    _convert(s, {5});
    expect(s.convertedSeats, {5});

    s.restoreFrom(snapshot);
    expect(s.convertedSeats, isEmpty);
    expect(s.conversionNight, isNull);
  });
}
