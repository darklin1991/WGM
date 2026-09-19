import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/win_checker.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';
import 'package:wgm/features/day/exile_vote_page.dart';
import 'package:wgm/features/night/seat_picker.dart';
import 'package:wgm/features/review/game_over_page.dart';
import 'package:wgm/shared/theme.dart';

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

void _kill(GameState s, List<int> seats) {
  for (final seat in seats) {
    s.playerAt(seat).alive = false;
  }
}

/// 歸票對象那一排的號碼。座位格也叫同樣的號碼，所以要指定是 chip。
Future<void> _tapChip(WidgetTester tester, int seat) async {
  final finder = find.descendant(
    of: find.byType(ChoiceChip),
    matching: find.text('$seat'),
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
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
  group('遊戲結束頁', () {
    Future<void> pump(WidgetTester tester, GameState state) =>
        tester.pumpWidget(
          MaterialApp(
            theme: WgmTheme.build(),
            home: GameOverPage(state: state, check: WinChecker.check(state)),
          ),
        );

    testWidgets('好人勝：宣布結果並寫出依據', (tester) async {
      final state = _state();
      _kill(state, [1, 2, 3, 4]);
      await pump(tester, state);

      expect(find.text('好人勝'), findsOneWidget);
      expect(find.text('狼人全數出局'), findsOneWidget);
    });

    testWidgets('狼人勝：屠邊的依據要講得出來', (tester) async {
      final state = _state();
      _kill(state, [5, 6, 7, 8]);
      await pump(tester, state);

      expect(find.text('狼人勝'), findsOneWidget);
      expect(find.text('神職全滅（屠邊）'), findsOneWidget);
    });

    testWidgets('全部身分攤開，並標出生死', (tester) async {
      final state = _state();
      _kill(state, [1, 2, 3, 4]);
      await pump(tester, state);

      // 兩個陣營各一張卡，標題帶存活數。
      expect(find.text('狼人陣營（存活 0／4）'), findsOneWidget);
      expect(find.text('好人陣營（存活 8／8）'), findsOneWidget);

      // 12 個座次全列出來，連狼的身分也照寫。
      for (var seat = 1; seat <= 12; seat++) {
        expect(find.text('$seat 號'), findsOneWidget);
      }
      expect(find.text('狼王'), findsOneWidget);
      expect(find.text('預言家'), findsOneWidget);
      expect(find.text('出局'), findsNWidgets(4));
      expect(find.text('存活'), findsNWidgets(8));
    });
  });

  group('放逐後的勝負判定', () {
    Future<void> pump(
      WidgetTester tester,
      GameState state, {
      List<bool>? finished,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            theme: WgmTheme.build(),
            home: ExileVotePage(
              state: state,
              onFinished: () => finished?.add(true),
            ),
          ),
        );

    testWidgets('推掉最後一匹狼 → 直接進結果頁，不再往下一夜走', (tester) async {
      final done = <bool>[];
      final state = _state();
      _kill(state, [1, 2, 4]); // 只剩 3 號這匹狼
      await pump(tester, state, finished: done);

      await _tapChip(tester, 3);
      for (final voter in [5, 6, 7, 8, 9]) {
        await _tapSeat(tester, voter);
      }
      await _tapText(tester, '算票');

      expect(state.playerAt(3).alive, isFalse);
      expect(find.byType(GameOverPage), findsOneWidget);
      expect(find.text('好人勝'), findsOneWidget);
      expect(done, isEmpty, reason: '分出勝負就不該再呼叫進下一夜');
    });

    testWidgets('推掉一個平民 → 照常進下一夜', (tester) async {
      final done = <bool>[];
      final state = _state();
      await pump(tester, state, finished: done);

      await _tapChip(tester, 12);
      for (final voter in [1, 2, 3, 4, 5, 6, 7]) {
        await _tapSeat(tester, voter);
      }
      await _tapText(tester, '算票');

      // 算完票先停在結算畫面，讓法官宣布完再走。
      expect(state.playerAt(12).alive, isFalse);
      expect(find.text('放逐結算'), findsOneWidget);
      expect(find.text('12 號被放逐出局'), findsOneWidget);
      expect(find.textContaining('12 號（放逐）'), findsOneWidget);
      expect(done, isEmpty, reason: '還沒按下一夜就不該離開這一頁');

      await _tapText(tester, '進入下一夜');

      expect(find.byType(GameOverPage), findsNothing);
      expect(done, [true]);
    });
  });
}
