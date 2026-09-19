import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/win_checker.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 12 人狼王守衛局：4狼 4神 4民。
Preset _preset({Map<String, dynamic>? rules}) => Preset.fromJson(
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
        'rules': ?rules,
      },
      sourceName: 'wk.json',
    );

/// 1-3 狼、4 狼王、5 預言家、6 女巫、7 獵人、8 守衛、9-12 平民。
GameState _state({Map<String, dynamic>? rules}) {
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
  return s;
}

void _kill(GameState s, List<int> seats) {
  for (final seat in seats) {
    s.playerAt(seat).alive = false;
  }
}

void main() {
  group('還沒分出勝負', () {
    test('開局', () {
      expect(WinChecker.check(_state()).result, GameResult.ongoing);
    });

    test('三邊都還有人', () {
      final s = _state();
      _kill(s, [1, 5, 9]); // 各死一個

      expect(WinChecker.check(s).result, GameResult.ongoing);
    });
  });

  group('好人勝', () {
    test('狼人全滅', () {
      final s = _state();
      _kill(s, [1, 2, 3, 4]);

      final w = WinChecker.check(s);
      expect(w.result, GameResult.goodWin);
      expect(w.reason, '狼人全數出局');
      expect(w.isOver, isTrue);
    });

    test('狼王也算狼 —— 只剩狼王時還沒輸', () {
      final s = _state();
      _kill(s, [1, 2, 3]);

      expect(WinChecker.check(s).result, GameResult.ongoing);
    });

    test('好人死到剩一個，只要狼全滅還是好人勝', () {
      final s = _state();
      _kill(s, [1, 2, 3, 4, 5, 6, 7, 9, 10, 11]);

      expect(WinChecker.check(s).result, GameResult.goodWin);
    });
  });

  // 目前六個板子都是屠邊。
  group('屠邊：神職全滅或平民全滅', () {
    test('神職全滅 → 狼勝', () {
      final s = _state();
      _kill(s, [5, 6, 7, 8]);

      final w = WinChecker.check(s);
      expect(w.result, GameResult.wolvesWin);
      expect(w.reason, '神職全滅（屠邊）');
    });

    test('平民全滅 → 狼勝', () {
      final s = _state();
      _kill(s, [9, 10, 11, 12]);

      final w = WinChecker.check(s);
      expect(w.result, GameResult.wolvesWin);
      expect(w.reason, '平民全滅（屠邊）');
    });

    test('神職剩一個就還沒輸', () {
      final s = _state();
      _kill(s, [5, 6, 7]);

      expect(WinChecker.check(s).result, GameResult.ongoing);
    });

    test('平民剩一個就還沒輸', () {
      final s = _state();
      _kill(s, [9, 10, 11]);

      expect(WinChecker.check(s).result, GameResult.ongoing);
    });

    test('狼與神職同時全滅 → 好人勝（狼全滅優先）', () {
      final s = _state();
      _kill(s, [1, 2, 3, 4, 5, 6, 7, 8]);

      expect(WinChecker.check(s).result, GameResult.goodWin,
          reason: '狼都死光了就是好人贏，不必再看屠邊');
    });

    test('白痴翻牌後還活著，算神職沒全滅', () {
      final s = _state();
      s.playerAt(5).role = Roles.idiot;
      _kill(s, [6, 7, 8]); // 其餘神職死光，白痴還在
      s.playerAt(5).canVote = false; // 翻過牌，沒投票權但活著

      expect(WinChecker.check(s).result, GameResult.ongoing,
          reason: '白痴還在場上就不算神職全滅');
    });
  });

  group('屠城：好人全滅才算', () {
    GameState totalState() =>
        _state(rules: const {'winCondition': 'totalElimination'});

    test('神職全滅但平民還在 → 還沒結束', () {
      final s = totalState();
      _kill(s, [5, 6, 7, 8]);

      expect(WinChecker.check(s).result, GameResult.ongoing,
          reason: '屠城要好人全部死光');
    });

    test('平民全滅但神職還在 → 還沒結束', () {
      final s = totalState();
      _kill(s, [9, 10, 11, 12]);

      expect(WinChecker.check(s).result, GameResult.ongoing);
    });

    test('好人全滅 → 狼勝', () {
      final s = totalState();
      _kill(s, [5, 6, 7, 8, 9, 10, 11, 12]);

      final w = WinChecker.check(s);
      expect(w.result, GameResult.wolvesWin);
      expect(w.reason, '好人全滅（屠城）');
    });
  });

  // 板子裡本來就沒配置的陣營不算「全滅」，否則開局就直接判狼勝。
  group('板子沒配置的陣營不算全滅', () {
    test('沒有平民的板子，不會因為平民數為 0 就判狼勝', () {
      final preset = Preset.fromJson(
        const {
          'presetId': 'nv',
          'name': '無平民局',
          'playerCount': 6,
          'roles': [
            {'role': 'wolf', 'count': 2},
            {'role': 'seer', 'count': 1},
            {'role': 'witch', 'count': 1},
            {'role': 'hunter', 'count': 1},
            {'role': 'guard', 'count': 1},
          ],
          'nightOrder': ['guard', 'wolf', 'witch', 'seer'],
        },
        sourceName: 'nv.json',
      );
      final s = GameState(preset: preset);
      void set(int seat, Role r) => s.playerAt(seat).role = r;
      set(1, Roles.wolf);
      set(2, Roles.wolf);
      set(3, Roles.seer);
      set(4, Roles.witch);
      set(5, Roles.hunter);
      set(6, Roles.guard);

      expect(s.preset.villagerCount, 0);
      expect(WinChecker.check(s).result, GameResult.ongoing);
    });
  });
}
