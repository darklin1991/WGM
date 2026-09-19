import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';
import 'package:wgm/features/day/badge_succession_page.dart';
import 'package:wgm/features/day/exile_vote_page.dart';
import 'package:wgm/features/night/seat_picker.dart';
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

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('警徽流頁', () {
    Future<void> pump(
      WidgetTester tester,
      GameState state, {
      List<bool>? finished,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            theme: WgmTheme.build(),
            home: BadgeSuccessionPage(
              state: state,
              onFinished: () => finished?.add(true),
            ),
          ),
        );

    GameState deadSheriff() {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      return s;
    }

    testWidgets('寫出是誰出局，沒選人之前不能移交', (tester) async {
      await pump(tester, deadSheriff());

      expect(find.text('5 號警長出局'), findsOneWidget);
      expect(find.text('請先選擇接任者'), findsOneWidget);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull, reason: '沒選人時移交鈕要是暗的');
    });

    testWidgets('移交：選了人之後按鈕寫出號碼，按下去換警長', (tester) async {
      final done = <bool>[];
      final state = deadSheriff();
      await pump(tester, state, finished: done);

      await _tapSeat(tester, 9);
      expect(find.text('警徽移交給 9 號'), findsOneWidget);

      await _tapText(tester, '警徽移交給 9 號');

      expect(state.sheriffSeat, 9);
      expect(find.text('警徽流結果'), findsOneWidget);
      expect(find.text('5 號的警徽移交給 9 號，9 號成為新警長'), findsOneWidget);
      expect(done, isEmpty, reason: '要等法官按繼續才走下一步');

      await _tapText(tester, '繼續');
      expect(done, [true]);
    });

    testWidgets('撕毀：本局之後沒有警長', (tester) async {
      final state = deadSheriff();
      await pump(tester, state);

      await _tapText(tester, '撕毀警徽');

      expect(state.sheriffSeat, isNull);
      expect(find.text('5 號撕毀警徽，本局之後沒有警長'), findsOneWidget);
      expect(find.textContaining('不再有加權票'), findsOneWidget);
    });

    testWidgets('撤銷：交錯人可以退回來重選', (tester) async {
      final state = deadSheriff();
      await pump(tester, state);

      await _tapSeat(tester, 9);
      await _tapText(tester, '警徽移交給 9 號');
      expect(state.sheriffSeat, 9);

      await _tapText(tester, '撤銷上一步（移交警徽）');

      expect(state.sheriffSeat, 5, reason: '撤銷後警徽回到原警長手上');
      expect(find.text('5 號警長出局'), findsOneWidget);
      expect(find.text('請先選擇接任者'), findsOneWidget);

      await _tapSeat(tester, 10);
      await _tapText(tester, '警徽移交給 10 號');
      expect(state.sheriffSeat, 10);
    });

    testWidgets('已出局的人不能被選為接任者', (tester) async {
      final state = deadSheriff();
      state.playerAt(9).alive = false;
      await pump(tester, state);

      await _tapSeat(tester, 9);

      expect(find.text('請先選擇接任者'), findsOneWidget,
          reason: '點死人不該選得起來');
    });
  });

  group('放逐推掉警長 → 接警徽流', () {
    testWidgets('按鈕寫出下一站是警徽流，走完才進下一夜', (tester) async {
      final done = <bool>[];
      final state = _state()..sheriffSeat = 12;

      await tester.pumpWidget(
        MaterialApp(
          theme: WgmTheme.build(),
          home: Navigator(
            onGenerateRoute: (_) => ExileVotePage.route(
              state,
              next: () => BadgeSuccessionPage.routeIfDue(
                state,
                next: () => MaterialPageRoute<void>(
                  builder: (_) {
                    done.add(true);
                    return const Scaffold(body: Text('下一夜'));
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // 12 號警長被推出去。
      await _tapChip(tester, 12);
      for (final voter in [1, 2, 3, 4, 5, 6, 7]) {
        await _tapSeat(tester, voter);
      }
      await _tapText(tester, '算票');

      expect(state.playerAt(12).alive, isFalse);
      expect(find.text('接著處理警徽流'), findsOneWidget);
      expect(done, isEmpty);

      await _tapText(tester, '接著處理警徽流');

      expect(find.byType(BadgeSuccessionPage), findsOneWidget);
      expect(find.text('12 號警長出局'), findsOneWidget);
      expect(done, isEmpty, reason: '警徽還沒交就不該進下一夜');

      await _tapText(tester, '撕毀警徽');
      await _tapText(tester, '繼續');

      expect(state.sheriffSeat, isNull);
      expect(done, [true]);
    });

    testWidgets('推掉的不是警長 → 不插警徽流，直接進下一夜', (tester) async {
      final done = <bool>[];
      final state = _state()..sheriffSeat = 5;

      await tester.pumpWidget(
        MaterialApp(
          theme: WgmTheme.build(),
          home: Navigator(
            onGenerateRoute: (_) => ExileVotePage.route(
              state,
              next: () => BadgeSuccessionPage.routeIfDue(
                state,
                next: () => MaterialPageRoute<void>(
                  builder: (_) {
                    done.add(true);
                    return const Scaffold(body: Text('下一夜'));
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await _tapChip(tester, 12);
      for (final voter in [1, 2, 3, 4, 5, 6, 7]) {
        await _tapSeat(tester, voter);
      }
      await _tapText(tester, '算票');

      expect(find.text('進入下一夜'), findsOneWidget);

      await _tapText(tester, '進入下一夜');

      expect(find.byType(BadgeSuccessionPage), findsNothing);
      expect(state.sheriffSeat, 5);
      expect(done, [true]);
    });
  });
}
