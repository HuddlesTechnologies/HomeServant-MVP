// The message model the chat screen renders, and where one of our own messages is on its way to the server.
part of '../chat_thread_screen.dart';

/// Where one of *our* messages is on its way to the server.
enum SendState { sending, sent, failed }

class ChatMessage {
  ChatMessage({
    required this.text,
    required this.fromMe,
    this.id,
    this.senderName,
    this.replyTo,
    this.type = MessageType.text,
    this.attachmentUrl,
    this.previewPropertyTitle,
    this.previewPropertyImageUrl,
    this.previewPropertyPrice,
    this.previewPropertyPriceUnit,
    this.read = false,
    this.sendState = SendState.sent,
  });

  final String text;
  final bool fromMe;
  final MessageType type;

  /// The server's id — null until one of our own messages is delivered.
  /// Only a delivered message can be replied to.
  String? id;
  final String? senderName;

  /// The message this one replies to, shown as a quote above its text.
  final MessageQuote? replyTo;

  /// Set only when [type] is [MessageType.image] — see backend
  /// Message.attachmentUrl.
  final String? attachmentUrl;
  final String? previewPropertyTitle;
  final String? previewPropertyImageUrl;
  final int? previewPropertyPrice;
  final String? previewPropertyPriceUnit;

  /// True once the other participant has read this message (see backend
  /// `Message.readAt`) — only ever rendered for [fromMe] bubbles, the way
  /// every social/messaging app shows "Seen" on your own last sent message.
  bool read;

  /// Only meaningful for [fromMe]: shown under the bubble as "Sending…" or
  /// "Not sent · Tap to retry", so a failed send never looks delivered.
  SendState sendState;
}
