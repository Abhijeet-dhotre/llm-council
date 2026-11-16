// Smoke test: the app builds and shows the council home screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llm_council/main.dart';

void main() {
  testWidgets('App builds with welcome screen', (tester) async {
    // No network font fetching in tests — fall back to system fonts.
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(const LlmCouncilApp());
    await tester.pump();
    expect(find.text('LLM Council'), findsWidgets);
    expect(find.text('Ask the council.'), findsOneWidget);
    expect(find.text('Ask the council anything…'), findsOneWidget);
  });
}
