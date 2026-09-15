import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_flow.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

Preset _parse(Map<String, dynamic> json) =>
    Preset.fromJson(json, sourceName: 'p.json');

/// 狼王守衛局：3狼 + 狼王 + 預女獵守 + 4民。
final _wolfKingGuard = _parse({
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
});

/// 預女獵白：4狼 + 預女獵白 + 4民。
final _yuNuLieBai = _parse({
  'presetId': 'ynlb',
  'name': '預女獵白',
  'playerCount': 12,
  'roles': const [
    {'role': 'wolf', 'count': 4},
    {'role': 'seer', 'count': 1},
    {'role': 'witch', 'count': 1},
    {'role': 'hunter', 'count': 1},
    {'role': 'idiot', 'count': 1},
    {'role': 'villager', 'count': 4},
  ],
  'nightOrder': const ['wolf', 'witch', 'seer'],
});

void main() {
  group('首夜步驟（狼王守衛局）', () {
    late List<NightStep> steps;

    setUp(() => steps = NightFlow.firstNightSteps(_wolfKingGuard));

    test('順序為 守衛 → 狼人 → 女巫 → 預言家 → 獵人', () {
      expect(
        steps.map((s) => s.title),
        ['守衛', '狼人', '女巫', '預言家', '獵人'],
      );
    });

    test('狼人與狼王合併成一步，共登記 4 個座次', () {
      final wolfStep = steps.firstWhere((s) => s.title == '狼人');
      expect(wolfStep.seatCount, 4);
      expect(
        wolfStep.roles.map((r) => r.id),
        containsAll(['wolf', 'wolfKing']),
      );
      expect(wolfStep.needsWolfKingPick, isTrue,
          reason: '登記完 4 個座次後要指定哪位是狼王');
      expect(wolfStep.wolfKingCount, 1);
    });

    test('各步驟的技能型別正確', () {
      Map<String, NightSkill> byTitle = {
        for (final s in steps) s.title: s.skill,
      };
      expect(byTitle['守衛'], NightSkill.guardProtect);
      expect(byTitle['狼人'], NightSkill.wolfKill);
      expect(byTitle['女巫'], NightSkill.witchPotion);
      expect(byTitle['預言家'], NightSkill.seerInspect);
      expect(
        byTitle['獵人'],
        NightSkill.hunterGesture,
        reason: '獵人每晚都要叫起來確認開槍手勢',
      );
    });

    test('獵人排在女巫之後 — 法官須先收完毒藥才知道給哪個手勢', () {
      final witchIndex = steps.indexWhere((s) => s.title == '女巫');
      final hunterIndex = steps.indexWhere((s) => s.title == '獵人');
      expect(witchIndex, greaterThanOrEqualTo(0));
      expect(hunterIndex, greaterThan(witchIndex));
    });

    test('平民不列入步驟 — 完成特殊身分後剩下的自動是平民', () {
      expect(steps.any((s) => s.roles.any((r) => r.id == Roles.villager.id)),
          isFalse);
      final registered =
          steps.fold<int>(0, (sum, s) => sum + s.seatCount);
      expect(registered, 8, reason: '12 人扣掉 4 平民');
    });
  });

  group('首夜步驟（預女獵白）', () {
    late List<NightStep> steps;

    setUp(() => steps = NightFlow.firstNightSteps(_yuNuLieBai));

    test('無守衛，且白痴排在最後只做登記', () {
      expect(steps.map((s) => s.title), ['狼人', '女巫', '預言家', '獵人', '白痴']);
      expect(steps.last.skill, NightSkill.none);
    });

    test('狼隊 4 人但沒有狼王，不需指定狼王', () {
      final wolfStep = steps.first;
      expect(wolfStep.seatCount, 4);
      expect(wolfStep.needsWolfKingPick, isFalse);
      expect(wolfStep.wolfKingCount, 0);
    });
  });

  group('第二夜起的步驟', () {
    test('不再登記座次，但獵人每晚保留（確認開槍手勢）', () {
      final steps = NightFlow.laterNightSteps(_wolfKingGuard);
      expect(steps.map((s) => s.title), ['守衛', '狼人', '女巫', '預言家', '獵人']);
      expect(steps.every((s) => s.seatCount == 0), isTrue);
      expect(steps.last.skill, NightSkill.hunterGesture);
    });

    test('白痴首夜登記完就不再出現，獵人仍每晚保留', () {
      final steps = NightFlow.laterNightSteps(_yuNuLieBai);
      expect(steps.map((s) => s.title), ['狼人', '女巫', '預言家', '獵人']);
      expect(steps.any((s) => s.title == '白痴'), isFalse);
      expect(steps.any((s) => s.skill == NightSkill.none), isFalse);
    });
  });
}
