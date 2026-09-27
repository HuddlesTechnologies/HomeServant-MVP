import 'package:flutter_test/flutter_test.dart';

import 'package:homeservant/api/models/chat.dart';

void main() {
  test('a message whose sender account was deleted still parses', () {
    // Message.sender is onDelete: SetNull, so these come back with a null
    // senderId and no sender. Parsing used to throw, failing the whole
    // inbox ("Couldn't load messages").
    final message = ChatMessage.fromApi({
      'id': 'm1',
      'threadId': 't1',
      'senderId': null,
      'sender': null,
      'body': 'Hello',
      'createdAt': '2026-09-27T10:00:00Z',
      'readAt': null,
      'type': 'TEXT',
    });
    expect(message.senderId, isNull);
    expect(message.senderName, 'Deleted user');
  });

  test('a thread whose last message is from a deleted account still parses', () {
    final thread = ChatThread.fromApi({
      'id': 't1',
      'otherParticipants': <Map<String, dynamic>>[],
      'property': null,
      'order': null,
      'lastMessage': {
        'id': 'm1',
        'threadId': 't1',
        'senderId': null,
        'body': 'Hello',
        'createdAt': '2026-09-27T10:00:00Z',
      },
      'unreadCount': 0,
      'updatedAt': '2026-09-27T10:00:00Z',
      'isSupport': true,
      'resolved': false,
    });
    expect(thread.lastMessage?.body, 'Hello');
  });
}
