/// 板子設定檔格式錯誤。
///
/// 錯誤訊息必須指出是哪個板子、哪個欄位出錯 —— 不要讓錯誤的設定檔
/// 在結算到一半才炸掉。
class PresetFormatException implements Exception {
  const PresetFormatException({
    required this.presetId,
    required this.field,
    required this.message,
  });

  /// 出錯的板子；載入階段連 presetId 都讀不到時，填入檔名。
  final String presetId;

  /// 出錯的欄位路徑，例如 `rules.tieBreak`、`roles[2].count`。
  final String field;

  final String message;

  @override
  String toString() => '板子「$presetId」設定錯誤 — 欄位 $field：$message';
}
