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

  testWidgets('Search field accepts text input', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const JusouApp());

    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, '流浪地球');
    await tester.pump();

    expect(find.text('流浪地球'), findsOneWidget);
  });

  testWidgets('Settings sheet shows expected controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const JusouApp());

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    // 设置面板应显示关键配置项
    expect(find.text('远程搜索'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('导出配置'), findsOneWidget);
    expect(find.text('导入配置'), findsOneWidget);
  });

  testWidgets('Empty state shows discovery categories', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const JusouApp());

    expect(find.text('电影'), findsOneWidget);
    expect(find.text('电视剧'), findsOneWidget);
    expect(find.text('纪录片'), findsOneWidget);
    expect(find.text('综艺'), findsOneWidget);
  });
}
