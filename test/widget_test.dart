import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sana/app/sana_app.dart';

void main() {
  testWidgets('SaNa home shows brand and mode cards', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SanaApp()));
    // Orb uses repeating animations; avoid pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SaNa'), findsWidgets);
    expect(find.textContaining('what are we working on today'), findsOneWidget);
    expect(find.text('Debate'), findsOneWidget);
    expect(find.text('Brainstorm'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
  });
}
