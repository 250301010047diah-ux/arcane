import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archer/main.dart';

void main() {
  testWidgets('ArcherApp builds a MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(const ArcherApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
