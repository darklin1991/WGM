import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/engine/night_flow_machine.dart';
import 'package:wgm/core/engine/vote_resolver.dart';
import 'package:wgm/core/engine/win_checker.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 白貓（擔當 2026-09-22 指定）：
///
/// - 任何原因出局時翻牌，**多活到下一次放逐投票結束**才真正離場
/// - 延後期間**算存活** —— 有投票權、可以發言、勝負判定也算他活著
/// - 延後期間**禁止成為技能目標**
/// - 白貓被放逐時，「下一次放逐投票」是**隔天**那一次
///
/// 因為整段期間都算存活，實作上是把死亡整個延後（`alive` 維持 true），
/// 不做「已死但還在場」的中間狀態。

const _arb = NightArbitrator();

/// 12 人測試板：3狼 + 預女獵貓 + 5民。
Preset _preset() => Preset.fromJson(
      const {
        'presetId': 'wc',
        'name': '白貓測試板',
        'playerCount': 12,
        'roles': [
          {'role': 'wolf', 'count': 3},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'whiteCat', 'count': 1},
          {'role': 'villager', 'count': 5},
        ],
        'nightOrder': ['wolf', 'witch', 'seer'],
      },
      sourceName: 'wc.json',
    );

/// 1-3 狼、4 預言家、5 女巫、6 獵人、7 白貓、8-12 平民。
GameState _state() {
  final s = GameState(preset: _preset());
  void set(int seat, Role role) => s.playerAt(seat).role = role;
  for (final seat in [1, 2, 3]) {
    set(seat, Roles.wolf);
  }
  set(4, Roles.seer);
  set(5, Roles.witch);
  set(6, Roles.hunter);
  set(7, Roles.whiteCat);
  for (var i = 8; i <= 12; i++) {
    set(i, Roles.villager);
  }
  s
    ..dayNumber = 1
    ..phase = GamePhase.night;
  return s;
}

/// 夜裡把白貓砍掉。
void _knifeWhiteCat(GameState s) {
  final a = NightActions(night: s.dayNumber)..wolfTarget = 7;
  _arb.apply(s, a, _arb.settle(s, a));
}

/// 跑完一次放逐投票（把 [target] 推出去；沒指定就全員棄票）。
ExileVote _runExileVote(GameState s, {int? target, List<int> voters = const []}) {
  s.phase = GamePhase.day;
  final v = ExileVote(state: s);
  if (target != null) {
    v.focusTarget(target);
    for (final voter in voters) {
      v.toggleVote(voter);
    }
  }
  v.next();
  return v;
}

void main() {
  group('夜裡被殺', () {
    test('當下不離場，翻牌但還活著', () {
      final s = _state();
      _knifeWhiteCat(s);

      expect(s.playerAt(7).alive, isTrue, reason: '延後期間算存活');
      expect(s.whiteCatRevealed, isTrue, reason: '翻牌是立刻的');
      expect(s.whiteCatPendingCause, DeathCause.wolfKill);
    });

    test('當天的放逐投票結束後才真正出局', () {
      final s = _state();
      _knifeWhiteCat(s);

      _runExileVote(s);
      expect(s.playerAt(7).alive, isFalse);
    });

    test('離場時死因保留原本的', () {
      final s = _state();
      _knifeWhiteCat(s);

      final v = _runExileVote(s);
      final death = v.deaths.where((d) => d.seat == 7).single;
      expect(death.cause, DeathCause.wolfKill, reason: '不是放逐');
    });

    test('延後期間有投票權', () {
      final s = _state();
      _knifeWhiteCat(s);

      s.phase = GamePhase.day;
      final v = ExileVote(state: s);
      expect(v.eligibleVoters, contains(7));
    });
  });

  group('白天被殺 → 隔天那次才生效', () {
    test('被放逐當下不離場，當次投票結束也還活著', () {
      final s = _state();
      final v = _runExileVote(s, target: 7, voters: [1, 2, 8]);

      expect(v.exiledSeat, 7);
      expect(s.playerAt(7).alive, isTrue, reason: '不是當下這一次');
      expect(s.whiteCatDeathDueAfterDay, 2, reason: '隔天');
    });

    test('隔天的放逐投票結束才出局', () {
      final s = _state();
      _runExileVote(s, target: 7, voters: [1, 2, 8]);
      expect(s.playerAt(7).alive, isTrue);

      s.dayNumber = 2;
      _runExileVote(s);
      expect(s.playerAt(7).alive, isFalse);
    });
  });

  group('延後期間禁止成為技能目標', () {
    test('刀、守、毒都選不到他', () {
      final s = _state();
      _knifeWhiteCat(s);
      s
        ..dayNumber = 2
        ..phase = GamePhase.night;

      final m = NightFlowMachine(state: s, night: 2, isFirstNight: false);
      // 第一步就是狼刀。
      expect(m.blockedSeats?[7], SeatBlockReason.whiteCatPending);
      expect(m.selectableSeats, isNot(contains(7)));
    });

    test('沒在延後中就不擋', () {
      final s = _state()
        ..dayNumber = 2
        ..phase = GamePhase.night;

      final m = NightFlowMachine(state: s, night: 2, isFirstNight: false);
      expect(m.blockedSeats?[7], isNull);
    });
  });

  group('勝負判定算他活著', () {
    test('白貓是最後一個神職時，屠邊還不成立', () {
      final s = _state();
      // 先讓其他神職全部出局。
      for (final seat in [4, 5, 6]) {
        s.playerAt(seat).alive = false;
      }
      _knifeWhiteCat(s);

      expect(s.aliveGodCount, 1, reason: '白貓還算活著');
      expect(WinChecker.check(s).result, GameResult.ongoing);
    });

    test('延後的死亡生效後才判狼勝', () {
      final s = _state();
      for (final seat in [4, 5, 6]) {
        s.playerAt(seat).alive = false;
      }
      _knifeWhiteCat(s);

      _runExileVote(s);
      expect(s.playerAt(7).alive, isFalse);
      expect(WinChecker.check(s).result, GameResult.wolvesWin);
    });
  });

  test('撤銷會連延後的死亡一起還原', () {
    final s = _state();
    final snapshot = s.copy();

    _knifeWhiteCat(s);
    expect(s.whiteCatPendingCause, isNotNull);

    s.restoreFrom(snapshot);
    expect(s.whiteCatPendingCause, isNull);
    expect(s.whiteCatDeathDueAfterDay, isNull);
    expect(s.whiteCatRevealed, isFalse);
  });
}
