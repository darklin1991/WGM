import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/badge_succession.dart';
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

/// 1-3 狼、4 狼王、5 預言家、6 女巫、7 獵人、8 守衛、9-12 平民。
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
  s.dayNumber = 2;
  return s;
}

void main() {
  group('什麼時候要走警徽流', () {
    test('沒有警長 → 不用走', () {
      expect(BadgeSuccession.isDue(_state()), isFalse);
    });

    test('警長還活著 → 不用走', () {
      final s = _state()..sheriffSeat = 5;

      expect(BadgeSuccession.isDue(s), isFalse);
    });

    test('警長出局 → 要走', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;

      expect(BadgeSuccession.isDue(s), isTrue);
    });

    test('死掉的人當選警長（第一天競選排在公布死訊之前）→ 一樣要走', () {
      final s = _state();
      s.playerAt(5).alive = false; // 昨晚死的，但死訊還沒公布
      s.sheriffSeat = 5; // 照樣上警當選

      expect(BadgeSuccession.isDue(s), isTrue,
          reason: '不看是哪一輪死的，只看警長現在是不是死人');
    });

    test('撕毀之後不會再觸發', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      BadgeSuccession(state: s).destroy();

      expect(BadgeSuccession.isDue(s), isFalse);
    });

    test('移交之後不會再觸發', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      BadgeSuccession(state: s).passTo(9);

      expect(BadgeSuccession.isDue(s), isFalse);
    });
  });

  group('移交對象', () {
    test('任一存活玩家都能接，包含狼', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      final b = BadgeSuccession(state: s);

      expect(b.candidates, {1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12});
      expect(b.candidates.contains(1), isTrue, reason: '法官不知道誰是狼，照樣可選');
    });

    test('已出局的人不在名單裡，也交不過去', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      s.playerAt(9).alive = false;
      final b = BadgeSuccession(state: s);

      expect(b.candidates.contains(9), isFalse);

      b.passTo(9);
      expect(b.finished, isFalse, reason: '交給死人應該沒有作用');
      expect(s.sheriffSeat, 5);
    });

    test('移交後 sheriffSeat 換人，並留下宣布稿', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      final b = BadgeSuccession(state: s)..passTo(9);

      expect(s.sheriffSeat, 9);
      expect(b.outcome, BadgeOutcome.passed);
      expect(b.newSheriff, 9);
      expect(b.formerSheriff, 5);
      expect(b.notes, ['5 號的警徽移交給 9 號，9 號成為新警長']);
    });

    test('決定過就不能再改（要改得先撤銷）', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      final b = BadgeSuccession(state: s)
        ..passTo(9)
        ..passTo(10);

      expect(s.sheriffSeat, 9);
      expect(b.notes.length, 1);
    });
  });

  group('撕警徽', () {
    test('撕掉後本局無警長', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      final b = BadgeSuccession(state: s)..destroy();

      expect(s.sheriffSeat, isNull);
      expect(b.outcome, BadgeOutcome.destroyed);
      expect(b.newSheriff, isNull);
      expect(b.notes, ['5 號撕毀警徽，本局之後沒有警長']);
    });

    test('全場只剩死人時只能撕', () {
      final s = _state()..sheriffSeat = 5;
      for (var seat = 1; seat <= 12; seat++) {
        s.playerAt(seat).alive = false;
      }
      final b = BadgeSuccession(state: s);

      expect(b.candidates, isEmpty);
      expect(b.mustDestroy, isTrue);
    });
  });

  group('毒死的警長照樣移交', () {
    test('死因不影響警徽 —— 毒藥只擋獵人開槍', () {
      final s = _state()..sheriffSeat = 7; // 獵人當警長
      s.playerAt(7).alive = false; // 假設是被毒死的
      final b = BadgeSuccession(state: s)..passTo(9);

      expect(s.sheriffSeat, 9);
      expect(b.outcome, BadgeOutcome.passed);
    });
  });

  group('撤銷', () {
    test('一開始沒有東西可撤銷', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;

      expect(BadgeSuccession(state: s).canUndo, isFalse);
    });

    test('撤銷移交 → 警徽回到原警長手上，可以重選', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      final b = BadgeSuccession(state: s)..passTo(9);

      expect(b.canUndo, isTrue);
      expect(b.undoLabel, '移交警徽');

      expect(b.undo(), isTrue);
      expect(s.sheriffSeat, 5);
      expect(b.outcome, BadgeOutcome.pending);
      expect(b.newSheriff, isNull);
      expect(b.notes, isEmpty);
      expect(b.finished, isFalse);

      b.passTo(10);
      expect(s.sheriffSeat, 10);
    });

    test('撤銷撕毀 → 警徽回來，改成移交也可以', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      final b = BadgeSuccession(state: s)..destroy();

      expect(b.undo(), isTrue);
      expect(s.sheriffSeat, 5);
      expect(b.outcome, BadgeOutcome.pending);

      b.passTo(9);
      expect(s.sheriffSeat, 9);
      expect(b.outcome, BadgeOutcome.passed);
    });

    test('撤銷不會動到別人的生死', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      s.playerAt(9).alive = false;
      final b = BadgeSuccession(state: s)..passTo(10);

      b.undo();
      expect(s.playerAt(5).alive, isFalse);
      expect(s.playerAt(9).alive, isFalse);
      expect(s.playerAt(10).alive, isTrue);
    });
  });
}
