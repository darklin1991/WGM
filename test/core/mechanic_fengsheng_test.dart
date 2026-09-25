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

/// 風聲諜影的機械狼學到本板特有的身分（擔當 2026-09-25 指定）：
///
/// - **熊、攝夢人、河豚、白貓** → 模擬技能
/// - **暗戀者、覺醒石像鬼** → 變成那個身分（查驗偽裝），但沒有技能
///
/// 熊與攝夢人是夜間技能，照一般規則隔夜生效；河豚與白貓是出局時才觸發的
/// 被動技能，比照槍牌學到就生效。

const _arb = NightArbitrator();

/// 照設定檔的角色順序配座次：
/// 1、2 石像鬼、3 機械狼、4 預言家、5 通靈師、6 熊、7 女巫、8 獵人、
/// 9 攝夢人、10 河豚、11 白貓、12 暗戀者。
GameState _state() {
  final json = jsonDecode(
    File('assets/presets/12p_fengsheng_dieying.json').readAsStringSync(),
  ) as Map;
  final s = GameState(
    preset: Preset.fromJson(
      json.cast<String, dynamic>(),
      sourceName: '12p_fengsheng_dieying.json',
    ),
  );
  var seat = 1;
  for (final slot in s.preset.roles) {
    for (var i = 0; i < slot.count; i++) {
      s.playerAt(seat++).role = slot.role;
    }
  }
  s
    ..dayNumber = 1
    ..phase = GamePhase.night;
  return s;
}

/// 機械狼首夜學到 [role]，現在是第二夜。
GameState _learned(Role role) => _state()
  ..mechanicWolfLearnedRole = role
  ..mechanicWolfLearnedNight = 1
  ..dayNumber = 2;

/// 走到機械狼開頭那一輪的技能段（跳過開刀手勢）。
NightFlowMachine _mechanicSkill(GameState s) {
  final m = NightFlowMachine(state: s, night: s.dayNumber, isFirstNight: false);
  expect(m.sub, NightSub.mechanicKnifeGesture);
  m.next();
  return m;
}

ExileVote _exile(GameState s, int target, List<int> voters) {
  s.phase = GamePhase.day;
  final v = ExileVote(state: s)..focusTarget(target);
  for (final voter in voters) {
    v.toggleVote(voter);
  }
  v.next();
  return v;
}

void main() {
  test('生效時機：夜間技能隔夜、被動技能學到就生效、其餘沒有技能', () {
    MechanicSkillTiming of(Role r) => NightFlow.mechanicSkillTimingOf(r);

    expect(of(Roles.bear), MechanicSkillTiming.nextNight);
    expect(of(Roles.dreamWeaver), MechanicSkillTiming.nextNight);
    expect(of(Roles.pufferfish), MechanicSkillTiming.immediate);
    expect(of(Roles.whiteCat), MechanicSkillTiming.immediate);
    expect(of(Roles.hunter), MechanicSkillTiming.immediate);
    expect(of(Roles.secretAdmirer), MechanicSkillTiming.none);
    expect(of(Roles.awakenedGargoyle), MechanicSkillTiming.none);
  });

  group('學到熊', () {
    test('每晚在自己那一輪比咆哮手勢，看的是機械狼自己的鄰座', () {
      final m = _mechanicSkill(_learned(Roles.bear));

      expect(m.sub, NightSub.bearGrowl);
      expect(m.bearNeighbors, [2, 4], reason: '3 號機械狼的鄰座，不是 6 號熊的');
      expect(m.bearGrowls, isTrue, reason: '2 號是石像鬼');
    });

    test('鄰座沒有狼就不咆哮', () {
      final s = _learned(Roles.bear);
      s.playerAt(2).alive = false; // 往外順延到 1 號 —— 也是石像鬼
      s.playerAt(1).alive = false; // 再順延到 12 號暗戀者
      final m = _mechanicSkill(s);

      expect(m.bearNeighbors, [4, 12]);
      expect(m.bearGrowls, isFalse);
    });

    test('咆哮記進日誌，標明是機械狼', () {
      final s = _learned(Roles.bear);
      _mechanicSkill(s).next();

      expect(
        s.log.entries.map((e) => e.text),
        contains(startsWith('機械狼（熊）的鄰座是 2、4 號')),
      );
    });

    test('學習當晚不生效', () {
      final s = _learned(Roles.bear)..mechanicWolfLearnedNight = 2;
      final m = _mechanicSkill(s);

      expect(m.sub, isNot(NightSub.bearGrowl));
    });
  });

  group('學到攝夢人', () {
    test('目標記在機械狼自己的欄位', () {
      final m = _mechanicSkill(_learned(Roles.dreamWeaver));

      expect(m.effectiveSkill, NightSkill.dreamWeave);
      m.toggleSeat(7);
      m.next();
      expect(m.actions.mechanicDreamTarget, 7);
      expect(m.actions.dreamTarget, isNull);
    });

    test('夢遊者免疫今晚的刀', () {
      final s = _learned(Roles.dreamWeaver);
      final a = NightActions(night: 2)
        ..mechanicDreamTarget = 7
        ..wolfTarget = 7;

      expect(_arb.settle(s, a).deadSeats, isNot(contains(7)));
    });

    test('連兩晚攝同一人 → 夢死', () {
      final s = _learned(Roles.dreamWeaver)..lastMechanicDreamTarget = 7;
      final a = NightActions(night: 2)..mechanicDreamTarget = 7;
      final o = _arb.settle(s, a);

      expect(o.deaths.single.seat, 7);
      expect(o.deaths.single.cause, DeathCause.dreamDeath);
    });

    test('與原攝夢人各自獨立 —— 換人攝同一人不算連續', () {
      final s = _learned(Roles.dreamWeaver)..lastDreamTarget = 7;
      final a = NightActions(night: 2)..mechanicDreamTarget = 7;

      expect(_arb.settle(s, a).deadSeats, isEmpty);
    });

    test('機械狼今晚出局 → 牠的夢遊者一併死亡', () {
      final s = _learned(Roles.dreamWeaver);
      final a = NightActions(night: 2)
        ..mechanicDreamTarget = 7
        ..witchPoisonTarget = 3;
      final o = _arb.settle(s, a);

      expect(o.deadSeats, containsAll([3, 7]));
      expect(
        o.deaths.firstWhere((d) => d.seat == 7).cause,
        DeathCause.dreamDeath,
      );
    });

    test('結算後記住上一晚攝了誰', () {
      final s = _learned(Roles.dreamWeaver);
      final a = NightActions(night: 2)..mechanicDreamTarget = 7;
      _arb.apply(s, a, _arb.settle(s, a));

      expect(s.lastMechanicDreamTarget, 7);
      expect(s.lastDreamTarget, isNull);
    });
  });

  group('學到河豚', () {
    test('被放逐時可以翻牌帶走投他的人', () {
      final s = _learned(Roles.pufferfish);
      final v = _exile(s, 3, [4, 5, 6]);

      expect(v.stage, ExileStage.pufferfishReveal);
      expect(v.pufferfishVoters, {4, 5, 6});

      v.revealPufferfish(activate: true);
      expect([4, 5, 6].every((x) => !s.playerAt(x).alive), isTrue);
    });

    test('學到就生效 —— 學習隔天白天被放逐也能翻', () {
      final s = _learned(Roles.pufferfish)..dayNumber = 1;
      expect(_exile(s, 3, [4, 5, 6]).stage, ExileStage.pufferfishReveal);
    });
  });

  group('學到白貓', () {
    test('夜裡被刀 → 翻牌但還在場，當天投票結束才離場', () {
      final s = _learned(Roles.whiteCat);
      final a = NightActions(night: 2)..wolfTarget = 3;
      final o = _arb.settle(s, a);
      _arb.apply(s, a, o);

      expect(o.whiteCatDeferredSeats, [3]);
      expect(s.playerAt(3).alive, isTrue);
      expect(s.mechanicWhiteCatPendingCause, DeathCause.wolfKill);
      expect(s.whiteCatPendingCause, isNull, reason: '與真正的白貓各自獨立');

      _exile(s, 12, []);
      expect(s.playerAt(3).alive, isFalse);
    });

    test('學到就生效 —— 學習當晚被刀也延後', () {
      final s = _state()..dayNumber = 2;
      final a = NightActions(night: 2)
        ..mechanicWolfLearnTarget = 11 // 學白貓
        ..wolfTarget = 3;
      final o = _arb.settle(s, a);
      _arb.apply(s, a, o);

      expect(o.whiteCatDeferredSeats, [3]);
      expect(s.playerAt(3).alive, isTrue);
    });

    test('真正的白貓與機械狼同一晚都被判死 → 兩位都延後', () {
      final s = _learned(Roles.whiteCat);
      final a = NightActions(night: 2)
        ..wolfTarget = 11
        ..witchPoisonTarget = 3;
      final o = _arb.settle(s, a);
      _arb.apply(s, a, o);

      expect(o.whiteCatDeferredSeats, [3, 11]);
      expect(s.playerAt(3).alive && s.playerAt(11).alive, isTrue);

      _exile(s, 12, []);
      expect(s.playerAt(3).alive || s.playerAt(11).alive, isFalse);
    });

    test('延後期間不能被選', () {
      final s = _learned(Roles.whiteCat)
        ..mechanicWhiteCatPendingCause = DeathCause.exile
        ..mechanicWhiteCatDueAfterDay = 2;
      final m = NightFlowMachine(state: s, night: 2, isFirstNight: false);
      while (m.sub != NightSub.witchPotion) {
        m.next();
      }

      expect(m.selectableSeats, isNot(contains(3)));
      expect(dayBlockedSeats(s)[3], SeatBlockReason.whiteCatPending,
          reason: '白天也一樣');
    });

    test('白天被放逐 → 延到隔天', () {
      final s = _learned(Roles.whiteCat);
      _exile(s, 3, [4, 5, 6]);

      expect(s.playerAt(3).alive, isTrue);
      expect(s.mechanicWhiteCatDueAfterDay, 3);
    });
  });

  group('學到暗戀者、石像鬼 —— 變成那個身分，但沒有技能', () {
    test('暗戀者：預言家查是金水，通靈師查是暗戀者', () {
      final s = _learned(Roles.secretAdmirer);

      expect(NightArbitrator.apparentCampAt(s, 3), Camp.good);
      expect(NightArbitrator.apparentRoleAt(s, 3)?.id, Roles.secretAdmirer.id);
    });

    test('石像鬼：預言家查是查殺，通靈師查是覺醒石像鬼', () {
      final s = _learned(Roles.awakenedGargoyle);

      expect(NightArbitrator.apparentCampAt(s, 3), Camp.wolf);
      expect(
        NightArbitrator.apparentRoleAt(s, 3)?.id,
        Roles.awakenedGargoyle.id,
      );
    });

    test('都沒有夜間技能', () {
      for (final role in [Roles.secretAdmirer, Roles.awakenedGargoyle]) {
        final step = NightFlow.laterNightStepsFor(_learned(role), night: 2)
            .firstWhere((x) => x.skill == NightSkill.mechanicTurn);
        expect(step.mechanicSubSkill, NightSkill.none, reason: role.nameZh);
      }
    });

    test('學到石像鬼也不算石像鬼 —— 不影響狼刀順位', () {
      final s = _learned(Roles.awakenedGargoyle);
      s.playerAt(1).alive = false;
      s.playerAt(2).alive = false;

      expect(s.mechanicWolfCarriesKnife, isTrue, reason: '兩隻石像鬼都出局');
    });
  });
}
