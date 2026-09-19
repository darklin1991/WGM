import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/log_entry.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';
import 'package:wgm/features/review/review_log_page.dart';
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
  s.dayNumber = 2;
  return s;
}

/// 塞幾筆典型的日誌。
GameState _stateWithLog() {
  final s = _state();
  s.log
    ..add(round: 0, isNight: true, kind: LogKind.setup, text: '開局：狼王守衛局（12 人）')
    ..add(round: 1, isNight: true, kind: LogKind.nightAction, text: '守衛守 9 號')
    ..add(round: 1, isNight: true, kind: LogKind.info, text: '預言家查驗 1 號 → 查殺')
    ..add(round: 1, isNight: true, kind: LogKind.death, text: '10 號出局（平民・狼刀）')
    ..add(round: 1, isNight: false, kind: LogKind.election, text: '3 號當選警長')
    ..add(round: 1, isNight: false, kind: LogKind.vote, text: '1 號被放逐出局');
  return s;
}

void main() {
  Future<void> pump(WidgetTester tester, GameState state) => tester.pumpWidget(
        MaterialApp(
          theme: WgmTheme.build(),
          home: ReviewLogPage(state: state),
        ),
      );

  testWidgets('依夜次與天次分段列出', (tester) async {
    await pump(tester, _stateWithLog());

    expect(find.text('開局'), findsOneWidget);
    expect(find.text('第 1 夜'), findsOneWidget);
    expect(find.text('第 1 天'), findsOneWidget);

    expect(find.text('守衛守 9 號'), findsOneWidget);
    expect(find.text('預言家查驗 1 號 → 查殺'), findsOneWidget);
    expect(find.text('10 號出局（平民・狼刀）'), findsOneWidget);
    expect(find.text('3 號當選警長'), findsOneWidget);
  });

  testWidgets('每一筆標出分類', (tester) async {
    await pump(tester, _stateWithLog());

    expect(find.text('配置'), findsOneWidget);
    expect(find.text('行動'), findsOneWidget);
    expect(find.text('情報'), findsOneWidget);
    expect(find.text('出局'), findsOneWidget);
    expect(find.text('競選'), findsOneWidget);
    expect(find.text('投票'), findsOneWidget);
  });

  testWidgets('寫出總筆數，並說明撤銷過的不會留下', (tester) async {
    await pump(tester, _stateWithLog());

    expect(find.textContaining('共 6 筆'), findsOneWidget);
    expect(find.textContaining('撤銷過的操作不會留在這裡'), findsOneWidget);
  });

  testWidgets('還沒有紀錄時給一句話，複製鍵是暗的', (tester) async {
    await pump(tester, _state());

    expect(find.text('還沒有任何紀錄'), findsOneWidget);

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('複製鍵把整份日誌送進剪貼簿', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pump(tester, _stateWithLog());
    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, contains('狼王守衛局　復盤日誌'));
    expect(copied.single, contains('【第 1 夜】'));
    expect(copied.single, contains('· 守衛守 9 號'));
    expect(find.text('已複製整份日誌'), findsOneWidget);
  });
}
