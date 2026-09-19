import '../models/log_entry.dart';

/// 一個段落：同一夜或同一天的所有日誌。
class LogSection {
  const LogSection({
    required this.round,
    required this.isNight,
    required this.entries,
  });

  final int round;
  final bool isNight;
  final List<LogEntry> entries;

  String get label => entries.first.roundLabel;
}

/// 復盤日誌。
///
/// **單向的** —— 只寫入、供事後查看與匯出，**不用來推導狀態**
/// （見 CLAUDE.md「關鍵設計原則 1」）。局面的真相永遠在 `GameState` 裡。
///
/// 掛在 `GameState` 上，所以 `copy()`／`restoreFrom()` 會一起處理它：
/// **法官撤銷誤觸時日誌也跟著退回去**，復盤看到的是實際發生的事，
/// 不是按錯又改掉的過程。
class GameLog {
  final List<LogEntry> entries = [];

  bool get isEmpty => entries.isEmpty;

  int get length => entries.length;

  /// 寫一筆。務必在**修改狀態的同一處**呼叫，否則很容易漏記。
  void add({
    required int round,
    required bool isNight,
    required LogKind kind,
    required String text,
    List<int> seats = const <int>[],
  }) {
    if (text.isEmpty) return;
    entries.add(
      LogEntry(
        round: round,
        isNight: isNight,
        kind: kind,
        text: text,
        seats: seats,
      ),
    );
  }

  /// 一次寫多句 —— 各引擎的 `notes` 本來就是一句一句的宣布稿，直接倒進來。
  void addAll({
    required int round,
    required bool isNight,
    required LogKind kind,
    required Iterable<String> texts,
  }) {
    for (final t in texts) {
      add(round: round, isNight: isNight, kind: kind, text: t);
    }
  }

  /// 依夜次／天次分段，順序照寫入順序。
  List<LogSection> get sections {
    final out = <LogSection>[];
    for (final e in entries) {
      final last = out.isEmpty ? null : out.last;
      if (last != null && last.round == e.round && last.isNight == e.isNight) {
        last.entries.add(e);
      } else {
        out.add(LogSection(round: e.round, isNight: e.isNight, entries: [e]));
      }
    }
    return out;
  }

  /// 匯出成純文字，貼到聊天室或筆記用。
  String toPlainText({String? title}) {
    final buffer = StringBuffer();
    if (title != null) {
      buffer
        ..writeln(title)
        ..writeln();
    }
    for (final section in sections) {
      buffer.writeln('【${section.label}】');
      for (final e in section.entries) {
        buffer.writeln('· ${e.text}');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  // ---- 撤銷支援 ----

  GameLog copy() => GameLog()..entries.addAll(entries.map((e) => e.copy()));

  void restoreFrom(GameLog other) {
    entries
      ..clear()
      ..addAll(other.entries.map((e) => e.copy()));
  }
}
