import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/chat.dart' show MessageType;
import '../../api/models/marketplace_api.dart';
import '../../core/date_format.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../services/chat_socket_service.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_text_field.dart';
import '../Market place/models/order_options.dart';
import 'models/property.dart';
import 'widgets/property_image.dart';

class ChatMessage {
  ChatMessage({
    required this.text,
    required this.fromMe,
    this.type = MessageType.text,
    this.previewPropertyTitle,
    this.previewPropertyImageUrl,
    this.previewPropertyPrice,
    this.previewPropertyPriceUnit,
  });

  final String text;
  final bool fromMe;
  final MessageType type;
  final String? previewPropertyTitle;
  final String? previewPropertyImageUrl;
  final int? previewPropertyPrice;
  final String? previewPropertyPriceUnit;
}

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.theme,
    required this.contactName,
    this.initialMessages = const [],
    this.threadId,
    this.property,
    this.orderItem,
  });

  final DashboardTheme theme;
  final String contactName;

  /// Used only when [threadId] is null — a caller not yet wired to a real
  /// backend thread (currently just the Marketplace's vendor-order chat,
  /// which has no server-side thread to load).
  final List<ChatMessage> initialMessages;

  /// When set, this screen loads and sends real messages via
  /// `AppState.chat` instead of just holding [initialMessages] in memory.
  final String? threadId;

  /// The property this conversation is about, if any. When set, a tenant
  /// can book an inspection right from the chat instead of coordinating a
  /// time through free-form messages alone.
  final Property? property;

  /// The pickup order item this conversation is about, if any — set when
  /// a vendor opens a chat from VendorMessagesScreen. Lets the vendor mark
  /// the order fulfilled or cancel it without leaving the chat.
  final MarketplaceOrderItemApi? orderItem;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  late final List<ChatMessage> _messages;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  OrderItemStatus? _orderStatus;
  bool _loadingRemote = false;
  StreamSubscription<ChatSocketMessage>? _socketSubscription;

  @override
  void initState() {
    super.initState();
    _messages = List.of(widget.initialMessages);
    _orderStatus = widget.orderItem?.status;
    final threadId = widget.threadId;
    if (threadId != null) {
      _loadingRemote = true;
      unawaited(_loadRemoteMessages(threadId));
      _socketSubscription = context.read<AppState>().chatSocket.onNewMessage.listen(_onSocketMessage);
    }
  }

  /// Appends a message pushed live over the socket (see
  /// ChatSocketService) — only ever the *other* participant's, since the
  /// Gateway excludes the sender from its own broadcast, so there's no
  /// risk of double-adding whatever [_send] already appended locally.
  void _onSocketMessage(ChatSocketMessage event) {
    if (event.threadId != widget.threadId) return;
    final appState = context.read<AppState>();
    final senderId = event.message['senderId'] as String?;
    final body = event.message['body'] as String?;
    if (senderId == null || body == null || senderId == appState.userId) return;
    setState(
      () => _messages.add(
        ChatMessage(
          text: body,
          fromMe: false,
          type: event.message['type'] == 'propertyPreview' ? MessageType.propertyPreview : MessageType.text,
          previewPropertyTitle: event.message['previewPropertyTitle'] as String?,
          previewPropertyImageUrl: event.message['previewPropertyImageUrl'] as String?,
          previewPropertyPrice: event.message['previewPropertyPrice'] as int?,
          previewPropertyPriceUnit: event.message['previewPropertyPriceUnit'] as String?,
        ),
      ),
    );
    _scrollToBottom();
    unawaited(appState.chat.markRead(widget.threadId!));
  }

  Future<void> _loadRemoteMessages(String threadId) async {
    final appState = context.read<AppState>();
    try {
      final remote = await appState.chat.messages(threadId);
      unawaited(appState.chat.markRead(threadId));
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(
            remote.map(
              (m) => ChatMessage(
                text: m.body,
                fromMe: m.senderId == appState.userId,
                type: m.type,
                previewPropertyTitle: m.previewPropertyTitle,
                previewPropertyImageUrl: m.previewPropertyImageUrl,
                previewPropertyPrice: m.previewPropertyPrice,
                previewPropertyPriceUnit: m.previewPropertyPriceUnit,
              ),
            ),
          );
        _loadingRemote = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRemote = false);
    }
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? text]) async {
    final message = (text ?? _inputController.text).trim();
    if (message.isEmpty) return;
    setState(() {
      _messages.add(ChatMessage(text: message, fromMe: true));
      _inputController.clear();
    });
    _scrollToBottom();

    final threadId = widget.threadId;
    if (threadId == null) return;
    try {
      await context.read<AppState>().chat.send(threadId, message);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't send — try again.")));
    }
  }

  Future<void> _bookInspection() async {
    final property = widget.property;
    if (property == null) return;
    final theme = widget.theme;
    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: theme.accent)),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: theme.accent)),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    final scheduled = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final formatted = _formatScheduledDateTime(scheduled);
    _send("I'd like to book an inspection of ${property.title} on $formatted.");
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Inspection request sent for $formatted')));
  }

  Future<void> _setOrderStatus(OrderItemStatus status) async {
    final item = widget.orderItem;
    if (item == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().marketplaceOrders.respondToItem(item.id, status: status);
      if (!mounted) return;
      setState(() => _orderStatus = status);
      messenger.showSnackBar(SnackBar(content: Text('Order marked as ${status.label}')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final orderItem = widget.orderItem;
    final orderStatus = _orderStatus;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text(
          widget.contactName,
          style: AppTextStyles.heading(color: theme.foreground, size: 18),
        ),
        actions: [
          if (orderItem != null && orderStatus == OrderItemStatus.pending)
            PopupMenuButton<OrderItemStatus>(
              icon: Icon(Icons.more_vert_rounded, color: theme.foreground),
              onSelected: _setOrderStatus,
              itemBuilder: (context) => const [
                PopupMenuItem(value: OrderItemStatus.completed, child: Text('Mark Order Completed')),
                PopupMenuItem(value: OrderItemStatus.cancelled, child: Text('Cancel Order')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 680,
          child: Column(
            children: [
              if (orderItem != null && orderStatus != null)
                _OrderStatusBanner(theme: theme, item: orderItem, status: orderStatus),
              if (_loadingRemote) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    if (message.type == MessageType.propertyPreview) {
                      return Align(
                        alignment: message.fromMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: _PropertyPreviewBubble(theme: theme, message: message),
                      );
                    }
                    return Align(
                      alignment:
                          message.fromMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.72,
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: message.fromMe ? theme.accent : theme.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          message.text,
                          style: AppTextStyles.body(
                            color:
                                message.fromMe
                                    ? theme.onAccent
                                    : theme.onSurface,
                            size: 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.property != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _bookInspection,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.accent, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      icon: Icon(Icons.event_available_rounded, color: theme.accent, size: 18),
                      label: Text(
                        'Book Inspection',
                        style: AppTextStyles.body(color: theme.accent, size: 13.5, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: PillTextField(
                        hint: 'Type a message',
                        controller: _inputController,
                        fillColor: theme.surface,
                        textColor: theme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _send,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.send_rounded,
                          color: theme.onAccent,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formats a future date/time as "24 Oct at 10:00 AM" for the inspection
/// booking confirmation message. Deliberately kept local rather than routed
/// through `formatRelativeTime` — that helper measures elapsed time since
/// [date] (`DateTime.now().difference(date)`), which only makes sense for
/// timestamps in the past; [date] here is always a chosen future date, so
/// reusing it would show "Just now" for every booking regardless of when
/// it's actually scheduled.
String _formatScheduledDateTime(DateTime date) {
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${date.day} ${monthAbbreviations[date.month - 1]} at $hour12:$minute $period';
}

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
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: message.fromMe ? theme.accent.withValues(alpha: 0.12) : theme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.accent.withValues(alpha: 0.25)),
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
                  style: AppTextStyles.body(color: theme.onSurface, size: 14, weight: FontWeight.w700),
                ),
                if (price != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '₦${formatNaira(price)}${priceUnit != null ? '/${priceUnit.toLowerCase()}' : ''}',
                    style: AppTextStyles.body(color: theme.accent, size: 13, weight: FontWeight.w700),
                  ),
                ],
                if (message.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(message.text, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.8), size: 13)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderStatusBanner extends StatelessWidget {
  const _OrderStatusBanner({required this.theme, required this.item, required this.status});

  final DashboardTheme theme;
  final MarketplaceOrderItemApi item;
  final OrderItemStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.productName,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(color: theme.onSurface, size: 13, weight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: status.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(status.label, style: AppTextStyles.body(color: status.color, size: 11, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
