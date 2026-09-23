import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/marketplace_orders_repository.dart';
import '../../api/models/marketplace_api.dart';
import '../../api/models/vendor.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/upload_picker.dart';
import 'marketplace_messages_screen.dart';
import 'marketplace_product_detail_screen.dart';
import 'models/order_options.dart';
import 'order_history_screen.dart';
import 'widgets/marketplace_product_card.dart';

/// The actual shopping screen a visitor lands on after choosing "Proceed as
/// a Customer" on [MarketplaceAuthScreen].
class MarketplaceHomeScreen extends StatefulWidget {
  const MarketplaceHomeScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<MarketplaceHomeScreen> createState() => _MarketplaceHomeScreenState();
}

class _MarketplaceHomeScreenState extends State<MarketplaceHomeScreen> {
  final _search = TextEditingController();
  MarketplaceCategory? _category;
  List<MarketplaceProductApi>? _products;

  /// productId -> quantity. Kept local to this screen — checkout resets it
  /// rather than persisting an order history.
  final Map<String, int> _cart = {};

  /// productId -> how that item should be fulfilled, defaulted to delivery
  /// the moment it's added to the cart.
  final Map<String, FulfillmentMethod> _fulfillment = {};

  int get _cartCount => _cart.values.fold(0, (sum, qty) => sum + qty);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final products = await context.read<AppState>().marketplaceProducts.findMany();
      if (!mounted) return;
      setState(() => _products = products);
    } catch (_) {
      if (!mounted) return;
      setState(() => _products = []);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MarketplaceProductApi> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return (_products ?? []).where((p) {
      final matchesCategory = _category == null || p.category == _category;
      final matchesQuery = query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          (p.vendor?.businessName.toLowerCase().contains(query) ?? false);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  MarketplaceProductApi? _productById(String id) => (_products ?? []).where((p) => p.id == id).firstOrNull;

  /// Adds [product] to the cart at exactly [quantity] units — a repeat tap
  /// with the same quantity already in the cart doesn't silently bump the
  /// count again; the shopper has to use the product card's +/- stepper to
  /// actually change how many they want first.
  void _addToCart(MarketplaceProductApi product, int quantity) {
    if (product.stock <= 0) return;
    final clampedQuantity = quantity.clamp(1, product.stock);
    if (_cart[product.id] == clampedQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item already added to cart')));
      return;
    }
    setState(() {
      _cart[product.id] = clampedQuantity;
      _fulfillment.putIfAbsent(product.id, () => product.fulfillmentOptions.first);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          clampedQuantity == 1 ? '${product.name} added to cart' : '$clampedQuantity × ${product.name} added to cart',
        ),
      ),
    );
  }

  void _removeFromCart(String productId) {
    setState(() {
      _cart.remove(productId);
      _fulfillment.remove(productId);
    });
  }

  /// Adjusts an item already in the cart via the cart sheet's own stepper —
  /// clamped between 1 (use the trash icon to remove it entirely) and however
  /// many the vendor has left in stock.
  void _setCartQuantity(MarketplaceProductApi product, int quantity) {
    setState(() => _cart[product.id] = quantity.clamp(1, product.stock));
  }

  int get _cartTotal => _cart.entries.fold<int>(0, (sum, entry) {
    final product = _productById(entry.key);
    return sum + (product?.price ?? 0) * entry.value;
  });

  void _openCart() {
    final theme = widget.theme;
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final items = _cart.keys.map(_productById).whereType<MarketplaceProductApi>().toList();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your Cart', style: AppTextStyles.heading(color: theme.onSurface, size: 18)),
                    const SizedBox(height: 16),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('Your cart is empty', style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6))),
                      )
                    else ...[
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, _) => Divider(height: 24, color: theme.onSurface.withValues(alpha: 0.1)),
                          itemBuilder: (context, index) {
                            final product = items[index];
                            final fulfillment = _fulfillment[product.id] ?? product.fulfillmentOptions.first;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: product.imageUrls.isNotEmpty
                                            ? Image(image: imageProviderForPath(product.imageUrls.first), fit: BoxFit.cover)
                                            : DecoratedBox(
                                                decoration: BoxDecoration(color: theme.onSurface.withValues(alpha: 0.06)),
                                                child: Icon(
                                                  product.category.icon,
                                                  color: theme.onSurface.withValues(alpha: 0.5),
                                                  size: 20,
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        product.name,
                                        style: AppTextStyles.body(color: theme.onSurface, size: 13.5, weight: FontWeight.w600),
                                      ),
                                    ),
                                    Text(
                                      '₦${formatWithThousandsSeparator(product.price * (_cart[product.id] ?? 0))}',
                                      style: AppTextStyles.body(color: theme.onSurface, size: 13.5, weight: FontWeight.w700),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        _removeFromCart(product.id);
                                        setSheetState(() {});
                                      },
                                      icon: Icon(Icons.delete_outline_rounded, color: theme.onSurface.withValues(alpha: 0.5), size: 20),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.only(left: 8),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const SizedBox(width: 56),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: theme.onSurface.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            onPressed: (_cart[product.id] ?? 1) > 1
                                                ? () => setSheetState(
                                                    () => _setCartQuantity(product, (_cart[product.id] ?? 1) - 1),
                                                  )
                                                : null,
                                            icon: Icon(
                                              Icons.remove_rounded,
                                              size: 16,
                                              color: (_cart[product.id] ?? 1) > 1
                                                  ? theme.onSurface.withValues(alpha: 0.8)
                                                  : theme.onSurface.withValues(alpha: 0.25),
                                            ),
                                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                            padding: EdgeInsets.zero,
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          SizedBox(
                                            width: 24,
                                            child: Text(
                                              '${_cart[product.id]}',
                                              textAlign: TextAlign.center,
                                              style: AppTextStyles.body(color: theme.onSurface, size: 13, weight: FontWeight.w700),
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: (_cart[product.id] ?? 1) < product.stock
                                                ? () => setSheetState(
                                                    () => _setCartQuantity(product, (_cart[product.id] ?? 1) + 1),
                                                  )
                                                : null,
                                            icon: Icon(
                                              Icons.add_rounded,
                                              size: 16,
                                              color: (_cart[product.id] ?? 1) < product.stock
                                                  ? theme.onSurface.withValues(alpha: 0.8)
                                                  : theme.onSurface.withValues(alpha: 0.25),
                                            ),
                                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                            padding: EdgeInsets.zero,
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (product.fulfillmentOptions.length > 1)
                                Row(
                                  children: [
                                    for (final method in product.fulfillmentOptions) ...[
                                      _FulfillmentChip(
                                        theme: theme,
                                        method: method,
                                        selected: fulfillment == method,
                                        onTap: () => setSheetState(() => setState(() => _fulfillment[product.id] = method)),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Divider(height: 28, color: theme.onSurface.withValues(alpha: 0.1)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total', style: AppTextStyles.body(color: theme.onSurface, weight: FontWeight.w700)),
                          Text(
                            '₦${formatWithThousandsSeparator(_cartTotal)}',
                            style: AppTextStyles.body(color: theme.onSurface, weight: FontWeight.w800, size: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      PillButton(
                        label: 'Checkout',
                        backgroundColor: theme.accent,
                        textColor: theme.onAccent,
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _openPaymentModal();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _placeOrder(PaymentMethod paymentMethod) async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await appState.marketplaceOrders.create(
        items: [
          for (final entry in _cart.entries)
            MarketplaceOrderItemInput(
              productId: entry.key,
              quantity: entry.value,
              fulfillment: _fulfillment[entry.key] ?? FulfillmentMethod.delivery,
            ),
        ],
        paymentMethod: paymentMethod,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _fulfillment.clear();
      });
      messenger.showSnackBar(const SnackBar(content: Text('Payment successful! Your order has been placed.')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openPaymentModal() {
    final theme = widget.theme;
    final total = _cartTotal;
    var selected = PaymentMethod.card;
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment', style: AppTextStyles.heading(color: theme.onSurface, size: 18)),
                const SizedBox(height: 4),
                Text(
                  'Amount to pay: ₦${formatWithThousandsSeparator(total)}',
                  style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 13.5),
                ),
                const SizedBox(height: 20),
                for (final method in PaymentMethod.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => setSheetState(() => selected = method),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: selected == method ? theme.accent.withValues(alpha: 0.12) : theme.onSurface.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: selected == method ? theme.accent : Colors.transparent, width: 1.4),
                        ),
                        child: Row(
                          children: [
                            Icon(method.icon, color: theme.onSurface, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                method.label,
                                style: AppTextStyles.body(color: theme.onSurface, size: 14, weight: FontWeight.w600),
                              ),
                            ),
                            Icon(
                              selected == method ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                              color: selected == method ? theme.accent : theme.onSurface.withValues(alpha: 0.4),
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                PillButton(
                  label: 'Pay ₦${formatWithThousandsSeparator(total)}',
                  backgroundColor: theme.accent,
                  textColor: theme.onAccent,
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _placeOrder(selected);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('Marketplace', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MarketplaceMessagesScreen(theme: theme)),
            ),
            icon: Icon(Icons.chat_bubble_outline_rounded, color: theme.foreground),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => OrderHistoryScreen(theme: theme)),
            ),
            icon: Icon(Icons.receipt_long_outlined, color: theme.foreground),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: _openCart,
                icon: Icon(Icons.shopping_cart_outlined, color: theme.foreground),
              ),
              if (_cartCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_cartCount',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(color: theme.onAccent, size: 9, weight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 1100,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: AppTextStyles.body(color: theme.onSurface, size: 14),
                  decoration: InputDecoration(
                    hintText: 'Search products or vendors',
                    hintStyle: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.5), size: 14),
                    prefixIcon: Icon(Icons.search_rounded, color: theme.onSurface.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: theme.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: MarketplaceCategory.values.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final category = index == 0 ? null : MarketplaceCategory.values[index - 1];
                    final label = category?.label ?? 'All';
                    final selected = category == _category;
                    return ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) => setState(() => _category = category),
                      backgroundColor: theme.surface,
                      selectedColor: theme.accent,
                      labelStyle: AppTextStyles.body(
                        color: selected ? theme.onAccent : theme.onSurface,
                        size: 12.5,
                        weight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                      side: BorderSide.none,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _products == null
                    ? const Center(child: CircularProgressIndicator())
                    : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No products match your search',
                          style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: gridColumnsForWidth(MediaQuery.of(context).size.width) + 1,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.58,
                          ),
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final product = _filtered[index];
                            return MarketplaceProductCard(
                              product: product,
                              theme: theme,
                              cartQuantity: _cart[product.id] ?? 0,
                              onAddToCart: (quantity) => _addToCart(product, quantity),
                              onOpen: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MarketplaceProductDetailScreen(
                                    product: product,
                                    theme: theme,
                                    cartQuantity: _cart[product.id] ?? 0,
                                    onAddToCart: _addToCart,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FulfillmentChip extends StatelessWidget {
  const _FulfillmentChip({required this.theme, required this.method, required this.selected, required this.onTap});

  final DashboardTheme theme;
  final FulfillmentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? theme.accent : theme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(method.icon, size: 14, color: selected ? theme.onAccent : theme.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 5),
            Text(
              method.label,
              style: AppTextStyles.body(
                color: selected ? theme.onAccent : theme.onSurface.withValues(alpha: 0.6),
                size: 11.5,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
