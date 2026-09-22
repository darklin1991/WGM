import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_flow.dart';
import 'package:wgm/core/engine/night_flow_machine.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 查驗結果必須**在查驗者睜著眼的當下**給出來。
///
/// 夜晚結算頁也會列出查驗結果，但那是整夜跑完之後的事 —— 那時預言家
/// 早就閉眼了，法官根本沒機會告知。所以查驗完要先停在結果那一頁，
/// 等同獵人的開槍手勢。

Preset _load(String id) => Preset.fromJson(
      jsonDecode(File('assets/presets/$id.json').readAsStringSync())
          as Map<String, dynamic>,
      sourceName: '$id.json',
    );

GameState _preassigned(Preset preset) {
  final state = GameState(preset: preset);
  var seat = 1;
  for (final slot in preset.roles) {
    for (var i = 0; i < slot.count; i++) {
      state.playerAt(seat++).role = slot.role;
    }
  }
  state.dayNumber = 1;
  return state;
}

/// 一路推進到指定技能的選目標那一步。
NightFlowMachine _advanceTo(NightFlowMachine m, NightSkill skill) {
  for (var guard = 0; guard < 40; guard++) {
    if (m.sub == NightSub.chooseTarget && m.effectiveSkill == skill) return m;
    m.next();
    if (m.outcome != null) fail('夜晚走完了還沒碰到 $skill');
  }
  fail('40 步還沒碰到 $skill');
}

void main() {
  group('預言家', () {
    test('查到狼人 → 查殺', () {
      final state = _preassigned(_load('12p_yu_nu_lie_bai'));
      final m = _advanceTo(
        NightFlowMachine(state: state, night: 1, isFirstNight: true),
        NightSkill.seerInspect,
      );

      final wolfSeat = state.seatsOfRole(Roles.wolf.id).first;
      m.toggleSeat(wolfSeat);
      m.next();

      expect(m.sub, NightSub.inspectResult);
      final reveal = m.inspectReveal!;
      expect(reveal.seat, wolfSeat);
      expect(reveal.sawWolf, isTrue);
      expect(reveal.isPsychic, isFalse);
    });

    test('查到好人 → 金水', () {
      final state = _preassigned(_load('12p_yu_nu_lie_bai'));
      final m = _advanceTo(
        NightFlowMachine(state: state, night: 1, isFirstNight: true),
        NightSkill.seerInspect,
      );

      final villagerSeat = state.seatsOfRole(Roles.villager.id).first;
      m.toggleSeat(villagerSeat);
      m.next();

      expect(m.sub, NightSub.inspectResult);
      expect(m.inspectReveal!.sawWolf, isFalse);
    });

    test('空驗（沒選人）就沒有結果可給，直接往下走', () {
      final state = _preassigned(_load('12p_yu_nu_lie_bai'));
      final m = _advanceTo(
        NightFlowMachine(state: state, night: 1, isFirstNight: true),
        NightSkill.seerInspect,
      );

      m.next(); // 沒選人
      expect(m.sub, isNot(NightSub.inspectResult));
      expect(m.inspectReveal, isNull);
    });

    test('結果那一頁不能選人，也不必選就能往下', () {
      final state = _preassigned(_load('12p_yu_nu_lie_bai'));
      final m = _advanceTo(
        NightFlowMachine(state: state, night: 1, isFirstNight: true),
        NightSkill.seerInspect,
      );

      m.toggleSeat(1);
      m.next();

      expect(m.sub, NightSub.inspectResult);
      expect(m.requiredPickCount, 0);
      expect(m.selectableSeats, isEmpty);
      expect(m.canProceed, isTrue);
      m.toggleSeat(5);
      expect(m.picked, isEmpty);
    });

    test('撤銷可以退回查驗那一步重選', () {
      final state = _preassigned(_load('12p_yu_nu_lie_bai'));
      final m = _advanceTo(
        NightFlowMachine(state: state, night: 1, isFirstNight: true),
        NightSkill.seerInspect,
      );

      final wolfSeat = state.seatsOfRole(Roles.wolf.id).first;
      m.toggleSeat(wolfSeat);
      m.next();
      expect(m.sub, NightSub.inspectResult);

      expect(m.undo(), isTrue);
      expect(m.sub, NightSub.chooseTarget);
      expect(m.effectiveSkill, NightSkill.seerInspect);
    });
  });

  group('通靈師', () {
    test('看到的是真實身分，不只好人／狼人', () {
      final state = _preassigned(_load('12p_jixielang_tonglingshi'));
      final m = _advanceTo(
        NightFlowMachine(state: state, night: 1, isFirstNight: true),
        NightSkill.psychicInspect,
      );

      final witchSeat = state.seatOfRole(Roles.witch.id)!;
      m.toggleSeat(witchSeat);
      m.next();

      expect(m.sub, NightSub.inspectResult);
      final reveal = m.inspectReveal!;
      expect(reveal.isPsychic, isTrue);
      expect(reveal.role?.id, Roles.witch.id);
      // 女巫是好人，所以查驗者拿到的不是查殺。
      expect(reveal.sawWolf, isFalse);
    });

    test('機械狼還沒學習時，查到的就是機械狼本人', () {
      final state = _preassigned(_load('12p_jixielang_tonglingshi'));
      // `_advanceTo` 一路按下一步都不選人，所以機械狼沒有學習。
      final m = _advanceTo(
        NightFlowMachine(state: state, night: 1, isFirstNight: true),
        NightSkill.psychicInspect,
      );

      final mechanicSeat = state.seatOfRole(Roles.mechanicWolf.id)!;
      m.toggleSeat(mechanicSeat);
      m.next();

      final reveal = m.inspectReveal!;
      expect(reveal.role?.id, Roles.mechanicWolf.id);
      expect(reveal.sawWolf, isTrue);
    });
  });

  // 擔當 2026-09-19 指定：機械狼學過之後，查驗看到的是**牠學到的身分**，
  // 而且**學習當晚就生效**（技能仍是隔夜生效，兩者刻意不同步）。
  // 預言家也一起被騙過 —— 學到好人身分就給金水。
  group('機械狼的身分偽裝', () {
    /// 讓機械狼在牠那一輪學 [learnSeat]，再推進到通靈師查驗。
    NightFlowMachine learnThenReachPsychic(GameState state, int learnSeat) {
      final m = NightFlowMachine(state: state, night: 1, isFirstNight: true);

      // 機械狼開頭那一輪：開刀手勢 →（有刀才問刀口）→ 學習。
      while (m.effectiveSkill != NightSkill.mechanicLearn ||
          m.sub != NightSub.chooseTarget) {
        m.next();
        if (m.outcome != null) fail('沒走到機械狼的學習');
      }
      m.toggleSeat(learnSeat);
      m.next();

      return _advanceTo(m, NightSkill.psychicInspect);
    }

    test('通靈師查到的是學到的身分，不是機械狼', () {
      final state = _preassigned(_load('12p_jixielang_tonglingshi'));
      final guardSeat = state.seatOfRole(Roles.guard.id)!;
      final mechanicSeat = state.seatOfRole(Roles.mechanicWolf.id)!;

      final m = learnThenReachPsychic(state, guardSeat);
      m.toggleSeat(mechanicSeat);
      m.next();

      final reveal = m.inspectReveal!;
      expect(reveal.role?.id, Roles.guard.id, reason: '學到守衛就顯示守衛');
      expect(reveal.sawWolf, isFalse, reason: '守衛是好人');
    });

    test('偽裝當晚就生效，不必等隔夜', () {
      final state = _preassigned(_load('12p_jixielang_tonglingshi'));
      final guardSeat = state.seatOfRole(Roles.guard.id)!;
      final mechanicSeat = state.seatOfRole(Roles.mechanicWolf.id)!;

      final m = learnThenReachPsychic(state, guardSeat);

      // 這正是要測的前提：學到的身分還沒寫進局面（結算後才寫）。
      expect(state.mechanicWolfLearnedRole, isNull);
      // 技能仍是隔夜生效，偽裝卻已經成立 —— 兩者刻意不同步。
      expect(state.mechanicSkillActiveOn(1), isFalse);

      m.toggleSeat(mechanicSeat);
      m.next();
      expect(m.inspectReveal!.role?.id, Roles.guard.id);
    });

    test('學到狼人仍然是查殺', () {
      final state = _preassigned(_load('12p_jixielang_tonglingshi'));
      final wolfSeat = state.seatsOfRole(Roles.wolf.id).first;
      final mechanicSeat = state.seatOfRole(Roles.mechanicWolf.id)!;

      final m = learnThenReachPsychic(state, wolfSeat);
      m.toggleSeat(mechanicSeat);
      m.next();

      final reveal = m.inspectReveal!;
      expect(reveal.role?.id, Roles.wolf.id);
      expect(reveal.sawWolf, isTrue);
    });

    test('偽裝只罩機械狼自己，查別人不受影響', () {
      final state = _preassigned(_load('12p_jixielang_tonglingshi'));
      final guardSeat = state.seatOfRole(Roles.guard.id)!;

      final m = learnThenReachPsychic(state, guardSeat);
      // 查被學習的那位守衛 —— 他本人照實顯示。
      m.toggleSeat(guardSeat);
      m.next();

      expect(m.inspectReveal!.role?.id, Roles.guard.id);
    });
  });

  test('身分尚未登記時視為好人 —— 與結算的補平民一致', () {
    // 首夜邊問邊登記的用法：預言家行動時，排在他後面的角色還沒登記。
    // 結算會把剩下的座次補成平民，所以這時照金水給才是對的。
    final state = GameState(preset: _load('12p_yu_nu_lie_bai'))..dayNumber = 1;
    final m = NightFlowMachine(state: state, night: 1, isFirstNight: true);

    // 狼隊登記 1-4 並空刀。
    for (final seat in [1, 2, 3, 4]) {
      m.toggleSeat(seat);
    }
    m.next();
    m.next();

    // 女巫登記 5，兩瓶藥都不用。
    m.toggleSeat(5);
    m.next();
    m.next();

    // 預言家登記 6，查 12 號 —— 那時 12 號還沒登記。
    m.toggleSeat(6);
    m.next();
    expect(state.playerAt(12).role, isNull, reason: '這正是要測的前提');
    m.toggleSeat(12);
    m.next();

    expect(m.sub, NightSub.inspectResult);
    final reveal = m.inspectReveal!;
    expect(reveal.role, isNull);
    expect(reveal.sawWolf, isFalse, reason: '未登記的座次最後會補成平民');
  });
}
