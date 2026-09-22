import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_flow_machine.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 法官有兩種開局方式，**兩種都要能跑完第一夜**：
///
/// 1. 夜裡邊問邊登記 —— 登記頁不指定身分，首夜依夜晚順序問出座次。
///    這條路徑由 `test/night_flow_page_test.dart` 覆蓋。
/// 2. **開局前就配好** —— 登記頁把身分全部指定好再進第一夜。
///    這是 App 目前唯一走得通的路（`進入第一夜` 要 `assignmentMatchesPreset`
///    才會亮），卻是這個檔案補上之前**完全沒有測試覆蓋**的一條。
///
/// 曾經的症狀：首夜第一步就停在「請填入座次號碼」，12 個座位全部點不動
/// （可選座次＝尚未登記身分的座次＝空集合），下一步鍵永遠是灰的，
/// 任何板子都過不了第一夜。

Preset _load(String id) => Preset.fromJson(
      jsonDecode(File('assets/presets/$id.json').readAsStringSync())
          as Map<String, dynamic>,
      sourceName: '$id.json',
    );

/// 照登記頁的結果建局面：12 個身分全部指定好。
GameState _preassigned(Preset preset) {
  final state = GameState(preset: preset);
  var seat = 1;
  for (final slot in preset.roles) {
    for (var i = 0; i < slot.count; i++) {
      state.playerAt(seat++).role = slot.role;
    }
  }
  state.dayNumber = 1;
  return state;
}

/// 一路按「下一步」直到結算；中途卡住就讓測試失敗。
NightFlowMachine _runFirstNight(Preset preset) {
  final state = _preassigned(preset);
  expect(
    state.assignmentMatchesPreset,
    isTrue,
    reason: '這就是登記頁讓「進入第一夜」亮起來的條件',
  );

  final m = NightFlowMachine(state: state, night: 1, isFirstNight: true);
  for (var guard = 0; guard < 40; guard++) {
    expect(
      m.canProceed,
      isTrue,
      reason: '卡在「${m.step.title}」的 ${m.sub} —— 法官按不了下一步',
    );
    m.next();
    if (m.outcome != null) return m;
  }
  fail('40 步還沒走完第一夜');
}

void main() {
  const presetIds = [
    '12p_jixielang_tonglingshi',
    '12p_langmei_qishi',
    '12p_langwang_shouwei',
    '12p_yu_nu_lie_bai',
    '12p_yu_nu_lie_shou',
  ];

  group('身分已於登記頁配好時，首夜仍走得完', () {
    for (final id in presetIds) {
      test(id, () => _runFirstNight(_load(id)));
    }
  });

  test('機械狼板：身分已配好時不再問機械狼的座次，但照樣要叫牠起來', () {
    final state = _preassigned(_load('12p_jixielang_tonglingshi'));
    final m = NightFlowMachine(state: state, night: 1, isFirstNight: true);

    // 機械狼仍是第一個睜眼的，而且照樣從開刀手勢開始 ——
    // 省掉的只有「你是幾號」，不是整步跳過。
    expect(m.step.title, '機械狼');
    expect(m.sub, NightSub.mechanicKnifeGesture);
    expect(m.needsRegistration(m.step), isFalse);
    expect(m.canProceed, isTrue);
  });

  test('身分未登記時，照樣走原本的逐一登記流程', () {
    // 這條是回歸防線：上面的修正不可以把「夜裡邊問邊登記」弄壞。
    final state = GameState(preset: _load('12p_jixielang_tonglingshi'))
      ..dayNumber = 1;
    final m = NightFlowMachine(state: state, night: 1, isFirstNight: true);

    expect(m.step.title, '機械狼');
    expect(m.sub, NightSub.registerSeats);
    expect(m.needsRegistration(m.step), isTrue);
    expect(m.selectableSeats, hasLength(12));
    expect(m.canProceed, isFalse, reason: '還沒選座次，本來就不該能按下一步');
  });

  test('沒有夜間技能的角色（白痴）在身分已配好時整步跳過', () {
    // 白痴首夜那一步存在的唯一目的是問出座次。座次已知就沒有內容了，
    // 留著會變成「請選擇白痴要查驗誰」這種不存在的操作。
    final state = _preassigned(_load('12p_yu_nu_lie_bai'));
    final m = NightFlowMachine(state: state, night: 1, isFirstNight: true);

    final visited = <String>[];
    for (var guard = 0; guard < 40 && m.outcome == null; guard++) {
      visited.add('${m.step.title}/${m.sub}');
      m.next();
    }

    expect(visited.any((v) => v.startsWith('白痴')), isFalse);
    // 白痴仍然在板子裡，只是夜裡沒事做。
    expect(state.seatOfRole(Roles.idiot.id), isNotNull);
  });
}
