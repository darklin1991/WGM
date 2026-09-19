import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/log/game_log.dart';
import '../../core/models/game_state.dart';
import '../../core/models/log_entry.dart';
import '../../shared/theme.dart';

/// 復盤日誌頁：依夜次／天次分段列出整局發生過的事。
///
/// **遊戲進行中隨時可以打開**（擔當 2026-09-19 指定）—— 法官自己拿手機，
/// 現場忘記前幾天發生什麼可以隨時翻。玩家看不到這支手機。
///
/// 日誌是單向的：只顯示 [GameLog] 的內容，不改任何狀態。
class ReviewLogPage extends StatelessWidget {
  const ReviewLogPage({super.key, required this.state});

  final GameState state;

  GameLog get _log => state.log;

  String get _title => '${state.preset.name}　復盤日誌';

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: _log.toPlainText(title: _title)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已複製整份日誌')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sections = _log.sections;

    return Scaffold(
      appBar: AppBar(
        title: const Text('復盤日誌'),
        actions: [
          IconButton(
            onPressed: _log.isEmpty ? null : () => _copy(context),
            icon: const Icon(Icons.copy_rounded),
            tooltip: '複製成文字',
          ),
        ],
      ),
      body: sections.isEmpty
          ? Center(
              child: Text(
                '還沒有任何紀錄',
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final section in sections) _sectionCard(scheme, section),
                const SizedBox(height: 8),
                Text(
                  '共 ${_log.length} 筆。撤銷過的操作不會留在這裡。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionCard(ColorScheme scheme, LogSection section) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    section.isNight
                        ? Icons.nightlight_round
                        : Icons.wb_sunny_rounded,
                    size: 18,
                    color: section.isNight
                        ? WgmTheme.wolfColor
                        : WgmTheme.godColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    section.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final e in section.entries) _line(scheme, e),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(ColorScheme scheme, LogEntry e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分類標籤固定寬度，句子才會對齊成一欄。
          SizedBox(
            width: 38,
            child: Text(
              e.kind.labelZh,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _kindColor(scheme, e.kind),
              ),
            ),
          ),
          Expanded(
            child: Text(
              e.text,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Color _kindColor(ColorScheme scheme, LogKind kind) => switch (kind) {
        LogKind.death || LogKind.duel => WgmTheme.wolfColor,
        LogKind.info || LogKind.gameOver => WgmTheme.godColor,
        _ => scheme.onSurfaceVariant,
      };
}
