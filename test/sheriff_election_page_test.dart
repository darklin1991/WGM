import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';
import 'package:wgm/features/day/sheriff_election_page.dart';
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

Future<void> _tapSeat(WidgetTester tester, int seat) async {
  await tester.tap(find.text('$seat').first);
  await tester.pump();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 走完警上發言：逐位按「下一位」，講到最後一位才會出現結束鍵。
Future<void> _passCampaignSpeech(WidgetTester tester) async {
  for (var guard = 0; guard < 20; guard++) {
    final next = find.textContaining('下一位（');
    if (next.evaluate().isEmpty) break;
    await tester.ensureVisible(next.first);
    await tester.pumpAndSettle();
    await tester.tap(next.first);
    await tester.pumpAndSettle();
  }
  await _tapText(tester, '警上發言結束');
}

void main() {
  /// 建好競選頁；[finished] 會在競選結束時被設成 true。
  Future<GameState> pump(WidgetTester tester, {List<bool>? finished}) async {
    final state = _state();
    await tester.pumpWidget(
      MaterialApp(
        theme: WgmTheme.build(),
        home: SheriffElectionPage(
          state: state,
          onFinished: () => finished?.add(true),
        ),
      ),
    );
    return state;
  }

  testWidgets('沒人上警 → 直接跳過競選', (tester) async {
    final done = <bool>[];
    final state = await pump(tester, finished: done);

    expect(find.text('要上警的請舉手'), findsOneWidget);
    await _tapText(tester, '沒人上警，跳過競選');

    expect(done, isNotEmpty, reason: '競選結束，接著公布死訊');
    expect(state.sheriffSeat, isNull);
  });

  testWidgets('只有一人上警 → 不必投票直接當選', (tester) async {
    final done = <bool>[];
    final state = await pump(tester, finished: done);

    await _tapSeat(tester, 3);
    await _tapText(tester, '上警完畢');
    await _passCampaignSpeech(tester);

    expect(find.text('有人要退水嗎？'), findsOneWidget);
    await _tapText(tester, '退水完畢，開始投票');

    expect(state.sheriffSeat, 3, reason: '唯一候選人直接當選');
    expect(done, isNotEmpty);
  });

  testWidgets('按候選人歸票：點候選人再圈選投他的人，票數即時算', (tester) async {
    final done = <bool>[];
    final state = await pump(tester, finished: done);

    // 上警 3、7 號。
    await _tapSeat(tester, 3);
    await _tapSeat(tester, 7);
    await _tapText(tester, '上警完畢');
    await _passCampaignSpeech(tester);
    await _tapText(tester, '退水完畢，開始投票');

    expect(find.text('警長投票'), findsOneWidget);
    expect(find.text('先點上方的候選人，再圈選投給他的人'), findsOneWidget);

    // 點候選人 3 號，圈 9、10、11。
    await _tapText(tester, '3 號');
    expect(find.textContaining('投 3 號的請舉手'), findsOneWidget);
    for (final v in [9, 10, 11]) {
      await _tapSeat(tester, v);
    }
    expect(find.text('3 號 3 票'), findsOneWidget);

    // 換候選人 7 號，圈 12。
    await _tapText(tester, '7 號');
    await _tapSeat(tester, 12);
    expect(find.text('7 號 1 票'), findsOneWidget);

    await _tapText(tester, '算票');
    expect(state.sheriffSeat, 3);
    expect(done, isNotEmpty);
  });

  testWidgets('一人一票：投過的人換候選人時點不動', (tester) async {
    await pump(tester);

    await _tapSeat(tester, 3);
    await _tapSeat(tester, 7);
    await _tapText(tester, '上警完畢');
    await _passCampaignSpeech(tester);
    await _tapText(tester, '退水完畢，開始投票');

    await _tapText(tester, '3 號');
    await _tapSeat(tester, 9);
    expect(find.text('3 號 1 票'), findsOneWidget);

    // 換成 7 號時，9 號應顯示「已投 3 號」且點不動。
    await _tapText(tester, '7 號');
    expect(find.text('已投 3 號'), findsOneWidget);
    await _tapSeat(tester, 9);
    expect(find.text('7 號 0 票'), findsOneWidget, reason: '票沒有被搶走');
    expect(find.text('3 號 1 票'), findsOneWidget);
  });

  testWidgets('候選人與退水者不能投票，畫面標明原因', (tester) async {
    await pump(tester);

    await _tapSeat(tester, 3);
    await _tapSeat(tester, 7);
    await _tapSeat(tester, 11);
    await _tapText(tester, '上警完畢');
    await _passCampaignSpeech(tester);

    // 11 號退水。
    await _tapSeat(tester, 11);
    await _tapText(tester, '退水完畢，開始投票');

    await _tapText(tester, '3 號');
    expect(find.text('已退水'), findsOneWidget);
    expect(find.text('候選人'), findsWidgets);

    // 退水的 11 號點不動。
    await _tapSeat(tester, 11);
    expect(find.text('3 號 0 票'), findsOneWidget);
  });

  testWidgets('未投票名單列出來，法官不會漏人', (tester) async {
    await pump(tester);

    await _tapSeat(tester, 3);
    await _tapSeat(tester, 7);
    await _tapText(tester, '上警完畢');
    await _passCampaignSpeech(tester);
    await _tapText(tester, '退水完畢，開始投票');

    await _tapText(tester, '3 號');
    for (final v in [1, 2, 4, 5, 6, 8, 9, 10]) {
      await _tapSeat(tester, v);
    }

    expect(find.textContaining('尚未投票：11、12 號'), findsOneWidget);
  });

  testWidgets('平票 → 進入 PK 重投，票數歸零', (tester) async {
    final state = await pump(tester);

    await _tapSeat(tester, 3);
    await _tapSeat(tester, 7);
    await _tapText(tester, '上警完畢');
    await _passCampaignSpeech(tester);
    await _tapText(tester, '退水完畢，開始投票');

    await _tapText(tester, '3 號');
    await _tapSeat(tester, 9);
    await _tapText(tester, '7 號');
    await _tapSeat(tester, 10);
    await _tapText(tester, '算票');

    expect(find.text('平票 PK · 重新投票'), findsOneWidget);
    expect(find.text('3 號 0 票'), findsOneWidget, reason: '票數歸零重投');
    expect(state.sheriffSeat, isNull);
  });

  testWidgets('撤銷退回上一階段，名單還在', (tester) async {
    await pump(tester);

    await _tapSeat(tester, 3);
    await _tapSeat(tester, 7);
    await _tapText(tester, '上警完畢');
    await _passCampaignSpeech(tester);

    expect(find.text('有人要退水嗎？'), findsOneWidget);

    // 警上發言也是一個階段，所以要退兩步才回到上警。
    await _tapText(tester, '撤銷上一步（警上發言）');
    expect(find.text('警上發言'), findsOneWidget);

    await _tapText(tester, '撤銷上一步（上警）');

    expect(find.text('要上警的請舉手'), findsOneWidget);
    // 名單保留 → 直接按下一步仍是兩位候選人。
    await _tapText(tester, '上警完畢');
    await _passCampaignSpeech(tester);
    await _tapText(tester, '退水完畢，開始投票');
    expect(find.text('3 號 0 票'), findsOneWidget);
    expect(find.text('7 號 0 票'), findsOneWidget);
  });
}
