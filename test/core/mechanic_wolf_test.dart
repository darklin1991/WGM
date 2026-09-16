import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/engine/night_flow.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/player.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 12 人機械狼通靈師局：3狼 + 機械狼 + 通靈師女獵守 + 4民。
Preset _preset({Map<String, dynamic>? rules}) => Preset.fromJson(
      {
        'presetId': 'jixielang',
        'name': '機械狼通靈師',
        'playerCount': 12,
        'roles': const [
          {'role': 'wolf', 'count': 3},
          {'role': 'mechanicWolf', 'count': 1},
          {'role': 'psychic', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'guard', 'count': 1},
          {'role': 'villager', 'count': 4},
        ],
        'nightOrder': const [
          'mechanicWolf',
          'guard',
          'wolf',
          'witch',
          'hunter',
          'psychic',
        ],
        'rules': ?rules,
      },
      sourceName: 'jixielang.json',
    );

/// 固定座位配置，方便測試閱讀：
/// 1-3 狼、4 機械狼、5 通靈師、6 女巫、7 獵人、8 守衛、9-12 平民。
GameState _state({Map<String, dynamic>? rules}) {
  final s = GameState(preset: _preset(rules: rules));
  void set(int seat, Role role) => s.playerAt(seat).role = role;
  set(1, Roles.wolf);
  set(2, Roles.wolf);
  set(3, Roles.wolf);
  set(4, Roles.mechanicWolf);
  set(5, Roles.psychic);
  set(6, Roles.witch);
  set(7, Roles.hunter);
  set(8, Roles.guard);
  for (var i = 9; i <= 12; i++) {
    set(i, Roles.villager);
  }
  return s;
}

/// 讓機械狼進入「已學會且技能已生效」的狀態。
GameState _learned(Role role, {int learnedNight = 1}) {
  final s = _state();
  s.mechanicWolfLearnedRole = role;
  s.mechanicWolfLearnedNight = learnedNight;
  return s;
}

const _arb = NightArbitrator();

Map<int, DeathCause> _deathMap(NightOutcome o) => {
      for (final d in o.deaths) d.seat: d.cause,
    };

void main() {
  test('本板子的學習對象只有這六種身分', () {
    // 機械狼學到什麼，決定了牠之後每晚要做什麼。這個板子上除了牠自己，
    // 場上只有下面六種身分 —— 其餘角色（狼王、狼美人、預言家、白痴、騎士）
    // 不在這個板子裡，學不到。
    final learnable = _preset()
        .roles
        .map((s) => s.role.id)
        .where((id) => id != Roles.mechanicWolf.id)
        .toSet();

    expect(learnable, {
      Roles.guard.id,
      Roles.witch.id,
      Roles.psychic.id,
      Roles.hunter.id,
      Roles.villager.id,
      Roles.wolf.id,
    });

    // 六種學習結果對應的夜晚行為。
    expect(NightFlow.mechanicSkillOf(Roles.guard), NightSkill.guardProtect);
    expect(NightFlow.mechanicSkillOf(Roles.witch), NightSkill.witchPotion);
    expect(NightFlow.mechanicSkillOf(Roles.psychic), NightSkill.psychicInspect);
    expect(NightFlow.mechanicSkillOf(Roles.hunter), NightSkill.none,
        reason: '槍牌的手勢改在夜晚結尾給');
    expect(NightFlow.mechanicSkillOf(Roles.villager), NightSkill.none);
    expect(NightFlow.mechanicSkillOf(Roles.wolf), NightSkill.none,
        reason: '多的那一刀要等帶刀才砍得到');
  });

  group('學習的時機與次數', () {
    test('學習當晚不生效，隔夜才生效', () {
      final s = _learned(Roles.guard, learnedNight: 2);

      expect(s.mechanicSkillActiveOn(2), isFalse, reason: '學習當晚還不能用');
      expect(s.mechanicSkillActiveOn(3), isTrue);
    });

    test('沒學過時技能永遠不生效', () {
      final s = _state();

      expect(s.mechanicSkillActiveOn(1), isFalse);
      expect(s.mechanicSkillActiveOn(9), isFalse);
    });

    test('結算會回報學到的身分，apply 後寫入狀態', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..wolfTarget = 9
        ..mechanicWolfLearnTarget = 8; // 8 號是守衛
      final o = _arb.settle(s, a);

      expect(o.mechanicLearnedRole?.id, Roles.guard.id);

      _arb.apply(s, a, o);
      expect(s.mechanicWolfLearnedRole?.id, Roles.guard.id);
      expect(s.mechanicWolfLearnedNight, 1);
    });

    test('整局只能學一次 —— 已學過就不會被覆蓋', () {
      final s = _learned(Roles.guard);
      final a = NightActions(night: 3)..mechanicWolfLearnTarget = 6; // 女巫
      _arb.apply(s, a, _arb.settle(s, a));

      expect(s.mechanicWolfLearnedRole?.id, Roles.guard.id, reason: '維持第一次學到的');
      expect(s.mechanicWolfLearnedNight, 1);
    });
  });

  group('學到守衛', () {
    test('機械狼守住刀口 → 存活', () {
      final s = _learned(Roles.guard);
      final a = NightActions(night: 2)
        ..wolfTarget = 9
        ..mechanicGuardTarget = 9;

      expect(_arb.settle(s, a).deaths, isEmpty);
    });

    test('機械狼守 ＋ 女巫救（同守同救）→ 依旗標死亡', () {
      final s = _learned(Roles.guard);
      final a = NightActions(night: 2)
        ..wolfTarget = 9
        ..mechanicGuardTarget = 9
        ..witchHealTarget = 9;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[9], DeathCause.guardHealConflict);
    });

    test('原守衛與機械狼可以守不同人，兩人都擋得住', () {
      final s = _learned(Roles.guard);
      final a = NightActions(night: 2)
        ..guardTarget = 10
        ..mechanicGuardTarget = 9
        ..wolfTarget = 9;

      expect(_arb.settle(s, a).deaths, isEmpty);
    });

    test('守護紀錄與原守衛各自獨立', () {
      final s = _learned(Roles.guard);
      final a = NightActions(night: 2)
        ..guardTarget = 10
        ..mechanicGuardTarget = 9;
      _arb.apply(s, a, _arb.settle(s, a));

      expect(s.lastGuardTarget, 10);
      expect(s.lastMechanicGuardTarget, 9);
      expect(_arb.guardMayProtect(s, 10), isFalse);
      expect(_arb.guardMayProtect(s, 9), isTrue, reason: '原守衛沒守過 9 號');
      expect(_arb.mechanicGuardMayProtect(s, 9), isFalse);
      expect(_arb.mechanicGuardMayProtect(s, 10), isTrue);
    });
  });

  group('學到女巫（只有毒藥，沒有解藥）', () {
    test('學到女巫後，那一輪要收的技能是用藥（只有毒藥）', () {
      final s = _learned(Roles.witch);
      final step = NightFlow.laterNightStepsFor(s, night: 2)
          .firstWhere((e) => e.skill == NightSkill.mechanicTurn);

      expect(step.mechanicSubSkill, NightSkill.witchPotion);
      expect(step.byMechanicWolf, isTrue);
    });

    test('機械狼的毒藥可以毒死人，一般守衛也擋不住', () {
      final s = _learned(Roles.witch);
      final a = NightActions(night: 2)
        ..guardTarget = 10
        ..mechanicPoisonTarget = 10;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[10], DeathCause.poison);
    });

    test('毒藥與原女巫的各自獨立', () {
      final s = _learned(Roles.witch);
      final a = NightActions(night: 2)..mechanicPoisonTarget = 11;
      _arb.apply(s, a, _arb.settle(s, a));

      expect(s.mechanicPoisonAvailable, isFalse, reason: '機械狼用掉了毒藥');
      expect(s.witchPoisonAvailable, isTrue, reason: '女巫的毒藥還在');
      expect(s.witchAntidoteAvailable, isTrue, reason: '解藥只有女巫有，沒被動到');
    });

    test('獵人被機械狼毒死 → 不可開槍', () {
      final s = _learned(Roles.witch);
      final a = NightActions(night: 2)..mechanicPoisonTarget = 7;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[7], DeathCause.poison);
      expect(o.hunterMayShoot, isFalse);
    });

    test('獵人手勢也要看機械狼的毒', () {
      final s = _learned(Roles.witch);
      final a = NightActions(night: 2)..mechanicPoisonTarget = 7;

      expect(_arb.hunterCanShootTonight(s, a), isFalse);
    });
  });

  group('學到查驗類角色', () {
    test('學到通靈師 → 查到真實身分', () {
      final s = _learned(Roles.psychic);
      final a = NightActions(night: 2)..mechanicInspectTarget = 8;
      final o = _arb.settle(s, a);

      expect(o.mechanicPsychicResult?.seat, 8);
      expect(o.mechanicPsychicResult?.revealedRole?.id, Roles.guard.id);
      expect(o.mechanicSeerTarget, isNull);
    });

    test('學到預言家 → 只查好人／狼人', () {
      final s = _learned(Roles.seer);
      final a = NightActions(night: 2)..mechanicInspectTarget = 1;
      final o = _arb.settle(s, a);

      expect(o.mechanicSeerTarget, 1);
      expect(o.mechanicSeerSawWolf, isTrue);
      expect(o.mechanicPsychicResult, isNull);
    });

  });

  // 機械狼學到槍牌的開槍條件比獵人本人嚴格：**只有吃刀或吃推**。
  // 小狼不認得機械狼，誤刀是真的會發生的情境。
  group('學到槍牌（獵人／狼王）', () {
    test('吃刀出局 → 可以開槍', () {
      final s = _learned(Roles.hunter);
      final a = NightActions(night: 2)..wolfTarget = 4; // 小狼誤刀機械狼

      expect(_arb.settle(s, a).hunterMayShoot, isTrue);
    });

    test('學到狼王一樣是槍牌', () {
      final s = _learned(Roles.wolfKing);
      final a = NightActions(night: 2)..wolfTarget = 4;

      expect(_arb.settle(s, a).hunterMayShoot, isTrue);
    });

    test('吃毒出局 → 不可開槍', () {
      final s = _learned(Roles.hunter);
      final a = NightActions(night: 2)..witchPoisonTarget = 4;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[4], DeathCause.poison);
      expect(o.hunterMayShoot, isFalse);
    });

    test('同守同救而死算吃刀 → 可以開槍', () {
      final s = _learned(Roles.hunter);
      final a = NightActions(night: 2)
        ..wolfTarget = 4
        ..guardTarget = 4
        ..witchHealTarget = 4;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[4], DeathCause.guardHealConflict);
      expect(o.hunterMayShoot, isTrue);
    });

    test('沒學到槍牌就沒有槍', () {
      final s = _learned(Roles.villager);
      final a = NightActions(night: 2)..wolfTarget = 4;

      expect(_arb.settle(s, a).hunterMayShoot, isFalse);
    });

    test('學習當晚就能給手勢 —— 身分還沒套用到狀態也算數', () {
      final s = _state();
      // 首夜：機械狼第一格指定學 7 號獵人，結尾才由法官告知並給手勢。
      final a = NightActions(night: 1)..mechanicWolfLearnTarget = 7;

      expect(_arb.mechanicLearnedRoleNow(s, a)?.id, Roles.hunter.id);
      expect(_arb.mechanicCanShootTonight(s, a), isTrue);
    });

    test('學到的目標尚未登記身分時視為平民 —— 首夜平民是最後才補的', () {
      final s = _state();
      s.playerAt(9).role = null;
      final a = NightActions(night: 1)..mechanicWolfLearnTarget = 9;

      expect(_arb.mechanicLearnedRoleNow(s, a)?.id, Roles.villager.id);
      expect(_arb.mechanicCanShootTonight(s, a), isFalse);
    });

    test('沒指定學習對象 → 沒有身分可告知', () {
      expect(
        _arb.mechanicLearnedRoleNow(_state(), NightActions(night: 1)),
        isNull,
      );
    });

    test('今晚手勢：沒中毒給可開槍，中毒給不可開槍', () {
      final s = _learned(Roles.hunter);

      expect(
        _arb.mechanicCanShootTonight(s, NightActions(night: 2)),
        isTrue,
      );
      expect(
        _arb.mechanicCanShootTonight(
          s,
          NightActions(night: 2)..witchPoisonTarget = 4,
        ),
        isFalse,
      );
    });
  });

  group('學到守衛：反彈毒藥', () {
    test('被守護者中毒 → 自己不死，毒反彈給下毒的女巫', () {
      final s = _learned(Roles.guard);
      final a = NightActions(night: 2)
        ..mechanicGuardTarget = 10
        ..witchPoisonTarget = 10;
      final o = _arb.settle(s, a);

      expect(_deathMap(o).containsKey(10), isFalse, reason: '被守護者不死');
      expect(_deathMap(o)[6], DeathCause.poison, reason: '6 號女巫被自己的毒反彈毒死');
      expect(o.poisonReflectedTo, 6);
    });

    test('一般守衛的守護不會反彈，照樣被毒死', () {
      final s = _learned(Roles.guard);
      final a = NightActions(night: 2)
        ..guardTarget = 10
        ..witchPoisonTarget = 10;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[10], DeathCause.poison);
      expect(o.poisonReflectedTo, isNull);
    });

    test('mechanicGuardReflectsPoison = false 時退回一般守衛的行為', () {
      final s = _state(rules: {'mechanicGuardReflectsPoison': false})
        ..mechanicWolfLearnedRole = Roles.guard
        ..mechanicWolfLearnedNight = 1;
      final a = NightActions(night: 2)
        ..mechanicGuardTarget = 10
        ..witchPoisonTarget = 10;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[10], DeathCause.poison);
      expect(_deathMap(o).containsKey(6), isFalse);
    });

    test('守護同時擋得住刀 —— 擋刀與反彈毒是同一道守護', () {
      final s = _learned(Roles.guard);
      final a = NightActions(night: 2)
        ..mechanicGuardTarget = 10
        ..wolfTarget = 10
        ..witchPoisonTarget = 10;
      final o = _arb.settle(s, a);

      expect(_deathMap(o).containsKey(10), isFalse);
      expect(_deathMap(o)[6], DeathCause.poison);
    });

    test('獵人被守護時毒會反彈，手勢仍給可開槍', () {
      final s = _learned(Roles.guard);
      final a = NightActions(night: 2)
        ..mechanicGuardTarget = 7
        ..witchPoisonTarget = 7;

      expect(_arb.hunterCanShootTonight(s, a), isTrue);
    });
  });

  // 機械狼要等其餘小狼全數出局才開得了刀；多的那一刀也只有在那時才砍得到。
  group('學到狼人：帶刀那晚多砍一刀', () {
    /// 小狼全滅、機械狼已學到狼人的狀態。
    GameState loneWolf({int learnedNight = 1}) {
      final s = _learned(Roles.wolf, learnedNight: learnedNight);
      for (final seat in [1, 2, 3]) {
        s.playerAt(seat).alive = false;
      }
      return s;
    }

    test('小狼還活著 → 機械狼沒有刀，也沒有第二刀', () {
      expect(_learned(Roles.wolf).mechanicHasExtraKnifeOn(2), isFalse);
    });

    test('小狼全滅 → 機械狼帶刀，且多一刀', () {
      expect(loneWolf().mechanicHasExtraKnifeOn(2), isTrue);
    });

    test('小狼全滅但沒學到狼人 → 只有一刀', () {
      final s = _learned(Roles.guard);
      for (final seat in [1, 2, 3]) {
        s.playerAt(seat).alive = false;
      }

      expect(s.mechanicWolfCarriesKnife, isTrue);
      expect(s.mechanicHasExtraKnifeOn(2), isFalse);
    });

    test('學習當晚還沒生效，機械狼死了也沒有第二刀', () {
      expect(loneWolf(learnedNight: 2).mechanicHasExtraKnifeOn(2), isFalse);

      final dead = loneWolf();
      dead.playerAt(4).alive = false;
      expect(dead.mechanicHasExtraKnifeOn(2), isFalse);
    });

    test('刀在機械狼自己那一輪開，不另外生一個狼刀步驟', () {
      final s = loneWolf();
      final steps = NightFlow.laterNightStepsFor(s, night: 3);

      expect(s.mechanicWolfCarriesKnife, isTrue);
      expect(s.mechanicHasExtraKnifeOn(3), isTrue);
      expect(steps.where((e) => e.skill == NightSkill.mechanicTurn).length, 1);
      // 小狼那一步還在清單裡，但角色全死，跑流程時會被自動跳過。
      expect(steps.any((e) => e.title == '狼人'), isTrue);
    });

    test('兩刀砍不同人 → 兩人都死', () {
      final s = _learned(Roles.wolf);
      final a = NightActions(night: 2)
        ..wolfTarget = 9
        ..wolfSecondTarget = 10;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[9], DeathCause.wolfKill);
      expect(_deathMap(o)[10], DeathCause.wolfKill);
    });

    test('兩刀砍不同人，守衛只擋得住其中一個', () {
      final s = _learned(Roles.wolf);
      final a = NightActions(night: 2)
        ..guardTarget = 9
        ..wolfTarget = 9
        ..wolfSecondTarget = 10;
      final o = _arb.settle(s, a);

      expect(_deathMap(o).containsKey(9), isFalse);
      expect(_deathMap(o)[10], DeathCause.wolfKill);
    });

    test('兩刀集中同一人 → 破盾，守衛守了也沒用', () {
      final s = _learned(Roles.wolf);
      final a = NightActions(night: 2)
        ..guardTarget = 9
        ..wolfTarget = 9
        ..wolfSecondTarget = 9;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[9], DeathCause.wolfKill);
      expect(o.shieldBrokenSeats, [9]);
      expect(o.notes.any((n) => n.contains('破盾')), isTrue);
    });

    test('破盾連解藥也救不回來', () {
      final s = _learned(Roles.wolf);
      final a = NightActions(night: 2)
        ..wolfTarget = 9
        ..wolfSecondTarget = 9
        ..witchHealTarget = 9;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[9], DeathCause.wolfKill);
      expect(o.shieldBrokenSeats, [9]);
    });

    test('破盾時同守同救不成立 —— 守與救都被打穿，死因就是狼刀', () {
      final s = _learned(Roles.wolf);
      final a = NightActions(night: 2)
        ..guardTarget = 9
        ..wolfTarget = 9
        ..wolfSecondTarget = 9
        ..witchHealTarget = 9;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[9], DeathCause.wolfKill,
          reason: '不是 guardHealConflict');
    });

    test('沒被守就不算破盾，只是單純死亡', () {
      final s = _learned(Roles.wolf);
      final a = NightActions(night: 2)
        ..wolfTarget = 9
        ..wolfSecondTarget = 9;
      final o = _arb.settle(s, a);

      expect(_deathMap(o)[9], DeathCause.wolfKill);
      expect(o.shieldBrokenSeats, isEmpty);
    });

    test('mechanicDoubleKnifeBreaksShield = false 時守得住', () {
      final s = _state(rules: {'mechanicDoubleKnifeBreaksShield': false})
        ..mechanicWolfLearnedRole = Roles.wolf
        ..mechanicWolfLearnedNight = 1;
      final a = NightActions(night: 2)
        ..guardTarget = 9
        ..wolfTarget = 9
        ..wolfSecondTarget = 9;

      expect(_arb.settle(s, a).deaths, isEmpty);
    });

    test('兩刀都記為被刀的事實標記', () {
      final s = _learned(Roles.wolf);
      final a = NightActions(night: 2)
        ..wolfTarget = 9
        ..wolfSecondTarget = 10;
      _arb.apply(s, a, _arb.settle(s, a));

      expect(s.playerAt(9).nightFacts, contains(FactTag.knifed));
      expect(s.playerAt(10).nightFacts, contains(FactTag.knifed));
    });
  });

  group('通靈師查驗', () {
    test('查到的是真實身分，不只好人／狼人', () {
      final s = _state();
      final a = NightActions(night: 1)..psychicTarget = 4;
      final o = _arb.settle(s, a);

      expect(o.psychicResult?.seat, 4);
      expect(o.psychicResult?.revealedRole?.id, Roles.mechanicWolf.id,
          reason: '通靈師看得出是機械狼，不只是「狼人」');
    });

    test('查驗平民也回報真實身分', () {
      final s = _state();
      final a = NightActions(night: 1)..psychicTarget = 9;

      expect(_arb.settle(s, a).psychicResult?.revealedRole?.id,
          Roles.villager.id);
    });
  });

  group('機械狼帶刀', () {
    test('還有小狼存活時，機械狼不帶刀', () {
      final s = _state();

      expect(s.mechanicWolfCarriesKnife, isFalse);
    });

    test('小狼全數出局後，機械狼獨自帶刀', () {
      final s = _state();
      for (final seat in [1, 2, 3]) {
        s.playerAt(seat).alive = false;
      }

      expect(s.mechanicWolfCarriesKnife, isTrue);
    });

    test('沒有機械狼的板子不受影響', () {
      final s = GameState(preset: _preset());
      // 全部設成平民 —— 板子裡沒人是機械狼。
      for (final p in s.players) {
        p.role = Roles.villager;
      }

      expect(s.mechanicWolfCarriesKnife, isFalse);
    });
  });

  // 機械狼那一輪（NightSkill.mechanicTurn）**每晚都在**：先給開刀手勢
  // （牠不與小狼相認，不知道小狼死光了沒），再問是否使用技能。
  group('夜晚步驟（機械狼通靈師）', () {
    /// 機械狼那一輪的步驟。
    NightStep turnOf(List<NightStep> steps) =>
        steps.firstWhere((e) => e.skill == NightSkill.mechanicTurn);

    test('首夜：機械狼第一個睜眼，最後再睜一次眼聽結果', () {
      final steps = NightFlow.firstNightSteps(_preset());
      final titles = steps.map((s) => s.title).toList();

      expect(titles, ['機械狼', '守衛', '狼人', '女巫', '獵人', '通靈師', '機械狼']);

      final turn = steps.first;
      expect(turn.skill, NightSkill.mechanicTurn);
      expect(turn.mechanicSubSkill, NightSkill.mechanicLearn);
      expect(turn.seatCount, 1, reason: '機械狼要單獨登記自己的座次');

      final wolfStep = steps[2];
      expect(wolfStep.seatCount, 3, reason: '只有 3 匹小狼，機械狼不與牠們相認');
      expect(wolfStep.roles.map((r) => r.id), [Roles.wolf.id]);

      expect(steps.last.skill, NightSkill.mechanicReveal,
          reason: '身分與毒藥都收完了，這時才告知得了學到什麼、能不能開槍');
    });

    test('獵人排在女巫之後 —— 要先收完毒才知道給哪個手勢', () {
      final titles =
          NightFlow.firstNightSteps(_preset()).map((s) => s.title).toList();

      expect(titles.indexOf('獵人'), greaterThan(titles.indexOf('女巫')));
    });

    test('不論學到什麼，機械狼每晚都會被叫起來給開刀手勢', () {
      for (final learned in [
        null,
        Roles.guard,
        Roles.witch,
        Roles.psychic,
        Roles.hunter,
        Roles.villager,
        Roles.wolf,
      ]) {
        final s = _state();
        if (learned != null) {
          s
            ..mechanicWolfLearnedRole = learned
            ..mechanicWolfLearnedNight = 1;
        }
        final steps = NightFlow.laterNightStepsFor(s, night: 2);

        expect(
          steps.where((e) => e.skill == NightSkill.mechanicTurn).length,
          1,
          reason: '學到 ${learned?.nameZh ?? "（還沒學）"} 時也要有這一輪',
        );
      }
    });

    test('學習當晚的隔夜 → 那一輪要收學到的技能', () {
      final turn = turnOf(
        NightFlow.laterNightStepsFor(_learned(Roles.guard), night: 2),
      );

      expect(turn.mechanicSubSkill, NightSkill.guardProtect);
      expect(turn.byMechanicWolf, isTrue);
      expect(turn.title, '機械狼（守衛）');
    });

    test('學了但還沒到隔夜 → 仍要睜眼給手勢，只是沒技能可用', () {
      final turn = turnOf(
        NightFlow.laterNightStepsFor(
          _learned(Roles.guard, learnedNight: 2),
          night: 2,
        ),
      );

      expect(turn.mechanicSubSkill, NightSkill.none);
      expect(turn.title, '機械狼');
    });

    test('學到平民 → 仍要睜眼給手勢，只是沒技能可用', () {
      final turn =
          turnOf(NightFlow.laterNightStepsFor(_learned(Roles.villager), night: 2));

      expect(turn.mechanicSubSkill, NightSkill.none);
    });

    test('學到狼人 → 沒有另外的技能，多的刀在同一輪收', () {
      final turn =
          turnOf(NightFlow.laterNightStepsFor(_learned(Roles.wolf), night: 2));

      expect(turn.mechanicSubSkill, NightSkill.none);
    });

    test('已學到沒槍的身分 → 結尾不再叫起來', () {
      final steps = NightFlow.laterNightStepsFor(_learned(Roles.guard), night: 2);

      expect(steps.any((e) => e.skill == NightSkill.mechanicReveal), isFalse);
    });

    test('已學到槍牌 → 結尾每晚都要給開槍手勢', () {
      final steps = NightFlow.laterNightStepsFor(_learned(Roles.hunter), night: 2);
      final mechanicSteps = steps
          .where((e) => e.primaryRole?.id == Roles.mechanicWolf.id)
          .map((e) => e.skill);

      expect(mechanicSteps, [NightSkill.mechanicTurn, NightSkill.mechanicReveal],
          reason: '開頭給開刀手勢，結尾給開槍手勢');
    });

    test('還沒學過 → 開頭是學習，結尾也照樣告知', () {
      final steps = NightFlow.laterNightStepsFor(_state(), night: 2);

      expect(turnOf(steps).mechanicSubSkill, NightSkill.mechanicLearn);
      expect(steps.last.skill, NightSkill.mechanicReveal);
    });
  });

  group('深拷貝', () {
    test('機械狼的欄位都要進快照，否則撤銷會壞掉', () {
      final s = _learned(Roles.witch)
        ..mechanicPoisonAvailable = false
        ..lastMechanicGuardTarget = 9
        ..mechanicCharmedSeat = 10
        ..lastMechanicCharmTarget = 10;
      final snapshot = s.copy();

      s
        ..mechanicWolfLearnedRole = Roles.guard
        ..mechanicPoisonAvailable = true
        ..lastMechanicGuardTarget = 11;

      expect(snapshot.mechanicWolfLearnedRole?.id, Roles.witch.id);
      expect(snapshot.mechanicWolfLearnedNight, 1);
      expect(snapshot.mechanicPoisonAvailable, isFalse);
      expect(snapshot.lastMechanicGuardTarget, 9);
      expect(snapshot.mechanicCharmedSeat, 10);
      expect(snapshot.lastMechanicCharmTarget, 10);
    });
  });
}
