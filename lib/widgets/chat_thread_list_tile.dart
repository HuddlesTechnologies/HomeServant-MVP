import 'package:flutter/material.dart';
import '../api/models/chat.dart';

/// A plain-text preview for the list row — an image message with no
/// caption would otherwise show as a blank line (or fall through to "No
/// messages yet", which is wrong once a real message exists).
String _lastMessagePreview(ChatMessage? lastMessage) {
  if (lastMessage == null) return 'No messages yet';
  if (lastMessage.type == MessageType.image && lastMessage.body.isEmpty) return '📷 Photo';
  return lastMessage.body;
}

/// One row in a conversation list: avatar, other participant's name, last
/// message preview, and an optional time/unread indicator, for the tenant
/// and landlord Messages screens. Their rows look different (the tenant
/// row shows a relative time and an unread dot; the landlord row an
/// unread-count badge), so every style, colour and the avatar/trailing
/// widgets are parameters the caller resolves.
///
/// Has no `onTap` of its own: the tenant screen wraps it in a
/// `GestureDetector` and the landlord screen in an `InkWell` (for the
/// splash). A tap handler here as well could fire twice and would hide the
/// landlord row's splash.
class ChatThreadListTile extends StatelessWidget {
  const ChatThreadListTile({
    super.key,
    required this.thread,
    required this.avatar,
    required this.nameStyle,
    required this.messageStyle,
    this.time,
    this.nameMessageSpacing = 4,
    this.trailing,
  });

  final ChatThread thread;

  /// The tenant screen uses a `CircleAvatar` with a person icon; the
  /// landlord screen uses the shared `LandlordAvatar`.
  final Widget avatar;

  final TextStyle nameStyle;
  final TextStyle messageStyle;

  /// Shown to the right of the name, on the same row, only on the tenant
  /// screen (a relative timestamp) — left null on the landlord screen,
  /// which doesn't show one at all.
  final Widget? time;

  /// Vertical gap between the name row and the message preview — 4 on the
  /// tenant screen, 3 on the landlord screen.
  final double nameMessageSpacing;

  /// The unread marker drawn at the end of the row — a small accent dot on
  /// the tenant screen, an unread-count badge on the landlord screen.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final online = thread.otherParticipant?.isOnline ?? false;
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            if (online)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (time != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(thread.otherParticipantName, overflow: TextOverflow.ellipsis, style: nameStyle),
                    ),
                    time!,
                  ],
                )
              else
                Text(thread.otherParticipantName, overflow: TextOverflow.ellipsis, style: nameStyle),
              SizedBox(height: nameMessageSpacing),
              Text(
                _lastMessagePreview(thread.lastMessage),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: messageStyle,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}
