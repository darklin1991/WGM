import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/speech_timer.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';
import 'package:wgm/features/day/speech_timer_page.dart';
import 'package:wgm/shared/theme.dart';

Preset _preset({int? speechSeconds}) => Preset.fromJson(
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
        'rules': {'speechSeconds': ?speechSeconds},
      },
      sourceName: 'wk.json',
    );

GameState _state({int? speechSeconds}) {
  final s = GameState(preset: _preset(speechSeconds: speechSeconds));
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

/// 大字倒數（快選晶片上也會出現一樣的字，所以用 key 取）。
String _countdown(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('speech-countdown'))).data!;

/// 倒數的秒數。`pumpAndSettle` 自己也會推進時間，所以會扣掉零點幾秒的零頭；
/// 需要精準比對的地方用「經過了幾秒」而不是絕對值。
int _remaining(WidgetTester tester) {
  final text = _countdown(tester);
  final over = text.startsWith('+');
  final parts = (over ? text.substring(1) : text).split(':');
  final v = int.parse(parts[0]) * 60 + int.parse(parts[1]);
  return over ? -v : v;
}

/// 讓碼表跑 [seconds] 秒。
Future<void> _elapse(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required GameState state,
    required List<int> order,
    SpeechPhase phase = SpeechPhase.day,
    List<bool>? finished,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          theme: WgmTheme.build(),
          home: SpeechTimerPage(
            state: state,
            order: order,
            phase: phase,
            onFinished: () => finished?.add(true),
          ),
        ),
      );

  testWidgets('開場顯示第一位與板子設定的額度，碼表還沒跑', (tester) async {
    await pump(tester, state: _state(), order: [5, 6, 7]);

    expect(find.text('5 號　發言'), findsOneWidget);
    expect(_countdown(tester), '2:00');
    expect(find.text('每人 2:00'), findsOneWidget);
    expect(find.text('開始'), findsOneWidget);
    expect(find.textContaining('還有 2 位'), findsOneWidget);

    // 沒按開始就不會動。
    await _elapse(tester, 5);
    expect(_countdown(tester), '2:00');
  });

  testWidgets('按開始後一秒一秒扣，可以暫停', (tester) async {
    await pump(tester, state: _state(), order: [5, 6]);

    await _tapText(tester, '開始');
    final start = _remaining(tester);

    await _elapse(tester, 15);
    expect(_remaining(tester), start - 15);

    await _tapText(tester, '暫停');
    final paused = _remaining(tester);
    await _elapse(tester, 30);
    expect(_remaining(tester), paused, reason: '暫停期間不該扣');
  });

  testWidgets('時間到只變成超時，不會自己換人', (tester) async {
    await pump(tester, state: _state(speechSeconds: 5), order: [5, 6]);

    await _tapText(tester, '開始');
    await _elapse(tester, 8);

    expect(_countdown(tester), '+0:03');
    expect(find.text('已超時'), findsOneWidget);
    expect(find.text('5 號　發言'), findsOneWidget, reason: '換人一律由法官按');
  });

  testWidgets('下一位會換人並直接開始計時', (tester) async {
    await pump(tester, state: _state(), order: [5, 6, 7]);

    await _tapText(tester, '開始');
    await _elapse(tester, 20);

    await _tapText(tester, '下一位（6 號）');
    expect(find.text('6 號　發言'), findsOneWidget);
    expect(_countdown(tester), '2:00');

    // 不必再按開始。
    await _elapse(tester, 10);
    expect(_countdown(tester), '1:50');
  });

  testWidgets('最後一位才出現結束鍵', (tester) async {
    final done = <bool>[];
    await pump(tester, state: _state(), order: [5, 6], finished: done);

    expect(find.text('發言結束，進入投票'), findsNothing);

    await _tapText(tester, '下一位（6 號）');
    expect(find.text('最後一位'), findsOneWidget);
    expect(find.text('發言結束，進入投票'), findsOneWidget);
    expect(done, isEmpty);

    await _tapText(tester, '發言結束，進入投票');
    expect(done, [true]);
  });

  testWidgets('點順序條可以直接跳到任一位', (tester) async {
    await pump(tester, state: _state(), order: [5, 6, 7]);

    await _tapText(tester, '7');

    expect(find.text('7 號　發言'), findsOneWidget);
    expect(find.text('最後一位'), findsOneWidget);
  });

  testWidgets('可以退回上一位重講', (tester) async {
    await pump(tester, state: _state(), order: [5, 6]);

    expect(find.text('上一位'), findsNothing, reason: '第一位沒有上一位');

    await _tapText(tester, '下一位（6 號）');
    await _elapse(tester, 30);

    await _tapText(tester, '上一位');
    expect(find.text('5 號　發言'), findsOneWidget);
    expect(_countdown(tester), '2:00', reason: '退回來重新計時');
  });

  testWidgets('法官現場可以改每人時間', (tester) async {
    await pump(tester, state: _state(), order: [5, 6]);

    await _tapText(tester, '開始');
    await _elapse(tester, 30);
    // 先暫停，碼表才不會在按晶片的那一瞬間又跳一秒。
    await _tapText(tester, '暫停');
    final before = _remaining(tester);

    await _tapText(tester, '3:00');
    expect(_remaining(tester), before + 60,
        reason: '額度多 60 秒，已講掉的秒數要留著');
    expect(find.text('每人 3:00'), findsOneWidget);
  });

  testWidgets('重來只歸零這一位', (tester) async {
    await pump(tester, state: _state(), order: [5, 6]);

    await _tapText(tester, '開始');
    await _elapse(tester, 40);

    await _tapText(tester, '重來');
    expect(_countdown(tester), '2:00');
    expect(find.text('5 號　發言'), findsOneWidget);
    expect(find.text('開始'), findsOneWidget, reason: '重來之後等法官重新按開始');
  });

  testWidgets('遺言用同一套碼表，只是稱呼不同', (tester) async {
    await pump(
      tester,
      state: _state(),
      order: [10],
      phase: SpeechPhase.lastWords,
    );

    expect(find.text('10 號　遺言'), findsOneWidget);
    expect(find.text('最後一位'), findsOneWidget);
    expect(find.text('遺言結束'), findsOneWidget);
  });

  testWidgets('板子可以自訂發言秒數', (tester) async {
    await pump(tester, state: _state(speechSeconds: 90), order: [5]);

    expect(_countdown(tester), '1:30');
    expect(find.text('每人 1:30'), findsOneWidget);
  });
}
