import 'package:flutter_test/flutter_test.dart';

import 'package:homeservant/api/models/app_notification.dart';
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

  test('a thread summary parses its transfer and permissions', () {
    final summary = ThreadSummary.fromApi({
      'id': 't1',
      'isSupport': true,
      'resolved': false,
      'resolvedAt': null,
      'assignedAdmin': {'id': 'a2', 'fullName': 'Bola'},
      'lastTransfer': {
        'fromAdmin': {'id': 'a1', 'fullName': 'Ada'},
        'toAdmin': {'id': 'a2', 'fullName': 'Bola'},
        'createdAt': '2026-09-27T10:00:00Z',
      },
      'otherParticipants': [
        {'id': 'u1', 'fullName': 'Tenant T', 'profilePhotoUrl': null},
      ],
      'canView': true,
      'canReply': false,
    });
    expect(summary.assignedAdmin?.displayName, 'Bola');
    expect(summary.lastTransferFrom?.id, 'a1');
    expect(summary.otherParticipants.single.fullName, 'Tenant T');
    expect(summary.canReply, isFalse);
    expect(summary.canReassign, isFalse);
  });

  test('a super admin summary can offer reassign', () {
    final summary = ThreadSummary.fromApi({'id': 't1', 'canView': true, 'canReassign': true, 'otherParticipants': []});
    expect(summary.canReassign, isTrue);
  });

  test('a transfer from a since-deleted admin still parses', () {
    final summary = ThreadSummary.fromApi({
      'id': 't1',
      'lastTransfer': {'fromAdmin': null, 'toAdmin': null, 'createdAt': '2026-09-27T10:00:00Z'},
      'otherParticipants': [],
    });
    expect(summary.lastTransferFrom, isNull);
    expect(summary.canView, isFalse);
  });

  test('notifications carry the thread they are about', () {
    final n = AppNotification.fromApi({
      'id': 'n1',
      'type': 'NEW_MESSAGE',
      'title': 'New message',
      'body': 'Hi',
      'threadId': 't1',
      'createdAt': '2026-09-27T10:00:00Z',
    });
    expect(n.threadId, 't1');
  });
}
