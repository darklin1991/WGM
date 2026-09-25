import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/knight_duel.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/engine/night_death_shot.dart';
import 'package:wgm/core/engine/night_flow.dart';
import 'package:wgm/core/engine/night_flow_machine.dart';
import 'package:wgm/core/engine/speech_order.dart';
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

    // 以前夜裡被判死是無聲延後：結算頁當成一般出局公布，日誌記一筆「出局」，
    // 真正離場時又記一筆「正式出局」，復盤看到同一個人死兩次。
    test('結算照實講「翻牌、還在場」', () {
      final s = _state();
      final a = NightActions(night: 1)..wolfTarget = 7;
      final o = _arb.settle(s, a);

      expect(o.whiteCatDeferredSeats, [7]);
      expect(o.notes, contains('白貓（7 號）翻牌，要到今天的放逐投票結束才真正出局'));
    });

    test('日誌只記一次出局 —— 在真正離場的時候', () {
      final s = _state();
      _knifeWhiteCat(s);
      _runExileVote(s);

      final texts = s.log.entries.map((e) => e.text).toList();
      expect(texts, contains('7 號翻牌（白貓・狼刀），今天的放逐投票結束才離場'));
      expect(texts.where((t) => t.startsWith('7 號出局')), isEmpty);
      expect(texts.where((t) => t.contains('正式出局')), hasLength(1));
    });

    test('不是白貓就沒有這個標記', () {
      final s = _state();
      final a = NightActions(night: 1)..wolfTarget = 8;
      expect(_arb.settle(s, a).whiteCatDeferredSeats, isEmpty);
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

    test('女巫的毒也選不到他', () {
      final s = _state();
      _knifeWhiteCat(s);
      s
        ..dayNumber = 2
        ..phase = GamePhase.night;

      final m = NightFlowMachine(state: s, night: 2, isFirstNight: false);
      while (m.sub != NightSub.witchPotion) {
        m.next();
      }
      expect(m.blockedSeats?[7], SeatBlockReason.whiteCatPending);
      m.toggleSeat(7);
      expect(m.picked, isEmpty, reason: '擋在引擎，不能只靠 UI');
    });

    group('機械狼', () {
      /// 1-2 狼、3 機械狼、4 白貓（延後中）、5 女巫、6 預言家、7 守衛、8-12 平民。
      GameState mechanicState() {
        final s = GameState(
          preset: Preset.fromJson(
            const {
              'presetId': 'wcm',
              'name': '白貓機械狼測試板',
              'playerCount': 12,
              'roles': [
                {'role': 'wolf', 'count': 2},
                {'role': 'mechanicWolf', 'count': 1},
                {'role': 'whiteCat', 'count': 1},
                {'role': 'witch', 'count': 1},
                {'role': 'seer', 'count': 1},
                {'role': 'guard', 'count': 1},
                {'role': 'villager', 'count': 5},
              ],
              'nightOrder': ['mechanicWolf', 'guard', 'wolf', 'witch', 'seer'],
            },
            sourceName: 'wcm.json',
          ),
        );
        final roles = <Role>[
          Roles.wolf,
          Roles.wolf,
          Roles.mechanicWolf,
          Roles.whiteCat,
          Roles.witch,
          Roles.seer,
          Roles.guard,
        ];
        for (var seat = 1; seat <= 12; seat++) {
          s.playerAt(seat).role =
              seat <= roles.length ? roles[seat - 1] : Roles.villager;
        }
        s
          ..dayNumber = 2
          ..phase = GamePhase.night
          ..whiteCatPendingCause = DeathCause.exile
          ..whiteCatDeathDueAfterDay = 2;
        return s;
      }

      test('帶刀的機械狼也砍不到他', () {
        final s = mechanicState();
        s.playerAt(1).alive = false;
        s.playerAt(2).alive = false; // 小狼全滅，機械狼帶刀
        final m = NightFlowMachine(state: s, night: 2, isFirstNight: false);
        while (m.sub != NightSub.mechanicKnife) {
          m.next();
          if (m.finished) fail('沒走到機械狼的刀');
        }

        expect(m.selectableSeats, isNot(contains(4)));
        m.toggleSeat(4);
        expect(m.picked, isEmpty);
      });

      // 以前有白貓在延後中，那一步就只擋白貓，原本的限制整批不見。
      test('白貓與「不能學自己」兩條一起擋', () {
        final m = NightFlowMachine(
          state: mechanicState(),
          night: 2,
          isFirstNight: false,
        );
        while (m.effectiveSkill != NightSkill.mechanicLearn ||
            m.sub != NightSub.chooseTarget) {
          m.next();
          if (m.finished) fail('沒走到學習');
        }

        expect(m.blockedSeats, {
          3: SeatBlockReason.mechanicSelfLearn,
          4: SeatBlockReason.whiteCatPending,
        });
      });

      test('白貓與「不能連守」兩條一起擋', () {
        final s = mechanicState()..lastGuardTarget = 9;
        final m = NightFlowMachine(state: s, night: 2, isFirstNight: false);
        while (m.effectiveSkill != NightSkill.guardProtect) {
          m.next();
          if (m.finished) fail('沒走到守衛');
        }

        expect(m.blockedSeats, {
          9: SeatBlockReason.guardedLastNight,
          4: SeatBlockReason.whiteCatPending,
        });
      });
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

  // 擔當 2026-09-24 指定：延後中的白貓也不能被獵人、狼王開槍帶走，
  // 不能被騎士決鬥。打中的話 deferWhiteCatDeath 不會再延一次，他會當場死亡。
  group('白天：開槍與決鬥也選不到他', () {
    GameState pending() {
      final s = _state()
        ..phase = GamePhase.day
        ..whiteCatPendingCause = DeathCause.wolfKill
        ..whiteCatDeathDueAfterDay = 1;
      return s;
    }

    test('獵人被放逐後開槍', () {
      final s = pending();
      final v = ExileVote(state: s)..focusTarget(6);
      for (final voter in [1, 2, 8]) {
        v.toggleVote(voter);
      }
      v.next();
      expect(v.stage, ExileStage.shoot);

      expect(v.shootTargets, isNot(contains(7)));
      v.shoot(7);
      expect(v.stage, ExileStage.shoot, reason: '點不動，還停在開槍');
      expect(s.playerAt(7).alive, isTrue);
    });

    test('夜死的獵人天亮後開槍', () {
      final s = pending();
      s.playerAt(6).alive = false;
      final shot = NightDeathShot(state: s, shooters: [6]);

      expect(shot.targets, isNot(contains(7)));
      shot.shoot(7);
      expect(shot.finished, isFalse);
      expect(s.playerAt(7).alive, isTrue);
    });

    test('騎士決鬥', () {
      final s = pending();
      s.playerAt(8).role = Roles.knight; // 只借用來測對手範圍
      final duel = KnightDuel(state: s);

      expect(duel.opponents, isNot(contains(7)));
      duel.duel(7);
      expect(duel.finished, isFalse);
      expect(s.knightDuelUsed, isFalse, reason: '沒發動就不算用掉');
    });
  });

  // 上面幾組都是手動設 phase 的單元測試。這一組走實際的夜晚狀態機，
  // 不碰 phase —— 以前 App 裡沒有任何地方把 phase 設成白天，
  // 白天判死一律被當成夜裡，當次投票結束就離場。
  group('走實際流程，不手動設 phase', () {
    /// 用狀態機跑完一夜；[knife] 指定狼刀目標。
    void runNight(GameState s, {int? knife}) {
      final m = NightFlowMachine(
        state: s,
        night: s.dayNumber,
        isFirstNight: false,
      );
      for (var i = 0; i < 50 && !m.finished; i++) {
        if (knife != null &&
            m.sub == NightSub.chooseTarget &&
            m.effectiveSkill == NightSkill.wolfKill) {
          m.toggleSeat(knife);
        }
        m.next();
      }
      expect(m.finished, isTrue);
    }

    ExileVote exile(GameState s, int target) {
      final v = ExileVote(state: s)..focusTarget(target);
      for (final voter in [1, 2, 8]) {
        v.toggleVote(voter);
      }
      v.next();
      return v;
    }

    test('夜晚結算完就是白天', () {
      final s = _state();
      runNight(s);
      expect(s.phase, GamePhase.day);
    });

    test('白天被放逐 → 當次投票結束還活著，隔天才生效', () {
      final s = _state();
      runNight(s);

      final v = exile(s, 7);
      expect(v.exiledSeat, 7);
      expect(s.playerAt(7).alive, isTrue, reason: '不是當下這一次');
      expect(s.whiteCatDeathDueAfterDay, 2);
    });

    test('夜裡被刀 → 當天的放逐投票結束就生效', () {
      final s = _state();
      runNight(s, knife: 7);
      expect(s.playerAt(7).alive, isTrue, reason: '延後期間算存活');

      exile(s, 9);
      expect(s.playerAt(7).alive, isFalse);
    });
  });

  // 擔當 2026-09-25 指定：延後離場的白貓**算**發言順序的死者。
  group('發言順序算他是死者', () {
    test('昨晚死一人、白貓也被判死 → 算雙死，從警長算起', () {
      final s = _state()..sheriffSeat = 4;
      final a = NightActions(night: 1)
        ..wolfTarget = 7
        ..witchPoisonTarget = 9;
      final o = _arb.settle(s, a);

      expect(o.deadSeats, [7, 9]);
      expect(SpeechOrder.basisFor(s, o.deadSeats), SpeechOrderBasis.sheriff);
    });

    test('只有白貓被判死 → 算單死；他還在場，排最後發言', () {
      final s = _state()..sheriffSeat = 4;
      _knifeWhiteCat(s);

      expect(SpeechOrder.basisFor(s, [7]), SpeechOrderBasis.deceased);
      final order = SpeechOrder.resolve(s, referenceSeat: 7, clockwise: true);
      expect(order.last, 7, reason: '延後期間算存活，照常發言');
    });
  });
}
