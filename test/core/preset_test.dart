import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/preset_format_exception.dart';
import 'package:wgm/core/rules/rule_flags.dart';

Map<String, dynamic> _base({
  int playerCount = 9,
  List<Map<String, Object>>? roles,
  List<String>? nightOrder,
  Map<String, dynamic>? rules,
}) =>
    {
      'presetId': 'p',
      'name': '測試板',
      'playerCount': playerCount,
      'roles': roles ??
          const [
            {'role': 'wolf', 'count': 3},
            {'role': 'seer', 'count': 1},
            {'role': 'witch', 'count': 1},
            {'role': 'hunter', 'count': 1},
            {'role': 'villager', 'count': 3},
          ],
      'nightOrder': nightOrder ?? const ['wolf', 'witch', 'seer'],
      'rules': ?rules,
    };

Preset _parse(Map<String, dynamic> json) =>
    Preset.fromJson(json, sourceName: 'p.json');

void main() {
  group('板子解析', () {
    test('合法設定可正確解析組成', () {
      final p = _parse(_base());
      expect(p.playerCount, 9);
      expect(p.wolfCount, 3);
      expect(p.godCount, 3);
      expect(p.villagerCount, 3);
      expect(p.composition, '3狼 3神 3民');
      expect(p.nightOrder.map((r) => r.id), ['wolf', 'witch', 'seer']);
    });

    test('身分牌堆長度等於人數', () {
      expect(_parse(_base()).buildRoleDeck().length, 9);
    });

    test('未提供 rules 時使用預設旗標', () {
      final r = _parse(_base()).rules;
      expect(r.guardHealKills, isTrue);
      expect(r.sheriffVoteWeight, 1.5);
      expect(r.tieBreak, TieBreak.pkThenNone);
      expect(r.winCondition, WinCondition.sideElimination);
    });
  });

  group('女巫自救的人數規則（9 人以上不可自救）', () {
    List<Map<String, Object>> rolesFor(int villagers) => [
          {'role': 'wolf', 'count': 2},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'villager', 'count': villagers},
        ];

    Preset presetOf(int playerCount, {Map<String, dynamic>? rules}) => _parse(
          _base(
            playerCount: playerCount,
            roles: rolesFor(playerCount - 4),
            nightOrder: const ['wolf', 'witch', 'seer'],
            rules: rules,
          ),
        );

    test('9 人局：預設不可自救', () {
      final r = presetOf(9).rules;
      expect(r.witchSelfHealNight, 0);
      expect(r.witchMaySelfHeal(1), isFalse);
    });

    test('12 人局：預設不可自救', () {
      expect(presetOf(12).rules.witchMaySelfHeal(1), isFalse);
    });

    test('8 人以下的小局：預設僅首夜可自救', () {
      final r = presetOf(8).rules;
      expect(r.witchSelfHealNight, 1);
      expect(r.witchMaySelfHeal(1), isTrue);
      expect(r.witchMaySelfHeal(2), isFalse);
    });

    test('設定檔明確指定時以指定值為準（規則變體仍可覆寫）', () {
      final r = presetOf(12, rules: const {'witchSelfHealNight': 1}).rules;
      expect(r.witchSelfHealNight, 1);
      expect(r.witchMaySelfHeal(1), isTrue);
    });

    test('直接使用 defaultWitchSelfHealNight 的邊界值', () {
      expect(RuleFlags.defaultWitchSelfHealNight(8), 1);
      expect(RuleFlags.defaultWitchSelfHealNight(9), 0);
      expect(RuleFlags.defaultWitchSelfHealNight(12), 0);
    });
  });

  group('板子驗證（錯誤設定必須在載入時就被擋下）', () {
    test('角色數量總和與 playerCount 不符', () {
      expect(
        () => _parse(_base(playerCount: 12)),
        throwsA(
          isA<PresetFormatException>().having(
            (e) => e.message,
            'message',
            contains('與 playerCount'),
          ),
        ),
      );
    });

    test('無法辨識的角色 id', () {
      expect(
        () => _parse(_base(roles: const [
          {'role': 'dragon', 'count': 9},
        ])),
        throwsA(isA<PresetFormatException>()
            .having((e) => e.field, 'field', 'roles[0].role')),
      );
    });

    test('nightOrder 含未配置的角色', () {
      expect(
        () => _parse(_base(nightOrder: const ['guard', 'wolf'])),
        throwsA(
          isA<PresetFormatException>().having(
            (e) => e.message,
            'message',
            contains('未出現在 roles 裡'),
          ),
        ),
      );
    });

    test('count 為 0 或負數', () {
      expect(
        () => _parse(_base(roles: const [
          {'role': 'wolf', 'count': 0},
          {'role': 'villager', 'count': 9},
        ])),
        throwsA(isA<PresetFormatException>()
            .having((e) => e.field, 'field', 'roles[0].count')),
      );
    });

    // 引擎用 seatOfRole 找身分，只會回傳第一個 —— 多填第二位的技能會直接消失。
    test('一般狼與平民以外的身分只能有 1 位', () {
      expect(
        () => _parse(_base(roles: const [
          {'role': 'wolf', 'count': 3},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 2},
          {'role': 'villager', 'count': 3},
        ])),
        throwsA(isA<PresetFormatException>()
            .having((e) => e.field, 'field', 'roles[2].count')
            .having((e) => e.message, 'message', contains('只能有 1 位'))),
      );
    });

    test('一般狼與平民可以多位', () {
      final p = _parse(_base(
        playerCount: 10,
        roles: const [
          {'role': 'wolf', 'count': 4},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'villager', 'count': 4},
        ],
      ));

      expect(p.wolfCount, 4);
      expect(p.villagerCount, 4);
    });

    test('同一角色重複列出', () {
      expect(
        () => _parse(_base(roles: const [
          {'role': 'wolf', 'count': 3},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'villager', 'count': 3},
        ])),
        throwsA(isA<PresetFormatException>()
            .having((e) => e.field, 'field', 'roles[3].role')
            .having((e) => e.message, 'message', contains('重複'))),
      );
    });

    // 漏排的角色會被流程產生器默默接在最後，法官照著跑就會出錯 ——
    // 例如漏了女巫，獵人的開槍手勢會在毒還沒收之前就給出去。
    test('有夜間行動的角色沒排進 nightOrder', () {
      expect(
        () => _parse(_base(nightOrder: const ['wolf', 'seer'])), // 漏了女巫
        throwsA(isA<PresetFormatException>()
            .having((e) => e.field, 'field', 'nightOrder')
            .having((e) => e.message, 'message', contains('女巫'))),
      );
    });

    test('沒有夜間行動的角色不必排進 nightOrder', () {
      // 獵人只需要手勢、白痴只需登記，兩者都不在 nightOrder 裡也合法。
      final p = _parse(_base(
        playerCount: 10,
        roles: const [
          {'role': 'wolf', 'count': 3},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'hunter', 'count': 1},
          {'role': 'idiot', 'count': 1},
          {'role': 'villager', 'count': 3},
        ],
      ));

      expect(p.nightOrder.map((r) => r.id), ['wolf', 'witch', 'seer']);
    });

    test('狼隊成員與一般狼合併成一步，只列 wolf 就算涵蓋狼王', () {
      final p = _parse(_base(
        playerCount: 10,
        roles: const [
          {'role': 'wolf', 'count': 3},
          {'role': 'wolfKing', 'count': 1},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'villager', 'count': 4},
        ],
        nightOrder: const ['wolf', 'witch', 'seer'], // 沒列 wolfKing
      ));

      expect(p.wolfCount, 4);
    });

    test('無法辨識的 tieBreak 值', () {
      expect(
        () => _parse(_base(rules: const {'tieBreak': 'coin_flip'})),
        throwsA(isA<PresetFormatException>()
            .having((e) => e.field, 'field', 'rules.tieBreak')),
      );
    });

    test('旗標型別錯誤', () {
      expect(
        () => _parse(_base(rules: const {'guardHealKills': 'yes'})),
        throwsA(isA<PresetFormatException>()
            .having((e) => e.field, 'field', 'rules.guardHealKills')),
      );
    });

    test('錯誤訊息含板子 id 與欄位，便於定位', () {
      final e = () {
        try {
          _parse(_base(playerCount: 12));
        } on PresetFormatException catch (e) {
          return e;
        }
        return null;
      }();
      expect(e, isNotNull);
      expect(e.toString(), contains('p'));
      expect(e.toString(), contains('roles'));
    });
  });

  group('女巫自救旗標的語意', () {
    test('witchSelfHealNight = 1：僅首夜可自救', () {
      const r = RuleFlags(witchSelfHealNight: 1);
      expect(r.witchMaySelfHeal(1), isTrue);
      expect(r.witchMaySelfHeal(2), isFalse);
    });

    test('witchSelfHealNight = 0：完全不可自救', () {
      const r = RuleFlags(witchSelfHealNight: 0);
      expect(r.witchMaySelfHeal(1), isFalse);
    });

    test('witchSelfHealNight = -1：不限夜次', () {
      const r = RuleFlags(witchSelfHealNight: -1);
      expect(r.witchMaySelfHeal(1), isTrue);
      expect(r.witchMaySelfHeal(9), isTrue);
    });
  });
}
