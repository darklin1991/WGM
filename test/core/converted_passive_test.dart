import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/knight_duel.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/engine/night_death_shot.dart';
import 'package:wgm/core/engine/seat_block_reason.dart';
import 'package:wgm/core/engine/vote_resolver.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 2026-09-25 重新檢查時修掉的幾項：
///
/// - 被轉換者接刀那一刻喪失原技能 —— 不只獵人的槍，白貓的延後離場、
///   河豚的翻牌也一樣
/// - 延後離場的白貓還在場上，不列進遺言
/// - 結算說明的「機械狼學習……」依學到的身分寫生效時機
/// - 騎士決鬥的禁選原因也由引擎回傳

const _arb = NightArbitrator();

/// 風聲諜影，照設定檔的角色順序配座次：
/// 1、2 石像鬼、3 機械狼、4 預言家、5 通靈師、6 熊、7 女巫、8 獵人、
/// 9 攝夢人、10 河豚、11 白貓、12 暗戀者。
GameState _state() {
  final json = jsonDecode(
    File('assets/presets/12p_fengsheng_dieying.json').readAsStringSync(),
  ) as Map;
  final s = GameState(
    preset: Preset.fromJson(
      json.cast<String, dynamic>(),
      sourceName: '12p_fengsheng_dieying.json',
    ),
  );
  var seat = 1;
  for (final slot in s.preset.roles) {
    for (var i = 0; i < slot.count; i++) {
      s.playerAt(seat++).role = slot.role;
    }
  }
  s
    ..dayNumber = 2
    ..phase = GamePhase.night
    ..conversionNight = 1;
  return s;
}

/// [seat] 被轉換，石像鬼與機械狼都已出局 —— 只剩他一位轉換者，今晚由他接刀。
GameState _knifeHolder(int seat) {
  final s = _state()..convertedSeats.add(seat);
  for (final dead in [1, 2, 3]) {
    s.playerAt(dead).alive = false;
  }
  return s;
}

ExileVote _exile(GameState s, int target, List<int> voters) {
  s.phase = GamePhase.day;
  final v = ExileVote(state: s)..focusTarget(target);
  for (final voter in voters) {
    v.toggleVote(voter);
  }
  v.next();
  return v;
}

void main() {
  group('被轉換的白貓接刀之後', () {
    test('接刀當夜被毒 → 不再延後，當場出局', () {
      final s = _knifeHolder(11);
      final a = NightActions(night: 2)..witchPoisonTarget = 11;
      final o = _arb.settle(s, a);
      _arb.apply(s, a, o);

      expect(o.whiteCatDeferredSeats, isEmpty);
      expect(s.playerAt(11).alive, isFalse);
    });

    test('已接刀、白天被放逐 → 當場出局', () {
      final s = _knifeHolder(11)..dayNumber = 3;
      s.convertedActivatedSeats.add(11);
      _exile(s, 11, [4, 5, 6]);

      expect(s.playerAt(11).alive, isFalse);
      expect(s.whiteCatPendingCause, isNull);
    });

    test('對照：還沒接刀時技能照常 —— 被刀照樣延後', () {
      final s = _state()..convertedSeats.add(11); // 石像鬼都還活著
      final a = NightActions(night: 2)..wolfTarget = 11;
      final o = _arb.settle(s, a);
      _arb.apply(s, a, o);

      expect(o.whiteCatDeferredSeats, [11]);
      expect(s.playerAt(11).alive, isTrue);
    });
  });

  group('被轉換的河豚接刀之後', () {
    test('被放逐 → 沒有翻牌帶人這一步', () {
      final s = _knifeHolder(10)..dayNumber = 3;
      s.convertedActivatedSeats.add(10);

      expect(_exile(s, 10, [4, 5, 6]).stage, isNot(ExileStage.pufferfishReveal));
    });

    test('對照：還沒接刀時照常能翻', () {
      final s = _state()..convertedSeats.add(10);

      expect(_exile(s, 10, [4, 5, 6]).stage, ExileStage.pufferfishReveal);
    });
  });

  group('延後離場的白貓不列進遺言', () {
    test('天亮開槍帶走白貓', () {
      final s = _state()..phase = GamePhase.day;
      s.playerAt(8).alive = false; // 8 號獵人夜死
      final shot = NightDeathShot(state: s, shooters: [8])..shoot(11);

      expect(shot.deaths.map((d) => d.seat), [11], reason: '發言順序仍算他');
      expect(shot.lastWordsSeats, isEmpty, reason: '他還在場上，今天照常發言');
    });

    test('白天放逐白貓', () {
      final s = _state();
      final v = _exile(s, 11, [4, 5, 6]);

      expect(s.playerAt(11).alive, isTrue);
      expect(v.lastWordsSeats, isEmpty);
    });

    test('延後的死亡生效那一刻才給遺言', () {
      final s = _state()
        ..phase = GamePhase.night
        ..dayNumber = 2;
      final a = NightActions(night: 2)..wolfTarget = 11;
      _arb.apply(s, a, _arb.settle(s, a));

      final v = _exile(s, 12, []); // 全員棄票，投票結束
      expect(s.playerAt(11).alive, isFalse);
      expect(v.lastWordsSeats, [11]);
    });
  });

  test('結算說明依學到的身分寫生效時機', () {
    String noteFor(int learnTarget) {
      final s = _state();
      final a = NightActions(night: 2)..mechanicWolfLearnTarget = learnTarget;
      return _arb
          .settle(s, a)
          .notes
          .firstWhere((n) => n.startsWith('機械狼學習'));
    }

    expect(noteFor(8), '機械狼學習 8 號（獵人），學到就生效');
    expect(noteFor(6), '機械狼學習 6 號（熊），隔夜起生效');
    expect(noteFor(12), '機械狼學習 12 號（暗戀者），沒有技能，只套用身分');
  });

  test('騎士決鬥的禁選原因由引擎回傳', () {
    final s = _state()
      ..phase = GamePhase.day
      ..whiteCatPendingCause = DeathCause.wolfKill
      ..whiteCatDeathDueAfterDay = 2;
    s.playerAt(4).role = Roles.knight; // 只借用來測
    final duel = KnightDuel(state: s);

    expect(duel.blockedSeats, {
      11: SeatBlockReason.whiteCatPending,
      4: SeatBlockReason.duelSelf,
    });
    expect(duel.opponents, isNot(contains(11)));
    expect(duel.opponents, isNot(contains(4)));
  });
}
