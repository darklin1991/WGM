import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';
import 'package:wgm/features/day/badge_succession_page.dart';
import 'package:wgm/features/day/night_death_shot_page.dart';
import 'package:wgm/features/day/speech_order_page.dart';
import 'package:wgm/features/night/night_result_page.dart';
import 'package:wgm/features/night/seat_picker.dart';
import 'package:wgm/features/review/game_over_page.dart';
import 'package:wgm/shared/theme.dart';

/// 夜死開槍接在夜晚結算之後、警徽流之前（擔當 2026-09-24 指定）。

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
/// 7 號獵人昨晚被刀出局，現在是第 2 天白天。
GameState _state() {
  final s = GameState(preset: _preset());
  final roles = <Role>[
    Roles.wolf,
    Roles.wolf,
    Roles.wolf,
    Roles.wolfKing,
    Roles.seer,
    Roles.witch,
    Roles.hunter,
    Roles.guard,
  ];
  for (var seat = 1; seat <= 12; seat++) {
    s.playerAt(seat).role =
        seat <= roles.length ? roles[seat - 1] : Roles.villager;
  }
  s.playerAt(7).alive = false;
  s
    ..dayNumber = 2
    ..phase = GamePhase.day;
  return s;
}

const _hunterKnifed = NightOutcome(
  deaths: [Death(seat: 7, cause: DeathCause.wolfKill)],
  notes: ['獵人（7 號）死亡，可以開槍'],
  seerTarget: null,
  seerSawWolf: false,
  hunterMayShoot: true,
  shooterSeats: [7],
);

Future<void> _pumpResult(WidgetTester tester, GameState state) =>
    tester.pumpWidget(
      MaterialApp(
        theme: WgmTheme.build(),
        home: NightResultPage(state: state, outcome: _hunterKnifed),
      ),
    );

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

/// 結算頁是 ListView，畫面外的按鈕還沒建出來 —— 先捲到看得見再找。
Future<void> _scrollTo(WidgetTester tester, String text) async {
  final scrollable = find.byType(Scrollable).first;
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: scrollable,
    );
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await _scrollTo(tester, text);
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('結算頁的按鈕寫出下一站是開槍', (tester) async {
    await _pumpResult(tester, _state());

    expect(find.text('7 號（獵人）可以開槍'), findsOneWidget);
    await _scrollTo(tester, '7 號開槍');
    expect(find.text('7 號開槍'), findsOneWidget);
    expect(find.text('決定發言順序'), findsNothing);
  });

  testWidgets('開槍帶走平民 → 繼續走到發言順序', (tester) async {
    final state = _state();
    await _pumpResult(tester, state);

    await _tapText(tester, '7 號開槍');
    expect(find.byType(NightDeathShotPage), findsOneWidget);

    await _tapSeat(tester, 9);
    await _tapText(tester, '開槍帶走 9 號');

    expect(state.playerAt(9).alive, isFalse);
    expect(find.text('7 號開槍帶走 9 號'), findsOneWidget);

    await _tapText(tester, '繼續');
    expect(find.byType(SpeechOrderPage), findsOneWidget);
  });

  testWidgets('帶走的是警長 → 先走警徽流', (tester) async {
    final state = _state()..sheriffSeat = 9;
    await _pumpResult(tester, state);

    await _tapText(tester, '7 號開槍');
    await _tapSeat(tester, 9);
    await _tapText(tester, '開槍帶走 9 號');
    await _tapText(tester, '繼續');

    expect(find.byType(BadgeSuccessionPage), findsOneWidget);
  });

  testWidgets('帶走最後一匹狼 → 直接進結果頁', (tester) async {
    final state = _state();
    for (final seat in [1, 2, 4]) {
      state.playerAt(seat).alive = false;
    }
    await _pumpResult(tester, state);

    await _tapText(tester, '7 號開槍');
    await _tapSeat(tester, 3);
    await _tapText(tester, '開槍帶走 3 號');

    expect(find.byType(GameOverPage), findsOneWidget);
    expect(find.text('好人勝'), findsOneWidget);
  });

  testWidgets('放棄開槍也要按，按完照常往下', (tester) async {
    final state = _state();
    await _pumpResult(tester, state);

    await _tapText(tester, '7 號開槍');
    await _tapText(tester, '放棄開槍');

    expect(find.text('7 號放棄開槍'), findsOneWidget);
    expect(state.alivePlayers, hasLength(11));

    await _tapText(tester, '繼續');
    expect(find.byType(SpeechOrderPage), findsOneWidget);
  });

  // 擔當 2026-09-24 指定：天亮後被槍帶走的人也算進「單死／雙死」。
  testWidgets('獵人夜死又帶走一人 → 算雙死，從警長算起', (tester) async {
    final state = _state()..sheriffSeat = 5;
    await _pumpResult(tester, state);

    await _tapText(tester, '7 號開槍');
    await _tapSeat(tester, 9);
    await _tapText(tester, '開槍帶走 9 號');
    await _tapText(tester, '繼續');

    expect(find.textContaining('昨晚到現在死了 2 位'), findsOneWidget);
  });

  testWidgets('獵人放棄開槍 → 仍是單死，從死者算起', (tester) async {
    final state = _state()..sheriffSeat = 5;
    await _pumpResult(tester, state);

    await _tapText(tester, '7 號開槍');
    await _tapText(tester, '放棄開槍');
    await _tapText(tester, '繼續');

    expect(find.textContaining('昨晚只死 7 號'), findsOneWidget);
  });

  testWidgets('沒有人能開槍 → 不插這一頁', (tester) async {
    final state = _state()..playerAt(7).alive = true;
    state.playerAt(9).alive = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: WgmTheme.build(),
        home: NightResultPage(
          state: state,
          outcome: const NightOutcome(
            deaths: [Death(seat: 9, cause: DeathCause.wolfKill)],
            notes: [],
            seerTarget: null,
            seerSawWolf: false,
            hunterMayShoot: false,
          ),
        ),
      ),
    );

    await _tapText(tester, '決定發言順序');
    expect(find.byType(NightDeathShotPage), findsNothing);
    expect(find.byType(SpeechOrderPage), findsOneWidget);
  });
}
