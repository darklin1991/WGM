/// 日誌項目的分類。只影響復盤頁怎麼分組與標色，不影響規則。
enum LogKind {
  /// 開局配置。
  setup('配置'),

  /// 夜間行動：守誰、刀誰、用了什麼藥、查了誰。
  nightAction('行動'),

  /// 查驗結果：金水、查殺、通靈的真實身分。
  info('情報'),

  /// 裁決說明：奶穿、破盾、毒反彈那類「為什麼是這個結果」。
  ruling('裁決'),

  /// 出局：不分死因，死因寫在句子裡。
  death('出局'),

  /// 警長競選。
  election('競選'),

  /// 放逐投票。
  vote('投票'),

  /// 騎士決鬥。
  duel('決鬥'),

  /// 警徽流。
  badge('警徽'),

  /// 勝負。
  gameOver('結束');

  const LogKind(this.labelZh);

  final String labelZh;
}

/// 一筆復盤日誌。
///
/// **只寫入，不用來推導狀態**（見 CLAUDE.md「關鍵設計原則 1」）。
/// 局面的真相永遠在 `GameState` 裡，這份日誌純粹是給人看的。
class LogEntry {
  const LogEntry({
    required this.round,
    required this.isNight,
    required this.kind,
    required this.text,
    this.seats = const <int>[],
  });

  /// 第幾夜或第幾天。開局那幾筆是 0。
  final int round;

  /// true 為夜晚，false 為白天。
  final bool isNight;

  final LogKind kind;

  /// 給人看的一句中文。復盤時直接念這句。
  final String text;

  /// 相關座次，供之後做「只看某人」的篩選。目前畫面還沒用到。
  final List<int> seats;

  /// 「第 3 夜」「第 2 天」「開局」。
  String get roundLabel {
    if (round == 0) return '開局';
    return isNight ? '第 $round 夜' : '第 $round 天';
  }

  LogEntry copy() => LogEntry(
        round: round,
        isNight: isNight,
        kind: kind,
        text: text,
        seats: List<int>.from(seats),
      );

  @override
  String toString() => '[${kind.labelZh}] $text';
}
