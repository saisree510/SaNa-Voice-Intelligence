import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sana/app/sana_app.dart';

void main() {
  testWidgets('SaNa home shows brand, greeting, modes, conversation handle', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SanaApp()));
    // Orb uses repeating animations; avoid pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SaNa'), findsWidgets);
    expect(find.text('Hey Sai,'), findsOneWidget);
    expect(find.text('what are we working on today?'), findsOneWidget);
    expect(find.text('Listening…'), findsOneWidget);
    expect(find.text('Debate'), findsOneWidget);
    expect(find.text('Brainstorm'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.textContaining('Tap the orb'), findsNothing);
    expect(find.textContaining('UI preview'), findsNothing);
  });

  testWidgets('SaNa home fits a compact Android viewport', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: SanaApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('Debate'), findsOneWidget);
  });
}
