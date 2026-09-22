import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/engine/night_flow.dart';
import 'package:wgm/core/engine/night_flow_machine.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 熊（擔當 2026-09-22 指定）：
///
/// - 每晚查看**左右兩位鄰座**，其中有狼就咆哮
/// - 法官給的是**是／否**，不是告訴他哪一位
/// - 鄰座死亡時**往外順延**，取環狀座次上最近的兩位存活玩家

/// 12 人測試板：3狼 + 預女熊 + 6民。座次刻意讓熊夾在中間好推。
Preset _preset() => Preset.fromJson(
      const {
        'presetId': 'bear',
        'name': '熊測試板',
        'playerCount': 12,
        'roles': [
          {'role': 'wolf', 'count': 3},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'bear', 'count': 1},
          {'role': 'villager', 'count': 6},
        ],
        'nightOrder': ['wolf', 'witch', 'seer', 'bear'],
      },
      sourceName: 'bear.json',
    );

/// 1-3 狼、4 預言家、5 女巫、6 熊、7-12 平民。
///
/// 熊在 6 號，鄰座是 5（女巫）與 7（平民）—— 預設**不咆哮**。
GameState _state() {
  final s = GameState(preset: _preset());
  void set(int seat, Role role) => s.playerAt(seat).role = role;
  for (final seat in [1, 2, 3]) {
    set(seat, Roles.wolf);
  }
  set(4, Roles.seer);
  set(5, Roles.witch);
  set(6, Roles.bear);
  for (var i = 7; i <= 12; i++) {
    set(i, Roles.villager);
  }
  s.dayNumber = 1;
  return s;
}

void _kill(GameState s, List<int> seats) {
  for (final seat in seats) {
    s.playerAt(seat).alive = false;
  }
}

void main() {
  group('鄰座', () {
    test('取左右各一位', () {
      final s = _state();
      expect(NightArbitrator.bearNeighbors(s), [5, 7]);
    });

    test('鄰座死了往外順延', () {
      final s = _state();
      _kill(s, [5, 7]);
      expect(NightArbitrator.bearNeighbors(s), [4, 8]);
    });

    test('連續死亡會一路順延過去', () {
      final s = _state();
      _kill(s, [4, 5, 7, 8]);
      expect(NightArbitrator.bearNeighbors(s), [3, 9]);
    });

    test('座次是環狀的 —— 熊在 1 號時鄰座是 12 與 2', () {
      final s = GameState(preset: _preset());
      void set(int seat, Role role) => s.playerAt(seat).role = role;
      set(1, Roles.bear);
      for (final seat in [2, 3, 4]) {
        set(seat, Roles.wolf);
      }
      set(5, Roles.seer);
      set(6, Roles.witch);
      for (var i = 7; i <= 12; i++) {
        set(i, Roles.villager);
      }

      expect(NightArbitrator.bearNeighbors(s), [2, 12]);
    });

    test('熊死了就沒有鄰座', () {
      final s = _state();
      _kill(s, [6]);
      expect(NightArbitrator.bearNeighbors(s), isEmpty);
    });

    test('場上只剩熊時沒有鄰座 —— 不會繞回自己', () {
      final s = _state();
      _kill(s, [1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12]);
      expect(NightArbitrator.bearNeighbors(s), isEmpty);
    });

    test('只剩兩人時兩側順延到同一位，只算一次', () {
      final s = _state();
      _kill(s, [1, 2, 3, 4, 5, 8, 9, 10, 11, 12]); // 只剩 6（熊）與 7
      expect(NightArbitrator.bearNeighbors(s), [7]);
    });
  });

  group('咆哮', () {
    test('兩側都是好人 → 不咆哮', () {
      expect(NightArbitrator.bearGrowls(_state()), isFalse);
    });

    test('一側是狼 → 咆哮', () {
      final s = _state();
      // 讓 3 號狼變成熊的鄰座：把 4、5 號弄死，左側順延到 3。
      _kill(s, [4, 5]);
      expect(NightArbitrator.bearNeighbors(s), [3, 7]);
      expect(NightArbitrator.bearGrowls(s), isTrue);
    });

    test('狼死了之後就不再咆哮 —— 順延到下一位好人', () {
      final s = _state();
      _kill(s, [4, 5]);
      expect(NightArbitrator.bearGrowls(s), isTrue);

      _kill(s, [3]);
      expect(NightArbitrator.bearNeighbors(s), [2, 7]);
      expect(NightArbitrator.bearGrowls(s), isTrue, reason: '2 號還是狼');

      _kill(s, [2]);
      expect(NightArbitrator.bearNeighbors(s), [1, 7]);
      expect(NightArbitrator.bearGrowls(s), isTrue, reason: '1 號還是狼');

      _kill(s, [1]);
      expect(NightArbitrator.bearGrowls(s), isFalse, reason: '狼全死光了');
    });

    test('熊死了不咆哮', () {
      final s = _state();
      _kill(s, [4, 5, 6]);
      expect(NightArbitrator.bearGrowls(s), isFalse);
    });
  });

  group('夜晚流程', () {
    test('熊那一步不必選人，直接能往下', () {
      final s = _state();
      final m = NightFlowMachine(state: s, night: 1, isFirstNight: true);

      while (m.sub != NightSub.bearGrowl) {
        m.next();
        if (m.outcome != null) fail('沒走到熊那一步');
      }

      expect(m.requiredPickCount, 0);
      expect(m.selectableSeats, isEmpty);
      expect(m.canProceed, isTrue);
      expect(m.bearNeighbors, [5, 7]);
      expect(m.bearGrowls, isFalse);
    });

    test('每晚都有這一步 —— 鄰座會變，答案也會變', () {
      final s = _state()..dayNumber = 2;
      final steps = NightFlow.laterNightStepsFor(s, night: 2);
      expect(
        steps.any((step) => step.skill == NightSkill.bearGrowl),
        isTrue,
      );
    });

    test('咆哮會寫進復盤日誌', () {
      final s = _state();
      final m = NightFlowMachine(state: s, night: 1, isFirstNight: true);
      while (m.sub != NightSub.bearGrowl) {
        m.next();
      }
      m.next();

      final logged = s.log.entries.where((e) => e.text.contains('熊的鄰座'));
      expect(logged, hasLength(1));
      expect(logged.single.text, contains('不咆哮'));
    });
  });
}
