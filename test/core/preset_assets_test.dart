import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wgm/core/models/preset.dart';

/// 直接讀 `assets/presets/` 的實際檔案來驗證。
///
/// 目的是讓「內建板子壞了」在 CI／本機測試就被抓到，而不是在法官
/// 開場時才發現板子載不進來。
void main() {
  final dir = Directory('assets/presets');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('assets/presets 底下有內建板子', () {
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;

    group(name, () {
      late Preset preset;

      setUpAll(() {
        final json = jsonDecode(file.readAsStringSync()) as Map;
        preset = Preset.fromJson(
          json.cast<String, dynamic>(),
          sourceName: name,
        );
      });

      test('可正確解析，且角色總數等於人數', () {
        expect(preset.buildRoleDeck().length, preset.playerCount);
      });

      test('9 人以上的板子，女巫不可自救', () {
        if (preset.playerCount >= 9) {
          expect(
            preset.rules.witchMaySelfHeal(1),
            isFalse,
            reason: '${preset.name}（${preset.playerCount} 人）不應允許女巫自救',
          );
        }
      });

      test('夜晚順序不為空', () {
        expect(preset.nightOrder, isNotEmpty);
      });
    });
  }
}
