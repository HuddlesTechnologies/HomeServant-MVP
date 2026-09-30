import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeservant/api/models/chat.dart' show MessageQuote, MessageType;
import 'package:homeservant/features/dashboard/chat_thread_screen.dart';
import 'package:homeservant/models/dashboard_theme.dart';
import 'package:homeservant/state/app_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<ChatMessage> _messages() => [
  ChatMessage(text: 'Payment confirmed', fromMe: false, type: MessageType.system),
  ChatMessage(text: 'Is the flat still available?', fromMe: false, id: 'm1', senderName: 'Ada'),
  ChatMessage(
    text: 'Yes it is',
    fromMe: true,
    id: 'm2',
    read: true,
    replyTo: const MessageQuote(id: 'm1', body: 'Is the flat still available?', isImage: false, senderName: 'Ada'),
  ),
  ChatMessage(text: 'Can I visit tomorrow?', fromMe: true, sendState: SendState.failed),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final theme in DashboardTheme.values) {
    testWidgets('renders every kind of message in the ${theme.name} theme', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppState(),
          child: MaterialApp(home: ChatThreadScreen(theme: theme, contactName: 'Ada', initialMessages: _messages())),
        ),
      );
      await tester.pump();
      expect(find.text('Payment confirmed'), findsOneWidget);
      expect(find.text('Is the flat still available?'), findsNWidgets(2)); // the message and its quote
      expect(find.text('Yes it is'), findsOneWidget);
      expect(find.text('Not sent · Tap to retry'), findsOneWidget);
      expect(find.text('Type a message'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
