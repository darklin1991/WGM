import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';
import 'package:wgm/features/night/night_flow_page.dart';
import 'package:wgm/features/night/night_result_page.dart';
import 'package:wgm/shared/theme.dart';

/// 12 人狼王守衛局。
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

Widget _wrap(Widget child) =>
    MaterialApp(theme: WgmTheme.build(), home: child);

/// 進入夜晚並建立流程頁 —— 推進 dayNumber 的職責在 NightFlowPage.route，
/// 測試走同一條路徑，才不會和實際流程脫節。
Widget _night(GameState state) {
  NightFlowPage.enterNight(state);
  return _wrap(NightFlowPage(state: state));
}

/// 點座次號碼。座次格子的文字就是號碼本身。
Future<void> _tapSeat(WidgetTester tester, int seat) async {
  await tester.tap(find.text('$seat').first);
  await tester.pump();
}

Future<void> _next(WidgetTester tester) async {
  await tester.ensureVisible(find.text('下一步'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('下一步'));
  await tester.pumpAndSettle();
}

/// 點一段文字（按鈕、chip）。測試視窗比手機矮，先捲到看得見再點。
Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

/// 第一天的警長競選排在公布死訊之前 —— 不上警直接跳過，接著才是結算頁。
Future<void> _skipElection(WidgetTester tester) async {
  expect(find.text('要上警的請舉手'), findsOneWidget);
  await _tapText(tester, '沒人上警，跳過競選');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首夜依序登記身分再發動技能，剩餘座次自動成為平民', (tester) async {
    final state = GameState(preset: _preset());
    await tester.pumpWidget(_night(state));

    // ---- 步驟 1：守衛登記 ----
    expect(find.text('守衛請睜眼'), findsOneWidget);
    await _tapSeat(tester, 8);
    await _next(tester);

    // 守衛守 9 號。
    expect(find.text('守衛要守誰？'), findsOneWidget);
    await _tapSeat(tester, 9);
    await _next(tester);

    // ---- 步驟 2：狼隊登記 4 位 ----
    expect(find.text('狼人請睜眼'), findsOneWidget);
    expect(find.text('請填入 4 位的座次號碼'), findsOneWidget);
    for (final seat in [1, 2, 3, 4]) {
      await _tapSeat(tester, seat);
    }
    await _next(tester);

    // 指定 4 號為狼王。
    expect(find.text('哪一位是狼王？'), findsOneWidget);
    await _tapSeat(tester, 4);
    await _next(tester);
    expect(state.playerAt(4).role?.id, Roles.wolfKing.id);
    expect(state.playerAt(1).role?.id, Roles.wolf.id);

    // 狼刀 9 號（已被守衛守住）。
    expect(find.text('狼人要刀誰？'), findsOneWidget);
    await _tapSeat(tester, 9);
    await _next(tester);

    // ---- 步驟 3：女巫 ----
    expect(find.text('女巫請睜眼'), findsOneWidget);
    await _tapSeat(tester, 6);
    await _next(tester);

    // 刀口寫在中間；女巫看到的是刀口，不套用守衛結果 —— 這是同守同救的前提。
    expect(find.text('今晚的刀口'), findsOneWidget);
    expect(find.text('9 號'), findsOneWidget);

    // 下方按解藥救 9 號 → 造成同守同救。毒藥同一頁，本局不可雙藥所以不用。
    await _tapText(tester, '救 9 號');
    await _next(tester);

    // ---- 步驟 4：預言家 ----
    expect(find.text('預言家請睜眼'), findsOneWidget);
    await _tapSeat(tester, 5);
    await _next(tester);
    expect(find.text('預言家要查驗誰？'), findsOneWidget);
    await _tapSeat(tester, 1); // 查到狼
    await _next(tester);

    // 查驗結果當場比給預言家看，再讓他閉眼。
    expect(find.text('比給預言家看'), findsOneWidget);
    expect(find.text('查殺'), findsOneWidget);
    await _next(tester);

    // ---- 步驟 5：獵人（登記號碼後給開槍手勢）----
    expect(find.text('獵人請睜眼'), findsOneWidget);
    expect(find.text('請填入座次號碼，接著給開槍手勢'), findsOneWidget);
    await _tapSeat(tester, 7);
    await _next(tester);

    // 獵人沒被毒 → 拇指向上。
    expect(find.text('請對獵人做出下面的手勢'), findsOneWidget);
    expect(find.text('拇指向上'), findsOneWidget);
    expect(find.text('可以開槍'), findsOneWidget);
    await _next(tester);

    // ---- 第一天先競選警長，再公布死訊 ----
    await _skipElection(tester);

    // ---- 結算頁 ----
    expect(find.byType(NightResultPage), findsOneWidget);

    // 同守同救 → 9 號仍然死亡。
    expect(state.playerAt(9).alive, isFalse);
    expect(find.textContaining('昨晚死亡：9 號'), findsOneWidget);
    expect(find.textContaining('奶穿'), findsOneWidget);

    // 剩餘 4 位自動成為平民。
    expect(state.allRolesAssigned, isTrue);
    expect(
      state.players.where((p) => p.role?.id == Roles.villager.id).length,
      4,
    );
    expect(find.textContaining('自動登記為平民'), findsOneWidget);

    // 預言家查殺。
    expect(find.textContaining('查殺'), findsOneWidget);
  });

  testWidgets('預女獵白：獵人與白痴都會被叫起來確認號碼', (tester) async {
    final preset = Preset.fromJson(
      const {
        'presetId': 'ynlb',
        'name': '預女獵白',
        'playerCount': 12,
        'roles': [
          {'role': 'wolf', 'count': 4},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'idiot', 'count': 1},
          {'role': 'villager', 'count': 4},
        ],
        'nightOrder': ['wolf', 'witch', 'seer'],
      },
      sourceName: 'ynlb.json',
    );
    final state = GameState(preset: preset);
    await tester.pumpWidget(_night(state));

    // 狼隊 4 位，無狼王。
    expect(find.text('狼人請睜眼'), findsOneWidget);
    for (final seat in [1, 2, 3, 4]) {
      await _tapSeat(tester, seat);
    }
    await _next(tester);
    expect(find.text('狼人要刀誰？'), findsOneWidget, reason: '無狼王，直接進技能');
    await _tapSeat(tester, 10);
    await _next(tester);

    // 女巫。
    await _tapSeat(tester, 6);
    await _next(tester);
    await _next(tester); // 女巫兩瓶藥都不用

    // 預言家。
    await _tapSeat(tester, 5);
    await _next(tester);
    await _tapSeat(tester, 1);
    await _next(tester);
    expect(find.text('比給預言家看'), findsOneWidget);
    await _next(tester);

    // 獵人 —— 登記號碼後給手勢。
    expect(find.text('獵人請睜眼'), findsOneWidget);
    await _tapSeat(tester, 7);
    await _next(tester);
    expect(find.text('拇指向上'), findsOneWidget);
    await _next(tester);

    // 白痴 —— 同樣叫起來確認號碼。
    expect(find.text('白痴請睜眼'), findsOneWidget);
    expect(find.text('確認號碼即可，白痴沒有夜間行動'), findsOneWidget);
    await _tapSeat(tester, 8);
    await _next(tester);

    // 結算：兩個身分都已登記，剩餘 4 位為平民。
    await _skipElection(tester);
    expect(find.byType(NightResultPage), findsOneWidget);
    expect(state.playerAt(7).role?.id, Roles.hunter.id);
    expect(state.playerAt(8).role?.id, Roles.idiot.id);
    expect(
      state.players.where((p) => p.role?.id == Roles.villager.id).length,
      4,
    );
  });

  group('第二夜（身分已登記）', () {
    /// 建好一個身分已配置、已進行過一夜的局面。
    GameState seeded() {
      final state = GameState(preset: _preset());
      void set(int seat, Role role) => state.playerAt(seat).role = role;
      for (final s in [1, 2, 3]) {
        set(s, Roles.wolf);
      }
      set(4, Roles.wolfKing);
      set(5, Roles.seer);
      set(6, Roles.witch);
      set(7, Roles.hunter);
      set(8, Roles.guard);
      for (var i = 9; i <= 12; i++) {
        set(i, Roles.villager);
      }
      state.dayNumber = 1; // 已過首夜
      return state;
    }

    testWidgets('不再問座次，直接收技能；獵人仍被叫起來給手勢', (tester) async {
      final state = seeded();
      await tester.pumpWidget(_night(state));

      expect(find.text('第 2 夜　1/5'), findsOneWidget);
      expect(find.text('守衛要守誰？'), findsOneWidget,
          reason: '第二夜起不再登記座次');
      await _tapSeat(tester, 9);
      await _next(tester);

      expect(find.text('狼人要刀誰？'), findsOneWidget);
      await _tapSeat(tester, 10);
      await _next(tester);

      // 女巫毒獵人 → 手勢應變成拇指向下。毒藥點號碼就選好，同一頁。
      expect(find.text('女巫請睜眼'), findsOneWidget);
      await _tapSeat(tester, 7);
      await _next(tester);

      await _tapSeat(tester, 2); // 預言家查驗
      await _next(tester);

      // 結果要**當場**比給預言家看 —— 2 號是狼，所以是查殺。
      // 等到夜晚結算頁才顯示就來不及了，那時預言家早就閉眼。
      expect(find.text('比給預言家看'), findsOneWidget);
      expect(find.text('查殺'), findsOneWidget);
      expect(find.text('2 號是狼人'), findsOneWidget);
      await _next(tester);

      expect(find.text('獵人請睜眼'), findsOneWidget);
      expect(find.text('拇指向下'), findsOneWidget);
      expect(find.text('不可開槍'), findsOneWidget);
      expect(find.textContaining('今晚被毒'), findsOneWidget);
      await _next(tester);

      expect(find.byType(NightResultPage), findsOneWidget);
      expect(state.playerAt(7).alive, isFalse, reason: '獵人被毒死');
    });

    // 跳過死掉的身分，玩家馬上就從流程長度聽出誰出局了 ——
    // 所以每個身分每晚都照喊，只是沒有東西要收。
    testWidgets('已出局的角色仍要照常喊，但沒有技能可收', (tester) async {
      final state = seeded();
      state.playerAt(8).alive = false; // 守衛出局
      state.playerAt(5).alive = false; // 預言家出局

      await tester.pumpWidget(_night(state));

      // 守衛已死 → 照常喊，但問不到守誰。
      expect(find.text('守衛請睜眼'), findsOneWidget);
      expect(find.text('守衛要守誰？'), findsNothing);
      expect(find.textContaining('照常喊'), findsWidgets);
      await _next(tester);

      // 狼人還活著 → 照常行動。
      expect(find.text('狼人要刀誰？'), findsOneWidget);
      await _tapSeat(tester, 10);
      await _next(tester);

      // 女巫（解藥＋毒藥同一頁）。
      await _next(tester);

      // 預言家已死 → 一樣照常喊。
      expect(find.text('預言家請睜眼'), findsOneWidget);
      expect(find.text('預言家要查驗誰？'), findsNothing);
      await _next(tester);

      expect(find.text('獵人請睜眼'), findsOneWidget);
    });

    // 直接跳過「狼人請睜眼」，玩家馬上從流程長度聽出狼死光了。
    testWidgets('狼隊全滅時仍要照常喊一次，只是沒有東西可收', (tester) async {
      final state = seeded();
      for (final seat in [1, 2, 3, 4]) {
        state.playerAt(seat).alive = false;
      }

      await tester.pumpWidget(_night(state));

      // 守衛先守。
      expect(find.text('守衛要守誰？'), findsOneWidget);
      await _tapSeat(tester, 9);
      await _next(tester);

      // 狼隊那一步保留，但變成走過場 —— 沒有刀口可選。
      expect(find.text('狼人請睜眼'), findsOneWidget);
      expect(find.text('狼人要刀誰？'), findsNothing);
      expect(find.textContaining('照常喊'), findsWidgets);
      await _next(tester);

      // 接著照常進入女巫。
      expect(find.textContaining('女巫'), findsWidgets);
    });

    testWidgets('狼隊只要還有一匹狼存活就照樣行動', (tester) async {
      final state = seeded();
      state.playerAt(1).alive = false;
      state.playerAt(2).alive = false;
      state.playerAt(3).alive = false;
      // 只剩狼王 4 號。

      await tester.pumpWidget(_night(state));
      await _tapSeat(tester, 9);
      await _next(tester); // 守衛

      expect(find.text('狼人要刀誰？'), findsOneWidget);
    });
  });

  testWidgets('登記階段未選滿人數時無法進入下一步', (tester) async {
    final state = GameState(preset: _preset());
    await tester.pumpWidget(_night(state));

    // 守衛只需 1 位，未選時按鈕應為 disabled。
    var button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await _tapSeat(tester, 8);
    button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('已登記身分的座次，不會在後續登記步驟中重複出現', (tester) async {
    final state = GameState(preset: _preset());
    await tester.pumpWidget(_night(state));

    await _tapSeat(tester, 8); // 守衛 = 8 號
    await _next(tester);
    await _tapSeat(tester, 9);
    await _next(tester);

    // 狼隊登記階段，8 號已是守衛，選它不應有效果。
    expect(find.text('狼人請睜眼'), findsOneWidget);
    await _tapSeat(tester, 8);
    expect(find.text('請選滿 4 位（已選 0）'), findsOneWidget);
  });

  // 解藥與毒藥收在同一畫面：刀口在中間，兩瓶藥並列在下方。
  // 解藥「能用的時候才變亮」，毒藥「點了號碼才變亮」。
  group('女巫那一頁', () {
    GameState seeded() {
      final state = GameState(preset: _preset());
      void set(int seat, Role role) => state.playerAt(seat).role = role;
      for (final s in [1, 2, 3]) {
        set(s, Roles.wolf);
      }
      set(4, Roles.wolfKing);
      set(5, Roles.seer);
      set(6, Roles.witch);
      set(7, Roles.hunter);
      set(8, Roles.guard);
      for (var i = 9; i <= 12; i++) {
        set(i, Roles.villager);
      }
      state.dayNumber = 1;
      return state;
    }

    /// 走到女巫那一頁，狼刀砍 [knifed] 號。
    Future<GameState> toWitch(WidgetTester tester, {int knifed = 10}) async {
      final state = seeded();
      await tester.pumpWidget(_night(state));
      await _tapSeat(tester, 9);
      await _next(tester); // 守衛
      await _tapSeat(tester, knifed);
      await _next(tester); // 狼刀
      expect(find.text('女巫請睜眼'), findsOneWidget);
      return state;
    }

    testWidgets('刀口寫在中間，解藥與毒藥並列在下方', (tester) async {
      await toWitch(tester);

      expect(find.text('今晚的刀口'), findsOneWidget);
      expect(find.text('10 號'), findsOneWidget);
      expect(find.text('解藥'), findsOneWidget);
      expect(find.text('毒藥'), findsOneWidget);

      // 解藥能用 → 出現「救 10 號」；毒藥還沒選號碼。
      expect(find.text('救 10 號'), findsOneWidget);
      expect(find.text('點上方號碼選毒藥目標'), findsOneWidget);
    });

    testWidgets('毒藥點了號碼才亮起來', (tester) async {
      final state = await toWitch(tester);

      expect(find.text('點上方號碼選毒藥目標'), findsOneWidget);
      await _tapSeat(tester, 11);
      expect(find.text('毒 11 號'), findsOneWidget, reason: '選了號碼，毒藥那排亮起');

      await _next(tester);
      await _next(tester); // 預言家不查
      await _next(tester); // 獵人手勢 → 結算
      expect(state.playerAt(11).alive, isFalse);
    });

    testWidgets('解藥用掉之後就不再亮，並說明原因', (tester) async {
      final state = seeded()..witchAntidoteAvailable = false;
      await tester.pumpWidget(_night(state));
      await _tapSeat(tester, 9);
      await _next(tester);
      await _tapSeat(tester, 10);
      await _next(tester);

      expect(find.text('救 10 號'), findsNothing);
      expect(find.text('解藥已在之前的夜晚用掉了'), findsOneWidget);
      expect(find.text('點上方號碼選毒藥目標'), findsOneWidget, reason: '毒藥還能用');
    });

    testWidgets('沒有人被刀時解藥不亮', (tester) async {
      final state = seeded();
      await tester.pumpWidget(_night(state));
      await _tapSeat(tester, 9);
      await _next(tester);
      await _next(tester); // 空刀

      expect(find.text('沒有人被刀'), findsOneWidget);
      expect(find.text('今晚沒有人被刀'), findsOneWidget);
    });

    testWidgets('本局不可同夜雙藥：下了解藥，毒藥整排就暗掉', (tester) async {
      await toWitch(tester);

      await _tapText(tester, '救 10 號');
      expect(find.text('已下解藥，本局不可同夜雙藥'), findsOneWidget);

      // 這時點號碼不該有作用。
      await _tapSeat(tester, 11);
      expect(find.text('毒 11 號'), findsNothing);
    });

    testWidgets('機械狼學到女巫：同一頁，但解藥那排是暗的', (tester) async {
      final preset = Preset.fromJson(
        const {
          'presetId': 'jx',
          'name': '機械狼通靈師',
          'playerCount': 12,
          'roles': [
            {'role': 'wolf', 'count': 3},
            {'role': 'mechanicWolf', 'count': 1},
            {'role': 'psychic', 'count': 1},
            {'role': 'witch', 'count': 1},
            {'role': 'hunter', 'count': 1},
            {'role': 'guard', 'count': 1},
            {'role': 'villager', 'count': 4},
          ],
          'nightOrder': [
            'mechanicWolf',
            'guard',
            'wolf',
            'witch',
            'hunter',
            'psychic',
          ],
        },
        sourceName: 'jx.json',
      );
      final state = GameState(preset: preset);
      void set(int seat, Role role) => state.playerAt(seat).role = role;
      for (final s in [1, 2, 3]) {
        set(s, Roles.wolf);
      }
      set(4, Roles.mechanicWolf);
      set(5, Roles.psychic);
      set(6, Roles.witch);
      set(7, Roles.hunter);
      set(8, Roles.guard);
      for (var i = 9; i <= 12; i++) {
        set(i, Roles.villager);
      }
      state
        ..dayNumber = 1
        ..mechanicWolfLearnedRole = Roles.witch
        ..mechanicWolfLearnedNight = 1;

      await tester.pumpWidget(_night(state));

      // 機械狼那一輪：開刀手勢 → 用藥（只有毒藥）。
      expect(find.text('機械狼請睜眼'), findsOneWidget);
      await _next(tester); // 開刀手勢

      expect(find.text('機械狼學到女巫只拿得到毒藥，沒有解藥'), findsOneWidget);
      await _tapSeat(tester, 10);
      expect(find.text('毒 10 號'), findsOneWidget);
    });
  });

  group('撤銷', () {
    GameState seeded() {
      final state = GameState(preset: _preset());
      void set(int seat, Role role) => state.playerAt(seat).role = role;
      for (final s in [1, 2, 3]) {
        set(s, Roles.wolf);
      }
      set(4, Roles.wolfKing);
      set(5, Roles.seer);
      set(6, Roles.witch);
      set(7, Roles.hunter);
      set(8, Roles.guard);
      for (var i = 9; i <= 12; i++) {
        set(i, Roles.villager);
      }
      state.dayNumber = 1;
      return state;
    }

    testWidgets('第一步沒有撤銷鈕，按過下一步才出現', (tester) async {
      await tester.pumpWidget(_night(seeded()));

      expect(find.textContaining('撤銷'), findsNothing);
      await _tapSeat(tester, 9);
      await _next(tester);

      expect(find.text('撤銷上一步（守衛）'), findsOneWidget);
    });

    testWidgets('撤銷退回上一步，之前選的座次還在，可以直接改', (tester) async {
      final state = seeded();
      await tester.pumpWidget(_night(state));

      // 守衛不小心守了 9 號。
      await _tapSeat(tester, 9);
      await _next(tester);
      expect(find.text('狼人要刀誰？'), findsOneWidget);

      // 撤銷 → 回到守衛那一步。
      await tester.tap(find.text('撤銷上一步（守衛）'));
      await tester.pumpAndSettle();
      expect(find.text('守衛要守誰？'), findsOneWidget);

      // 改守 11 號後繼續，狼刀 9 號應該就守不到了。
      await _tapSeat(tester, 11);
      await _next(tester);
      await _tapSeat(tester, 9);
      await _next(tester);
      await _next(tester); // 女巫兩瓶藥都不用
      await _next(tester); // 預言家不查
      await _next(tester); // 獵人手勢 → 結算

      expect(find.byType(NightResultPage), findsOneWidget);
      expect(state.playerAt(9).alive, isFalse, reason: '守衛改守 11 號，9 號沒被守到');
      expect(state.lastGuardTarget, 11);
    });
  });

  group('狼美騎士（12人）', () {
    Preset lmPreset() => Preset.fromJson(
          const {
            'presetId': 'lm',
            'name': '狼美騎士',
            'playerCount': 12,
            'roles': [
              {'role': 'wolf', 'count': 3},
              {'role': 'wolfBeauty', 'count': 1},
              {'role': 'seer', 'count': 1},
              {'role': 'witch', 'count': 1},
              {'role': 'guard', 'count': 1},
              {'role': 'knight', 'count': 1},
              {'role': 'villager', 'count': 4},
            ],
            'nightOrder': ['guard', 'wolf', 'wolfBeauty', 'witch', 'seer'],
          },
          sourceName: 'lm.json',
        );

    /// 1-3 狼、4 狼美人、5 預言家、6 女巫、7 守衛、8 騎士、9-12 平民。
    GameState seededLm() {
      final state = GameState(preset: lmPreset());
      void set(int seat, Role role) => state.playerAt(seat).role = role;
      for (final s in [1, 2, 3]) {
        set(s, Roles.wolf);
      }
      set(4, Roles.wolfBeauty);
      set(5, Roles.seer);
      set(6, Roles.witch);
      set(7, Roles.guard);
      set(8, Roles.knight);
      for (var i = 9; i <= 12; i++) {
        set(i, Roles.villager);
      }
      state.dayNumber = 1; // 已過首夜
      return state;
    }

    // 魅惑的連續限制與守衛的「不可連守同一人」完全對稱。
    testWidgets('昨晚魅惑過的人不能再選，狼刀也不能指向狼美人', (tester) async {
      final state = seededLm()
        ..lastCharmTarget = 10
        ..charmedSeat = 10
        ..lastGuardTarget = 9;
      await tester.pumpWidget(_night(state));

      // 守衛：昨晚守過的 9 號不可選。
      expect(find.text('守衛要守誰？'), findsOneWidget);
      expect(find.text('昨晚已守'), findsOneWidget);
      await _tapSeat(tester, 11);
      await _next(tester);

      // 狼刀：狼美人（4 號）不可選。
      expect(find.text('狼人要刀誰？'), findsOneWidget);
      expect(find.text('狼美人不能自刀'), findsOneWidget);
      await _tapSeat(tester, 12);
      await _next(tester);

      // 魅惑：昨晚魅惑過的 10 號不可選，點了也沒作用。
      expect(find.text('狼美人要魅惑誰？'), findsOneWidget);
      expect(find.text('昨晚已魅惑'), findsOneWidget);
      await _tapSeat(tester, 10);
      await _tapSeat(tester, 11);
      await _next(tester);

      // 女巫不用藥、預言家不查 → 結算。
      await _next(tester);
      await _next(tester);

      expect(find.byType(NightResultPage), findsOneWidget);
      expect(state.charmedSeat, 11, reason: '10 號點不動，實際魅惑的是 11 號');
      expect(state.lastCharmTarget, 11);
    });

    testWidgets('狼美人出局後，魅惑那一步走過場', (tester) async {
      final state = seededLm();
      state.playerAt(4).alive = false;

      await tester.pumpWidget(_night(state));

      await _tapSeat(tester, 9);
      await _next(tester); // 守衛
      await _tapSeat(tester, 10);
      await _next(tester); // 狼刀

      expect(find.text('狼美人請睜眼'), findsOneWidget);
      expect(find.text('狼美人要魅惑誰？'), findsNothing);
      expect(find.textContaining('照常喊'), findsWidgets);
    });
  });

  group('機械狼帶刀（12人 機械狼通靈師）', () {
    Preset mechanicPreset() => Preset.fromJson(
          const {
            'presetId': 'jx',
            'name': '機械狼通靈師',
            'playerCount': 12,
            'roles': [
              {'role': 'wolf', 'count': 3},
              {'role': 'mechanicWolf', 'count': 1},
              {'role': 'psychic', 'count': 1},
              {'role': 'witch', 'count': 1},
              {'role': 'hunter', 'count': 1},
              {'role': 'guard', 'count': 1},
              {'role': 'villager', 'count': 4},
            ],
            'nightOrder': [
              'mechanicWolf',
              'guard',
              'wolf',
              'witch',
              'hunter',
              'psychic',
            ],
          },
          sourceName: 'jx.json',
        );

    /// 第二夜起：身分已登記，小狼全滅，機械狼首夜學到狼人。
    GameState loneMechanic() {
      final state = GameState(preset: mechanicPreset());
      void set(int seat, Role role) => state.playerAt(seat).role = role;
      for (final s in [1, 2, 3]) {
        set(s, Roles.wolf);
      }
      set(4, Roles.mechanicWolf);
      set(5, Roles.psychic);
      set(6, Roles.witch);
      set(7, Roles.hunter);
      set(8, Roles.guard);
      for (var i = 9; i <= 12; i++) {
        set(i, Roles.villager);
      }
      for (final s in [1, 2, 3]) {
        state.playerAt(s).alive = false; // 小狼全滅
      }
      state
        ..dayNumber = 1
        ..mechanicWolfLearnedRole = Roles.wolf
        ..mechanicWolfLearnedNight = 1;
      return state;
    }

    testWidgets('第一刀在開頭那一輪，第二刀在狼人那一格', (tester) async {
      final state = loneMechanic();
      await tester.pumpWidget(_night(state));

      // ---- 第 1 格：機械狼的開刀手勢 ----
      expect(find.text('機械狼請睜眼'), findsOneWidget);
      expect(find.textContaining('今晚有刀'), findsWidgets);
      await _next(tester);

      // 第一刀砍 9 號。
      expect(find.text('機械狼第一刀要砍誰？'), findsOneWidget);
      await _tapSeat(tester, 9);
      await _next(tester);

      // ---- 第 2 格：守衛守 9 號 ----
      expect(find.text('守衛要守誰？'), findsOneWidget);
      await _tapSeat(tester, 9);
      await _next(tester);

      // ---- 第 3 格：原本的狼人位置，改問第二刀 ----
      expect(find.text('機械狼第二刀要砍誰？'), findsOneWidget);
      await _tapSeat(tester, 9); // 集中同一人 → 破盾
      await _next(tester);

      // ---- 女巫：不用藥（解藥＋毒藥同一頁）----
      await _next(tester);
      // ---- 獵人手勢 ----
      await _next(tester);
      // ---- 通靈師不查 ----
      await _next(tester);

      // 兩刀集中 9 號，守衛守了也沒用。
      expect(find.byType(NightResultPage), findsOneWidget);
      expect(state.playerAt(9).alive, isFalse);
    });

    testWidgets('沒學到狼人時，狼人那一格是走過場', (tester) async {
      final state = loneMechanic()..mechanicWolfLearnedRole = Roles.guard;
      await tester.pumpWidget(_night(state));

      // 開刀手勢 → 第一刀（沒有「第一刀」的字樣，因為只有一刀）。
      await _next(tester);
      expect(find.text('機械狼要刀誰？'), findsOneWidget);
      await _tapSeat(tester, 10);
      await _next(tester);

      // 學到守衛 → 接著守誰。
      expect(find.text('機械狼（守衛）要守誰？'), findsOneWidget);
      await _next(tester);

      // 守衛。
      expect(find.text('守衛要守誰？'), findsOneWidget);
      await _next(tester);

      // 狼人那一格：走過場，沒有第二刀。
      expect(find.text('狼人請睜眼'), findsOneWidget);
      expect(find.text('機械狼第二刀要砍誰？'), findsNothing);
      expect(find.textContaining('照常喊'), findsWidgets);
    });
  });
}
