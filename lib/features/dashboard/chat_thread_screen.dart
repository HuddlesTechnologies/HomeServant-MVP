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
import '../../models/user_role.dart';
import '../../services/chat_socket_service.dart';
import '../../api/models/booking.dart';
import '../../state/app_state.dart';
import '../../widgets/confirm_sheet.dart';
import '../../widgets/support_rating_card.dart';
import '../../widgets/contact_avatar.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/upload_picker.dart';
import '../marketplace/models/order_options.dart';
import '../admin/widgets/support_tool_sheets.dart';
import '../admin/chat_transcript_pdf.dart';
import '../admin/admin_user_detail_screen.dart' show showAdminUserProfilePopup;
import 'legal/tenancy_agreement_view_screen.dart';
import 'models/property.dart';
import 'property_gallery_screen.dart';
import 'widgets/property_image.dart';

part 'chat_thread/chat_message.dart';
part 'chat_thread/message_widgets.dart';
part 'chat_thread/support_widgets.dart';
part 'chat_thread/property_widgets.dart';

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
    final isTenant = context.read<AppState>().role == UserRole.tenant;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => _PropertyDetailsSheet(
        theme: theme,
        property: property,
        showTenantStatus: isTenant,
        // The in-chat date picker needs the chat's own property.
        onBookInspection: widget.property?.id == property.id
            ? () {
                Navigator.of(sheetContext).pop();
                _bookInspection();
              }
            : null,
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
    // The socket sends Prisma's MessageType names as-is, in upper case,
    // the same as the REST API (see _messageTypeFromApi in chat.dart).
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
    // Records the date on the booking, so the landlord has a date to accept
    // or decline. The server posts the note into this chat itself.
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
                    return _MessageRow(
                      theme: theme,
                      message: message,
                      // lastFromMeIndex is found once per build, so this
                      // stays linear however long the history gets.
                      showSeen: message.fromMe && message.read && index == lastFromMeIndex,
                      quoteAuthor: _quoteAuthor,
                      swipeable: message.type != MessageType.system && widget.threadId != null,
                      canReply: message.id != null && !_readOnly,
                      onReply: () => _startReply(message),
                      onLongPress: () => _showMessageActions(message),
                      onRetry: () => _retry(message),
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
              if (_accessNotice != null) _AccessNotice(theme: theme, text: _accessNotice!),
              if (!_readOnly && _replyingTo != null)
                _ReplyPreviewBar(
                  theme: theme,
                  author: _replyingTo!.fromMe ? 'Replying to your message' : 'Replying to ${_replyingTo!.senderName ?? widget.contactName}',
                  preview: _quoteOf(_replyingTo!).preview,
                  onCancel: () => setState(() => _replyingTo = null),
                ),
              if (!_readOnly)
                _MessageComposer(
                  theme: theme,
                  controller: _inputController,
                  focusNode: _inputFocus,
                  sendingImage: _sendingImage,
                  onPickImage: _pickAndSendImage,
                  onSend: _send,
                  onSavedReplies: _history != null ? _insertSavedReply : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
