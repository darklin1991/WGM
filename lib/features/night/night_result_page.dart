import 'package:flutter/material.dart';

import '../../core/engine/badge_succession.dart';
import '../../core/engine/speech_timer.dart';
import '../../core/engine/win_checker.dart';
import '../../core/models/game_state.dart';
import '../../core/models/night_action.dart';
import '../../core/models/role.dart';
import '../../shared/theme.dart';
import '../day/badge_succession_page.dart';
import '../day/night_death_shot_page.dart';
import '../day/speech_order_page.dart';
import '../day/speech_timer_page.dart';
import '../review/game_over_page.dart';
import '../review/review_log_button.dart';
import 'night_flow_page.dart';

/// 夜晚結算結果。
///
/// 除了死亡名單，也把裁決說明一併列出 —— 現場如果有爭議
/// （為什麼同守同救還是死了），法官要能立刻說明依據。
class NightResultPage extends StatelessWidget {
  const NightResultPage({
    super.key,
    required this.state,
    required this.outcome,
    this.autoFilledVillagers = const [],
  });

  final GameState state;
  final NightOutcome outcome;

  /// 首夜自動填為平民的座次。
  final List<int> autoFilledVillagers;

  WinCheck get _win => WinChecker.check(state);

  static const _catDeferred = '（翻牌，今天的放逐投票結束才離場）';

  /// 可以給遺言的人 —— 延後離場的白貓還在場上，今天照常發言，不算。
  List<int> get _lastWordsSeats => [
        for (final seat in outcome.deadSeats)
          if (!outcome.whiteCatDeferredSeats.contains(seat)) seat,
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${state.dayNumber} 夜　結算'),
        actions: [ReviewLogButton(state: state)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- 天亮了 ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '天亮了',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (outcome.isPeacefulNight)
                    const Text(
                      '昨晚是平安夜',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  else
                    Text(
                      '昨晚死亡：${outcome.deadSeats.join('、')} 號',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: WgmTheme.wolfColor,
                      ),
                    ),
                  if (!outcome.isPeacefulNight) ...[
                    const SizedBox(height: 10),
                    for (final d in outcome.deaths)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${d.seat} 號 · '
                          '${state.playerAt(d.seat).role?.nameZh ?? "未知"} · '
                          '${d.cause.labelZh}'
                          '${outcome.whiteCatDeferredSeats.contains(d.seat) ? _catDeferred : ""}',
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ---- 開槍 ----
          // 獵人、被自刀的狼王、學到槍牌且吃刀的機械狼。為什麼能開寫在
          // 下方的裁決說明裡；開槍目標在下一頁記。狼王不給夜間手勢 ——
          // 狼隊自己知道有沒有自刀，白天起來直接發動。
          for (final seat in outcome.shooterSeats)
            _InfoCard(
              icon: Icons.crisis_alert_rounded,
              iconColor: WgmTheme.wolfColor,
              title: '$seat 號'
                  '（${state.playerAt(seat).role?.nameZh ?? "?"}）可以開槍',
              body: '公布死訊後，按下方的開槍鍵記下他要帶走誰。',
            ),

          // ---- 預言家查驗結果 ----
          if (outcome.seerTarget != null)
            _InfoCard(
              icon: Icons.visibility_rounded,
              iconColor:
                  outcome.seerSawWolf ? WgmTheme.wolfColor : WgmTheme.godColor,
              title: '預言家查驗 ${outcome.seerTarget} 號',
              body: outcome.seerSawWolf ? '結果：查殺（狼人）' : '結果：金水（好人）',
            ),

          // ---- 通靈師查驗結果 ----
          // 通靈師看到的是真實身分，不是好人／狼人，所以要把角色名寫出來。
          if (outcome.psychicResult != null)
            _InfoCard(
              icon: Icons.auto_awesome_rounded,
              iconColor:
                  outcome.psychicResult!.revealedRole?.camp == Camp.wolf
                      ? WgmTheme.wolfColor
                      : WgmTheme.godColor,
              title: '通靈師查驗 ${outcome.psychicResult!.seat} 號',
              body: '真實身分：'
                  '${outcome.psychicResult!.revealedRole?.nameZh ?? "尚未登記"}',
            ),

          // ---- 機械狼 ----
          if (outcome.mechanicLearnedRole != null)
            _InfoCard(
              icon: Icons.memory_rounded,
              iconColor: WgmTheme.wolfColor,
              title: '機械狼學習了 ${outcome.mechanicLearnedRole!.nameZh}',
              body: mechanicSkillTimingText(outcome.mechanicLearnedRole!),
            ),
          if (outcome.mechanicSeerTarget != null)
            _InfoCard(
              icon: Icons.memory_rounded,
              iconColor: outcome.mechanicSeerSawWolf
                  ? WgmTheme.wolfColor
                  : WgmTheme.godColor,
              title: '機械狼查驗 ${outcome.mechanicSeerTarget} 號',
              body: outcome.mechanicSeerSawWolf ? '結果：查殺（狼人）' : '結果：金水（好人）',
            ),
          if (outcome.mechanicPsychicResult != null)
            _InfoCard(
              icon: Icons.memory_rounded,
              iconColor: WgmTheme.godColor,
              title: '機械狼查驗 ${outcome.mechanicPsychicResult!.seat} 號',
              body: '真實身分：'
                  '${outcome.mechanicPsychicResult!.revealedRole?.nameZh ?? "尚未登記"}',
            ),

          if (outcome.shieldBrokenSeats.isNotEmpty)
            _InfoCard(
              icon: Icons.shield_outlined,
              iconColor: WgmTheme.wolfColor,
              title: '破盾：${outcome.shieldBrokenSeats.join('、')} 號',
              body: '機械狼（已學到狼人）雙刀集中，守衛的守護與女巫的解藥都被打穿。',
            ),
          if (outcome.poisonReflectedTo != null)
            _InfoCard(
              icon: Icons.u_turn_left_rounded,
              iconColor: WgmTheme.wolfColor,
              title: '毒藥反彈到 ${outcome.poisonReflectedTo} 號',
              body: '目標被機械狼（已學到守衛）守住，毒反噬下毒的人。',
            ),

          // ---- 殉情 ----
          if (outcome.charmSuicideSeat != null)
            _InfoCard(
              icon: Icons.favorite_rounded,
              iconColor: WgmTheme.wolfColor,
              title: '${outcome.charmSuicideSeat} 號殉情',
              body: '狼美人出局，被魅惑者隨之死亡。',
            ),

          // ---- 裁決說明 ----
          if (outcome.notes.isNotEmpty)
            _InfoCard(
              icon: Icons.gavel_rounded,
              iconColor: scheme.onSurfaceVariant,
              title: '裁決說明',
              bodyWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final n in outcome.notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '· $n',
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                ],
              ),
            ),

          // ---- 首夜自動填入平民 ----
          if (autoFilledVillagers.isNotEmpty)
            _InfoCard(
              icon: Icons.groups_rounded,
              iconColor: WgmTheme.villagerColor,
              title: '剩餘 ${autoFilledVillagers.length} 位自動登記為平民',
              body: '${autoFilledVillagers.join('、')} 號',
            ),

          // ---- 場上狀態 ----
          _InfoCard(
            icon: Icons.people_alt_rounded,
            iconColor: scheme.primary,
            title: '場上狀態',
            bodyWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '存活 ${state.aliveCount} / ${state.preset.playerCount}　'
                  '狼 ${state.aliveWolfCount}　'
                  '神 ${state.aliveGodCount}　'
                  '民 ${state.aliveVillagerCount}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in state.players)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (p.alive
                                    ? WgmTheme.colorOf(p.role)
                                    : WgmTheme.deadColor)
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          '${p.seat} ${p.role?.nameZh ?? "?"}'
                          '${p.alive ? "" : " ✕"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: p.alive
                                ? WgmTheme.colorOf(p.role)
                                : WgmTheme.deadColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          // 夜晚結算完就要檢查勝負 —— 不必等白天走完。
          if (_win.isOver) ...[
            _InfoCard(
              icon: Icons.emoji_events_rounded,
              iconColor: _win.result == GameResult.wolvesWin
                  ? WgmTheme.wolfColor
                  : WgmTheme.godColor,
              title: '${_win.result.labelZh} —— ${_win.reason}',
              body: '昨晚的死亡已經分出勝負，白天不必再進行。',
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _toGameOver(context),
              icon: const Icon(Icons.emoji_events_rounded),
              label: const Text('查看結果'),
            ),
          ] else ...[
            // 遺言由法官決定要不要給 —— 誰有遺言權各家規則不同
            // （常見的是首夜死者與被放逐者才有），App 不替桌上決定，
            // 只在有死者時提供碼表。
            if (_lastWordsSeats.isNotEmpty) ...[
              OutlinedButton.icon(
                onPressed: () => _toLastWords(context),
                icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                label: Text('${_lastWordsSeats.join('、')} 號遺言計時'),
              ),
              const SizedBox(height: 8),
            ],

            // 下一站是開槍或警徽流時，按鈕要講實話。
            if (outcome.shooterSeats.isNotEmpty)
              FilledButton.icon(
                onPressed: () => _toSpeechOrder(context),
                icon: const Icon(Icons.crisis_alert_rounded),
                label: Text('${outcome.shooterSeats.join('、')} 號開槍'),
              )
            else if (BadgeSuccession.isDue(state))
              FilledButton.icon(
                onPressed: () => _toSpeechOrder(context),
                icon: const Icon(Icons.shield_rounded),
                label: Text('${state.sheriffSeat} 號警長出局，處理警徽流'),
              )
            else
              FilledButton.icon(
                onPressed: () => _toSpeechOrder(context),
                icon: const Icon(Icons.record_voice_over_rounded),
                label: const Text('決定發言順序'),
              ),
            const SizedBox(height: 8),
            Text(
              '接著是發言順序 → 逐人發言 → 放逐投票 → 下一夜。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  /// 遺言計時。講完退回這一頁，法官再繼續往下走 —— 不接管流程，
  /// 因為要不要給遺言、給誰，都是桌上的規則，不是 App 的。
  void _toLastWords(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (inner) => SpeechTimerPage(
          state: state,
          order: _lastWordsSeats,
          phase: SpeechPhase.lastWords,
          finishLabel: '遺言結束',
          onFinished: () => Navigator.of(inner).pop(),
        ),
      ),
    );
  }

  /// 夜晚就分出勝負時直接進結果頁，白天整套流程都不必走。
  void _toGameOver(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GameOverPage(state: state, check: _win),
      ),
    );
  }

  /// 公布死訊之後才決定發言順序 —— 單死與雙死的規則不同，
  /// 得先知道死了幾個才判斷得出來。
  ///
  /// 警長昨晚出局時，警徽流要插在發言順序**之前** —— 警左警右由警長決定，
  /// 得先知道現在誰是警長。
  ///
  /// 夜死的槍牌開槍再排在警徽流**之前**（擔當 2026-09-24 指定）——
  /// 獵人可能帶走的就是警長。`routeIfDue` 的 `next` 是延遲求值的，
  /// 所以警徽流要不要走，是開完槍之後才判斷。
  ///
  /// 發言順序的「單死／雙死」**連天亮後被槍帶走的人也算**（擔當 2026-09-24
  /// 指定）—— 獵人夜死又帶走一人，就是雙死，從警長算起。
  void _toSpeechOrder(BuildContext context) {
    Navigator.of(context).pushReplacement(
      NightDeathShotPage.routeIfDue(
        state,
        shooters: outcome.shooterSeats,
        next: (taken) => BadgeSuccessionPage.routeIfDue(
          state,
          next: () => SpeechOrderPage.routeThenExile(
            state,
            [...outcome.deadSeats, ...taken],
            nextNight: () => NightFlowPage.route(state),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.body,
    this.bodyWidget,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? body;
  final Widget? bodyWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (body != null || bodyWidget != null) ...[
                const SizedBox(height: 8),
                bodyWidget ??
                    Text(
                      body!,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
