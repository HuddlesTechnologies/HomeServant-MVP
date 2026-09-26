import 'package:flutter/material.dart';
import '../api/models/chat.dart';

/// One row in a conversation list: avatar, other participant's name, last
/// message preview, and an optional time/unread indicator — shared by the
/// tenant and landlord Messages screens, which each used to define this
/// same row inline with slightly different styling (the tenant row shows a
/// relative timestamp next to the name and a small unread dot; the landlord
/// row has no timestamp and shows an unread-count badge instead). Every
/// style/colour and the avatar/trailing widgets themselves are taken as
/// parameters — fully resolved by the caller — so each screen's exact
/// current look carries over unchanged rather than this widget guessing at
/// shared unread-styling rules that don't actually match between the two.
///
/// Deliberately has no `onTap` of its own — the tenant screen wraps its row
/// in a plain `GestureDetector` while the landlord screen wraps its row in
/// an `InkWell` (for the splash feedback); nesting this widget's own tap
/// handler inside either would risk a double-fire (and would drop the
/// landlord row's splash), so each caller keeps its existing wrapper as-is
/// and this widget only renders the row's content.
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
                thread.lastMessage?.body ?? 'No messages yet',
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
