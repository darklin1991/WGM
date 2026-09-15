import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/features/setup/player_registry_page.dart';
import 'package:wgm/shared/theme.dart';

/// 測試用板子：3狼 / 預言家 / 女巫 / 獵人 / 3民 = 9 人。
Preset _testPreset() => Preset.fromJson(
      const {
        'presetId': 'test_9p',
        'name': '測試 9 人局',
        'playerCount': 9,
        'roles': [
          {'role': 'wolf', 'count': 3},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'villager', 'count': 3},
        ],
        'nightOrder': ['wolf', 'witch', 'seer'],
      },
      sourceName: 'test_9p.json',
    );

Widget _wrap(Widget child) =>
    MaterialApp(theme: WgmTheme.build(), home: child);

void main() {
  testWidgets('玩家登記頁顯示所有座次，且未完成登記時無法進入第一夜', (tester) async {
    final state = GameState(preset: _testPreset());
    await tester.pumpWidget(_wrap(PlayerRegistryPage(state: state)));

    // 9 個座次都要出現。
    for (var seat = 1; seat <= 9; seat++) {
      expect(find.text('$seat'), findsOneWidget);
    }

    expect(find.text('請先完成身分登記'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull, reason: '身分未登記完成時按鈕應為 disabled');
  });

  testWidgets('隨機發牌後身分符合板子配置，按鈕變為可用', (tester) async {
    final state = GameState(preset: _testPreset());
    await tester.pumpWidget(_wrap(PlayerRegistryPage(state: state)));

    await tester.tap(find.byTooltip('隨機發牌'));
    await tester.pumpAndSettle();

    expect(state.allRolesAssigned, isTrue);
    expect(state.assignmentMatchesPreset, isTrue);
    expect(find.text('進入第一夜'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });
}
