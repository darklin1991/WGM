import '../models/game_state.dart';

/// 座次不可選的原因。
///
/// 只回傳原因本身，顯示文字由 UI 決定 —— 引擎不碰呈現。
/// 夜晚與白天共用同一份：`NightFlowMachine.blockedSeats`、
/// `ExileVote.shootBlockedSeats`、`NightDeathShot.blockedSeats`、
/// `KnightDuel.blockedSeats`。
enum SeatBlockReason {
  /// 守衛昨晚守過這位（不可連守同一人）。
  guardedLastNight,

  /// 狼美人昨晚魅惑過這位（不可連續兩晚魅惑同一人）。
  charmedLastNight,

  /// 狼美人不能被自刀。
  wolfBeautySelfKill,

  /// 機械狼不能學自己。
  mechanicSelfLearn,

  /// 暗戀者不能暗戀自己。
  secretAdmirerSelf,

  /// 白貓已翻牌、正在延後離場中 —— 這段期間禁止成為技能目標。
  whiteCatPending,

  /// 覺醒石像鬼不能轉換另一隻石像鬼（兩隻互認）。
  ///
  /// 只擋石像鬼，**不擋機械狼** —— 石像鬼不認得機械狼，擋了會洩漏
  /// （擔當 2026-09-25 指定）。
  convertGargoyle,

  /// 另一隻石像鬼已經轉換了這位 —— 一定轉換兩位，不會撞車（擔當 2026-09-25 指定）。
  alreadyConverted,

  /// 本局不可同夜雙藥。
  witchDualUse,

  /// 騎士不能跟自己決鬥。
  duelSelf,
}

/// 延後離場中的白貓（含學到白貓的機械狼）—— **夜晚與白天都**不能被選。
///
/// 打中的話 `deferWhiteCatDeath` 不會再延一次，他會當場死亡、跳過延後，
/// 所以乾脆選不到他。夜晚的狀態機與白天的三個引擎都從這裡取，
/// 規則只有這一份。
Map<int, SeatBlockReason> pendingCatBlocks(GameState state) => {
      for (final p in state.alivePlayers)
        if (state.isWhiteCatPending(p.seat))
          p.seat: SeatBlockReason.whiteCatPending,
    };

/// 白天的開槍（獵人、狼王）與騎士決鬥不能選的座次。
///
/// 目前只有延後中的白貓（擔當 2026-09-24 指定，見 [pendingCatBlocks]）。
/// 三個白天的引擎都從這裡取，日後白天多一條規則只改這裡。
Map<int, SeatBlockReason> dayBlockedSeats(GameState state) =>
    pendingCatBlocks(state);
