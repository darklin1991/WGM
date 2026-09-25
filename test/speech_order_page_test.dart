import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';
import 'package:wgm/features/day/speech_order_page.dart';
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
  s.dayNumber = 1;
  return s;
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required GameState state,
    required List<int> deceased,
    List<List<int>>? finished,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          theme: WgmTheme.build(),
          home: SpeechOrderPage(
            state: state,
            deceased: deceased,
            onFinished: (order) => finished?.add(order),
          ),
        ),
      );

  testWidgets('單死 → 從死者算起，兩個方向的號碼順序都列出來', (tester) async {
    final state = _state()..sheriffSeat = 5;
    state.playerAt(10).alive = false;
    await pump(tester, state: state, deceased: [10]);

    expect(find.text('單死 · 由警長決定方向'), findsOneWidget);
    expect(find.textContaining('昨晚只死 10 號'), findsOneWidget);

    // 順時鐘：11 開始；逆時鐘：9 開始。死者 10 號都不在名單裡。
    expect(find.text('11 → 12 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9'),
        findsOneWidget);
    expect(find.text('9 → 8 → 7 → 6 → 5 → 4 → 3 → 2 → 1 → 12 → 11'),
        findsOneWidget);
  });

  testWidgets('平安夜 → 從警長算起，警長最後發言', (tester) async {
    final state = _state()..sheriffSeat = 5;
    await pump(tester, state: state, deceased: []);

    expect(find.text('由警長決定方向'), findsOneWidget);
    expect(find.textContaining('昨晚是平安夜'), findsOneWidget);
    expect(find.text('6 → 7 → 8 → 9 → 10 → 11 → 12 → 1 → 2 → 3 → 4 → 5'),
        findsOneWidget);
    expect(find.textContaining('警長（5 號）最後發言'), findsWidgets);
  });

  testWidgets('雙死 → 一樣從警長算起', (tester) async {
    final state = _state()..sheriffSeat = 5;
    for (final seat in [9, 10]) {
      state.playerAt(seat).alive = false;
    }
    await pump(tester, state: state, deceased: [9, 10]);

    expect(find.textContaining('昨晚到現在死了 2 位'), findsOneWidget);
    expect(find.text('6 → 7 → 8 → 11 → 12 → 1 → 2 → 3 → 4 → 5'), findsOneWidget);
  });

  testWidgets('要先選方向才能繼續', (tester) async {
    final done = <List<int>>[];
    final state = _state()..sheriffSeat = 5;
    await pump(tester, state: state, deceased: [], finished: done);

    expect(find.text('請先選一個方向'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await _tapText(tester, '順時鐘（號碼遞增）');
    expect(find.text('順序確定，開始發言'), findsOneWidget);

    await _tapText(tester, '順序確定，開始發言');
    expect(done, [
      [6, 7, 8, 9, 10, 11, 12, 1, 2, 3, 4, 5],
    ], reason: '確定的順序要原樣傳給計時頁');
  });

  testWidgets('沒有警長 → 起點與方向都抽籤，可以重抽', (tester) async {
    final state = _state(); // sheriffSeat 為 null
    await pump(tester, state: state, deceased: [10]);

    expect(find.text('無警長 · 上帝抽籤'), findsOneWidget);
    expect(find.textContaining('本局沒有警長'), findsOneWidget);
    expect(find.text('重抽'), findsOneWidget);

    // 抽籤已完成 → 直接可以繼續，不必選方向。
    expect(find.text('順序確定，開始發言'), findsOneWidget);

    // 沒有兩張方向卡可選。
    expect(find.text('順時鐘（號碼遞增）'), findsNothing);
    expect(find.text('逆時鐘（號碼遞減）'), findsNothing);
  });
}
