import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/engine/night_flow_machine.dart';
import 'package:wgm/core/engine/undo_stack.dart';
import 'package:wgm/core/models/game_state.dart';
import 'package:wgm/core/models/night_action.dart';
import 'package:wgm/core/models/player.dart';
import 'package:wgm/core/models/preset.dart';
import 'package:wgm/core/models/role.dart';

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

/// 身分已登記、已過首夜的局面。
GameState _seeded() {
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

NightFlowMachine _machine(GameState s) =>
    NightFlowMachine(state: s, night: 2, isFirstNight: false);

void main() {
  group('UndoStack', () {
    test('空堆疊不能撤銷', () {
      final stack = UndoStack();

      expect(stack.canUndo, isFalse);
      expect(stack.undo(), isNull);
      expect(stack.topLabel, isNull);
    });

    test('存的是動作發生之前的局面，之後怎麼改都不影響快照', () {
      final s = _seeded();
      final stack = UndoStack()..push(s, '守衛');

      s.playerAt(9).alive = false;
      s.witchPoisonAvailable = false;

      final snap = stack.undo()!;
      expect(snap.state.playerAt(9).alive, isTrue);
      expect(snap.state.witchPoisonAvailable, isTrue);
      expect(snap.label, '守衛');
    });

    test('後進先出，取完就不能再撤', () {
      final s = _seeded();
      final stack = UndoStack()
        ..push(s, '第一步')
        ..push(s, '第二步');

      expect(stack.depth, 2);
      expect(stack.topLabel, '第二步');
      expect(stack.undo()!.label, '第二步');
      expect(stack.undo()!.label, '第一步');
      expect(stack.canUndo, isFalse);
    });

    test('超過上限時丟掉最舊的', () {
      final s = _seeded();
      final stack = UndoStack(limit: 2);
      for (final label in ['a', 'b', 'c']) {
        stack.push(s, label);
      }

      expect(stack.depth, 2);
      expect(stack.undo()!.label, 'c');
      expect(stack.undo()!.label, 'b');
    });

    test('clear 丟棄全部', () {
      final s = _seeded();
      final stack = UndoStack()..push(s, 'a');
      stack.clear();

      expect(stack.canUndo, isFalse);
    });
  });

  group('GameState.restoreFrom', () {
    test('就地還原，不換物件 —— 既有參照仍然有效', () {
      final s = _seeded();
      final snapshot = s.copy();
      final playerRef = s.playerAt(9);

      s.playerAt(9).alive = false;
      s.restoreFrom(snapshot);

      expect(playerRef.alive, isTrue, reason: '同一個 Player 物件被就地覆寫');
      expect(identical(s.playerAt(9), playerRef), isTrue);
    });

    test('每個可變欄位都會被還原', () {
      final s = _seeded();
      final snapshot = s.copy();

      s
        ..dayNumber = 5
        ..phase = GamePhase.day
        ..sheriffSeat = 3
        ..witchAntidoteAvailable = false
        ..witchPoisonAvailable = false
        ..lastGuardTarget = 9
        ..charmedSeat = 10
        ..lastCharmTarget = 10
        ..mechanicWolfLearnedRole = Roles.guard
        ..mechanicWolfLearnedNight = 2
        ..mechanicPoisonAvailable = false
        ..lastMechanicGuardTarget = 11
        ..mechanicCharmedSeat = 12
        ..lastMechanicCharmTarget = 12;
      s.playerAt(9)
        ..alive = false
        ..canVote = false
        ..role = Roles.idiot;
      s.playerAt(9).nightFacts.add(FactTag.knifed);
      s.playerAt(9).infoTags.add(InfoTag.verifiedWolf);

      s.restoreFrom(snapshot);

      expect(s.dayNumber, 1);
      expect(s.phase, GamePhase.setup);
      expect(s.sheriffSeat, isNull);
      expect(s.witchAntidoteAvailable, isTrue);
      expect(s.witchPoisonAvailable, isTrue);
      expect(s.lastGuardTarget, isNull);
      expect(s.charmedSeat, isNull);
      expect(s.lastCharmTarget, isNull);
      expect(s.mechanicWolfLearnedRole, isNull);
      expect(s.mechanicWolfLearnedNight, isNull);
      expect(s.mechanicPoisonAvailable, isTrue);
      expect(s.lastMechanicGuardTarget, isNull);
      expect(s.mechanicCharmedSeat, isNull);
      expect(s.lastMechanicCharmTarget, isNull);
      expect(s.playerAt(9).alive, isTrue);
      expect(s.playerAt(9).canVote, isTrue);
      expect(s.playerAt(9).role?.id, Roles.villager.id);
      expect(s.playerAt(9).nightFacts, isEmpty);
      expect(s.playerAt(9).infoTags, isEmpty);
    });

    // 上一項是從空快照還原，只驗得到 restoreFrom —— copy() 漏掉的欄位
    // 在快照裡剛好也是預設值，照樣會過。這一項反過來：先填非預設值再存快照，
    // copy() 漏掉哪一個，還原後就會掉回預設值。
    test('copy() 保留每個欄位的非預設值', () {
      final s = _seeded()
        ..dayNumber = 4
        ..phase = GamePhase.day
        ..sheriffSeat = 3
        ..witchAntidoteAvailable = false
        ..witchPoisonAvailable = false
        ..lastGuardTarget = 9
        ..charmedSeat = 10
        ..lastCharmTarget = 10
        ..mechanicWolfLearnedRole = Roles.guard
        ..mechanicWolfLearnedNight = 2
        ..mechanicPoisonAvailable = false
        ..lastMechanicGuardTarget = 11
        ..mechanicCharmedSeat = 12
        ..lastMechanicCharmTarget = 12
        ..knightDuelUsed = true
        ..conversionNight = 1
        ..whiteCatPendingCause = DeathCause.wolfKill
        ..whiteCatDeathDueAfterDay = 5
        ..lastDreamTarget = 7
        ..mechanicWhiteCatPendingCause = DeathCause.poison
        ..mechanicWhiteCatDueAfterDay = 6
        ..lastMechanicDreamTarget = 8
        ..secretAdmirerTarget = 5
        ..secretAdmirerCamp = Camp.wolf;
      s.convertedSeats.add(5);
      s.convertedActivatedSeats.add(5);

      final snapshot = s.copy();

      s
        ..dayNumber = 1
        ..phase = GamePhase.setup
        ..sheriffSeat = null
        ..witchAntidoteAvailable = true
        ..witchPoisonAvailable = true
        ..lastGuardTarget = null
        ..charmedSeat = null
        ..lastCharmTarget = null
        ..mechanicWolfLearnedRole = null
        ..mechanicWolfLearnedNight = null
        ..mechanicPoisonAvailable = true
        ..lastMechanicGuardTarget = null
        ..mechanicCharmedSeat = null
        ..lastMechanicCharmTarget = null
        ..knightDuelUsed = false
        ..conversionNight = null
        ..whiteCatPendingCause = null
        ..whiteCatDeathDueAfterDay = null
        ..lastDreamTarget = null
        ..mechanicWhiteCatPendingCause = null
        ..mechanicWhiteCatDueAfterDay = null
        ..lastMechanicDreamTarget = null
        ..secretAdmirerTarget = null
        ..secretAdmirerCamp = null;
      s.convertedSeats.clear();
      s.convertedActivatedSeats.clear();

      s.restoreFrom(snapshot);

      expect(s.dayNumber, 4);
      expect(s.phase, GamePhase.day);
      expect(s.sheriffSeat, 3);
      expect(s.witchAntidoteAvailable, isFalse);
      expect(s.witchPoisonAvailable, isFalse);
      expect(s.lastGuardTarget, 9);
      expect(s.charmedSeat, 10);
      expect(s.lastCharmTarget, 10);
      expect(s.mechanicWolfLearnedRole, Roles.guard);
      expect(s.mechanicWolfLearnedNight, 2);
      expect(s.mechanicPoisonAvailable, isFalse);
      expect(s.lastMechanicGuardTarget, 11);
      expect(s.mechanicCharmedSeat, 12);
      expect(s.lastMechanicCharmTarget, 12);
      expect(s.knightDuelUsed, isTrue);
      expect(s.conversionNight, 1);
      expect(s.whiteCatPendingCause, DeathCause.wolfKill);
      expect(s.whiteCatDeathDueAfterDay, 5);
      expect(s.lastDreamTarget, 7);
      expect(s.mechanicWhiteCatPendingCause, DeathCause.poison);
      expect(s.mechanicWhiteCatDueAfterDay, 6);
      expect(s.lastMechanicDreamTarget, 8);
      expect(s.secretAdmirerTarget, 5);
      expect(s.secretAdmirerCamp, Camp.wolf);
      expect(s.convertedSeats, {5});
      expect(s.convertedActivatedSeats, {5});
    });

    test('快照裡的集合與現況互不影響', () {
      final s = _seeded();
      s.convertedSeats.add(5);
      final snapshot = s.copy();

      s.convertedSeats.add(6);

      expect(snapshot.convertedSeats, {5}, reason: '改現況不能連快照一起改');
    });
  });

  // 規則要守在引擎裡 —— UI 的座位格雖然也會擋，但不能只靠它，
  // 否則換一個呼叫端（模擬、匯入存檔）就繞過去了。
  group('引擎層的選取限制', () {
    test('藥用完了就選不動 —— 不能只靠 UI 擋', () {
      final s = _seeded()..witchPoisonAvailable = false;
      final m = _machine(s);

      m.toggleSeat(9);
      m.next(); // 守衛
      m.toggleSeat(10);
      m.next(); // 狼刀 → 女巫

      expect(m.sub, NightSub.witchPotion);
      m.toggleSeat(11);
      expect(m.picked, isEmpty, reason: '毒藥已用掉，點不動');

      m.next();
      expect(m.actions.witchPoisonTarget, isNull);
    });

    test('死人選不動', () {
      final s = _seeded();
      s.playerAt(10).alive = false;
      final m = _machine(s);

      m.toggleSeat(10);
      expect(m.picked, isEmpty);

      m.toggleSeat(11);
      expect(m.picked, {11});
    });

    test('昨晚守過的人選不動', () {
      final s = _seeded()..lastGuardTarget = 9;
      final m = _machine(s);

      m.toggleSeat(9);
      expect(m.picked, isEmpty, reason: '不可連守同一人');

      m.toggleSeat(10);
      expect(m.picked, {10});
    });

    test('手勢與走過場的步驟不能選任何人', () {
      final s = _seeded();
      final m = _machine(s);

      m.toggleSeat(9);
      m.next(); // 守衛
      m.toggleSeat(10);
      m.next(); // 狼刀
      m.next(); // 女巫（解藥＋毒藥同一頁）
      m.toggleSeat(1);
      m.next(); // 預言家查 1 → 查驗結果
      expect(m.sub, NightSub.inspectResult, reason: '結果要當場比給預言家看');
      expect(m.requiredPickCount, 0);
      m.toggleSeat(9);
      expect(m.picked, isEmpty, reason: '結果那一頁不能選人');
      m.next(); // 查驗結果 → 獵人手勢

      expect(m.sub, NightSub.hunterGesture);
      expect(m.requiredPickCount, 0);
      m.toggleSeat(9);
      expect(m.picked, isEmpty);
    });
  });

  group('夜晚流程的撤銷', () {
    test('剛進入時沒有東西可撤', () {
      expect(_machine(_seeded()).canUndo, isFalse);
    });

    test('撤銷會退回上一步，收到的行動意圖一併退掉', () {
      final m = _machine(_seeded());

      // 守衛守 9 號。
      expect(m.step.title, '守衛');
      m.toggleSeat(9);
      m.next();

      expect(m.step.title, '狼人');
      expect(m.actions.guardTarget, 9);

      expect(m.undo(), isTrue);
      expect(m.step.title, '守衛', reason: '退回守衛那一步');
      expect(m.actions.guardTarget, isNull, reason: '守護意圖一併退掉');
      expect(m.picked, {9}, reason: '連當時選好的座次都還在，法官可以直接改');
    });

    test('連續撤銷可以一路退回開頭', () {
      final m = _machine(_seeded());

      m.toggleSeat(9);
      m.next(); // 守衛
      m.toggleSeat(10);
      m.next(); // 狼刀

      expect(m.step.title, '女巫');
      expect(m.undo(), isTrue);
      expect(m.step.title, '狼人');
      expect(m.undo(), isTrue);
      expect(m.step.title, '守衛');
      expect(m.canUndo, isFalse);
      expect(m.undo(), isFalse);
    });

    test('撤銷會還原局面 —— 已結算的死亡要活回來', () {
      final m = _machine(_seeded());

      m.toggleSeat(9);
      m.next(); // 守衛守 9
      m.toggleSeat(10);
      m.next(); // 狼刀 10
      m.next(); // 女巫兩瓶藥都不用
      m.toggleSeat(1);
      m.next(); // 預言家查 1
      m.next(); // 查驗結果比給預言家看
      m.next(); // 獵人手勢 → 結算

      expect(m.finished, isTrue);
      expect(m.state.playerAt(10).alive, isFalse);
      expect(m.state.lastGuardTarget, 9);

      expect(m.undo(), isTrue);
      expect(m.finished, isFalse, reason: '退回夜晚中途，不再是已結算狀態');
      expect(m.state.playerAt(10).alive, isTrue, reason: '死亡被還原');
      expect(m.state.lastGuardTarget, isNull, reason: '守護紀錄也被還原');
    });

    test('撤銷首夜的身分登記', () {
      final s = GameState(preset: _preset())..dayNumber = 1;
      final m = NightFlowMachine(state: s, night: 1, isFirstNight: true);

      expect(m.sub, NightSub.registerSeats);
      m.toggleSeat(8);
      m.next();

      expect(s.playerAt(8).role?.id, Roles.guard.id);
      expect(m.sub, NightSub.chooseTarget);

      expect(m.undo(), isTrue);
      expect(s.playerAt(8).role, isNull, reason: '登記的身分要退掉');
      expect(m.sub, NightSub.registerSeats);
    });

    test('撤銷後重做，結果跟沒撤過一樣', () {
      final m = _machine(_seeded());

      m.toggleSeat(9);
      m.next();
      m.undo();

      // 改守 11 號。
      m.toggleSeat(11);
      m.next();

      expect(m.actions.guardTarget, 11);
      expect(m.step.title, '狼人');
    });
  });
}
