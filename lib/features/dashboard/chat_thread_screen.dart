import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../api/models/chat.dart' show HandoffKind, MessageQuote, MessageType, ThreadHandlingHistory, ThreadHandoff, ThreadParticipant, ThreadPersonRef;
import '../../api/models/marketplace_api.dart';
import '../../api/models/support_tools.dart' show SupportTopic;
import '../../core/date_format.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../services/chat_socket_service.dart';
import '../../api/models/booking.dart';
import '../../state/app_state.dart';
import '../../widgets/support_rating_card.dart';
import '../../widgets/contact_avatar.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/upload_picker.dart';
import '../Market place/models/order_options.dart';
import '../admin/widgets/support_tool_sheets.dart';
import '../admin/chat_transcript_pdf.dart';
import '../admin/admin_user_detail_screen.dart' show showAdminUserProfilePopup;
import 'models/property.dart';
import 'property_gallery_screen.dart';
import 'widgets/property_image.dart';

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

  /// Only meaningful for [fromMe]: shown as "Sending…", or "Not sent · Tap
  /// to retry" — a failed send used to leave the bubble looking delivered,
  /// with only a passing snackbar to say otherwise.
  SendState sendState;
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
    this.onReassign,
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

  /// Super admins viewing a support conversation they aren't handling:
  /// hand it to another admin (see reassignSupportThread). Shown even
  /// though the screen is otherwise read-only for them.
  final Future<void> Function()? onReassign;

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
  final _inputFocus = FocusNode();

  /// The message the next one sent will reply to (swipe it, or long-press
  /// → Reply); shown above the input with a button to cancel.
  ChatMessage? _replyingTo;

  /// The property this tenant–landlord chat is about, once the tenant has
  /// paid (from the thread summary) — pinned above the messages.
  Property? _bookedProperty;

  MessageQuote _quoteOf(ChatMessage m) => MessageQuote(
    id: m.id!,
    body: m.text,
    isImage: m.type == MessageType.image,
    senderId: m.fromMe ? context.read<AppState>().userId : null,
    senderName: m.fromMe ? 'You' : (m.senderName ?? widget.contactName),
  );

  /// Who a quote is from, as the reader sees it.
  String _quoteAuthor(MessageQuote q) =>
      q.senderId != null && q.senderId == context.read<AppState>().userId ? 'You' : (q.senderName ?? widget.contactName);

  void _startReply(ChatMessage m) {
    if (m.id == null || _readOnly) return;
    setState(() => _replyingTo = m);
    _inputFocus.requestFocus();
  }

  /// The booked property's full details in a sheet over the chat, so either
  /// side can check them without leaving the conversation.
  Future<void> _showPropertyPopup(Property property) {
    final theme = widget.theme;
    final images = [property.image, ...property.galleryImages].where((p) => p.isNotEmpty).toSet().toList();
    // theme.surface/onSurface: a fixed light-surface/navy-text pair in every
    // DashboardTheme (see CLAUDE.md).
    final text = theme.onSurface;
    Widget fact(IconData icon, String label) => Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: text.withValues(alpha: 0.75), size: 17),
          const SizedBox(width: 5),
          Text(label, style: AppTextStyles.body(color: text, size: 13, weight: FontWeight.w600)),
        ],
      ),
    );
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Property details', style: AppTextStyles.heading(color: text, size: 17)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: text),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  if (images.isNotEmpty)
                    SizedBox(
                      height: 210,
                      child: PageView(
                        children: [
                          for (var i = 0; i < images.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Semantics(
                                button: true,
                                label: 'View photo',
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PropertyGalleryScreen(images: images, initialIndex: i, title: property.title),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: PropertyImage(path: images[i], width: double.infinity, height: 210),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (images.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Swipe for ${images.length - 1} more photo${images.length == 2 ? '' : 's'}',
                        style: AppTextStyles.body(color: text.withValues(alpha: 0.7), size: 12),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(property.title, style: AppTextStyles.heading(color: text, size: 19)),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (property.unitAddress?.isNotEmpty ?? false) property.unitAddress!,
                      _placeLine(property),
                    ].join(' · '),
                    style: AppTextStyles.body(color: text.withValues(alpha: 0.8), size: 13.5),
                  ),
                  if (property.listingNumber != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Listing #${property.listingNumber}', style: AppTextStyles.body(color: text.withValues(alpha: 0.7), size: 12.5)),
                    ),
                  const SizedBox(height: 12),
                  Text(property.priceLabel, style: AppTextStyles.heading(color: text, size: 17)),
                  const SizedBox(height: 10),
                  Wrap(
                    children: [
                      fact(Icons.home_work_outlined, property.category),
                      fact(Icons.bed_outlined, '${property.bedrooms} bed${property.bedrooms == 1 ? '' : 's'}'),
                      fact(Icons.bathtub_outlined, '${property.bathrooms} bath${property.bathrooms == 1 ? '' : 's'}'),
                    ],
                  ),
                  if (property.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('About this property', style: AppTextStyles.body(color: text, size: 14, weight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(property.description, style: AppTextStyles.body(color: text.withValues(alpha: 0.85), size: 13.5)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press (or right-click on the web): Copy and Reply.
  Future<void> _showMessageActions(ChatMessage m) async {
    final theme = widget.theme;
    final canCopy = m.text.trim().isNotEmpty;
    final canReply = m.id != null && !_readOnly;
    if (!canCopy && !canReply) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      // theme.surface/onSurface: a fixed light-surface/navy-text pair in
      // every DashboardTheme (see CLAUDE.md).
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (canCopy)
              ListTile(
                leading: Icon(Icons.copy_rounded, color: theme.onSurface),
                title: Text('Copy', style: AppTextStyles.body(color: theme.onSurface, size: 15, weight: FontWeight.w600)),
                onTap: () => Navigator.of(context).pop('copy'),
              ),
            if (canReply)
              ListTile(
                leading: Icon(Icons.reply_rounded, color: theme.onSurface),
                title: Text('Reply', style: AppTextStyles.body(color: theme.onSurface, size: 15, weight: FontWeight.w600)),
                onTap: () => Navigator.of(context).pop('reply'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied'), duration: Duration(seconds: 1)));
    } else if (action == 'reply') {
      _startReply(m);
    }
  }
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
  bool _sendingImage = false;
  StreamSubscription<String>? _claimedSubscription;
  StreamSubscription<String>? _accessRevokedSubscription;
  StreamSubscription<void>? _reconnectedSubscription;

  /// Set once an admin loses the ability to reply here while the screen is
  /// open — another admin took the support conversation over, or it was
  /// transferred away or resolved. Turns the screen read-only and explains
  /// why, instead of leaving a composer whose sends the server now refuses.
  String? _accessNotice;

  bool get _readOnly => widget.readOnly || _accessNotice != null;

  /// Support threads, for the handling admin and super admins only: who
  /// took the conversation up and every hand-off since. Null when not
  /// applicable (or not allowed) — the history UI is simply not shown.
  ThreadHandlingHistory? _history;

  /// Admin side of a support chat: what the customer said it's about when
  /// they opened it (or what an admin has since set it to).
  SupportTopic? _supportTopic;
  bool _isSupportThread = false;

  /// Customer side: this resolved support chat can still be rated.
  bool _canRate = false;

  /// Customer side: an open support chat they can end themselves.
  bool _canEndSupport = false;

  /// Customer: ends their support conversation after confirming.
  Future<void> _endSupportChat() async {
    final threadId = widget.threadId;
    if (threadId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('End this chat?', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
        content: Text(
          "Our team won't be able to reply here any more. If you need help again, start a new chat from Contact Support.",
          style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.75), size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep chatting', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600)),
          ),
          TextButton(
            style: TextButton.styleFrom(backgroundColor: AppColors.navy),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('End chat', style: AppTextStyles.body(color: Colors.white, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().chat.endSupportThread(threadId);
      await _refreshAccess();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openTriage() async {
    final threadId = widget.threadId;
    if (threadId == null) return;
    try {
      final summary = await context.read<AppState>().chat.summary(threadId);
      if (!mounted) return;
      await showTriageSheet(context, threadId, topic: summary.supportTopic, priority: summary.priority);
      // The topic may have just changed — keep the banner in step.
      if (mounted) unawaited(_refreshAccess());
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// The admin's tools for this chat, in app-bar order: calling and editing
  /// the customer (any admin chat with a customer on it), then the support
  /// tools (handling admin and super admins only — see [_history]).
  List<({String id, String label, IconData icon})> get _adminTools {
    if (!context.read<AppState>().role.isAdmin) return const [];
    final customerId = widget.adminViewOfUserId;
    return [
      if (customerId != null && !widget.readOnly)
        (id: 'call', label: 'Call customer', icon: Icons.call_outlined),
      // Oversight views can't call, but can see the calls made.
      if (widget.readOnly) (id: 'calls', label: 'Calls from this chat', icon: Icons.phone_callback_outlined),
      if (customerId != null && !widget.readOnly)
        (id: 'edit', label: 'Edit customer details', icon: Icons.manage_accounts_outlined),
      if (_history != null) ...[
        (id: 'customer', label: 'Customer details', icon: Icons.badge_outlined),
        (id: 'notes', label: 'Internal notes', icon: Icons.sticky_note_2_outlined),
        (id: 'triage', label: 'Topic & priority', icon: Icons.flag_outlined),
        (id: 'history', label: 'Handling history', icon: Icons.history_rounded),
      ],
    ];
  }

  Future<void> _runAdminTool(String id) async {
    final threadId = widget.threadId!;
    switch (id) {
      case 'call':
        await showCallCustomerSheet(context, threadId, customerName: widget.contactName);
      case 'calls':
        await showCallCustomerSheet(context, threadId, customerName: widget.contactName, canCall: false);
      case 'edit':
        // The full profile, with exactly the edits this admin's level allows
        // (the server enforces the same levels).
        await showAdminUserProfilePopup(context, userId: widget.adminViewOfUserId!, title: 'Customer Details', showMessageAction: false);
        // A name or phone change should show in the info panel right away.
        if (mounted && _recipientDetail != null) {
          setState(() => _recipientDetail = null);
          if (_infoPanelOpen) unawaited(_loadRecipientDetail());
        }
      case 'customer':
        await showCustomerContextSheet(context, threadId);
      case 'notes':
        await showSupportNotesSheet(context, threadId);
      case 'triage':
        await _openTriage();
      default:
        _showHistorySheet();
    }
  }

  /// Drops the chosen saved reply into the message box (appending to any
  /// text already there) for the admin to adjust before sending.
  Future<void> _insertSavedReply() async {
    final body = await showSavedRepliesSheet(context);
    if (body == null || !mounted) return;
    final current = _inputController.text.trimRight();
    final text = current.isEmpty ? body : '$current\n$body';
    _inputController.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  void _showHistorySheet() {
    final history = _history;
    if (history == null) return;
    final myId = context.read<AppState>().userId;
    // White sheet, navy text (AppColors) — the admin console's palette.
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            children: [
              Text('Handling history', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
              const SizedBox(height: 4),
              Text(
                'Who has handled this conversation, oldest first.',
                style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.65), size: 13),
              ),
              const SizedBox(height: 16),
              if (history.entries.isEmpty)
                Text(
                  history.firstHandler != null
                      ? '${_capitalise(_personName(history.firstHandler, myId))} took up this conversation.'
                      : 'Nobody has taken up this conversation yet.',
                  style: AppTextStyles.body(color: AppColors.navy, size: 14),
                ),
              // Conversations claimed before claims were recorded start
              // with a transfer — say who had it first.
              if (history.entries.isNotEmpty &&
                  history.entries.first.kind != HandoffKind.claim &&
                  history.entries.first.kind != HandoffKind.autoAssign &&
                  history.firstHandler != null)
                _HistoryRow(
                  text: '${_capitalise(_personName(history.firstHandler, myId))} took up this conversation',
                  time: null,
                  isLast: false,
                ),
              for (var i = 0; i < history.entries.length; i++)
                _HistoryRow(
                  text: _describeHandoff(history.entries[i], myId),
                  time: _handoffTime(history.entries[i].at),
                  isLast: false,
                ),
              _HistoryRow(
                text: history.currentAdmin != null
                    ? 'Currently assigned to ${_personName(history.currentAdmin, myId)}'
                    : 'Not currently assigned',
                time: null,
                isLast: true,
                emphasised: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadHistory() async {
    final threadId = widget.threadId;
    if (threadId == null) return;
    try {
      final history = await context.read<AppState>().chat.handlingHistory(threadId);
      if (mounted) setState(() => _history = history);
    } on ApiException {
      if (mounted) setState(() => _history = null);
    }
  }

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
      // Messages pushed while the socket was down were missed — refetch.
      _reconnectedSubscription = chatSocket.onReconnected.listen((_) {
        unawaited(_loadRemoteMessages(threadId));
        unawaited(_refreshAccess());
      });
      // Tenant/landlord threads can be closed by the payment rules (not
      // paid yet, or refunded) — check up front so the composer is
      // replaced by the reason instead of failing on send.
      unawaited(_refreshAccess());
      if (context.read<AppState>().role.isAdmin) {
        // A claim or transfer of *this* thread may have just taken it away
        // from this admin — re-check rather than guess from the event.
        _claimedSubscription = chatSocket.onThreadClaimed.listen((id) {
          if (id == threadId) {
            _refreshAccess();
            _loadHistory();
          }
        });
        _accessRevokedSubscription = chatSocket.onAccessRevoked.listen((id) {
          if (id == threadId) {
            _refreshAccess();
            _loadHistory();
          }
        });
        unawaited(_loadHistory());
      }
    }
  }

  /// Asks the server whether the caller can still reply here (see backend
  /// ChatService.getThreadSummary) and updates [_accessNotice]: for a
  /// tenant/landlord, whether the payment rules have closed the thread;
  /// for an admin, also whether the support conversation moved on.
  Future<void> _refreshAccess() async {
    final threadId = widget.threadId;
    if (threadId == null || widget.readOnly) return;
    final appState = context.read<AppState>();
    final isAdmin = appState.role.isAdmin;
    String? notice;
    try {
      final summary = await appState.chat.summary(threadId);
      if (mounted) {
        setState(() {
          _canRate = summary.canRate;
          _canEndSupport = !isAdmin && summary.isSupport && !summary.resolved;
          _isSupportThread = summary.isSupport;
          _supportTopic = summary.supportTopic;
          _bookedProperty = summary.bookedProperty;
        });
      }
      if (!isAdmin && summary.isSupport && summary.resolved) {
        notice = 'This conversation has ended. Start a new one from Contact Support if you still need help.';
      } else if (summary.lockedReason != null) {
        notice = summary.lockedReason;
      } else if (isAdmin && !summary.canReply) {
        final assigned = summary.assignedAdmin;
        notice = summary.resolved
            ? 'This conversation has been resolved.'
            : assigned != null && assigned.id != appState.userId
            ? 'This conversation is now handled by ${assigned.displayName}.'
            : "You can't reply to this conversation anymore.";
      }
    } on ApiException {
      // A non-admin's summary failing is just a network hiccup — sends
      // are still checked server-side, so don't lock the screen for it.
      if (!isAdmin) return;
      notice = "You don't have access to this conversation anymore.";
    }
    if (!mounted) return;
    setState(() => _accessNotice = notice);
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
    if (body == null) return;
    final isSystem = event.message['type'] == 'SYSTEM';
    // A SYSTEM notice has no sender and goes to both sides; anything else
    // from us was already echoed locally by [_send].
    if (!isSystem && (senderId == null || senderId == appState.userId)) return;
    // The raw type string here is Prisma's enum member as-is (TEXT /
    // PROPERTY_PREVIEW / IMAGE) — this previously compared against
    // 'propertyPreview', which the backend never actually sends, so a
    // live-pushed property-preview message silently never rendered as its
    // card (see ChatMessage._messageTypeFromApi's doc comment for the same
    // fix on the initial-load path).
    final type = switch (event.message['type']) {
      'PROPERTY_PREVIEW' => MessageType.propertyPreview,
      'IMAGE' => MessageType.image,
      'SYSTEM' => MessageType.system,
      _ => MessageType.text,
    };
    setState(
      () => _messages.add(
        ChatMessage(
          text: body,
          fromMe: false,
          type: type,
          id: event.message['id'] as String?,
          senderName: (event.message['sender'] as Map<String, dynamic>?)?['fullName'] as String?,
          replyTo: MessageQuote.fromApi(event.message['replyTo'] as Map<String, dynamic>?),
          attachmentUrl: event.message['attachmentUrl'] as String?,
          previewPropertyTitle: event.message['previewPropertyTitle'] as String?,
          previewPropertyImageUrl: event.message['previewPropertyImageUrl'] as String?,
          previewPropertyPrice: event.message['previewPropertyPrice'] as int?,
          previewPropertyPriceUnit: event.message['previewPropertyPriceUnit'] as String?,
        ),
      ),
    );
    _scrollToBottom();
    unawaited(appState.chat.markRead(widget.threadId!));
    // A system notice usually means messaging just closed (a refund or
    // rejection) — swap the composer for the reason right away.
    if (isSystem) unawaited(_refreshAccess());
  }

  Future<void> _loadRemoteMessages(String threadId) async {
    final appState = context.read<AppState>();
    try {
      final remote = await appState.chat.messages(threadId);
      unawaited(appState.chat.markRead(threadId));
      if (!mounted) return;
      // Our own not-yet-delivered messages aren't on the server — keep
      // them (still sending, or failed and waiting for a retry).
      final unsent = _messages.where((m) => m.fromMe && m.sendState != SendState.sent).toList();
      setState(() {
        _messages
          ..clear()
          ..addAll(
            remote.map(
              (m) => ChatMessage(
                text: m.body,
                fromMe: m.senderId == appState.userId,
                type: m.type,
                id: m.id,
                senderName: m.senderName,
                replyTo: m.replyTo,
                attachmentUrl: m.attachmentUrl,
                previewPropertyTitle: m.previewPropertyTitle,
                previewPropertyImageUrl: m.previewPropertyImageUrl,
                previewPropertyPrice: m.previewPropertyPrice,
                previewPropertyPriceUnit: m.previewPropertyPriceUnit,
                read: m.readAt != null,
              ),
            ),
          )
          ..addAll(unsent);
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
    _claimedSubscription?.cancel();
    _accessRevokedSubscription?.cancel();
    _reconnectedSubscription?.cancel();
    _socketSubscription?.cancel();
    _readSubscription?.cancel();
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _toggleInfoPanel() async {
    setState(() => _infoPanelOpen = !_infoPanelOpen);
    if (_infoPanelOpen) await _loadRecipientDetail();
  }

  Future<void> _loadRecipientDetail() async {
    final userId = widget.adminViewOfUserId;
    if (userId == null || _recipientDetail != null || _loadingRecipientDetail) return;
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
    // Resolving or handing it off ends this admin's ability to reply.
    if (mounted) await _refreshAccess();
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
    // Resolving or handing it off ends this admin's ability to reply.
    if (mounted) await _refreshAccess();
  }

  Future<void> _handleReassign() async {
    final onReassign = widget.onReassign;
    if (onReassign == null || _resolvingOrTransferring) return;
    setState(() => _resolvingOrTransferring = true);
    try {
      await onReassign();
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
    final body = (text ?? _inputController.text).trim();
    if (body.isEmpty) return;
    final threadId = widget.threadId;
    final message = ChatMessage(
      text: body,
      fromMe: true,
      replyTo: _replyingTo == null ? null : _quoteOf(_replyingTo!),
      sendState: threadId == null ? SendState.sent : SendState.sending,
    );
    setState(() {
      _messages.add(message);
      _inputController.clear();
      _replyingTo = null;
    });
    _scrollToBottom();
    if (threadId == null) return;
    await _deliver(message, threadId);
  }

  /// Sends [message] (already shown in the list) and records the outcome
  /// on it: sent, or failed with the reason in a snackbar.
  Future<void> _deliver(ChatMessage message, String threadId) async {
    try {
      final sent = await context
          .read<AppState>()
          .chat
          .send(threadId, message.text, attachmentUrl: message.attachmentUrl, replyToId: message.replyTo?.id);
      message.id = sent.id;
      if (mounted) setState(() => message.sendState = SendState.sent);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => message.sendState = SendState.failed);
      // e.g. the booking was refunded while this chat was open — show the
      // server's reason and swap the composer for it.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      unawaited(_refreshAccess());
    } catch (_) {
      if (!mounted) return;
      setState(() => message.sendState = SendState.failed);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't send — tap the message to retry.")));
    }
  }

  Future<void> _retry(ChatMessage message) async {
    final threadId = widget.threadId;
    if (threadId == null || message.sendState != SendState.failed || _readOnly) return;
    setState(() => message.sendState = SendState.sending);
    await _deliver(message, threadId);
  }

  /// Uploads through the same generic signed-upload flow every other image
  /// in this app uses (folder: 'chat'), then sends it as an IMAGE message.
  /// The bubble appears once the upload is done (the attach button shows
  /// progress meanwhile) and then tracks sending/sent/failed like text.
  Future<void> _pickAndSendImage() async {
    if (_sendingImage) return;
    final threadId = widget.threadId;
    if (threadId == null) return;
    final picked = await pickUpload(context);
    if (picked == null || !mounted) return;
    if (!picked.isImage) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only photos can be sent in chat.')));
      return;
    }
    setState(() => _sendingImage = true);
    String url;
    try {
      url = await context.read<AppState>().uploads.upload(file: picked, folder: 'chat');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't upload photo — try again.")));
        setState(() => _sendingImage = false);
      }
      return;
    }
    if (!mounted) return;
    final message = ChatMessage(
      text: '',
      fromMe: true,
      type: MessageType.image,
      attachmentUrl: url,
      replyTo: _replyingTo == null ? null : _quoteOf(_replyingTo!),
      sendState: SendState.sending,
    );
    setState(() {
      _messages.add(message);
      _sendingImage = false;
      _replyingTo = null;
    });
    _scrollToBottom();
    await _deliver(message, threadId);
  }

  Future<void> _bookInspection() async {
    final property = widget.property;
    if (property == null) return;
    final theme = widget.theme;
    final now = DateTime.now();
    final appState = context.read<AppState>();
    // Fresh, so a payment that just went through counts.
    try {
      await appState.loadMyBookings();
    } catch (_) {}
    if (!mounted) return;
    for (final b in appState.myBookings) {
      if (b.property.id == property.id && b.status == BookingStatus.inspectionConfirmed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              b.requestedDate != null
                  ? 'Your inspection is already confirmed for ${_formatScheduledDateTime(b.requestedDate!)}.'
                  : 'Your inspection is already confirmed.',
            ),
          ),
        );
        return;
      }
    }

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
    final booking = _inspectableBooking;
    final messenger = ScaffoldMessenger.of(context);
    if (booking == null) {
      // Nothing paid for yet: the landlord has no booking to confirm a date
      // on, so this can only be a question in the chat.
      _send("I'd like to inspect ${property.title} on $formatted. Is that possible?");
      messenger.showSnackBar(
        const SnackBar(content: Text('Sent as a message. Inspections are booked after you pay (Rent Now) — then choose your date here.')),
      );
      return;
    }
    // Records the date on the booking (this button used to only send a chat
    // message, so the landlord then had "no inspection date" to accept).
    // The server posts the note into this chat itself.
    try {
      await context.read<AppState>().proposeInspection(booking.id, scheduled);
      messenger.showSnackBar(SnackBar(content: Text('Inspection date sent to the landlord: $formatted')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// The tenant's paid booking for [ChatThreadScreen.property] that's still
  /// arranging an inspection, if any.
  Booking? get _inspectableBooking {
    final property = widget.property;
    if (property == null) return null;
    for (final b in context.read<AppState>().myBookings) {
      if (b.property.id == property.id &&
          (b.status == BookingStatus.paidAwaitingInspection || b.status == BookingStatus.inspectionProposed)) {
        return b;
      }
    }
    return null;
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
        titleSpacing: 0,
        title: Row(
          children: [
            ContactAvatar(
              participant: widget.otherParticipant,
              radius: 18,
              backgroundColor: theme.accent.withValues(alpha: 0.25),
              iconColor: theme.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.contactName,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.heading(color: theme.foreground, size: 18),
                  ),
                  if (widget.otherParticipant != null) _presenceLabel(widget.otherParticipant!, theme),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_canEndSupport)
            TextButton(
              onPressed: _endSupportChat,
              child: Text('End chat', style: AppTextStyles.body(color: theme.foreground, size: 14, weight: FontWeight.w700)),
            ),
          // Support tools — shown to the admin handling a support chat and
          // to super admins (the same people the handling history is for) —
          // plus calling and editing the customer, for any admin chat.
          if (widget.threadId != null && _adminTools.isNotEmpty && MediaQuery.of(context).size.width < 700)
            // Phone width: one menu instead of a row of icons. The menu is a
            // light Material surface, so items use onSurface (fixed navy).
            PopupMenuButton<String>(
              icon: Icon(Icons.support_agent_rounded, color: theme.foreground),
              tooltip: 'Support tools',
              onSelected: _runAdminTool,
              itemBuilder: (_) => [
                for (final tool in _adminTools)
                  PopupMenuItem(
                    value: tool.id,
                    child: Row(
                      children: [
                        Icon(tool.icon, color: theme.onSurface, size: 20),
                        const SizedBox(width: 12),
                        Text(tool.label, style: AppTextStyles.body(color: theme.onSurface, size: 14)),
                      ],
                    ),
                  ),
              ],
            )
          else if (widget.threadId != null)
            for (final tool in _adminTools)
              IconButton(
                onPressed: () => _runAdminTool(tool.id),
                icon: Icon(tool.icon, color: theme.foreground),
                tooltip: tool.label,
              ),
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
              // The popup menu itself is always a light Material surface
              // regardless of theme — theme.foreground flips to white on
              // Midnight and would be invisible here, so this uses
              // onSurface (fixed navy, paired with a light surface in
              // every theme).
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: OrderItemStatus.completed,
                  child: Text('Mark Order Completed', style: AppTextStyles.body(color: theme.onSurface, size: 14)),
                ),
                PopupMenuItem(
                  value: OrderItemStatus.cancelled,
                  child: Text('Cancel Order', style: AppTextStyles.body(color: Colors.redAccent, size: 14)),
                ),
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
              if (context.read<AppState>().role.isAdmin && _isSupportThread)
                _SupportTopicBanner(theme: theme, topic: _supportTopic),
              if (_history != null && _history!.lastHandoff != null)
                _HandoffBanner(
                  theme: theme,
                  history: _history!,
                  myId: context.read<AppState>().userId,
                  onViewHistory: _showHistorySheet,
                ),
              if (orderItem != null && orderStatus != null)
                _OrderStatusBanner(theme: theme, item: orderItem, status: orderStatus),
              if (widget.onReassign != null && !widget.isResolved)
                _ReassignBar(
                  theme: theme,
                  busy: _resolvingOrTransferring,
                  onReassign: _handleReassign,
                ),
              if (widget.showResolveTransferActions && !_readOnly)
                _ResolveTransferBar(
                  theme: theme,
                  isResolved: widget.isResolved,
                  busy: _resolvingOrTransferring,
                  onResolve: _handleResolve,
                  onTransfer: _handleTransfer,
                ),
              if (_loadingRemote) const LinearProgressIndicator(minHeight: 2),
              if (_bookedProperty != null)
                _BookedPropertyCard(
                  theme: theme,
                  property: _bookedProperty!,
                  onView: () => _showPropertyPopup(_bookedProperty!),
                ),
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
                    final statusLabel = !message.fromMe
                        ? null
                        : switch (message.sendState) {
                            SendState.sending => 'Sending…',
                            SendState.failed => 'Not sent · Tap to retry',
                            SendState.sent => showSeen ? 'Seen' : null,
                          };
                    Widget bubble;
                    if (message.type == MessageType.system) {
                      // Centred notice, not a bubble — theme.surface/onSurface
                      // is a fixed contrast pair in every DashboardTheme.
                      bubble = Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 480),
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline_rounded, color: theme.onSurface, size: 16),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  message.text,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.body(
                                    color: theme.onSurface,
                                    size: 12.5,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else if (message.type == MessageType.propertyPreview) {
                      bubble = Align(
                        alignment: message.fromMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: _PropertyPreviewBubble(theme: theme, message: message),
                      );
                    } else if (message.type == MessageType.image) {
                      bubble = Align(
                        alignment: message.fromMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: _ImageMessageBubble(theme: theme, message: message),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (message.replyTo != null)
                                _QuoteBlock(
                                  author: _quoteAuthor(message.replyTo!),
                                  text: message.replyTo!.preview,
                                  // Drawn in the bubble's own text colour.
                                  color: message.fromMe ? theme.onAccent : theme.onSurface,
                                ),
                              Text(
                                message.text,
                                style: AppTextStyles.body(
                                  color:
                                      message.fromMe
                                          ? theme.onAccent
                                          : theme.onSurface,
                                  size: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    // A photo sent as a reply shows what it answers above it.
                    if (message.type == MessageType.image && message.replyTo != null) {
                      bubble = Column(
                        crossAxisAlignment: message.fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                            decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(12)),
                            child: _QuoteBlock(author: _quoteAuthor(message.replyTo!), text: message.replyTo!.preview, color: theme.onSurface),
                          ),
                          bubble,
                        ],
                      );
                    }
                    // Swipe right to reply; long-press (right-click on the
                    // web) for Copy / Reply. Not on system notices.
                    if (message.type != MessageType.system && widget.threadId != null) {
                      bubble = _SwipeToReply(
                        enabled: message.id != null && !_readOnly,
                        iconColor: theme.foreground,
                        onReply: () => _startReply(message),
                        onLongPress: () => _showMessageActions(message),
                        child: bubble,
                      );
                    }
                    if (statusLabel == null) return bubble;
                    final failed = message.sendState == SendState.failed;
                    return GestureDetector(
                      onTap: failed ? () => _retry(message) : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Opacity(opacity: message.sendState == SendState.sent ? 1 : 0.6, child: bubble),
                          Padding(
                            padding: const EdgeInsets.only(right: 4, bottom: 8, top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Red is only the icon; the label stays
                                // theme.foreground on theme.background.
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
              if (_canRate && widget.threadId != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SupportRatingCard(theme: theme, threadId: widget.threadId!),
                ),
              if (_accessNotice != null)
                // theme.surface/onSurface: a fixed light-surface/navy-text
                // pair in every DashboardTheme (see CLAUDE.md).
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, color: theme.onSurface, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _accessNotice!,
                          style: AppTextStyles.body(color: theme.onSurface, size: 13.5, weight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_readOnly && _replyingTo != null)
                // theme.surface/onSurface: a fixed contrast pair in every
                // DashboardTheme.
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Icon(Icons.reply_rounded, color: theme.onSurface, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _QuoteBlock(
                          author: _replyingTo!.fromMe ? 'Replying to your message' : 'Replying to ${_replyingTo!.senderName ?? widget.contactName}',
                          text: _quoteOf(_replyingTo!).preview,
                          color: theme.onSurface,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel reply',
                        onPressed: () => setState(() => _replyingTo = null),
                        icon: Icon(Icons.close_rounded, color: theme.onSurface, size: 18),
                      ),
                    ],
                  ),
                ),
              if (!_readOnly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      if (_history != null)
                        IconButton(
                          onPressed: _insertSavedReply,
                          icon: Icon(Icons.bolt_rounded, color: theme.foreground),
                          tooltip: 'Saved replies',
                        ),
                      IconButton(
                        onPressed: _sendingImage ? null : _pickAndSendImage,
                        icon: _sendingImage
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: theme.foreground),
                              )
                            : Icon(Icons.add_photo_alternate_outlined, color: theme.foreground),
                        tooltip: 'Send a photo',
                      ),
                      Expanded(
                        child: PillTextField(
                          hint: 'Type a message',
                          controller: _inputController,
                          focusNode: _inputFocus,
                          fillColor: theme.surface,
                          textColor: theme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Tooltip(message: 'Send', child: Semantics(button: true, child: GestureDetector(
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
                      ))),
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

/// A super admin's view into someone else's support conversation: says
/// it's read-only and offers Reassign. theme.surface/onSurface is a fixed
/// light-surface/navy-text pair in every DashboardTheme (see CLAUDE.md);
/// the button uses the accent/onAccent pair.
String _personName(ThreadPersonRef? person, String? myId) {
  if (person == null) return 'a former admin';
  if (person.id == myId) return 'you';
  return person.displayName;
}

String _handoffTime(DateTime at) {
  final local = at.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${formatShortDate(local)}, $hh:$mm';
}

String _describeHandoff(ThreadHandoff entry, String? myId) {
  final to = _personName(entry.to, myId);
  final from = _personName(entry.from, myId);
  final by = _personName(entry.by, myId);
  return switch (entry.kind) {
    HandoffKind.claim => '${_capitalise(to)} took up this conversation',
    HandoffKind.transfer => '${_capitalise(from)} transferred it to $to',
    HandoffKind.reassign => '${_capitalise(by)} (super admin) reassigned it from $from to $to',
    HandoffKind.autoAssign => 'Auto assigned to $to by system admin',
  };
}

String _capitalise(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Admins only: what the customer is contacting support about, as they
/// picked it when opening the chat. theme.surface/onSurface is a fixed
/// light-surface/navy-text pair in every theme.
class _SupportTopicBanner extends StatelessWidget {
  const _SupportTopicBanner({required this.theme, required this.topic});

  final DashboardTheme theme;
  final SupportTopic? topic;

  @override
  Widget build(BuildContext context) {
    final topic = this.topic;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, color: theme.onSurface, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: topic == null
                    ? [const TextSpan(text: "The customer didn't pick a topic for this conversation.")]
                    : [
                        const TextSpan(text: 'Contacting support about: '),
                        TextSpan(text: topic.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(text: ' · ${topic.hint}'),
                      ],
              ),
              style: AppTextStyles.body(color: theme.onSurface, size: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown above the messages once a support conversation has changed
/// hands: who moved it to whom, and who first took it up.
/// theme.surface/onSurface is a fixed contrast pair in every theme.
class _HandoffBanner extends StatelessWidget {
  const _HandoffBanner({required this.theme, required this.history, required this.myId, required this.onViewHistory});

  final DashboardTheme theme;
  final ThreadHandlingHistory history;
  final String? myId;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    final last = history.lastHandoff!;
    final first = history.firstHandler;
    final current = history.currentAdmin;
    final handlingIt = current != null && current.id == myId;
    final headline = handlingIt
        ? switch (last.kind) {
            HandoffKind.reassign => 'Reassigned to you by ${_personName(last.by, myId)}',
            // Nobody handed it over — the system picked this admin.
            HandoffKind.autoAssign => 'Auto Assigned to you by system admin',
            _ => 'Transferred to you by ${_personName(last.from, myId)}',
          }
        : 'Now handled by ${_personName(current, myId)}';
    // "First taken up by" only adds anything once it has changed hands.
    final showFirst = first != null && !(last.kind == HandoffKind.autoAssign && history.entries.length == 1);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.swap_horiz_rounded, color: theme.onSurface, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$headline · ${_handoffTime(last.at)}',
                  style: AppTextStyles.body(color: theme.onSurface, size: 13, weight: FontWeight.w700),
                ),
                if (showFirst)
                  Text(
                    'First taken up by ${_personName(first, myId)}',
                    style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.7), size: 12),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onViewHistory,
            child: Text('History', style: AppTextStyles.body(color: theme.onSurface, size: 13, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _ReassignBar extends StatelessWidget {
  const _ReassignBar({required this.theme, required this.busy, required this.onReassign});

  final DashboardTheme theme;
  final bool busy;
  final VoidCallback onReassign;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, color: theme.onSurface, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Viewing as super admin',
              style: AppTextStyles.body(color: theme.onSurface, size: 12.5, weight: FontWeight.w600),
            ),
          ),
          ElevatedButton.icon(
            onPressed: busy ? null : onReassign,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accent,
              disabledBackgroundColor: theme.accent.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: Icon(Icons.swap_horiz_rounded, color: theme.onAccent, size: 16),
            label: Text('Reassign', style: AppTextStyles.body(color: theme.onAccent, size: 12.5, weight: FontWeight.w700)),
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

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.text, required this.time, required this.isLast, this.emphasised = false});

  final String text;
  final String? time;
  final bool isLast;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: emphasised ? AppColors.gold : AppColors.navy,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: AppColors.navy.withValues(alpha: 0.15))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: AppTextStyles.body(
                      color: AppColors.navy,
                      size: 14,
                      weight: emphasised ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  if (time != null)
                    Text(time!, style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.6), size: 12)),
                ],
              ),
            ),
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


/// Pinned above the messages in a tenant–landlord chat once the tenant has
/// paid: the property's photo, name, address and price, with View property.
/// theme.surface/onSurface (a fixed pair in every DashboardTheme), and the
/// button in theme.accent/onAccent.
class _BookedPropertyCard extends StatelessWidget {
  const _BookedPropertyCard({required this.theme, required this.property, required this.onView});

  final DashboardTheme theme;
  final Property property;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final text = theme.onSurface;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: PropertyImage(path: property.image, width: 64, height: 64),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(property.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body(color: text, size: 14, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  _placeLine(property),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(color: text.withValues(alpha: 0.8), size: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '${property.priceLabel} · ${property.bedrooms} bed · ${property.bathrooms} bath',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(color: text, size: 12, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onView,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text('View property', style: AppTextStyles.body(color: theme.onAccent, size: 12, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// "Lekki Phase 1, Lagos" — without repeating the state when the location
/// already ends with it.
String _placeLine(Property p) =>
    p.location.toLowerCase().trim().endsWith(p.state.toLowerCase().trim()) ? p.location : '${p.location}, ${p.state}';
