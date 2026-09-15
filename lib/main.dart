import 'package:flutter/material.dart';

import 'features/setup/preset_list_page.dart';
import 'shared/theme.dart';

void main() {
  runApp(const WgmApp());
}

class WgmApp extends StatelessWidget {
  const WgmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WGM 法官助手',
      debugShowCheckedModeBanner: false,
      theme: WgmTheme.build(),
      home: const PresetListPage(),
    );
  }
}
