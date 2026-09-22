import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/engine/night_flow.dart';
import 'package:wgm/core/engine/win_checker.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 暗戀者（擔當 2026-09-22 指定）：
///
/// - 首夜選一名暗戀對象，雙方都不知情
/// - **本人永遠算好人** —— 預言家查是金水，屠邊也算神職人頭
/// - **勝負跟著對象的陣營走**，且**固定在選定那一刻**（對象之後變狼也不改）
/// - 對象死了勝利條件不變
///
/// 所以會出現「好人勝但暗戀者輸」與「狼人勝而暗戀者贏」這兩種結果。

const _arb = NightArbitrator();

/// 12 人測試板：3狼 + 預女獵暗 + 5民。
Preset _preset() => Preset.fromJson(
      const {
        'presetId': 'sa',
        'name': '暗戀者測試板',
        'playerCount': 12,
        'roles': [
          {'role': 'wolf', 'count': 3},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'secretAdmirer', 'count': 1},
          {'role': 'villager', 'count': 5},
        ],
        'nightOrder': ['wolf', 'witch', 'seer', 'secretAdmirer'],
      },
      sourceName: 'sa.json',
    );

/// 1-3 狼、4 預言家、5 女巫、6 獵人、7 暗戀者、8-12 平民。
GameState _state() {
  final s = GameState(preset: _preset());
  void set(int seat, Role role) => s.playerAt(seat).role = role;
  for (final seat in [1, 2, 3]) {
    set(seat, Roles.wolf);
  }
  set(4, Roles.seer);
  set(5, Roles.witch);
  set(6, Roles.hunter);
  set(7, Roles.secretAdmirer);
  for (var i = 8; i <= 12; i++) {
    set(i, Roles.villager);
  }
  s.dayNumber = 1;
  return s;
}

/// 把 [seats] 標記為出局。
void _kill(GameState s, List<int> seats) {
  for (final seat in seats) {
    s.playerAt(seat).alive = false;
  }
}

void main() {
  group('選定與固定', () {
    test('首夜選定後，對象與陣營都記進局面', () {
      final s = _state();
      final a = NightActions(night: 1)..secretAdmirerTarget = 1; // 1 號是狼
      _arb.apply(s, a, _arb.settle(s, a));

      expect(s.secretAdmirerTarget, 1);
      expect(s.secretAdmirerCamp, Camp.wolf);
    });

    test('選好人就固定在好人', () {
      final s = _state();
      final a = NightActions(night: 1)..secretAdmirerTarget = 8;
      _arb.apply(s, a, _arb.settle(s, a));

      expect(s.secretAdmirerCamp, Camp.good);
    });

    test('沒選就沒有勝負條件', () {
      final s = _state();
      final a = NightActions(night: 1);
      _arb.apply(s, a, _arb.settle(s, a));

      expect(s.secretAdmirerTarget, isNull);
      expect(s.secretAdmirerCamp, isNull);
    });

    test('選定之後不會被後續的夜晚覆蓋', () {
      final s = _state();
      final first = NightActions(night: 1)..secretAdmirerTarget = 1;
      _arb.apply(s, first, _arb.settle(s, first));

      // 第二夜不該再有這個步驟，但就算真的送進來也不能改。
      final second = NightActions(night: 2)..secretAdmirerTarget = 8;
      _arb.apply(s, second, _arb.settle(s, second));

      expect(s.secretAdmirerTarget, 1);
      expect(s.secretAdmirerCamp, Camp.wolf);
    });
  });

  group('本人永遠算好人', () {
    test('預言家查暗戀者是金水 —— 就算他暗戀的是狼', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..secretAdmirerTarget = 1
        ..seerTarget = 7;

      expect(_arb.settle(s, a).seerSawWolf, isFalse);
    });

    test('屠邊算神職人頭', () {
      final s = _state();
      expect(s.aliveGodCount, 4, reason: '預言家、女巫、獵人、暗戀者');
    });
  });

  group('勝負跟著對象走', () {
    test('暗戀狼 ＋ 狼人勝 → 暗戀者贏', () {
      final s = _state()
        ..secretAdmirerCamp = Camp.wolf
        ..secretAdmirerTarget = 1;
      _kill(s, [4, 5, 6, 7]); // 神職全滅（屠邊）

      final check = WinChecker.check(s);
      expect(check.result, GameResult.wolvesWin);
      expect(check.secretAdmirerWon, isTrue);
    });

    test('暗戀狼 ＋ 好人勝 → 暗戀者輸（好人贏了他還是輸）', () {
      final s = _state()
        ..secretAdmirerCamp = Camp.wolf
        ..secretAdmirerTarget = 1;
      _kill(s, [1, 2, 3]); // 狼全滅

      final check = WinChecker.check(s);
      expect(check.result, GameResult.goodWin);
      expect(check.secretAdmirerWon, isFalse);
    });

    test('暗戀好人 ＋ 好人勝 → 暗戀者贏', () {
      final s = _state()
        ..secretAdmirerCamp = Camp.good
        ..secretAdmirerTarget = 8;
      _kill(s, [1, 2, 3]);

      final check = WinChecker.check(s);
      expect(check.result, GameResult.goodWin);
      expect(check.secretAdmirerWon, isTrue);
    });

    test('暗戀好人 ＋ 狼人勝 → 暗戀者輸', () {
      final s = _state()
        ..secretAdmirerCamp = Camp.good
        ..secretAdmirerTarget = 8;
      _kill(s, [4, 5, 6, 7]);

      final check = WinChecker.check(s);
      expect(check.result, GameResult.wolvesWin);
      expect(check.secretAdmirerWon, isFalse);
    });

    test('對象死了，勝利條件不變', () {
      final s = _state()
        ..secretAdmirerCamp = Camp.wolf
        ..secretAdmirerTarget = 1;
      _kill(s, [1]); // 暗戀對象先出局
      _kill(s, [4, 5, 6, 7]); // 神職全滅

      expect(WinChecker.check(s).secretAdmirerWon, isTrue,
          reason: '對象死了照樣跟狼隊一起贏');
    });

    test('暗戀者自己死了也照算', () {
      final s = _state()
        ..secretAdmirerCamp = Camp.wolf
        ..secretAdmirerTarget = 1;
      _kill(s, [4, 5, 6, 7]);

      expect(s.playerAt(7).alive, isFalse);
      expect(WinChecker.check(s).secretAdmirerWon, isTrue);
    });
  });

  group('沒有暗戀者的局不受影響', () {
    test('secretAdmirerWon 為 null，陣營判定照舊', () {
      final s = _state();
      _kill(s, [1, 2, 3]);

      final check = WinChecker.check(s);
      expect(check.result, GameResult.goodWin);
      expect(check.secretAdmirerWon, isNull);
    });

    test('還沒分出勝負時也是 null', () {
      final s = _state()..secretAdmirerCamp = Camp.wolf;

      final check = WinChecker.check(s);
      expect(check.result, GameResult.ongoing);
      expect(check.secretAdmirerWon, isNull);
    });
  });

  group('夜晚步驟', () {
    test('首夜有暗戀者這一步', () {
      final steps = NightFlow.firstNightSteps(_preset());
      expect(
        steps.any((s) => s.skill == NightSkill.secretAdmire),
        isTrue,
      );
    });

    test('第二夜起不再叫起來', () {
      final s = _state();
      final steps = NightFlow.laterNightStepsFor(s, night: 2);
      expect(
        steps.any((step) => step.skill == NightSkill.secretAdmire),
        isFalse,
      );
    });
  });

  test('撤銷會連暗戀者的欄位一起還原', () {
    final s = _state();
    final snapshot = s.copy();

    final a = NightActions(night: 1)..secretAdmirerTarget = 1;
    _arb.apply(s, a, _arb.settle(s, a));
    expect(s.secretAdmirerCamp, Camp.wolf);

    s.restoreFrom(snapshot);
    expect(s.secretAdmirerTarget, isNull);
    expect(s.secretAdmirerCamp, isNull);
  });
}
