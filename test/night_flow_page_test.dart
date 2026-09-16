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

/// 點座次號碼。座次格子的文字就是號碼本身。
Future<void> _tapSeat(WidgetTester tester, int seat) async {
  await tester.tap(find.text('$seat').first);
  await tester.pump();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('下一步'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首夜依序登記身分再發動技能，剩餘座次自動成為平民', (tester) async {
    final state = GameState(preset: _preset());
    await tester.pumpWidget(_wrap(NightFlowPage(state: state)));

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

    // 女巫看到的是刀口，不套用守衛結果 —— 這是同守同救成立的前提。
    expect(find.textContaining('今晚 9 號被刀'), findsOneWidget);
    await _tapSeat(tester, 9); // 下解藥 → 造成同守同救
    await _next(tester);

    // 毒藥：本局不可同夜雙藥，直接跳過。
    expect(find.text('女巫：要用毒藥嗎？'), findsOneWidget);
    await _next(tester);

    // ---- 步驟 4：預言家 ----
    expect(find.text('預言家請睜眼'), findsOneWidget);
    await _tapSeat(tester, 5);
    await _next(tester);
    expect(find.text('預言家要查驗誰？'), findsOneWidget);
    await _tapSeat(tester, 1); // 查到狼
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
    await tester.pumpWidget(_wrap(NightFlowPage(state: state)));

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
    await _next(tester); // 不用解藥
    await _next(tester); // 不用毒藥

    // 預言家。
    await _tapSeat(tester, 5);
    await _next(tester);
    await _tapSeat(tester, 1);
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
      await tester.pumpWidget(_wrap(NightFlowPage(state: state)));

      expect(find.text('第 2 夜　1/5'), findsOneWidget);
      expect(find.text('守衛要守誰？'), findsOneWidget,
          reason: '第二夜起不再登記座次');
      await _tapSeat(tester, 9);
      await _next(tester);

      expect(find.text('狼人要刀誰？'), findsOneWidget);
      await _tapSeat(tester, 10);
      await _next(tester);

      // 女巫毒獵人 → 手勢應變成拇指向下。
      await _next(tester); // 不用解藥
      expect(find.text('女巫：要用毒藥嗎？'), findsOneWidget);
      await _tapSeat(tester, 7);
      await _next(tester);

      await _tapSeat(tester, 2); // 預言家查驗
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

      await tester.pumpWidget(_wrap(NightFlowPage(state: state)));

      // 守衛已死 → 照常喊，但問不到守誰。
      expect(find.text('守衛請睜眼'), findsOneWidget);
      expect(find.text('守衛要守誰？'), findsNothing);
      expect(find.textContaining('照常喊'), findsWidgets);
      await _next(tester);

      // 狼人還活著 → 照常行動。
      expect(find.text('狼人要刀誰？'), findsOneWidget);
      await _tapSeat(tester, 10);
      await _next(tester);

      // 女巫。
      await _next(tester);
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

      await tester.pumpWidget(_wrap(NightFlowPage(state: state)));

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

      await tester.pumpWidget(_wrap(NightFlowPage(state: state)));
      await _tapSeat(tester, 9);
      await _next(tester); // 守衛

      expect(find.text('狼人要刀誰？'), findsOneWidget);
    });
  });

  testWidgets('登記階段未選滿人數時無法進入下一步', (tester) async {
    final state = GameState(preset: _preset());
    await tester.pumpWidget(_wrap(NightFlowPage(state: state)));

    // 守衛只需 1 位，未選時按鈕應為 disabled。
    var button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await _tapSeat(tester, 8);
    button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('已登記身分的座次，不會在後續登記步驟中重複出現', (tester) async {
    final state = GameState(preset: _preset());
    await tester.pumpWidget(_wrap(NightFlowPage(state: state)));

    await _tapSeat(tester, 8); // 守衛 = 8 號
    await _next(tester);
    await _tapSeat(tester, 9);
    await _next(tester);

    // 狼隊登記階段，8 號已是守衛，選它不應有效果。
    expect(find.text('狼人請睜眼'), findsOneWidget);
    await _tapSeat(tester, 8);
    expect(find.text('請選滿 4 位（已選 0）'), findsOneWidget);
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
      await tester.pumpWidget(_wrap(NightFlowPage(state: state)));

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

      // ---- 女巫：不用藥 ----
      await _next(tester);
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
      await tester.pumpWidget(_wrap(NightFlowPage(state: state)));

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
