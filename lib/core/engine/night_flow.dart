import '../models/game_state.dart';
import '../models/preset.dart';
import '../models/role.dart';

/// 一個夜間步驟要收集什麼技能目標。
enum NightSkill {
  /// 守衛守護。
  guardProtect,

  /// 狼刀。
  wolfKill,

  /// 女巫用藥（解藥／毒藥）。
  witchPotion,

  /// 預言家查驗（只看好人／狼人）。
  seerInspect,

  /// 通靈師查驗（看到的是**真實身分**）。
  psychicInspect,

  /// 狼美人魅惑。狼美人出局時，被魅惑者殉情。
  charm,

  /// 機械狼學習一名玩家的身分技能（整局限一次，隔夜起生效）。
  mechanicLearn,

  /// 攝夢人指定夢遊者。夢遊者免疫夜間傷害，連續兩晚被攝會夢死。
  dreamWeave,

  /// 覺醒石像鬼轉換相鄰座次的一位玩家。**只有首夜**。
  ///
  /// 兩隻石像鬼各選一次，所以這一步會逐隻問過去。
  gargoyleConvert,

  /// 熊：法官看兩側鄰座有沒有狼，給「咆哮／不咆哮」。
  ///
  /// 與 [hunterGesture] 同型 —— 沒有目標要選，只是把一則資訊比給他看。
  /// **每晚都有**：鄰座會因為死亡而往外順延，答案每晚都可能不同。
  bearGrowl,

  /// 暗戀者指定暗戀對象。**只有首夜**，之後不再叫起來。
  ///
  /// 勝負跟著對象**當下**的陣營走，選完就固定 —— 對象之後被轉換成狼
  /// 也不改，見 `GameState.secretAdmirerCamp`。
  secretAdmire,

  /// 機械狼在夜晚開頭的那一輪，**每晚都有**。依序是：
  ///
  /// 1. 開刀手勢 —— 機械狼不與小狼相認，自己不知道小狼死光了沒，
  ///    要由法官比手勢告知今晚有沒有刀
  /// 2. 有刀的話選刀口（學到狼人時再多問一刀）
  /// 3. 是否使用技能（還沒學就是學習，學過就是施放學到的技能）
  ///
  /// 實際要收哪個技能看 [NightStep.mechanicSubSkill]。
  mechanicTurn,

  /// 機械狼在**夜晚結尾**再睜一次眼：法官告知牠學到的身分，
  /// 並給「可否開槍」的手勢（學到槍牌時）。
  ///
  /// 一定要排在最後：機械狼是第一個睜眼的，那時候身分都還沒登記完，
  /// 法官根本無從告知學到了什麼；毒藥也還沒收，手勢同樣給不出來。
  mechanicReveal,

  /// 獵人：**每晚**都要叫起來，由法官給「可否開槍」的手勢。
  ///
  /// 獵人本身沒有夜間行動，但需要知道自己的技能狀態（被毒就不能開槍），
  /// 所以每晚都得睜眼看法官手勢。
  hunterGesture,

  /// 首夜的最後，法官逐一叫醒被轉換者告知（擔當 2026-09-22 指定：
  /// 「第一位轉換者請睜眼」）。**只有首夜**，只在有覺醒石像鬼的板子。
  ///
  /// 兩隻石像鬼一定各轉換一位、不會撞車（擔當 2026-09-25 指定），所以固定叫
  /// 兩次。某隻選到機械狼（轉換悄悄白費）時那一格沒有人 —— 照樣喊，
  /// 少喊一次玩家從流程長度就聽得出來（同「角色全滅照樣走過場」）。
  convertedNotify,

  /// 第二夜起，法官逐一叫醒被轉換者，比**開刀手勢**（擔當 2026-09-25 指定）。
  ///
  /// 被轉換者不與任何人相認，自己不知道石像鬼與機械狼死光了沒 —— 有沒有刀
  /// 只有法官知道，所以每晚都要比（同機械狼的開刀手勢）。有刀的那一位就在
  /// 這一輪選刀口，狼隊那一格改走過場。
  ///
  /// 排在狼隊步驟**之前**（一般板子守衛的位置；風聲諜影沒有守衛，就是攝夢人
  /// 之後）。叫的次數固定是石像鬼的數量，理由同 [convertedNotify]。
  convertedTurn,

  /// 無夜間行動，只在首夜登記座次（白痴、騎士等）。
  none,
}

/// 機械狼學到的技能什麼時候開始算，見 [NightFlow.mechanicSkillTimingOf]。
enum MechanicSkillTiming {
  /// 夜間技能：學習當晚不生效，隔夜起才用得到。
  nextNight,

  /// 出局時才觸發的被動技能（槍、河豚、白貓）：學到就生效。
  immediate,

  /// 沒有技能，只套用身分偽裝。
  none,
}

/// 首夜的一個步驟。
///
/// [seatCount] 是這一步**最多**要登記幾個座次，不代表一定會問。
/// 擔當 2026-09-19 決定身分一律在開局前的登記頁配完，所以實際跑局時
/// 座次早就知道了，`NightFlowMachine.needsRegistration()` 會跳過登記，
/// 直接進技能。
///
/// 步驟本身仍帶著登記資訊，是因為引擎另外支援「夜裡邊問邊登記」
/// （「守衛請睜眼，你是幾號」→「你要守誰」）—— 那條路目前介面沒有入口，
/// 但單元測試還在跑它。
class NightStep {
  const NightStep({
    required this.title,
    required this.roles,
    required this.seatCount,
    required this.skill,
    this.primaryRole,
    this.specialPicks = const <Role>[],
    this.byMechanicWolf = false,
    this.mechanicSubSkill = NightSkill.none,
  });

  /// [NightSkill.mechanicTurn] 專用：這一輪除了開刀手勢之外，還要收哪個技能。
  ///
  /// [NightSkill.none] 表示今晚沒有技能可用（學到平民、或學了還沒生效），
  /// 這時仍要叫機械狼睜眼給開刀手勢，只是技能那段直接跳過。
  final NightSkill mechanicSubSkill;

  /// 步驟標題，例如「守衛」、「狼人」。
  final String title;

  /// 本步驟要登記的角色。狼隊（一般狼、狼王、狼美人）合併成一步 ——
  /// 現場「狼人請睜眼」是一次性動作，狼隊同時互相識別。
  ///
  /// **機械狼不在狼隊步驟裡** —— 牠不與小狼相認，必須單獨睜眼。
  final List<Role> roles;

  /// 本步驟要登記幾個座次。
  final int seatCount;

  final NightSkill skill;

  /// 技能歸屬的角色；狼隊步驟為 [Roles.wolf]。
  final Role? primaryRole;

  /// 狼隊登記完後，還要再單獨指認的特殊成員（狼王、狼美人）。
  ///
  /// 這些角色死亡時有額外效果（開槍、殉情），法官必須知道是哪一位。
  final List<Role> specialPicks;

  /// 此步驟由機械狼用**學來的**技能行動 —— 目標要記到機械狼自己的欄位，
  /// 不能和原角色共用（兩者的藥量、守護紀錄各自獨立）。
  final bool byMechanicWolf;

  /// 本步驟是否需要在登記後額外指定特殊成員。
  bool get needsSpecialPick => specialPicks.isNotEmpty;

  /// 本步驟是否需要指定狼王。
  bool get needsWolfKingPick =>
      specialPicks.any((r) => r.id == Roles.wolfKing.id);

  /// 狼隊步驟中，狼王要指定幾位。
  int get wolfKingCount => needsWolfKingPick ? 1 : 0;
}

/// 依板子產生夜晚的步驟序列。
///
/// 規則：
/// 1. 先走板子的 `nightOrder`（有主動夜間行動的角色）
/// 2. 一般狼、狼王、狼美人合併為一個「狼隊」步驟，之後再指認特殊成員
/// 3. 狼美人在狼隊決定刀口後，單獨睜眼魅惑
/// 4. 機械狼單獨睜眼（不與小狼相認）
/// 5. 再補上尚未登記、且有夜間技能以外身分的非平民角色（獵人、白痴、騎士）
/// 6. 平民不列入步驟 —— 完成所有特殊身分後，剩下的座次自動是平民
abstract final class NightFlow {
  static List<NightStep> firstNightSteps(Preset preset) {
    final steps = <NightStep>[];
    final covered = <String>{};

    int countOf(String roleId) => preset.roles
        .where((s) => s.role.id == roleId)
        .fold<int>(0, (sum, s) => sum + s.count);

    void addWolfTeamStep() {
      final teamRoles = <Role>[];
      final specials = <Role>[];
      var seatCount = 0;
      for (final id in Roles.wolfTeamIds) {
        final c = countOf(id);
        if (c == 0) continue;
        final role = Roles.byId(id)!;
        teamRoles.add(role);
        seatCount += c;
        covered.add(id);
        // 狼王與狼美人死亡時有額外效果，登記完必須再指認是哪一位。
        if (id != Roles.wolf.id) specials.add(role);
      }
      if (teamRoles.isEmpty) return;

      // 整個狼隊只有一種身分時不必指認 —— 沒有別的身分要分辨。
      // 風聲諜影的狼隊就是兩隻覺醒石像鬼，問「哪一位是石像鬼」毫無意義。
      if (teamRoles.length == 1) specials.clear();

      // 沒有一般狼時，喊的與記的都用那個實際身分（例如覺醒石像鬼），
      // 否則畫面會出現不存在的「狼人」。
      final primary = teamRoles.length == 1 ? teamRoles.first : Roles.wolf;

      steps.add(
        NightStep(
          title: primary.nameZh,
          roles: teamRoles,
          seatCount: seatCount,
          skill: NightSkill.wolfKill,
          primaryRole: primary,
          specialPicks: specials,
        ),
      );

      // 覺醒石像鬼在決定刀口之後，**首夜**各自轉換一位相鄰座次
      // （座次已於狼隊步驟登記完）。要排在熊之前，熊首夜才咆哮得出來。
      if (countOf(Roles.awakenedGargoyle.id) > 0) {
        steps.add(
          const NightStep(
            title: '覺醒石像鬼',
            roles: [Roles.awakenedGargoyle],
            seatCount: 0,
            skill: NightSkill.gargoyleConvert,
            primaryRole: Roles.awakenedGargoyle,
          ),
        );
      }

      // 狼美人在狼隊決定刀口之後，單獨睜眼魅惑（座次已於狼隊步驟登記完）。
      if (countOf(Roles.wolfBeauty.id) > 0) {
        steps.add(
          const NightStep(
            title: '狼美人',
            roles: [Roles.wolfBeauty],
            seatCount: 0,
            skill: NightSkill.charm,
            primaryRole: Roles.wolfBeauty,
          ),
        );
      }
    }

    for (final role in preset.nightOrder) {
      if (covered.contains(role.id)) continue;

      if (Roles.wolfTeamIds.contains(role.id)) {
        addWolfTeamStep();
        continue;
      }

      covered.add(role.id);
      steps.add(
        NightStep(
          title: role.nameZh,
          roles: [role],
          seatCount: countOf(role.id),
          skill: skillOf(role),
          primaryRole: role,
          byMechanicWolf: role.id == Roles.mechanicWolf.id,
          mechanicSubSkill: role.id == Roles.mechanicWolf.id
              ? NightSkill.mechanicLearn
              : NightSkill.none,
        ),
      );
    }

    // 補上不在 nightOrder、但仍需叫起來的角色（獵人、白痴、騎士等）。
    // 獵人排在最後有其必要：法官必須先收完女巫的毒藥，才知道該給
    // 「可開槍」還是「不可開槍」的手勢。
    for (final slot in preset.roles) {
      final role = slot.role;
      if (covered.contains(role.id)) continue;
      if (role.kind == RoleKind.villager) continue; // 平民最後自動填入
      covered.add(role.id);
      steps.add(
        NightStep(
          title: role.nameZh,
          roles: [role],
          seatCount: countOf(role.id),
          skill: skillOf(role),
          primaryRole: role,
        ),
      );
    }

    // 機械狼在夜晚結尾再睜一次眼（見 [NightSkill.mechanicReveal]）。
    if (preset.roles.any((s) => s.role.id == Roles.mechanicWolf.id)) {
      steps.add(_revealStep);
    }

    // 被轉換者要等轉換發生才叫得起來，排在整夜的最後
    //（見 [NightSkill.convertedNotify]）。放在機械狼結尾那一輪之後也不影響
    // 牠的理由 —— 那一輪要的是「身分登記完、毒收完」，這裡照樣成立。
    if (preset.roles.any((s) => s.role.id == Roles.awakenedGargoyle.id)) {
      steps.add(_convertedNotifyStep);
    }

    return steps;
  }

  /// 這一步的角色是不是**已經接刀因而喪失技能**的被轉換者。
  ///
  /// 被轉換者保有原技能一直用到接刀那一刻（擔當 2026-09-22 指定），
  /// 所以不能一被轉換就把他的步驟拿掉 —— 只有真的接了刀才失效。
  ///
  /// 多人角色（一般狼、平民）不套用：那些身分不會單獨對應一個人。
  static bool _lostSkillsStep(GameState state, NightStep step) {
    final role = step.primaryRole;
    if (role == null || role.allowsMultiple) return false;
    final seat = state.seatOfRole(role.id);
    return seat != null && state.losesSkillsTonight(seat);
  }

  static const _revealStep = NightStep(
    title: '機械狼',
    roles: [Roles.mechanicWolf],
    seatCount: 0,
    skill: NightSkill.mechanicReveal,
    primaryRole: Roles.mechanicWolf,
    byMechanicWolf: true,
  );

  static const _convertedNotifyStep = NightStep(
    title: '轉換者',
    roles: [],
    seatCount: 0,
    skill: NightSkill.convertedNotify,
  );

  static const _convertedTurnStep = NightStep(
    title: '轉換者',
    roles: [],
    seatCount: 0,
    skill: NightSkill.convertedTurn,
  );

  /// 第二夜起的步驟：身分已登記，只收集技能目標，不再填座次。
  ///
  /// 獵人雖然沒有夜間行動，但每晚都要叫起來確認開槍手勢，所以保留；
  /// 白痴、騎士這類純登記的角色首夜登記完就不再出現。
  ///
  /// 這個版本只看板子，不套用機械狼的執行期狀態 —— 實際跑局請用
  /// [laterNightStepsFor]。
  static List<NightStep> laterNightSteps(Preset preset) => [
        for (final step in firstNightSteps(preset))
          if (step.skill != NightSkill.none &&
              step.skill != NightSkill.convertedNotify)
            NightStep(
              title: step.title,
              roles: step.roles,
              seatCount: 0,
              skill: step.skill,
              primaryRole: step.primaryRole,
              byMechanicWolf: step.byMechanicWolf,
            ),
      ];

  /// 第二夜起的步驟，並套用機械狼的執行期狀態：
  ///
  /// - 還沒學過 → 維持「學習」步驟
  /// - 學了但還沒到隔夜 → 這晚沒事做，不叫起來
  /// - 技能已生效 → 換成學到的技能（目標記在機械狼自己的欄位）
  /// - 其餘小狼全數出局 → 狼隊步驟改由機械狼帶刀
  static List<NightStep> laterNightStepsFor(
    GameState state, {
    required int night,
  }) {
    final steps = <NightStep>[];

    for (final step in firstNightSteps(state.preset)) {
      if (step.skill == NightSkill.none) continue;

      // 暗戀者只有首夜選對象，之後整局不再叫起來。
      if (step.skill == NightSkill.secretAdmire) continue;

      // 轉換只有首夜，第二夜起石像鬼就只剩開刀。
      if (step.skill == NightSkill.gargoyleConvert) continue;

      // 告知被轉換者也只有首夜。
      if (step.skill == NightSkill.convertedNotify) continue;

      // 轉換者的開刀手勢排在狼隊之前 —— 有刀的那一位要在那裡開刀。
      if (step.skill == NightSkill.wolfKill &&
          state.preset.roles
              .any((s) => s.role.id == Roles.awakenedGargoyle.id)) {
        steps.add(_convertedTurnStep);
      }

      // 被轉換者接刀之後**喪失原技能** —— 他原本那一步就沒有東西可收了。
      // 接刀的**那一夜**就算（見 `GameState.losesSkillsTonight`）。
      // 仍然保留成走過場：跳掉會讓玩家從流程長度聽出事情有變。
      if (_lostSkillsStep(state, step)) {
        steps.add(
          NightStep(
            title: step.title,
            roles: step.roles,
            seatCount: 0,
            skill: NightSkill.none,
            primaryRole: step.primaryRole,
          ),
        );
        continue;
      }

      // 小狼全滅時狼隊那一步會被自動跳過（角色全死），刀改由機械狼在
      // 自己那一輪開 —— 見 [NightSkill.mechanicTurn]。

      if (step.skill == NightSkill.mechanicTurn) {
        steps.add(_mechanicStepFor(state, night: night));
        continue;
      }

      // 結尾的告知步驟：還沒學過（今晚可能會學）或持有槍牌（每晚要給手勢）
      // 才需要；已經學到守衛之類的沒槍角色就不必再叫起來。
      if (step.skill == NightSkill.mechanicReveal) {
        final learned = state.mechanicWolfLearnedRole;
        final needsReveal =
            learned == null || Roles.gunRoleIds.contains(learned.id);
        if (needsReveal) steps.add(step);
        continue;
      }

      steps.add(
        NightStep(
          title: step.title,
          roles: step.roles,
          seatCount: 0,
          skill: step.skill,
          primaryRole: step.primaryRole,
        ),
      );
    }

    return steps;
  }

  /// 機械狼在第 [night] 夜開頭的那一輪。
  ///
  /// **每晚都有** —— 就算沒技能可用，也要叫起來給開刀手勢，
  /// 否則機械狼無從得知小狼是不是死光了、自己有沒有刀。
  static NightStep _mechanicStepFor(GameState state, {required int night}) {
    final learned = state.mechanicWolfLearnedRole;

    final sub = switch (learned) {
      // 還沒學過 —— 任一晚都可以學。
      null => NightSkill.mechanicLearn,
      // 學習當晚不生效，隔夜起才取得技能。
      _ when !state.mechanicSkillActiveOn(night) => NightSkill.none,
      _ => mechanicSkillOf(learned),
    };

    return NightStep(
      title: sub == NightSkill.none || learned == null
          ? '機械狼'
          : '機械狼（${learned.nameZh}）',
      roles: const [Roles.mechanicWolf],
      seatCount: 0,
      skill: NightSkill.mechanicTurn,
      mechanicSubSkill: sub,
      primaryRole: Roles.mechanicWolf,
      byMechanicWolf: true,
    );
  }

  /// 機械狼學到 [learned] 之後，每晚要做什麼。
  ///
  /// - 學到**狼人**在這一格沒事做 —— 多的那一刀要等機械狼真的帶刀（小狼全滅）
  ///   才砍得到，屆時併在「機械狼（帶刀）」那一步收兩刀
  ///   （見 [GameState.mechanicHasExtraKnifeOn]）
  /// - 學到**槍牌**（獵人、狼王）在這一格也沒事做 —— 開槍手勢改在夜晚結尾的
  ///   [NightSkill.mechanicReveal] 給，因為那時候才收完女巫的毒
  /// - 學到**熊**看的是機械狼自己的鄰座；學到**攝夢人**有自己的夢遊者與
  ///   「上一晚」紀錄（擔當 2026-09-25 指定，風聲諜影）
  /// - 學到**河豚、白貓**在這一格也沒事做 —— 那是出局時才觸發的被動技能
  /// - 學到平民、白痴、騎士、機械狼、**暗戀者、覺醒石像鬼**沒有技能，
  ///   只套用身分偽裝（擔當 2026-09-25 指定後兩者）
  static NightSkill mechanicSkillOf(Role learned) => switch (learned.id) {
        'guard' => NightSkill.guardProtect,
        'witch' => NightSkill.witchPotion,
        'seer' => NightSkill.seerInspect,
        'psychic' => NightSkill.psychicInspect,
        'wolfBeauty' => NightSkill.charm,
        'bear' => NightSkill.bearGrowl,
        'dreamWeaver' => NightSkill.dreamWeave,
        _ => NightSkill.none,
      };

  /// 機械狼學到 [learned] 之後，技能什麼時候開始算。
  ///
  /// - 夜間技能（含學到狼人的第二刀）**隔夜生效**
  /// - 出局時才觸發的被動技能（槍、河豚、白貓）**學到就生效**
  ///   —— 擔當 2026-09-24 指定槍如此，河豚與白貓比照
  /// - 其餘沒有技能，只套用身分偽裝
  static MechanicSkillTiming mechanicSkillTimingOf(Role learned) {
    if (Roles.mechanicPassiveIds.contains(learned.id)) {
      return MechanicSkillTiming.immediate;
    }
    if (mechanicSkillOf(learned) != NightSkill.none ||
        learned.id == Roles.wolf.id) {
      return MechanicSkillTiming.nextNight;
    }
    return MechanicSkillTiming.none;
  }

  static NightSkill skillOf(Role role) => switch (role.id) {
        'guard' => NightSkill.guardProtect,
        'wolf' || 'wolfKing' => NightSkill.wolfKill,
        'wolfBeauty' => NightSkill.charm,
        'mechanicWolf' => NightSkill.mechanicTurn,
        'witch' => NightSkill.witchPotion,
        'seer' => NightSkill.seerInspect,
        'psychic' => NightSkill.psychicInspect,
        'hunter' => NightSkill.hunterGesture,
        'bear' => NightSkill.bearGrowl,
        'dreamWeaver' => NightSkill.dreamWeave,
        'secretAdmirer' => NightSkill.secretAdmire,
        _ => NightSkill.none,
      };
}
