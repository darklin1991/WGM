import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/seat_ring.dart';
import 'package:wgm/core/engine/speech_order.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

Preset _preset() => Preset.fromJson(
      const {
        'presetId': 'wk',
        'name': '狼王守衛局',
        'playerCount': 12,
        'roles': [
          {'role': 'wolf', 'count': 3},
          {'role': 'wolfKing', 'count': 1},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'guard', 'count': 1},
          {'role': 'villager', 'count': 4},
        ],
        'nightOrder': ['guard', 'wolf', 'witch', 'seer'],
      },
      sourceName: 'wk.json',
    );

GameState _state() {
  final s = GameState(preset: _preset());
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

void main() {
  group('環狀座次走訪', () {
    test('順時鐘＝座號遞增，走一圈繞回來', () {
      expect(
        SeatRing.walkFrom(_state(), from: 10, clockwise: true),
        [11, 12, 1, 2, 3, 4, 5, 6, 7, 8, 9],
      );
    });

    test('逆時鐘＝座號遞減', () {
      expect(
        SeatRing.walkFrom(_state(), from: 3, clockwise: false),
        [2, 1, 12, 11, 10, 9, 8, 7, 6, 5, 4],
      );
    });

    test('不含起點本身', () {
      final seats = SeatRing.walkFrom(_state(), from: 5, clockwise: true);

      expect(seats.contains(5), isFalse);
      expect(seats.length, 11, reason: '12 人扣掉起點');
    });

    test('只取存活的會跳過死人', () {
      final s = _state();
      for (final seat in [11, 12, 2]) {
        s.playerAt(seat).alive = false;
      }

      expect(
        SeatRing.aliveFrom(s, from: 10, clockwise: true),
        [1, 3, 4, 5, 6, 7, 8, 9],
      );
    });
  });

  // 擔當指定的規則：
  // 單死 → 死者起算；其餘 → 警長起算；沒有警長 → 起點與方向都隨機。
  group('用什麼當起點', () {
    test('單死 → 從死者算起', () {
      final s = _state()..sheriffSeat = 5;

      expect(SpeechOrder.basisFor(s, [10]), SpeechOrderBasis.deceased);
    });

    test('平安夜 → 從警長算起', () {
      final s = _state()..sheriffSeat = 5;

      expect(SpeechOrder.basisFor(s, []), SpeechOrderBasis.sheriff);
    });

    test('雙死以上 → 從警長算起', () {
      final s = _state()..sheriffSeat = 5;

      expect(SpeechOrder.basisFor(s, [9, 10]), SpeechOrderBasis.sheriff);
      expect(SpeechOrder.basisFor(s, [9, 10, 11]), SpeechOrderBasis.sheriff);
    });

    test('沒有警長 → 一律隨機，就算只死一個也一樣', () {
      final s = _state();

      expect(SpeechOrder.basisFor(s, []), SpeechOrderBasis.random);
      expect(SpeechOrder.basisFor(s, [10]), SpeechOrderBasis.random,
          reason: '死左死右的方向本來就該由警長決定，沒警長就沒人能決定');
    });
  });

  group('警長起算（警左／警右）', () {
    test('順時鐘：從警長下一位開始，警長最後發言', () {
      final s = _state()..sheriffSeat = 5;

      expect(
        SpeechOrder.resolve(s, referenceSeat: 5, clockwise: true),
        [6, 7, 8, 9, 10, 11, 12, 1, 2, 3, 4, 5],
      );
    });

    test('逆時鐘：號碼往下走，警長一樣最後', () {
      final s = _state()..sheriffSeat = 5;

      expect(
        SpeechOrder.resolve(s, referenceSeat: 5, clockwise: false),
        [4, 3, 2, 1, 12, 11, 10, 9, 8, 7, 6, 5],
      );
    });

    test('死掉的人不排進發言順序', () {
      final s = _state()..sheriffSeat = 5;
      for (final seat in [7, 8]) {
        s.playerAt(seat).alive = false;
      }

      expect(
        SpeechOrder.resolve(s, referenceSeat: 5, clockwise: true),
        [6, 9, 10, 11, 12, 1, 2, 3, 4, 5],
      );
    });
  });

  group('死者起算（死左／死右）', () {
    test('順時鐘：從死者下一位開始，死者不發言', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(10).alive = false;

      final order = SpeechOrder.resolve(s, referenceSeat: 10, clockwise: true);

      expect(order, [11, 12, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(order.contains(10), isFalse, reason: '死者不在名單裡');
    });

    test('逆時鐘', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(10).alive = false;

      expect(
        SpeechOrder.resolve(s, referenceSeat: 10, clockwise: false),
        [9, 8, 7, 6, 5, 4, 3, 2, 1, 12, 11],
      );
    });

    test('警長夾在中間照樣發言，不會被排到最後', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(10).alive = false;

      final order = SpeechOrder.resolve(s, referenceSeat: 10, clockwise: true);

      expect(order.indexOf(5), 6, reason: '警長只是順序中的一位');
      expect(order.last, 9);
    });
  });

  group('plan 產出的資訊', () {
    test('警長起算時，警長自己排最後', () {
      final s = _state()..sheriffSeat = 5;
      final p = SpeechOrder.plan(
        s,
        basis: SpeechOrderBasis.sheriff,
        referenceSeat: 5,
        clockwise: true,
      );

      expect(p.referenceSpeaks, isTrue);
      expect(p.order.last, 5);
    });

    test('死者起算時，參考座次不發言', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(10).alive = false;
      final p = SpeechOrder.plan(
        s,
        basis: SpeechOrderBasis.deceased,
        referenceSeat: 10,
        clockwise: true,
      );

      expect(p.referenceSpeaks, isFalse);
    });
  });

  group('沒有警長：起點與方向都隨機', () {
    test('抽到的那位自己先發言', () {
      final s = _state();
      final p = SpeechOrder.randomPlan(s, random: Random(1));

      expect(p.basis, SpeechOrderBasis.random);
      expect(p.order.first, p.referenceSeat,
          reason: '抽到誰誰先講，不是從他的下一位開始');
      expect(p.order.length, 12);
    });

    test('順序涵蓋所有存活玩家且不重複', () {
      final s = _state();
      for (final seat in [2, 7, 11]) {
        s.playerAt(seat).alive = false;
      }

      final p = SpeechOrder.randomPlan(s, random: Random(7));

      expect(p.order.length, 9);
      expect(p.order.toSet().length, 9, reason: '不重複');
      expect(p.order.any((seat) => !s.playerAt(seat).alive), isFalse);
    });

    test('起點一定是存活玩家', () {
      final s = _state();
      for (final seat in [1, 2, 3, 4, 5]) {
        s.playerAt(seat).alive = false;
      }

      for (var seed = 0; seed < 30; seed++) {
        final p = SpeechOrder.randomPlan(s, random: Random(seed));
        expect(s.playerAt(p.referenceSeat).alive, isTrue);
      }
    });

    test('多抽幾次，順時鐘與逆時鐘都出得來', () {
      final s = _state();
      final directions = {
        for (var seed = 0; seed < 20; seed++)
          SpeechOrder.randomPlan(s, random: Random(seed)).clockwise,
      };

      expect(directions, {true, false}, reason: '方向是隨機的，不是固定一邊');
    });

    test('全場都死了不會爆掉', () {
      final s = _state();
      for (final p in s.players) {
        p.alive = false;
      }

      expect(SpeechOrder.randomPlan(s).order, isEmpty);
    });
  });
}
