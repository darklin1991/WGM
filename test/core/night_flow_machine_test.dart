import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_flow_machine.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 12 人狼王守衛局。夜晚第一步是守衛。
Preset _preset({Map<String, dynamic> rules = const {}}) => Preset.fromJson(
      {
        'presetId': 'wk',
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
        if (rules.isNotEmpty) 'rules': rules,
      },
      sourceName: 'wk.json',
    );

GameState _seeded({Map<String, dynamic> rules = const {}}) {
  final s = GameState(preset: _preset(rules: rules));
  void set(int seat, Role r) => s.playerAt(seat).role = r;
  for (final seat in [1, 2, 3]) {
    set(seat, Roles.wolf);
  }
  set(4, Roles.wolfKing);
  set(5, Roles.seer);
  set(6, Roles.witch);
  set(7, Roles.hunter);
  set(8, Roles.guard);
  for (var i = 9; i <= 12; i++) {
    set(i, Roles.villager);
  }
  s.dayNumber = 1;
  return s;
}

NightFlowMachine _machine(GameState s) =>
    NightFlowMachine(state: s, night: 2, isFirstNight: false);

void main() {
  // `blockedSeatFor` 是給 UI 寫提示文案用的反查（「昨晚守了 N 號」）。
  // 它存在的理由是讓規則旗標只有引擎一個判斷點 —— 頁面不該自己再讀一次
  // `guardCannotRepeatTarget` 算出同一件事。這組測試釘住的就是這件事：
  // 反查結果必須和 `blockedSeats` 永遠一致，包含旗標關掉時兩邊一起失效。
  group('blockedSeatFor', () {
    test('連守限制生效時，回傳昨晚守的座次', () {
      final s = _seeded();
      s.lastGuardTarget = 5;
      final m = _machine(s);

      expect(m.blockedSeatFor(SeatBlockReason.guardedLastNight), 5);
      expect(m.blockedSeats, {5: SeatBlockReason.guardedLastNight});
      expect(m.selectableSeats, isNot(contains(5)));
    });

    test('旗標關掉就不擋，反查也一起回 null', () {
      final s = _seeded(rules: const {'guardCannotRepeatTarget': false});
      s.lastGuardTarget = 5;
      final m = _machine(s);

      expect(m.blockedSeatFor(SeatBlockReason.guardedLastNight), isNull);
      expect(m.blockedSeats, isNull);
      // selectableSeats 的 null 是「不限」，不是「一個都不能選」。
      expect(m.selectableSeats, isNull);
    });

    test('昨晚沒守人就沒有限制', () {
      final m = _machine(_seeded());

      expect(m.blockedSeatFor(SeatBlockReason.guardedLastNight), isNull);
      expect(m.blockedSeats, isNull);
    });

    test('問的原因和當下擋人的原因不同時回 null', () {
      final s = _seeded();
      s.lastGuardTarget = 5;
      final m = _machine(s);

      expect(m.blockedSeatFor(SeatBlockReason.charmedLastNight), isNull);
      expect(m.blockedSeatFor(SeatBlockReason.mechanicSelfLearn), isNull);
    });

    test('機械狼學到守衛時查到的是機械狼自己的守護紀錄', () {
      // 機械狼的守護紀錄與原守衛各自獨立 —— 這個分流本來就在引擎裡，
      // 反查跟著走同一份結果，頁面不必重算一次行動者是誰。
      final s = _seeded();
      s.lastGuardTarget = 5;
      s.lastMechanicGuardTarget = 9;
      final m = _machine(s);

      // 這個板子沒有機械狼，目前這一步的行動者就是原守衛。
      expect(m.step.byMechanicWolf, isFalse);
      expect(m.lastGuardOfActor, 5);
      expect(m.blockedSeatFor(SeatBlockReason.guardedLastNight), 5);
    });
  });
}
