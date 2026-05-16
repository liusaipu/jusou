import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'presentation/pages/home_page.dart';

final isDarkMode = ValueNotifier<bool>(true);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JusouApp());
}

class JusouApp extends StatelessWidget {
  const JusouApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkMode,
      builder: (context, isDark, _) {
        return MaterialApp(
          title: '剧搜/JUSOU',
          debugShowCheckedModeBanner: false,
          theme: isDark ? AppTheme.dark : AppTheme.light,
          home: const HomePage(),
        );
      },
    );
  }
}
