import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 攝夢人（擔當 2026-09-22 指定）：
///
/// - 每晚指定一名夢遊者，夢遊者**免疫夜間傷害**（**連女巫的毒都擋**）
/// - **連續兩晚被攝的人會死**，死因是夢死
/// - 夢死**擋不住**，而且**獵人不能開槍**
/// - 攝夢人夜裡出局時，當晚的夢遊者一併死亡
///
/// 免疫與夢死看似矛盾，其實不是：免疫擋的是**別人造成的**傷害，
/// 夢死是被攝這件事本身造成的。

const _arb = NightArbitrator();

/// 12 人測試板：3狼 + 預女獵守攝 + 4民。
Preset _preset() => Preset.fromJson(
      const {
        'presetId': 'dw',
        'name': '攝夢人測試板',
        'playerCount': 12,
        'roles': [
          {'role': 'wolf', 'count': 3},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'guard', 'count': 1},
          {'role': 'dreamWeaver', 'count': 1},
          {'role': 'villager', 'count': 4},
        ],
        'nightOrder': ['dreamWeaver', 'guard', 'wolf', 'witch', 'seer'],
      },
      sourceName: 'dw.json',
    );

/// 1-3 狼、4 預言家、5 女巫、6 獵人、7 守衛、8 攝夢人、9-12 平民。
GameState _state() {
  final s = GameState(preset: _preset());
  void set(int seat, Role role) => s.playerAt(seat).role = role;
  for (final seat in [1, 2, 3]) {
    set(seat, Roles.wolf);
  }
  set(4, Roles.seer);
  set(5, Roles.witch);
  set(6, Roles.hunter);
  set(7, Roles.guard);
  set(8, Roles.dreamWeaver);
  for (var i = 9; i <= 12; i++) {
    set(i, Roles.villager);
  }
  s.dayNumber = 1;
  return s;
}

DeathCause? _causeOf(NightOutcome o, int seat) {
  for (final d in o.deaths) {
    if (d.seat == seat) return d.cause;
  }
  return null;
}

void main() {
  group('夢遊者免疫', () {
    test('擋得住狼刀', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..dreamTarget = 9
        ..wolfTarget = 9;

      expect(_arb.settle(s, a).deaths, isEmpty);
    });

    test('**連女巫的毒都擋** —— 守衛做不到這件事', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..dreamTarget = 9
        ..witchPoisonTarget = 9;

      expect(_arb.settle(s, a).deaths, isEmpty, reason: '這是攝夢人的核心強度');
    });

    test('對照：守衛守住的人照樣被毒死', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..guardTarget = 9
        ..witchPoisonTarget = 9;

      expect(_causeOf(_arb.settle(s, a), 9), DeathCause.poison);
    });

    test('同時被刀又被毒也擋得住', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..dreamTarget = 9
        ..wolfTarget = 9
        ..witchPoisonTarget = 9;

      expect(_arb.settle(s, a).deaths, isEmpty);
    });

    test('沒被攝的人不受保護', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..dreamTarget = 9
        ..wolfTarget = 10;

      expect(_causeOf(_arb.settle(s, a), 10), DeathCause.wolfKill);
    });
  });

  group('連續兩晚夢死', () {
    test('連兩晚攝同一人 → 夢死', () {
      final s = _state()..lastDreamTarget = 9;
      final a = NightActions(night: 2)..dreamTarget = 9;

      expect(_causeOf(_arb.settle(s, a), 9), DeathCause.dreamDeath);
    });

    test('換人攝就不會夢死', () {
      final s = _state()..lastDreamTarget = 9;
      final a = NightActions(night: 2)..dreamTarget = 10;

      expect(_arb.settle(s, a).deaths, isEmpty);
    });

    test('中間斷一晚就不算連續', () {
      final s = _state();

      // 第 1 夜攝 9。
      final n1 = NightActions(night: 1)..dreamTarget = 9;
      _arb.apply(s, n1, _arb.settle(s, n1));
      expect(s.lastDreamTarget, 9);

      // 第 2 夜不攝 —— 紀錄要跟著清掉。
      final n2 = NightActions(night: 2);
      _arb.apply(s, n2, _arb.settle(s, n2));
      expect(s.lastDreamTarget, isNull);

      // 第 3 夜又攝 9，不算連續。
      final n3 = NightActions(night: 3)..dreamTarget = 9;
      expect(_arb.settle(s, n3).deaths, isEmpty);
    });
  });

  group('夢死擋不住', () {
    test('守衛守住也照死', () {
      final s = _state()..lastDreamTarget = 9;
      final a = NightActions(night: 2)
        ..dreamTarget = 9
        ..guardTarget = 9;

      expect(_causeOf(_arb.settle(s, a), 9), DeathCause.dreamDeath);
    });

    test('夢遊本身的免疫也擋不了它', () {
      // 同一晚既被刀又連兩晚被攝：刀被免疫擋掉，夢死照樣成立。
      final s = _state()..lastDreamTarget = 9;
      final a = NightActions(night: 2)
        ..dreamTarget = 9
        ..wolfTarget = 9;

      expect(_causeOf(_arb.settle(s, a), 9), DeathCause.dreamDeath,
          reason: '死因是夢死，不是狼刀');
    });

    test('獵人夢死不能開槍', () {
      final s = _state()..lastDreamTarget = 6; // 6 號是獵人
      final a = NightActions(night: 2)..dreamTarget = 6;

      final o = _arb.settle(s, a);
      expect(_causeOf(o, 6), DeathCause.dreamDeath);
      expect(o.hunterMayShoot, isFalse);
    });

    test('對照：獵人被狼刀死可以開槍', () {
      final s = _state();
      final a = NightActions(night: 1)..wolfTarget = 6;

      expect(_arb.settle(s, a).hunterMayShoot, isTrue);
    });
  });

  // 法官在「獵人請睜眼」時比的手勢是**預告**：今晚若出局能不能開槍。
  // 以前只看毒 —— 獵人今晚會夢死，手勢卻比「可開槍」，天亮後又不讓他開。
  group('獵人的開槍手勢', () {
    test('連續第二晚被攝 → 比「不可開槍」', () {
      final s = _state()
        ..dayNumber = 2
        ..lastDreamTarget = 6;
      final a = NightActions(night: 2)..dreamTarget = 6;

      expect(_arb.hunterCanShootTonight(s, a), isFalse);
      expect(_arb.gunBlockedTonight(s, a, 6), DeathCause.dreamDeath);
    });

    test('他是夢遊者、攝夢人今晚被刀 → 一併夢死，比「不可開槍」', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..dreamTarget = 6
        ..wolfTarget = 8; // 8 號攝夢人

      expect(_arb.hunterCanShootTonight(s, a), isFalse);
      expect(_arb.gunBlockedTonight(s, a, 6), DeathCause.dreamDeath);
    });

    test('被毒但正在夢遊 → 毒沒作用，槍完好', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..dreamTarget = 6
        ..witchPoisonTarget = 6;

      expect(_arb.hunterCanShootTonight(s, a), isTrue);
      expect(_arb.gunBlockedTonight(s, a, 6), isNull);
    });

    test('對照：被毒、沒被攝 → 比「不可開槍」', () {
      final s = _state();
      final a = NightActions(night: 1)..witchPoisonTarget = 6;

      expect(_arb.hunterCanShootTonight(s, a), isFalse);
      expect(_arb.gunBlockedTonight(s, a, 6), DeathCause.poison);
    });

    test('對照：只被刀 → 比「可開槍」', () {
      final s = _state();
      final a = NightActions(night: 1)..wolfTarget = 6;

      expect(_arb.hunterCanShootTonight(s, a), isTrue);
    });

    // 擔當 2026-09-25 確認：學到槍牌的機械狼走同一套判斷。
    test('學到獵人的機械狼連續第二晚被攝 → 比「不可開槍」', () {
      final s = GameState(
        preset: Preset.fromJson(
          const {
            'presetId': 'dwm',
            'name': '攝夢機械狼測試板',
            'playerCount': 12,
            'roles': [
              {'role': 'wolf', 'count': 3},
              {'role': 'mechanicWolf', 'count': 1},
              {'role': 'dreamWeaver', 'count': 1},
              {'role': 'hunter', 'count': 1},
              {'role': 'villager', 'count': 6},
            ],
            'nightOrder': ['mechanicWolf', 'dreamWeaver', 'wolf'],
          },
          sourceName: 'dwm.json',
        ),
      );
      // 1-3 狼、4 機械狼、5 攝夢人、6 獵人、7-12 平民。
      final roles = <Role>[
        Roles.wolf,
        Roles.wolf,
        Roles.wolf,
        Roles.mechanicWolf,
        Roles.dreamWeaver,
        Roles.hunter,
      ];
      for (var seat = 1; seat <= 12; seat++) {
        s.playerAt(seat).role =
            seat <= roles.length ? roles[seat - 1] : Roles.villager;
      }
      s
        ..dayNumber = 2
        ..mechanicWolfLearnedRole = Roles.hunter
        ..mechanicWolfLearnedNight = 1
        ..lastDreamTarget = 4;

      final dreamed = NightActions(night: 2)..dreamTarget = 4;
      expect(_arb.mechanicCanShootTonight(s, dreamed), isFalse);
      expect(_arb.gunBlockedTonight(s, dreamed, 4), DeathCause.dreamDeath);

      final knifed = NightActions(night: 2)..wolfTarget = 4;
      expect(_arb.mechanicCanShootTonight(s, knifed), isTrue, reason: '對照：吃刀能開');
    });
  });

  group('攝夢人出局的連帶', () {
    test('攝夢人今晚被刀 → 夢遊者一併死亡', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..dreamTarget = 9
        ..wolfTarget = 8; // 8 號是攝夢人

      final o = _arb.settle(s, a);
      expect(_causeOf(o, 8), DeathCause.wolfKill);
      expect(_causeOf(o, 9), DeathCause.dreamDeath);
    });

    test('攝夢人活著就沒有連帶', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..dreamTarget = 9
        ..wolfTarget = 10;

      expect(_causeOf(_arb.settle(s, a), 9), isNull);
    });
  });

  test('撤銷會連上一晚的攝夢紀錄一起還原', () {
    final s = _state();
    final snapshot = s.copy();

    final a = NightActions(night: 1)..dreamTarget = 9;
    _arb.apply(s, a, _arb.settle(s, a));
    expect(s.lastDreamTarget, 9);

    s.restoreFrom(snapshot);
    expect(s.lastDreamTarget, isNull);
  });
}
