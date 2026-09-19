import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/engine/speech_timer.dart';
import '../../shared/theme.dart';

/// 發言計時元件。
///
/// 做成元件而不是只有頁面，是因為四個使用點的外框不一樣：警上發言與
/// 平票 PK 發言是**嵌在原本那一頁的一個階段裡**（競選頁、放逐頁），
/// 白天發言與遺言才是獨立的一頁。
///
/// 規則（誰在講、剩幾秒、超時多久）全在 [SpeechTimer] 裡；這裡只負責
/// 每秒敲一次 [SpeechTimer.tick]、把狀態畫出來、把操作轉回去。
class SpeechTimerView extends StatefulWidget {
  const SpeechTimerView({
    super.key,
    required this.timer,
    required this.phase,
    required this.onFinished,
    this.finishLabel,
  });

  final SpeechTimer timer;

  /// 是哪一種發言，只影響稱呼。
  final SpeechPhase phase;

  /// 最後一位講完、法官按下結束鍵時要做什麼。
  final VoidCallback onFinished;

  /// 結束鍵的字樣；不給就依 [phase] 自動決定。
  final String? finishLabel;

  @override
  State<SpeechTimerView> createState() => _SpeechTimerViewState();
}

class _SpeechTimerViewState extends State<SpeechTimerView> {
  Timer? _ticker;

  /// 已經為這一位提示過超時了 —— 每位只震一次，不要每秒都震。
  bool _alerted = false;

  SpeechTimer get _t => widget.timer;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!_t.running) return;
    setState(() {
      _t.tick();
      if (_t.overtime && !_alerted) {
        _alerted = true;
        HapticFeedback.heavyImpact();
      }
    });
  }

  /// 換人之後要重新允許提示一次。
  void _act(void Function() change) {
    setState(() {
      change();
      _alerted = _t.overtime;
    });
  }

  String get _finishLabel =>
      widget.finishLabel ??
      switch (widget.phase) {
        SpeechPhase.campaign => '警上發言結束',
        SpeechPhase.day => '發言結束，進入投票',
        SpeechPhase.runoff => 'PK 發言結束，開始重投',
        SpeechPhase.lastWords => '遺言結束',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = _t.overtime;
    final color = over ? WgmTheme.wolfColor : WgmTheme.godColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _speakerStrip(scheme),
        const SizedBox(height: 12),

        // ---- 碼表 ----
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: color.withValues(alpha: over ? 0.18 : 0.08),
              border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
            ),
            child: Column(
              children: [
                Text(
                  '${_t.currentSeat} 號　${widget.phase.labelZh}',
                  style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  _t.display,
                  // 快選晶片上也會出現一樣的字（例如 2:00），測試要分得出來。
                  key: const Key('speech-countdown'),
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  over ? '已超時' : '每人 ${SpeechTimer.format(_t.seconds)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: over ? WgmTheme.wolfColor : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        _durationRow(scheme),
        const SizedBox(height: 16),

        // ---- 開始／暫停、重來 ----
        Row(
          children: [
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => _act(_t.toggle),
                icon: Icon(
                  _t.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(_t.running ? '暫停' : '開始'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _act(_t.resetCurrent),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('重來'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ---- 換人 ----
        Row(
          children: [
            if (!_t.isFirst) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _act(_t.previous),
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  label: const Text('上一位'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              flex: 2,
              child: _t.isLast
                  ? FilledButton.icon(
                      onPressed: widget.onFinished,
                      icon: const Icon(Icons.done_all_rounded),
                      label: Text(_finishLabel),
                    )
                  : FilledButton.icon(
                      onPressed: () => _act(_t.next),
                      icon: const Icon(Icons.chevron_right_rounded),
                      label: Text('下一位（${_t.order[_t.index + 1]} 號）'),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  /// 發言順序條。點號碼可以直接跳過去 —— 現場漏聽一位是常態。
  Widget _speakerStrip(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t.remainingSpeakers == 0
              ? '最後一位'
              : '發言順序（還有 ${_t.remainingSpeakers} 位）',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < _t.order.length; i++)
              ChoiceChip(
                label: Text('${_t.order[i]}'),
                selected: i == _t.index,
                onSelected: (_) => _act(() => _t.jumpTo(_t.order[i])),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: i < _t.index ? TextDecoration.lineThrough : null,
                  color: i < _t.index ? scheme.onSurfaceVariant : null,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// 額度快選。擔當要的是「預設 2 分鐘、現場可調」。
  Widget _durationRow(ColorScheme scheme) {
    const choices = [60, 90, 120, 180];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '每人時間',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (final s in choices)
              ChoiceChip(
                label: Text(SpeechTimer.format(s)),
                selected: _t.seconds == s,
                onSelected: (_) => _act(() => _t.setSeconds(s)),
              ),
          ],
        ),
      ],
    );
  }
}
