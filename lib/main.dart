import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'presentation/pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JusouApp());
}

class JusouApp extends StatelessWidget {
  const JusouApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '剧搜/JUSOU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomePage(),
    );
  }
}
