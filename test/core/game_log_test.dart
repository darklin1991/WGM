import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/badge_succession.dart';
import 'package:wgm/core/engine/knight_duel.dart';
import 'package:wgm/core/engine/night_arbitrator.dart';
import 'package:wgm/core/engine/vote_resolver.dart';
import 'package:wgm/core/log/game_log.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/log_entry.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

/// 12人 狼美騎士：3狼＋狼美人、預女守騎、4民。
Preset _preset({Map<String, dynamic>? rules}) => Preset.fromJson(
      {
        'presetId': 'lmqs',
        'name': '狼美騎士',
        'playerCount': 12,
        'roles': const [
          {'role': 'wolf', 'count': 3},
          {'role': 'wolfBeauty', 'count': 1},
          {'role': 'seer', 'count': 1},
          {'role': 'witch', 'count': 1},
          {'role': 'guard', 'count': 1},
          {'role': 'knight', 'count': 1},
          {'role': 'villager', 'count': 4},
        ],
        'nightOrder': const ['guard', 'wolf', 'wolfBeauty', 'witch', 'seer'],
        'rules': ?rules,
      },
      sourceName: 'lmqs.json',
    );

/// 1-3 狼、4 狼美人、5 預言家、6 女巫、7 守衛、8 騎士、9-12 平民。
GameState _state({Map<String, dynamic>? rules}) {
  final s = GameState(preset: _preset(rules: rules));
  void set(int seat, Role r) => s.playerAt(seat).role = r;
  for (final seat in [1, 2, 3]) {
    set(seat, Roles.wolf);
  }
  set(4, Roles.wolfBeauty);
  set(5, Roles.seer);
  set(6, Roles.witch);
  set(7, Roles.guard);
  set(8, Roles.knight);
  for (var i = 9; i <= 12; i++) {
    set(i, Roles.villager);
  }
  s.dayNumber = 1;
  return s;
}

/// 日誌裡的所有句子。
List<String> _texts(GameState s) => s.log.entries.map((e) => e.text).toList();

void main() {
  group('GameLog 本身', () {
    test('空的時候沒有段落', () {
      final log = GameLog();

      expect(log.isEmpty, isTrue);
      expect(log.sections, isEmpty);
      expect(log.toPlainText(), '');
    });

    test('空字串不記', () {
      final log = GameLog()
        ..add(round: 1, isNight: true, kind: LogKind.info, text: '');

      expect(log.length, 0);
    });

    test('依夜次／天次分段，順序照寫入順序', () {
      final log = GameLog()
        ..add(round: 1, isNight: true, kind: LogKind.death, text: 'a')
        ..add(round: 1, isNight: true, kind: LogKind.death, text: 'b')
        ..add(round: 1, isNight: false, kind: LogKind.vote, text: 'c')
        ..add(round: 2, isNight: true, kind: LogKind.death, text: 'd');

      final s = log.sections;
      expect(s.length, 3);
      expect(s[0].label, '第 1 夜');
      expect(s[0].entries.length, 2);
      expect(s[1].label, '第 1 天');
      expect(s[2].label, '第 2 夜');
    });

    test('第 0 輪叫開局', () {
      final log = GameLog()
        ..add(round: 0, isNight: true, kind: LogKind.setup, text: '開局：測試板');

      expect(log.sections.single.label, '開局');
    });

    test('匯出成純文字，帶標題與段落', () {
      final log = GameLog()
        ..add(round: 1, isNight: true, kind: LogKind.death, text: '3 號出局')
        ..add(round: 1, isNight: false, kind: LogKind.vote, text: '9 號被放逐');

      expect(
        log.toPlainText(title: '狼美騎士　復盤日誌'),
        '狼美騎士　復盤日誌\n'
        '\n'
        '【第 1 夜】\n'
        '· 3 號出局\n'
        '\n'
        '【第 1 天】\n'
        '· 9 號被放逐',
      );
    });
  });

  group('日誌掛在 GameState 上，撤銷會一起退回去', () {
    test('深拷貝是獨立的，不會互相污染', () {
      final s = _state();
      s.log.add(round: 1, isNight: true, kind: LogKind.info, text: '第一筆');

      final snapshot = s.copy();
      s.log.add(round: 1, isNight: true, kind: LogKind.info, text: '第二筆');

      expect(s.log.length, 2);
      expect(snapshot.log.length, 1, reason: '快照不該被後來的寫入影響');
    });

    test('還原之後多寫的那幾筆會消失', () {
      final s = _state();
      s.log.add(round: 1, isNight: true, kind: LogKind.info, text: '第一筆');
      final snapshot = s.copy();

      s.log.add(round: 1, isNight: true, kind: LogKind.info, text: '第二筆');
      s.restoreFrom(snapshot);

      expect(_texts(s), ['第一筆'], reason: '撤銷過的操作不該留在復盤裡');
    });

    test('撤銷放逐 → 那一輪的日誌也不見了', () {
      final s = _state();
      final v = ExileVote(state: s)..focusTarget(9);
      for (final voter in [1, 2, 3, 4, 5, 6, 7]) {
        v.toggleVote(voter);
      }
      v.next();

      expect(s.playerAt(9).alive, isFalse);
      expect(_texts(s).any((t) => t.contains('9 號被放逐出局')), isTrue);

      v.undo();
      expect(s.playerAt(9).alive, isTrue);
      expect(s.log.isEmpty, isTrue, reason: '局面退回去了，日誌也要退');
    });
  });

  group('夜晚結算寫進日誌', () {
    NightOutcome settleNight(GameState s, NightActions a) {
      const arb = NightArbitrator();
      final outcome = arb.settle(s, a);
      arb.apply(s, a, outcome);
      return outcome;
    }

    test('行動、情報、裁決、死亡都記下來', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..guardTarget = 9
        ..wolfTarget = 10
        ..witchPoisonTarget = 11
        ..seerTarget = 1;
      settleNight(s, a);

      final texts = _texts(s);
      expect(texts, contains('守衛守 9 號'));
      expect(texts, contains('狼刀 10 號'));
      expect(texts, contains('女巫用毒藥毒 11 號'));
      expect(texts, contains('預言家查驗 1 號 → 查殺'));
      expect(texts.any((t) => t.startsWith('10 號出局')), isTrue);
      expect(texts.any((t) => t.startsWith('11 號出局')), isTrue);
    });

    test('死亡那筆帶身分與死因', () {
      final s = _state();
      final a = NightActions(night: 1)..wolfTarget = 5;
      settleNight(s, a);

      expect(_texts(s), contains('5 號出局（預言家・狼刀）'));
    });

    test('平安夜也要留一筆', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..guardTarget = 9
        ..wolfTarget = 9;
      settleNight(s, a);

      expect(_texts(s), contains('平安夜，沒有人出局'));
    });

    test('空刀記成空刀 —— 裁決說明那筆就夠，不另外再記一行', () {
      final s = _state();
      settleNight(s, NightActions(night: 1));

      final texts = _texts(s);
      expect(texts, contains('狼人空刀'));
      expect(texts.where((t) => t.contains('空刀')).length, 1);
    });

    test('雙刀集中同一人標示出來', () {
      final s = _state();
      final a = NightActions(night: 1)..wolfTarget = 9
        ..wolfSecondTarget = 9;
      settleNight(s, a);

      expect(_texts(s), contains('狼刀 9 號（兩刀集中）'));
    });

    test('裁決說明一併進日誌 —— 事後對得出為什麼沒死', () {
      final s = _state();
      final a = NightActions(night: 1)
        ..guardTarget = 9
        ..wolfTarget = 9
        ..witchHealTarget = 9;
      settleNight(s, a);

      expect(_texts(s), contains('9 號同守同救（奶穿），依規則仍然死亡'));
    });

    test('分到正確的夜次', () {
      final s = _state();
      final a = NightActions(night: 1)..wolfTarget = 9;
      settleNight(s, a);

      expect(s.log.sections.single.label, '第 1 夜');
      expect(s.log.entries.every((e) => e.isNight), isTrue);
    });
  });

  group('白天各環節寫進日誌', () {
    test('放逐記票型與結果', () {
      final s = _state()..sheriffSeat = 1;
      final v = ExileVote(state: s)..focusTarget(9);
      for (final voter in [1, 2, 3]) {
        v.toggleVote(voter);
      }
      v
        ..focusTarget(10)
        ..toggleVote(4);
      v.next();

      final texts = _texts(s);
      expect(
        texts.any((t) => t.contains('放逐投票票型：') && t.contains('9 號 3.5 票')),
        isTrue,
        reason: '警長那一票要算 1.5',
      );
      expect(texts.any((t) => t.contains('棄票')), isTrue);
      expect(texts, contains('9 號被放逐出局'));
    });

    test('警徽流記移交與撕毀', () {
      final s = _state()..sheriffSeat = 5;
      s.playerAt(5).alive = false;
      BadgeSuccession(state: s).passTo(9);

      expect(_texts(s), contains('5 號的警徽移交給 9 號，9 號成為新警長'));
      expect(s.log.entries.last.kind, LogKind.badge);
    });

    test('騎士決鬥記結果', () {
      final s = _state();
      KnightDuel(state: s).duel(2);

      final texts = _texts(s);
      expect(texts.any((t) => t.contains('是狼人，2 號出局')), isTrue);
      expect(texts, contains('決鬥出狼，白天就此結束，直接進入黑夜'));
      expect(s.log.entries.first.kind, LogKind.duel);
    });

    test('白天那幾筆記在白天，不是夜晚', () {
      final s = _state();
      KnightDuel(state: s).duel(2);

      expect(s.log.entries.every((e) => !e.isNight), isTrue);
      expect(s.log.sections.single.label, '第 1 天');
    });
  });

  group('整局串起來', () {
    test('夜晚與白天依序分段', () {
      final s = _state();
      const arb = NightArbitrator();
      final a = NightActions(night: 1)..wolfTarget = 9;
      arb.apply(s, a, arb.settle(s, a));

      // 白天推掉 10 號。
      final v = ExileVote(state: s)..focusTarget(10);
      for (final voter in [1, 2, 3, 4, 5]) {
        v.toggleVote(voter);
      }
      v.next();

      final labels = s.log.sections.map((x) => x.label).toList();
      expect(labels, ['第 1 夜', '第 1 天']);

      final text = s.log.toPlainText(title: '測試');
      expect(text, contains('【第 1 夜】'));
      expect(text, contains('【第 1 天】'));
    });
  });
}
