import 'dart:async';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../api/models/chat.dart' show MessageType, ThreadParticipant;
import '../../api/models/marketplace_api.dart';
import '../../core/date_format.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../services/chat_socket_service.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_text_field.dart';
import '../Market place/models/order_options.dart';
import '../admin/chat_transcript_pdf.dart';
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
    this.read = false,
  });

  final String text;
  final bool fromMe;
  final MessageType type;
  final String? previewPropertyTitle;
  final String? previewPropertyImageUrl;
  final int? previewPropertyPrice;
  final String? previewPropertyPriceUnit;

  /// True once the other participant has read this message (see backend
  /// `Message.readAt`) — only ever rendered for [fromMe] bubbles, the way
  /// every social/messaging app shows "Seen" on your own last sent message.
  bool read;
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
    this.adminViewOfUserId,
    this.showExportAction = false,
    this.otherParticipant,
    this.showResolveTransferActions = false,
    this.isResolved = false,
    this.onResolve,
    this.onTransfer,
    this.readOnly = false,
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

  /// Set only from an admin console call site — the other participant's
  /// user id, fetched lazily (via `AdminRepository.findUserDetail`) into a
  /// collapsible info panel the admin can toggle open while replying,
  /// instead of having to leave the chat to look someone up.
  final String? adminViewOfUserId;

  /// True to show a "download as PDF" action in the AppBar — an admin
  /// backing up/saving a conversation locally. Only ever passed `true` from
  /// an admin call site.
  final bool showExportAction;

  /// The other participant, carrying a presence snapshot (see
  /// ChatThread.otherParticipant) — when set, the AppBar shows "Active
  /// now" or "Last active X ago" under the contact name. Null for a caller
  /// that doesn't have a ChatThread on hand (e.g. a brand-new thread with
  /// no prior participant data) or a non-1:1 context.
  final ThreadParticipant? otherParticipant;

  /// True to render the "Mark as Resolved"/"Transfer" bar under the AppBar
  /// — only ever passed `true` from an admin's own Inbox (never from the
  /// shared Support Queue, and never for the read-only Chat Log viewer),
  /// since transferring/resolving only makes sense once a conversation is
  /// genuinely in that admin's inbox.
  final bool showResolveTransferActions;

  /// Only meaningful when [showResolveTransferActions] is true — swaps the
  /// action buttons for a plain green "Resolved" label once the thread's
  /// already resolved (nothing left to transfer or resolve again).
  final bool isResolved;

  final Future<void> Function()? onResolve;
  final Future<void> Function()? onTransfer;

  /// True for the super-admin Chat Log's history viewer — hides the input
  /// row and the resolve/transfer bar entirely so browsing another admin's
  /// past conversation can't be mistaken for actually replying to it.
  final bool readOnly;

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
  StreamSubscription<String>? _readSubscription;
  bool _infoPanelOpen = false;
  AdminUserDetail? _recipientDetail;
  bool _loadingRecipientDetail = false;
  String? _recipientDetailError;
  bool _exportingPdf = false;
  bool _resolvingOrTransferring = false;

  @override
  void initState() {
    super.initState();
    _messages = List.of(widget.initialMessages);
    _orderStatus = widget.orderItem?.status;
    final threadId = widget.threadId;
    if (threadId != null) {
      _loadingRemote = true;
      unawaited(_loadRemoteMessages(threadId));
      final chatSocket = context.read<AppState>().chatSocket;
      _socketSubscription = chatSocket.onNewMessage.listen(_onSocketMessage);
      _readSubscription = chatSocket.onRead.listen(_onSocketRead);
    }
  }

  /// The other participant just read this thread — flip every message we
  /// sent to "Seen" (backend markRead marks them all at once, so there's
  /// no per-message id to reconcile against).
  void _onSocketRead(String threadId) {
    if (threadId != widget.threadId) return;
    setState(() {
      for (final message in _messages) {
        if (message.fromMe) message.read = true;
      }
    });
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
                read: m.readAt != null,
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
    _readSubscription?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _toggleInfoPanel() async {
    setState(() => _infoPanelOpen = !_infoPanelOpen);
    final userId = widget.adminViewOfUserId;
    if (!_infoPanelOpen || userId == null || _recipientDetail != null || _loadingRecipientDetail) return;
    setState(() {
      _loadingRecipientDetail = true;
      _recipientDetailError = null;
    });
    try {
      final detail = await context.read<AppState>().admin.findUserDetail(userId);
      if (!mounted) return;
      setState(() {
        _recipientDetail = detail;
        _loadingRecipientDetail = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _recipientDetailError = e.message;
        _loadingRecipientDetail = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recipientDetailError = "Couldn't load this user's details.";
        _loadingRecipientDetail = false;
      });
    }
  }

  Future<void> _exportPdf() async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final doc = await buildChatTranscriptPdf(contactName: widget.contactName, messages: _messages);
      final bytes = await doc.save();
      final slug = widget.contactName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      await Printing.sharePdf(bytes: bytes, filename: 'chat_$slug.pdf');
    } catch (_) {
      if (mounted) messenger.showSnackBar(const SnackBar(content: Text("Couldn't export this chat.")));
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _handleResolve() async {
    final onResolve = widget.onResolve;
    if (onResolve == null || _resolvingOrTransferring) return;
    setState(() => _resolvingOrTransferring = true);
    try {
      await onResolve();
    } finally {
      if (mounted) setState(() => _resolvingOrTransferring = false);
    }
  }

  Future<void> _handleTransfer() async {
    final onTransfer = widget.onTransfer;
    if (onTransfer == null || _resolvingOrTransferring) return;
    setState(() => _resolvingOrTransferring = true);
    try {
      await onTransfer();
    } finally {
      if (mounted) setState(() => _resolvingOrTransferring = false);
    }
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
    final lastFromMeIndex = _messages.lastIndexWhere((m) => m.fromMe);
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.contactName,
              style: AppTextStyles.heading(color: theme.foreground, size: 18),
            ),
            if (widget.otherParticipant != null) _presenceLabel(widget.otherParticipant!, theme),
          ],
        ),
        actions: [
          if (widget.adminViewOfUserId != null)
            IconButton(
              onPressed: _toggleInfoPanel,
              icon: Icon(_infoPanelOpen ? Icons.info_rounded : Icons.info_outline_rounded, color: theme.foreground),
              tooltip: 'User info',
            ),
          if (widget.showExportAction)
            _exportingPdf
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: theme.foreground),
                    ),
                  )
                : IconButton(
                    onPressed: _exportPdf,
                    icon: Icon(Icons.download_rounded, color: theme.foreground),
                    tooltip: 'Export as PDF',
                  ),
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
              if (_infoPanelOpen)
                _RecipientInfoPanel(
                  theme: theme,
                  detail: _recipientDetail,
                  loading: _loadingRecipientDetail,
                  error: _recipientDetailError,
                ),
              if (orderItem != null && orderStatus != null)
                _OrderStatusBanner(theme: theme, item: orderItem, status: orderStatus),
              if (widget.showResolveTransferActions && !widget.readOnly)
                _ResolveTransferBar(
                  theme: theme,
                  isResolved: widget.isResolved,
                  busy: _resolvingOrTransferring,
                  onResolve: _handleResolve,
                  onTransfer: _handleTransfer,
                ),
              if (_loadingRemote) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    // Only the last message we sent ever shows "Seen" — the
                    // same convention every mainstream chat app uses, since
                    // a receipt on every past bubble would be noise.
                    // `lastFromMeIndex` is computed once per build (above),
                    // not rescanned per item, so this stays O(n) over the
                    // whole list instead of O(n²) as history grows.
                    final showSeen = message.fromMe && message.read && index == lastFromMeIndex;
                    final Widget bubble;
                    if (message.type == MessageType.propertyPreview) {
                      bubble = Align(
                        alignment: message.fromMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: _PropertyPreviewBubble(theme: theme, message: message),
                      );
                    } else {
                      bubble = Align(
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
                    }
                    if (!showSeen) return bubble;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        bubble,
                        Padding(
                          padding: const EdgeInsets.only(right: 4, bottom: 8, top: 2),
                          child: Text(
                            'Seen',
                            style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.45), size: 11),
                          ),
                        ),
                      ],
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
              if (!widget.readOnly)
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

/// "Active now" (green dot) or "Last active X ago", under the contact
/// name in the AppBar — the same presence snapshot ChatThreadListTile's
/// avatar dot already uses, just spelled out as text here since there's no
/// list of other threads' avatars to dot next to.
Widget _presenceLabel(ThreadParticipant participant, DashboardTheme theme) {
  if (participant.isOnline) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('Active now', style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 11.5)),
      ],
    );
  }
  final lastActiveAt = participant.lastActiveAt;
  if (lastActiveAt == null) return const SizedBox();
  return Text(
    'Last active ${formatRelativeTime(lastActiveAt)}',
    style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.5), size: 11.5),
  );
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

/// The literal "at the top of a chat there should be a section that says
/// mark as resolved" bar — a plain green "Resolved" label once [isResolved]
/// (nothing left to do), otherwise a "Mark as Resolved" button plus a
/// "Transfer" icon button. `theme.surface`/`theme.onSurface` are used
/// rather than `theme.background`/`theme.foreground` since this sits as
/// its own raised bar (same convention as [_OrderStatusBanner]/
/// `_RecipientInfoPanel`), and `onSurface` stays navy-on-light-surface
/// across every `DashboardTheme` variant.
class _ResolveTransferBar extends StatelessWidget {
  const _ResolveTransferBar({
    required this.theme,
    required this.isResolved,
    required this.busy,
    required this.onResolve,
    required this.onTransfer,
  });

  final DashboardTheme theme;
  final bool isResolved;
  final bool busy;
  final VoidCallback onResolve;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: isResolved
          ? Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Text('Resolved', style: AppTextStyles.body(color: Colors.green, size: 13.5, weight: FontWeight.w700)),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onResolve,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.green),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 16),
                    label: Text(
                      'Mark as Resolved',
                      style: AppTextStyles.body(color: Colors.green, size: 12.5, weight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: busy ? null : onTransfer,
                  icon: Icon(Icons.swap_horiz_rounded, color: theme.onSurface),
                  tooltip: 'Transfer to another admin',
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

/// Collapsible box showing everything on file about the person an admin is
/// chatting with — toggled via the AppBar's info icon, so an admin can
/// check who they're replying to without leaving the conversation.
class _RecipientInfoPanel extends StatelessWidget {
  const _RecipientInfoPanel({required this.theme, required this.detail, required this.loading, required this.error});

  final DashboardTheme theme;
  final AdminUserDetail? detail;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : error != null
              ? Text(error!, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 12.5))
              : detail == null
                  ? const SizedBox()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.fullName?.isNotEmpty == true ? detail.fullName! : detail.email,
                          style: AppTextStyles.body(color: theme.onSurface, size: 14.5, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        _InfoRow('Email', detail.email, theme),
                        if (detail.phoneNumber != null && detail.phoneNumber!.isNotEmpty)
                          _InfoRow('Phone', detail.phoneNumber!, theme),
                        _InfoRow('Role', detail.role.adminLabel, theme),
                        if (detail.houseAddress != null && detail.houseAddress!.isNotEmpty)
                          _InfoRow('Address', detail.houseAddress!, theme),
                        if (detail.vendorBusinessName != null) _InfoRow('Shop', detail.vendorBusinessName!, theme),
                        _InfoRow('Joined', formatShortDate(detail.createdAt), theme),
                        if (detail.deactivatedAt != null) _InfoRow('Status', 'Deactivated', theme),
                      ],
                    ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, this.theme);

  final String label;
  final String value;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.5), size: 12)),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body(color: theme.onSurface, size: 12.5, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
