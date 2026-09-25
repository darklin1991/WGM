import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/engine/night_flow.dart';
import 'package:wgm/core/engine/night_flow_machine.dart';
import 'package:wgm/core/engine/vote_resolver.dart';
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

  // 擔當 2026-09-25 指定：一定轉換兩位，不會撞車。
  group('轉換的選擇範圍', () {
    /// 兩隻石像鬼隔一個座位（1、3 號），共用鄰座 2 號 —— 才測得到撞車。
    /// 1 石像鬼、2 平民、3 石像鬼、4 預言家、5 女巫、6 熊、7 獵人、8 機械狼、
    /// 9-12 平民。
    GameState spread() {
      final s = _state();
      s.playerAt(2).role = Roles.villager;
      s.playerAt(3).role = Roles.awakenedGargoyle;
      s.playerAt(8).role = Roles.mechanicWolf;
      return s;
    }

    NightFlowMachine walkToConvert(GameState s) {
      final m = NightFlowMachine(state: s, night: 1, isFirstNight: true);
      for (var i = 0; i < 20 && m.sub != NightSub.gargoyleConvert; i++) {
        m.next();
      }
      if (m.sub != NightSub.gargoyleConvert) fail('沒走到轉換那一步');
      return m;
    }

    // 擔當 2026-09-25 指定：可以選另一隻石像鬼旁邊的位置。
    test('兩隻石像鬼的左右鄰座都能選', () {
      final m = walkToConvert(spread());

      // 先問 1 號石像鬼：自己的鄰座 12、2，加上 3 號石像鬼的鄰座 2、4。
      expect(m.currentGargoyleSeat, 1);
      expect(m.selectableSeats, {2, 4, 12});
    });

    test('可以轉換只挨著另一隻的人', () {
      final m = walkToConvert(spread());
      m.toggleSeat(4); // 4 號只挨著 3 號石像鬼
      m.next();

      expect(m.actions.gargoyleConvertTargets, {4});
    });

    test('範圍以外的人選不到', () {
      final m = walkToConvert(spread());
      m.toggleSeat(7);

      expect(m.picked, isEmpty);
    });

    test('第二隻選不到第一隻轉換過的人 —— 不會撞車', () {
      final m = walkToConvert(spread());
      m.toggleSeat(2); // 1 號石像鬼轉 2 號
      m.next();

      expect(m.currentGargoyleSeat, 3, reason: '換第二隻');
      expect(m.selectableSeats, {4, 12}, reason: '範圍 {2, 4, 12} 扣掉已轉換的 2');
      expect(m.blockedSeats?[2], SeatBlockReason.alreadyConverted);

      m.toggleSeat(2);
      expect(m.picked, isEmpty, reason: '擋在引擎');
      m.toggleSeat(4);
      m.next();
      expect(m.actions.gargoyleConvertTargets, {2, 4});
    });

    test('一定要轉換 —— 沒選就不能往下', () {
      final m = walkToConvert(spread());

      expect(m.canProceed, isFalse);
      m.next();
      expect(m.currentGargoyleSeat, 1, reason: '還停在第一隻');
    });

    // 擔當 2026-09-25 指定：只擋石像鬼自己人，機械狼可以被選。
    // 石像鬼與機械狼互不相認，擋掉那一格等於告訴石像鬼「這個人是狼」。
    test('石像鬼不能轉換石像鬼；機械狼不擋', () {
      // 原本的座位：1、2 石像鬼相鄰，3 機械狼。範圍是 12、1、2、3。
      final m = walkToConvert(_state());

      expect(m.selectableSeats, {3, 12});
      expect(m.blockedSeats, {
        1: SeatBlockReason.convertGargoyle,
        2: SeatBlockReason.convertGargoyle,
      });
    });

    test('選到機械狼 → 轉換悄悄白費，不記成轉換者', () {
      final s = _state();
      final m = walkToConvert(s);
      m.toggleSeat(12);
      m.next();
      m.toggleSeat(3); // 2 號石像鬼選了機械狼
      m.next();

      expect(m.actions.gargoyleConvertTargets, {3, 12}, reason: '選了誰照記');
      expect(m.convertedTonight, {12}, reason: '實際生效的只有 12 號');

      while (!m.finished) {
        m.next();
      }
      expect(s.convertedSeats, {12});
      expect(s.isConverted(3), isFalse);
      expect(
        s.log.entries.map((e) => e.text),
        containsAll(['石像鬼轉換 12 號（平民）', '石像鬼選了 3 號（機械狼），轉換無效']),
      );
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

    // 上一項是先 apply 再問熊，實際流程不是這樣 —— 首夜的轉換要到整夜收完
    // 才結算，熊那一步排在轉換之後、結算之前，只看 state 會看不到。
    test('走實際流程：熊那一步就看得到剛發生的轉換', () {
      final s = _state();
      s.playerAt(6).role = Roles.villager;
      s.playerAt(11).role = Roles.bear; // 鄰座 10、12
      final m = NightFlowMachine(state: s, night: 1, isFirstNight: true);

      for (var i = 0; i < 30 && m.sub != NightSub.bearGrowl; i++) {
        // 1 號石像鬼轉 12 號；2 號石像鬼只剩 3 號機械狼可選（轉換白費）。
        if (m.sub == NightSub.gargoyleConvert) {
          m.toggleSeat(12);
          if (m.picked.isEmpty) m.toggleSeat(3);
        }
        m.next();
      }
      if (m.sub != NightSub.bearGrowl) fail('沒走到熊那一步');

      expect(m.convertedTonight, {12});
      expect(s.isConverted(12), isFalse, reason: '還沒結算');
      expect(m.bearNeighbors, [10, 12]);
      expect(m.bearGrowls, isTrue, reason: '轉換當晚熊就咆哮');
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

  // 「轉換」發生在接刀那一刻，同時喪失尚未使用的原技能（擔當 2026-09-22 指定）。
  group('接刀之後喪失原技能', () {
    /// 5 號女巫被轉換，石像鬼與機械狼都出局 —— 今晚由她接刀。
    GameState knifeTonight({int converted = 5}) {
      final s = _state();
      s.convertedSeats.add(converted);
      s.conversionNight = 1;
      _kill(s, [1, 2, 3]);
      s.dayNumber = 2;
      return s;
    }

    NightFlowMachine walkToRole(GameState s, String roleId) {
      final m = NightFlowMachine(state: s, night: s.dayNumber, isFirstNight: false);
      while (m.step.primaryRole?.id != roleId) {
        m.next();
        if (m.finished) fail('沒走到 $roleId');
      }
      return m;
    }

    test('接刀的那一夜，原技能那一步就是走過場', () {
      final s = knifeTonight();
      expect(s.hasLostSkills(5), isFalse, reason: '還沒結算');

      final m = walkToRole(s, Roles.witch.id);
      expect(m.sub, NightSub.passThrough, reason: '藥已經失效');
      expect(m.isLostSkillsStep, isTrue);
      expect(m.selectableSeats, isEmpty);
    });

    test('之後每一夜也是走過場，不是全員可點的選座頁', () {
      final s = knifeTonight()..dayNumber = 3;
      s.convertedActivatedSeats.add(5);

      final m = walkToRole(s, Roles.witch.id);
      expect(m.sub, NightSub.passThrough);
      expect(m.selectableSeats, isEmpty);
    });

    test('接刀之前原技能照常能用', () {
      final s = knifeTonight();
      s.playerAt(3).alive = true; // 機械狼還活著，輪不到被轉換者

      final m = walkToRole(s, Roles.witch.id);
      expect(m.sub, NightSub.witchPotion);
      expect(m.isLostSkillsStep, isFalse);
    });

    test('今晚接刀的獵人死了也不能開槍', () {
      final s = knifeTonight(converted: 7);
      final a = NightActions(night: 2)..witchPoisonTarget = 7;
      final o = _arb.settle(s, a);

      expect(o.hunterMayShoot, isFalse);
      expect(o.shooterSeats, isEmpty);
      expect(o.notes, contains('獵人（7 號）已轉換進狼隊，槍已失效'));
    });

    test('已接刀的獵人被放逐也不能開槍', () {
      final s = knifeTonight(converted: 7)
        ..dayNumber = 3
        ..phase = GamePhase.day;
      s.convertedActivatedSeats.add(7);

      final v = ExileVote(state: s)..focusTarget(7);
      for (final voter in [4, 5, 6]) {
        v.toggleVote(voter);
      }
      v.next();

      expect(v.stage, isNot(ExileStage.shoot));
      // 宣布稿是法官照著念的 —— 念出「已轉換進狼隊」等於當眾公布誰是狼。
      expect(v.notes.where((n) => n.contains('轉換')), isEmpty);
      expect(
        s.log.entries.map((e) => e.text),
        contains('7 號（被轉換的獵人）已接刀，槍已失效，不能開槍'),
        reason: '只記進日誌給法官復盤',
      );
    });

    test('還沒接刀的被轉換獵人被放逐，照樣能開槍', () {
      final s = _state()
        ..dayNumber = 2
        ..phase = GamePhase.day;
      s.convertedSeats.add(7);
      s.conversionNight = 1;

      final v = ExileVote(state: s)..focusTarget(7);
      for (final voter in [4, 5, 6]) {
        v.toggleVote(voter);
      }
      v.next();

      expect(v.stage, ExileStage.shoot);
    });
  });

  // 規格：「第一夜的最後增加叫人環節，由法官告知本人 ——『第一位轉換者請睜眼』」。
  group('首夜最後告知被轉換者', () {
    NightFlowMachine walkToNotify(GameState s, {Set<int> convert = const {}}) {
      final m = NightFlowMachine(state: s, night: 1, isFirstNight: true);
      for (var i = 0; i < 50 && m.sub != NightSub.convertedNotify; i++) {
        if (m.sub == NightSub.gargoyleConvert) {
          final target =
              convert.where((t) => m.selectableSeats?.contains(t) ?? false);
          if (target.isNotEmpty) m.toggleSeat(target.first);
        }
        m.next();
      }
      if (m.sub != NightSub.convertedNotify) fail('沒走到告知那一步');
      return m;
    }

    /// 1、3 號石像鬼（見「轉換的選擇範圍」），兩隻各有能轉換的鄰座。
    GameState spread() {
      final s = _state();
      s.playerAt(2).role = Roles.villager;
      s.playerAt(3).role = Roles.awakenedGargoyle;
      s.playerAt(8).role = Roles.mechanicWolf;
      return s;
    }

    test('排在整夜的最後，機械狼結尾那一輪之後', () {
      final skills = NightFlow.firstNightSteps(_preset()).map((s) => s.skill);
      expect(skills.last, NightSkill.convertedNotify);
      expect(
        skills.toList().indexOf(NightSkill.mechanicReveal),
        skills.length - 2,
      );
    });

    test('第二夜起沒有這一步', () {
      final s = _state()..dayNumber = 2;
      final steps = NightFlow.laterNightStepsFor(s, night: 2);
      expect(steps.any((x) => x.skill == NightSkill.convertedNotify), isFalse);
    });

    test('逐位叫醒，一格一位', () {
      final m = walkToNotify(spread(), convert: {12, 4});

      expect(m.convertedTonight, {4, 12});
      expect(m.convertedNotifySlots, 2);
      expect(m.convertedNotifyOrdinal, 1);
      expect(m.convertedNotifySeat, 4);
      expect(m.requiredPickCount, 0);

      m.next();
      expect(m.convertedNotifyOrdinal, 2);
      expect(m.convertedNotifySeat, 12);

      m.next();
      expect(m.finished, isTrue);
    });

    // 一定各選一位；只有選到機械狼（轉換悄悄白費）時才會少一位轉換者。
    test('第二隻選到機械狼 → 還是叫兩次，第二格沒有人', () {
      final m = walkToNotify(_state(), convert: {12, 3});

      expect(m.convertedNotifySeat, 12);
      m.next();
      expect(m.sub, NightSub.convertedNotify, reason: '少喊一次就露餡');
      expect(m.convertedNotifySeat, isNull, reason: '不能叫醒機械狼說他被轉換了');
      m.next();
      expect(m.finished, isTrue);
    });

    test('撤銷會退回上一格', () {
      final m = walkToNotify(_state(), convert: {12, 3});
      m.next();
      expect(m.convertedNotifyOrdinal, 2);

      m.undo();
      expect(m.convertedNotifyOrdinal, 1);
      expect(m.convertedNotifySeat, 12);
    });

    test('沒有石像鬼的板子沒有這一步', () {
      final p = Preset.fromJson(
        const {
          'presetId': 'plain',
          'name': '預女獵白',
          'playerCount': 12,
          'roles': [
            {'role': 'wolf', 'count': 4},
            {'role': 'seer', 'count': 1},
            {'role': 'witch', 'count': 1},
            {'role': 'hunter', 'count': 1},
            {'role': 'idiot', 'count': 1},
            {'role': 'villager', 'count': 4},
          ],
          'nightOrder': ['wolf', 'witch', 'seer'],
        },
        sourceName: 'plain.json',
      );
      final skills = NightFlow.firstNightSteps(p).map((s) => s.skill);
      expect(skills, isNot(contains(NightSkill.convertedNotify)));
    });
  });

  // 擔當 2026-09-25 指定：第二夜起在狼隊之前（守衛的位置）叫轉換者比開刀手勢。
  // 被轉換者不與任何人相認，不知道石像鬼與機械狼死光了沒，有沒有刀只有法官知道。
  group('第二夜起轉換者的開刀手勢', () {
    /// 5、12 號被轉換（12 是 1 號石像鬼的鄰座，5 直接指定）。
    GameState converted({Set<int> seats = const {5, 12}}) {
      final s = _state();
      s.convertedSeats.addAll(seats);
      s.conversionNight = 1;
      s.dayNumber = 2;
      return s;
    }

    NightFlowMachine walkToTurn(GameState s) {
      final m = NightFlowMachine(state: s, night: s.dayNumber, isFirstNight: false);
      while (m.sub != NightSub.convertedKnifeGesture) {
        m.next();
        if (m.finished) fail('沒走到轉換者那一輪');
      }
      return m;
    }

    test('排在狼隊之前；首夜沒有', () {
      final later = NightFlow.laterNightStepsFor(converted(), night: 2)
          .map((s) => s.skill)
          .toList();
      final turn = later.indexOf(NightSkill.convertedTurn);
      expect(turn, isNonNegative);
      expect(later[turn + 1], NightSkill.wolfKill);

      final first = NightFlow.firstNightSteps(_preset()).map((s) => s.skill);
      expect(first, isNot(contains(NightSkill.convertedTurn)));
    });

    test('實際的風聲諜影：攝夢人之後、石像鬼之前', () {
      final json = jsonDecode(
        File('assets/presets/12p_fengsheng_dieying.json').readAsStringSync(),
      ) as Map;
      final preset = Preset.fromJson(
        json.cast<String, dynamic>(),
        sourceName: '12p_fengsheng_dieying.json',
      );
      final s = GameState(preset: preset)..dayNumber = 2;
      var seat = 1;
      for (final slot in preset.roles) {
        for (var i = 0; i < slot.count; i++) {
          s.playerAt(seat++).role = slot.role;
        }
      }

      final titles = NightFlow.laterNightStepsFor(s, night: 2)
          .map((x) => x.title)
          .toList();
      final turn = titles.indexOf('轉換者');
      expect(titles[turn - 1], '攝夢人');
      expect(titles[turn + 1], '覺醒石像鬼');
    });

    test('石像鬼還活著 → 兩位都比「沒刀」，狼刀照常由石像鬼開', () {
      final m = walkToTurn(converted());

      expect(m.convertedTurnOrdinal, 1);
      expect(m.convertedTurnSeat, 5);
      expect(m.convertedTurnHasKnife, isFalse);
      expect(m.requiredPickCount, 0);

      m.next();
      expect(m.convertedTurnOrdinal, 2);
      expect(m.convertedTurnSeat, 12);
      expect(m.convertedTurnHasKnife, isFalse);

      m.next();
      expect(m.effectiveSkill, NightSkill.wolfKill);
      expect(m.sub, NightSub.chooseTarget);
    });

    test('只剩一位轉換者 → 他在這一輪開刀，狼隊那一格走過場', () {
      final s = converted(seats: {5});
      _kill(s, [1, 2, 3]);
      final m = walkToTurn(s);

      expect(m.convertedTurnSeat, 5);
      expect(m.convertedTurnHasKnife, isTrue);
      m.next();
      expect(m.sub, NightSub.convertedKnife);
      m.toggleSeat(9);
      m.next();

      // 第二格沒有人（只轉換了一位），照樣叫。
      expect(m.sub, NightSub.convertedKnifeGesture);
      expect(m.convertedTurnSeat, isNull);
      m.next();

      expect(m.effectiveSkill, NightSkill.wolfKill);
      expect(m.sub, NightSub.passThrough, reason: '刀已經在轉換者那一輪開過');

      while (!m.finished) {
        m.next();
      }
      expect(m.outcome!.deadSeats, contains(9));
    });

    test('出局的轉換者照樣佔一格，照樣叫', () {
      final s = converted();
      _kill(s, [1, 2, 3, 12]); // 12 號出局 → 只剩 5 號，由他開刀
      final m = walkToTurn(s);

      expect(m.convertedTurnSeat, 5);
      expect(m.convertedTurnHasKnife, isTrue);
      m.next(); // 刀口
      m.next(); // 空刀

      expect(m.sub, NightSub.convertedKnifeGesture);
      expect(m.convertedTurnSeat, 12);
      expect(m.convertedTurnSeatAlive, isFalse);
    });

    test('兩位都還活著、其他狼都出局 → 兩位都沒刀（空刀）', () {
      final s = converted();
      _kill(s, [1, 2, 3]);
      final m = walkToTurn(s);

      expect(m.convertedTurnHasKnife, isFalse);
      m.next();
      expect(m.convertedTurnHasKnife, isFalse);
    });

    test('撤銷會退回上一格', () {
      final m = walkToTurn(converted());
      m.next();
      expect(m.convertedTurnOrdinal, 2);

      m.undo();
      expect(m.convertedTurnOrdinal, 1);
      expect(m.convertedTurnSeat, 5);
    });
  });
}
