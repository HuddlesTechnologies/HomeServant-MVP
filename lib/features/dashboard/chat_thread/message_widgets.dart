// The message list: one widget per kind of message (text, image, property preview), the quote shown above a reply, and swipe-to-reply.
part of '../chat_thread_screen.dart';

/// Rich preview card rendered in place of a plain text bubble for the
/// first message in a listing-originated thread (`type: propertyPreview`),
/// for both participants — everything else in the thread stays a normal
/// text bubble.
class _PropertyPreviewBubble extends StatelessWidget {
  const _PropertyPreviewBubble({required this.theme, required this.message});

  final DashboardTheme theme;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final imageUrl = message.previewPropertyImageUrl;
    final price = message.previewPropertyPrice;
    final priceUnit = message.previewPropertyPriceUnit;
    // Opaque accent/onAccent for fromMe, surface/onSurface otherwise — the
    // same paired convention the plain-text bubble above uses. A
    // translucent accent tint (as this used to be) is only guaranteed to
    // stay light against a light theme.background; in Midnight,
    // theme.background is dark navy, so a low-alpha tint over it stays
    // dark and theme.onSurface (always navy) text on it is unreadable.
    final bubbleColor = message.fromMe ? theme.accent : theme.surface;
    final onBubbleColor = message.fromMe ? theme.onAccent : theme.onSurface;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: onBubbleColor.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty) PropertyImage(path: imageUrl, height: 130, width: double.infinity),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.previewPropertyTitle ?? 'Property',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(color: onBubbleColor, size: 14, weight: FontWeight.w700),
                ),
                if (price != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '₦${formatNaira(price)}${priceUnit != null ? '/${priceUnit.toLowerCase()}' : ''}',
                    style: AppTextStyles.body(color: message.fromMe ? theme.onAccent : theme.accent, size: 13, weight: FontWeight.w700),
                  ),
                ],
                if (message.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(message.text, style: AppTextStyles.body(color: onBubbleColor.withValues(alpha: 0.8), size: 13)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A photo message, with an optional caption underneath — tapping opens it
/// full-screen (reusing [PropertyGalleryScreen]'s pinch-to-zoom viewer with
/// a single-image list, rather than a second one-off full-screen widget).
class _ImageMessageBubble extends StatelessWidget {
  const _ImageMessageBubble({required this.theme, required this.message});

  final DashboardTheme theme;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final url = message.attachmentUrl;
    // Opaque accent/onAccent for fromMe, surface/onSurface otherwise —
    // matches the plain-text bubble and _PropertyPreviewBubble above. A
    // translucent accent tint over theme.background stays dark in Midnight
    // (background is navy there), so onSurface (always navy) text on it
    // used to be unreadable for outgoing messages.
    final bubbleColor = message.fromMe ? theme.accent : theme.surface;
    final onBubbleColor = message.fromMe ? theme.onAccent : theme.onSurface;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (url != null)
            Semantics(button: true, label: 'View photo', child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PropertyGalleryScreen(images: [url], initialIndex: 0, title: 'Photo')),
              ),
              child: PropertyImage(path: url, height: 180, width: double.infinity, fit: BoxFit.cover),
            )),
          if (message.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Text(message.text, style: AppTextStyles.body(color: onBubbleColor, size: 14)),
            ),
        ],
      ),
    );
  }
}

/// The quoted message at the top of a reply: who wrote it and a line or two
/// of its text, with a bar on the left. [color] is the text colour of
/// whatever it's drawn on (the bubble's, or the reply bar's).
class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.author, required this.text, required this.color});

  final String author;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: color.withValues(alpha: 0.6), width: 3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body(color: color, size: 12, weight: FontWeight.w700)),
          Text(
            text.isEmpty ? 'Message' : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body(color: color.withValues(alpha: 0.8), size: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Drag a message to the right to reply to it (a reply arrow appears as it
/// moves; letting go past the threshold replies), and long-press or
/// right-click it for Copy / Reply.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.enabled,
    required this.iconColor,
    required this.onReply,
    required this.onLongPress,
    required this.child,
  });

  final bool enabled;
  final Color iconColor;
  final VoidCallback onReply;
  final VoidCallback onLongPress;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const _threshold = 56.0;
  static const _max = 76.0;
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: widget.onLongPress,
      onSecondaryTap: widget.onLongPress,
      onHorizontalDragUpdate: widget.enabled
          ? (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, _max))
          : null,
      onHorizontalDragEnd: widget.enabled
          ? (_) {
              if (_dx >= _threshold) {
                HapticFeedback.selectionClick();
                widget.onReply();
              }
              setState(() => _dx = 0);
            }
          : null,
      onHorizontalDragCancel: () => setState(() => _dx = 0),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_dx > 8)
            Opacity(
              opacity: (_dx / _threshold).clamp(0.0, 1.0),
              child: Icon(Icons.reply_rounded, color: widget.iconColor, size: 22),
            ),
          AnimatedContainer(
            duration: Duration(milliseconds: _dx == 0 ? 180 : 0),
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// One entry in the message list: the bubble for its kind of message, the
/// quote it replies to, swipe-to-reply and long-press actions, and, under
/// our own messages, "Sending…", "Not sent · Tap to retry" or "Seen".
class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.theme,
    required this.message,
    required this.showSeen,
    required this.quoteAuthor,
    required this.swipeable,
    required this.canReply,
    required this.onReply,
    required this.onLongPress,
    required this.onRetry,
  });

  final DashboardTheme theme;
  final ChatMessage message;

  /// Only our last read message shows "Seen", as in other chat apps.
  final bool showSeen;
  final String Function(MessageQuote quote) quoteAuthor;

  /// False for system notices and for a chat not backed by a server thread.
  final bool swipeable;
  final bool canReply;
  final VoidCallback onReply;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.72;
    final alignment = message.fromMe ? Alignment.centerRight : Alignment.centerLeft;
    Widget bubble = switch (message.type) {
      MessageType.system => _SystemNotice(theme: theme, text: message.text),
      MessageType.propertyPreview => Align(alignment: alignment, child: _PropertyPreviewBubble(theme: theme, message: message)),
      MessageType.image => Align(alignment: alignment, child: _ImageMessageBubble(theme: theme, message: message)),
      _ => Align(
        alignment: alignment,
        child: _TextBubble(theme: theme, message: message, maxWidth: maxBubbleWidth, quoteAuthor: quoteAuthor),
      ),
    };
    // A photo sent as a reply shows what it answers above it.
    if (message.type == MessageType.image && message.replyTo != null) {
      bubble = Column(
        crossAxisAlignment: message.fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
            decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(12)),
            child: _QuoteBlock(author: quoteAuthor(message.replyTo!), text: message.replyTo!.preview, color: theme.onSurface),
          ),
          bubble,
        ],
      );
    }
    if (swipeable) {
      bubble = _SwipeToReply(
        enabled: canReply,
        iconColor: theme.foreground,
        onReply: onReply,
        onLongPress: onLongPress,
        child: bubble,
      );
    }

    final statusLabel = !message.fromMe
        ? null
        : switch (message.sendState) {
            SendState.sending => 'Sending…',
            SendState.failed => 'Not sent · Tap to retry',
            SendState.sent => showSeen ? 'Seen' : null,
          };
    if (statusLabel == null) return bubble;
    final failed = message.sendState == SendState.failed;
    return GestureDetector(
      onTap: failed ? onRetry : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Opacity(opacity: message.sendState == SendState.sent ? 1 : 0.6, child: bubble),
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 8, top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Only the icon is red; the label stays theme.foreground on
                // theme.background.
                if (failed) ...[
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFD64545), size: 14),
                  const SizedBox(width: 4),
                ],
                Text(
                  statusLabel,
                  style: AppTextStyles.body(
                    color: theme.foreground.withValues(alpha: failed ? 0.85 : 0.45),
                    size: 11,
                    weight: failed ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An automatic notice in the conversation, centred rather than drawn as a
/// bubble. theme.surface/onSurface are a fixed contrast pair in every
/// DashboardTheme.
class _SystemNotice extends StatelessWidget {
  const _SystemNotice({required this.theme, required this.text});

  final DashboardTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline_rounded, color: theme.onSurface, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: AppTextStyles.body(color: theme.onSurface, size: 12.5, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A text message: accent/onAccent for ours, surface/onSurface for theirs,
/// with the quoted message above the text when it is a reply.
class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.theme, required this.message, required this.maxWidth, required this.quoteAuthor});

  final DashboardTheme theme;
  final ChatMessage message;
  final double maxWidth;
  final String Function(MessageQuote quote) quoteAuthor;

  @override
  Widget build(BuildContext context) {
    final textColor = message.fromMe ? theme.onAccent : theme.onSurface;
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: message.fromMe ? theme.accent : theme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.replyTo != null)
            _QuoteBlock(author: quoteAuthor(message.replyTo!), text: message.replyTo!.preview, color: textColor),
          Text(message.text, style: AppTextStyles.body(color: textColor, size: 14)),
        ],
      ),
    );
  }
}

/// Above the input while replying: what is being replied to, and a button
/// to cancel. theme.surface/onSurface are a fixed contrast pair in every
/// DashboardTheme.
class _ReplyPreviewBar extends StatelessWidget {
  const _ReplyPreviewBar({required this.theme, required this.author, required this.preview, required this.onCancel});

  final DashboardTheme theme;
  final String author;
  final String preview;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, color: theme.onSurface, size: 18),
          const SizedBox(width: 8),
          Expanded(child: _QuoteBlock(author: author, text: preview, color: theme.onSurface)),
          IconButton(
            tooltip: 'Cancel reply',
            onPressed: onCancel,
            icon: Icon(Icons.close_rounded, color: theme.onSurface, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Replaces the input when this admin can no longer reply here, saying
/// why. theme.surface/onSurface are a fixed contrast pair in every
/// DashboardTheme.
class _AccessNotice extends StatelessWidget {
  const _AccessNotice({required this.theme, required this.text});

  final DashboardTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: theme.onSurface, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: AppTextStyles.body(color: theme.onSurface, size: 13.5, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// The input row: saved replies (admins in a support chat), send a photo,
/// the text field, and the send button. Icons are theme.foreground on
/// theme.background; the field is onSurface text on a surface fill.
class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.theme,
    required this.controller,
    required this.focusNode,
    required this.sendingImage,
    required this.onPickImage,
    required this.onSend,
    this.onSavedReplies,
  });

  final DashboardTheme theme;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sendingImage;
  final VoidCallback onPickImage;
  final VoidCallback onSend;

  /// Null hides the saved-replies button.
  final VoidCallback? onSavedReplies;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          if (onSavedReplies != null)
            IconButton(
              onPressed: onSavedReplies,
              icon: Icon(Icons.bolt_rounded, color: theme.foreground),
              tooltip: 'Saved replies',
            ),
          IconButton(
            onPressed: sendingImage ? null : onPickImage,
            icon: sendingImage
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: theme.foreground))
                : Icon(Icons.add_photo_alternate_outlined, color: theme.foreground),
            tooltip: 'Send a photo',
          ),
          Expanded(
            child: PillTextField(
              hint: 'Type a message',
              controller: controller,
              focusNode: focusNode,
              fillColor: theme.surface,
              textColor: theme.onSurface,
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Send',
            child: Semantics(
              button: true,
              child: GestureDetector(
                onTap: onSend,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
                  child: Icon(Icons.send_rounded, color: theme.onAccent, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
