import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/preset.dart';

/// 載入板子設定檔的結果。
///
/// 單一板子格式錯誤不應讓整個清單載入失敗 —— 其他板子照樣能用，
/// 壞掉的那份連同錯誤訊息一起回報給法官。
class PresetLoadResult {
  const PresetLoadResult({required this.presets, required this.errors});

  final List<Preset> presets;

  /// 載入失敗的板子，key 為資產路徑，value 為錯誤描述。
  final Map<String, String> errors;

  bool get hasErrors => errors.isNotEmpty;
}

/// 從 `assets/presets/` 載入所有板子設定檔。
class PresetLoader {
  const PresetLoader({this.bundle});

  /// 測試時可注入替代 bundle；null 表示使用 [rootBundle]。
  /// 不直接把 rootBundle 當預設值，因為它不是編譯期常數。
  final AssetBundle? bundle;

  AssetBundle get _bundle => bundle ?? rootBundle;

  static const _dir = 'assets/presets/';

  Future<PresetLoadResult> loadAll() async {
    final bundle = _bundle;
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final paths = manifest
        .listAssets()
        .where((p) => p.startsWith(_dir) && p.endsWith('.json'))
        .toList()
      ..sort();

    final presets = <Preset>[];
    final errors = <String, String>{};

    for (final path in paths) {
      try {
        final raw = await bundle.loadString(path);
        final json = jsonDecode(raw);
        if (json is! Map) {
          errors[path] = '檔案內容必須是 JSON 物件';
          continue;
        }
        presets.add(
          Preset.fromJson(
            json.cast<String, dynamic>(),
            sourceName: path.split('/').last,
          ),
        );
      } catch (e) {
        errors[path] = e.toString();
      }
    }

    presets.sort((a, b) {
      final byCount = a.playerCount.compareTo(b.playerCount);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });

    return PresetLoadResult(presets: presets, errors: errors);
  }
}
