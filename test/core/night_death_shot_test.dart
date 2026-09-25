import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_death_shot.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 夜死開槍（擔當 2026-09-24 指定）：
///
/// - 夜裡出局的槍牌，天亮後由法官記下開槍目標
/// - 位置在公布死訊之後、警徽流之前
/// - 連鎖與放逐時的開槍相同：目標死亡 → 狼美人殉情；被帶走的人不再開槍

/// 12 人測試板：2狼 + 狼美人 + 獵人 + 白貓 + 預女 + 5民。
Preset _preset() => Preset.fromJson(
      const {
        'presetId': 'shot',
        'name': '開槍測試板',
        'playerCount': 12,
        'roles': [
          {'role': 'wolf', 'count': 2},
          {'role': 'wolfBeauty', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'whiteCat', 'count': 1},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'villager', 'count': 5},
        ],
        'nightOrder': ['wolf', 'wolfBeauty', 'witch', 'seer'],
      },
      sourceName: 'shot.json',
    );

/// 1-2 狼、3 狼美人、4 獵人、5 白貓、6 預言家、7 女巫、8-12 平民。
/// 4 號獵人昨晚已出局，現在是第 1 天白天。
GameState _state() {
  final s = GameState(preset: _preset());
  final roles = <Role>[
    Roles.wolf,
    Roles.wolf,
    Roles.wolfBeauty,
    Roles.hunter,
    Roles.whiteCat,
    Roles.seer,
    Roles.witch,
  ];
  for (var seat = 1; seat <= 12; seat++) {
    s.playerAt(seat).role =
        seat <= roles.length ? roles[seat - 1] : Roles.villager;
  }
  s.playerAt(4).alive = false;
  s
    ..dayNumber = 1
    ..phase = GamePhase.day;
  return s;
}

void main() {
  group('開槍', () {
    test('帶走目標，死因是開槍', () {
      final s = _state();
      final shot = NightDeathShot(state: s, shooters: [4]);

      expect(shot.currentShooter, 4);
      shot.shoot(9);

      expect(s.playerAt(9).alive, isFalse);
      expect(shot.deaths.single.seat, 9);
      expect(shot.deaths.single.cause, DeathCause.hunterShot);
      expect(shot.notes, ['4 號開槍帶走 9 號']);
      expect(shot.finished, isTrue);
    });

    test('放棄開槍 → 沒有人死，照樣結束', () {
      final s = _state();
      final shot = NightDeathShot(state: s, shooters: [4])..shoot(null);

      expect(shot.deaths, isEmpty);
      expect(shot.notes, ['4 號放棄開槍']);
      expect(shot.finished, isTrue);
      expect(s.alivePlayers, hasLength(11));
    });

    test('死人選不動', () {
      final s = _state();
      s.playerAt(9).alive = false;
      final shot = NightDeathShot(state: s, shooters: [4]);

      expect(shot.targets, isNot(contains(9)));
      shot.shoot(9);
      expect(shot.finished, isFalse, reason: '點不動就不算開過');
    });

    test('兩位槍牌依序開', () {
      final s = _state();
      s.playerAt(3).alive = false; // 假設狼美人也能開，只為了測順序
      final shot = NightDeathShot(state: s, shooters: [3, 4]);

      shot.shoot(9);
      expect(shot.currentShooter, 4);
      shot.shoot(10);

      expect(shot.finished, isTrue);
      expect(shot.notes, ['3 號開槍帶走 9 號', '4 號開槍帶走 10 號']);
    });

    test('宣布稿與日誌寫同一句', () {
      final s = _state();
      NightDeathShot(state: s, shooters: [4]).shoot(9);

      expect(s.log.entries.last.text, '4 號開槍帶走 9 號');
      expect(s.log.entries.last.isNight, isFalse);
    });
  });

  group('連鎖', () {
    test('帶走狼美人 → 被魅惑者殉情', () {
      final s = _state()..charmedSeat = 10;
      final shot = NightDeathShot(state: s, shooters: [4])..shoot(3);

      expect(s.playerAt(3).alive, isFalse);
      expect(s.playerAt(10).alive, isFalse);
      expect(
        shot.deaths.map((d) => (d.seat, d.cause)),
        [(3, DeathCause.hunterShot), (10, DeathCause.loveSuicide)],
      );
    });

    test('帶走白貓 → 翻牌但延到隔天的放逐投票才離場', () {
      final s = _state();
      NightDeathShot(state: s, shooters: [4]).shoot(5);

      expect(s.playerAt(5).alive, isTrue, reason: '延後期間算存活');
      expect(s.whiteCatPendingCause, DeathCause.hunterShot);
      expect(s.whiteCatDeathDueAfterDay, 2, reason: '白天判死 → 隔天');
    });
  });

  group('撤銷', () {
    test('局面與流程位置一起退回', () {
      final s = _state()..charmedSeat = 10;
      final shot = NightDeathShot(state: s, shooters: [4])..shoot(3);

      expect(shot.canUndo, isTrue);
      shot.undo();

      expect(s.playerAt(3).alive, isTrue);
      expect(s.playerAt(10).alive, isTrue);
      expect(shot.currentShooter, 4);
      expect(shot.deaths, isEmpty);
      expect(shot.notes, isEmpty);
      expect(
        s.log.entries.where((e) => e.text.contains('開槍')),
        isEmpty,
        reason: '日誌跟著退回',
      );
    });
  });
}
