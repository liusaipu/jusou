import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:jusou/main.dart';

void main() {
  testWidgets('Jusou app shows search field', (WidgetTester tester) async {
    await tester.pumpWidget(const JusouApp());

    expect(find.text('搜电影、电视剧...'), findsOneWidget);
    expect(find.text('搜索多来源网盘资源'), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('Jusou settings exposes config import and export actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const JusouApp());

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('导出配置'), findsOneWidget);
    expect(find.text('导入配置'), findsOneWidget);
  });
}
