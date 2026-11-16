import 'package:material_ui/material_ui.dart';

import 'screens/chat_screen.dart';

void main() {
  runApp(const LlmCouncilApp());
}

class LlmCouncilApp extends StatelessWidget {
  const LlmCouncilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LLM Council',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
      ),
      home: const ChatScreen(),
    );
  }
}
