import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/speech_timer.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';
import 'package:wgm/features/day/knight_duel_page.dart';
import 'package:wgm/features/day/speech_timer_page.dart';
import 'package:wgm/features/night/seat_picker.dart';
import 'package:wgm/features/review/game_over_page.dart';
import 'package:wgm/shared/theme.dart';

/// 12人 狼美騎士：3狼＋狼美人、預女守騎、4民。
Preset _preset({Map<String, dynamic>? rules}) => Preset.fromJson(
      {
        'presetId': 'lmqs',
        'name': '狼美騎士',
        'playerCount': 12,
        'roles': const [
          {'role': 'wolf', 'count': 3},
          {'role': 'wolfBeauty', 'count': 1},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'guard', 'count': 1},
          {'role': 'knight', 'count': 1},
          {'role': 'villager', 'count': 4},
        ],
        'nightOrder': const ['guard', 'wolf', 'wolfBeauty', 'witch', 'seer'],
        'rules': ?rules,
      },
      sourceName: 'lmqs.json',
    );

/// 1-3 狼、4 狼美人、5 預言家、6 女巫、7 守衛、8 騎士、9-12 平民。
GameState _state({Map<String, dynamic>? rules}) {
  final s = GameState(preset: _preset(rules: rules));
  void set(int seat, Role r) => s.playerAt(seat).role = r;
  for (final seat in [1, 2, 3]) {
    set(seat, Roles.wolf);
  }
  set(4, Roles.wolfBeauty);
  set(5, Roles.seer);
  set(6, Roles.witch);
  set(7, Roles.guard);
  set(8, Roles.knight);
  for (var i = 9; i <= 12; i++) {
    set(i, Roles.villager);
  }
  s.dayNumber = 1;
  return s;
}

Future<void> _tapSeat(WidgetTester tester, int seat) async {
  final finder = find.descendant(
    of: find.byType(SeatPicker),
    matching: find.text('$seat'),
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('決鬥頁', () {
    Future<void> pump(
      WidgetTester tester,
      GameState state, {
      List<String>? log,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            theme: WgmTheme.build(),
            home: KnightDuelPage(
              state: state,
              onDayContinues: () => log?.add('繼續白天'),
              onDayEnds: () => log?.add('進黑夜'),
            ),
          ),
        );

    testWidgets('寫出是誰翻牌，沒選對手之前不能決鬥', (tester) async {
      await pump(tester, _state());

      expect(find.text('騎士（8 號）翻牌'), findsOneWidget);
      expect(find.text('請先選擇對手'), findsOneWidget);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('騎士本人不能被選', (tester) async {
      await pump(tester, _state());

      expect(find.text('騎士本人'), findsOneWidget);

      await _tapSeat(tester, 8);
      expect(find.text('請先選擇對手'), findsOneWidget, reason: '點自己不該選得起來');
    });

    testWidgets('決鬥到狼 → 對手出局，下一步是進黑夜', (tester) async {
      final log = <String>[];
      final state = _state();
      await pump(tester, state, log: log);

      await _tapSeat(tester, 2);
      expect(find.text('與 2 號決鬥'), findsOneWidget);
      await _tapText(tester, '與 2 號決鬥');

      expect(state.playerAt(2).alive, isFalse);
      expect(state.playerAt(8).alive, isTrue);
      expect(find.text('決鬥到狼'), findsOneWidget);
      expect(find.textContaining('是狼人，2 號出局'), findsOneWidget);
      expect(find.text('進入黑夜'), findsOneWidget);
      expect(log, isEmpty);

      await _tapText(tester, '進入黑夜');
      expect(log, ['進黑夜']);
    });

    testWidgets('決鬥到好人 → 騎士自刎，白天照常繼續', (tester) async {
      final log = <String>[];
      final state = _state();
      await pump(tester, state, log: log);

      await _tapSeat(tester, 9);
      await _tapText(tester, '與 9 號決鬥');

      expect(state.playerAt(8).alive, isFalse);
      expect(state.playerAt(9).alive, isTrue);
      expect(find.text('決鬥到好人'), findsOneWidget);
      expect(find.text('回到發言'), findsOneWidget);

      await _tapText(tester, '回到發言');
      expect(log, ['繼續白天']);
    });

    testWidgets('決鬥掉狼美人 → 被魅惑者不殉情', (tester) async {
      final state = _state()..charmedSeat = 10;
      await pump(tester, state);

      await _tapSeat(tester, 4);
      await _tapText(tester, '與 4 號決鬥');

      expect(state.playerAt(4).alive, isFalse);
      expect(state.playerAt(10).alive, isTrue);
      expect(find.text('狼美人被決鬥致死，10 號不殉情'), findsOneWidget);
    });

    testWidgets('撤銷決鬥 → 人活回來，可以改對手', (tester) async {
      final state = _state();
      await pump(tester, state);

      await _tapSeat(tester, 2);
      await _tapText(tester, '與 2 號決鬥');
      expect(state.playerAt(2).alive, isFalse);

      await _tapText(tester, '撤銷上一步（騎士決鬥）');

      expect(state.playerAt(2).alive, isTrue);
      expect(state.knightDuelUsed, isFalse);
      expect(find.text('騎士（8 號）翻牌'), findsOneWidget);

      await _tapSeat(tester, 3);
      await _tapText(tester, '與 3 號決鬥');
      expect(state.playerAt(3).alive, isFalse);
      expect(state.playerAt(2).alive, isTrue);
    });

    testWidgets('誤按進來可以直接退出，什麼都沒發生', (tester) async {
      final log = <String>[];
      final state = _state();
      await pump(tester, state, log: log);

      await _tapText(tester, '不決鬥，回到發言');

      expect(state.knightDuelUsed, isFalse);
      expect(state.aliveCount, 12);
      expect(log, ['繼續白天']);
    });

    testWidgets('決鬥掉最後一匹狼 → 直接進結果頁', (tester) async {
      final log = <String>[];
      final state = _state();
      for (final seat in [1, 2, 4]) {
        state.playerAt(seat).alive = false;
      }
      await pump(tester, state, log: log);

      await _tapSeat(tester, 3);
      await _tapText(tester, '與 3 號決鬥');
      await _tapText(tester, '進入黑夜');

      expect(find.byType(GameOverPage), findsOneWidget);
      expect(find.text('好人勝'), findsOneWidget);
      expect(log, isEmpty, reason: '分出勝負就不該再進黑夜');
    });
  });

  group('發言計時頁上的決鬥入口', () {
    Future<void> pump(
      WidgetTester tester,
      GameState state, {
      bool withDuel = true,
      SpeechPhase phase = SpeechPhase.day,
      List<String>? log,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            theme: WgmTheme.build(),
            home: SpeechTimerPage(
              state: state,
              order: const [9, 10],
              phase: phase,
              onFinished: () => log?.add('進投票'),
              onDayEndsEarly: withDuel ? () => log?.add('進黑夜') : null,
            ),
          ),
        );

    testWidgets('騎士還在就顯示決鬥入口', (tester) async {
      await pump(tester, _state());

      expect(find.text('騎士翻牌決鬥（8 號）'), findsOneWidget);
    });

    testWidgets('騎士已出局就不顯示', (tester) async {
      final state = _state();
      state.playerAt(8).alive = false;
      await pump(tester, state);

      expect(find.textContaining('騎士翻牌決鬥'), findsNothing);
    });

    testWidgets('技能用過了就不顯示', (tester) async {
      final state = _state()..knightDuelUsed = true;
      await pump(tester, state);

      expect(find.textContaining('騎士翻牌決鬥'), findsNothing);
    });

    testWidgets('遺言那一輪沒有決鬥入口', (tester) async {
      await pump(
        tester,
        _state(),
        withDuel: false,
        phase: SpeechPhase.lastWords,
      );

      expect(find.textContaining('騎士翻牌決鬥'), findsNothing);
    });

    testWidgets('決鬥到好人 → 退回發言頁，入口消失', (tester) async {
      final log = <String>[];
      final state = _state();
      await pump(tester, state, log: log);

      await _tapText(tester, '騎士翻牌決鬥（8 號）');
      expect(find.byType(KnightDuelPage), findsOneWidget);

      await _tapSeat(tester, 9);
      await _tapText(tester, '與 9 號決鬥');
      await _tapText(tester, '回到發言');

      expect(find.byType(SpeechTimerPage), findsOneWidget);
      expect(find.textContaining('騎士翻牌決鬥'), findsNothing,
          reason: '技能用掉了，入口要收起來');
      expect(log, isEmpty);
    });

    testWidgets('決鬥到狼 → 走進黑夜那條路，不進投票', (tester) async {
      final log = <String>[];
      final state = _state();
      await pump(tester, state, log: log);

      await _tapText(tester, '騎士翻牌決鬥（8 號）');
      await _tapSeat(tester, 2);
      await _tapText(tester, '與 2 號決鬥');
      await _tapText(tester, '進入黑夜');

      expect(log, ['進黑夜'], reason: '跳過剩下的發言與投票');
    });
  });
}
