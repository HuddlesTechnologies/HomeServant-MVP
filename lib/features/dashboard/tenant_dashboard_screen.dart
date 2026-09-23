import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/dashboard_tab_scaffold.dart';
import '../../widgets/notification_bell.dart';
import 'legal/tenancy_agreements_screen.dart';
import 'messages_screen.dart';
import 'models/property.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/property_card.dart';

class TenantDashboardScreen extends StatefulWidget {
  const TenantDashboardScreen({super.key});

  @override
  State<TenantDashboardScreen> createState() => _TenantDashboardScreenState();
}

enum _PriceSort { none, lowToHigh, highToLow }

class _TenantDashboardScreenState extends State<TenantDashboardScreen> {
  static const _categories = ['House', 'Shortlet', 'Self-Con', 'Apartment'];
  int _selectedCategory = 0;
  int _navIndex = 0;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  double? _minPrice;
  double? _maxPrice;
  _PriceSort _priceSort = _PriceSort.none;
  String? _selectedState;
  String _locationQuery = '';

  @override
  void initState() {
    super.initState();
    // AppState.load() only fetches the public feed once, at cold start —
    // a property a landlord adds afterward (including in this same
    // session, from another tab) wouldn't otherwise show up here until a
    // full app restart. Refreshing on entry means at least opening this
    // tab picks up anything new, on top of the pull-to-refresh below.
    context.read<AppState>().loadProperties();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectCategory(int index) {
    setState(() {
      _selectedCategory = index;
      // Price bands aren't comparable across categories (yearly rent vs.
      // nightly shortlet rates), so a filter set for one tab would just
      // silently zero out another's results — reset it on switch instead.
      _minPrice = null;
      _maxPrice = null;
      _priceSort = _PriceSort.none;
    });
  }

  List<Property> get _filteredProperties {
    final query = _searchQuery.trim().toLowerCase();
    final locationQuery = _locationQuery.trim().toLowerCase();
    final selectedCategory = _categories[_selectedCategory];
    final allProperties = context.watch<AppState>().properties;
    final filtered =
        allProperties.where((property) {
          final matchesQuery =
              query.isEmpty ||
              property.title.toLowerCase().contains(query) ||
              property.location.toLowerCase().contains(query);
          // A typed search looks across every category — restricting to the
          // active tab on top of it hid real matches (e.g. searching
          // "Lekki" found nothing while the House tab was selected, even
          // though a Shortlet in Lekki exists) and made the search box look
          // broken. With no query, the category tabs filter as normal.
          final matchesCategory =
              query.isNotEmpty || property.category == selectedCategory;
          final matchesState =
              _selectedState == null || property.state == _selectedState;
          final matchesLocation =
              locationQuery.isEmpty ||
              property.location.toLowerCase().contains(locationQuery);
          final matchesMinPrice =
              _minPrice == null || property.price >= _minPrice!;
          final matchesMaxPrice =
              _maxPrice == null || property.price <= _maxPrice!;
          return matchesQuery &&
              matchesCategory &&
              matchesState &&
              matchesLocation &&
              matchesMinPrice &&
              matchesMaxPrice;
        }).toList();
    switch (_priceSort) {
      case _PriceSort.lowToHigh:
        filtered.sort((a, b) => a.price.compareTo(b.price));
      case _PriceSort.highToLow:
        filtered.sort((a, b) => b.price.compareTo(a.price));
      case _PriceSort.none:
        break;
    }
    return filtered;
  }

  Future<void> _openFilterSheet(DashboardTheme theme) async {
    final categoryPrices =
        context
            .read<AppState>()
            .properties
            .where((p) => p.category == _categories[_selectedCategory])
            .map((p) => p.price.toDouble())
            .toList();
    final boundsMin =
        categoryPrices.isEmpty
            ? 0.0
            : categoryPrices.reduce((a, b) => a < b ? a : b);
    final boundsMax =
        categoryPrices.isEmpty
            ? 0.0
            : categoryPrices.reduce((a, b) => a > b ? a : b);
    final hasRange = boundsMax > boundsMin;

    var priceRange = RangeValues(
      _minPrice ?? boundsMin,
      _maxPrice ?? boundsMax,
    );
    var priceSort = _priceSort;
    var selectedState = _selectedState;
    final locationController = TextEditingController(text: _locationQuery);
    final minPriceController = TextEditingController(
      text: formatWithThousandsSeparator(priceRange.start),
    );
    final maxPriceController = TextEditingController(
      text: formatWithThousandsSeparator(priceRange.end),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                32 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filters',
                      style: AppTextStyles.heading(
                        color: theme.onSurface,
                        size: 18,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Price Range',
                      style: AppTextStyles.body(
                        color: theme.onSurface,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minPriceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              ThousandsSeparatorInputFormatter(),
                            ],
                            style: AppTextStyles.body(color: theme.onSurface),
                            decoration: InputDecoration(
                              prefixText: '₦ ',
                              labelText: 'Min',
                              filled: true,
                              fillColor: theme.onSurface.withValues(
                                alpha: 0.06,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (text) {
                              final value = double.tryParse(
                                text.replaceAll(',', ''),
                              );
                              if (value == null) return;
                              setSheetState(() {
                                priceRange = RangeValues(
                                  value,
                                  value > priceRange.end
                                      ? value
                                      : priceRange.end,
                                );
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxPriceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              ThousandsSeparatorInputFormatter(),
                            ],
                            style: AppTextStyles.body(color: theme.onSurface),
                            decoration: InputDecoration(
                              prefixText: '₦ ',
                              labelText: 'Max',
                              filled: true,
                              fillColor: theme.onSurface.withValues(
                                alpha: 0.06,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (text) {
                              final value = double.tryParse(
                                text.replaceAll(',', ''),
                              );
                              if (value == null) return;
                              setSheetState(() {
                                priceRange = RangeValues(
                                  value < priceRange.start
                                      ? value
                                      : priceRange.start,
                                  value,
                                );
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (hasRange)
                      RangeSlider(
                        values: RangeValues(
                          priceRange.start.clamp(boundsMin, boundsMax),
                          priceRange.end.clamp(boundsMin, boundsMax),
                        ),
                        min: boundsMin,
                        max: boundsMax,
                        activeColor: theme.accent,
                        onChanged:
                            (values) => setSheetState(() {
                              priceRange = values;
                              minPriceController.text =
                                  formatWithThousandsSeparator(values.start);
                              maxPriceController.text =
                                  formatWithThousandsSeparator(values.end);
                            }),
                      )
                    else
                      const SizedBox(height: 12),
                    const SizedBox(height: 8),
                    Text(
                      'Sort by Price',
                      style: AppTextStyles.body(
                        color: theme.onSurface,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: [
                        for (final option in _PriceSort.values)
                          ChoiceChip(
                            label: Text(switch (option) {
                              _PriceSort.none => 'None',
                              _PriceSort.lowToHigh => 'Low to High',
                              _PriceSort.highToLow => 'High to Low',
                            }),
                            selected: priceSort == option,
                            onSelected:
                                (_) => setSheetState(() => priceSort = option),
                            selectedColor: theme.accent,
                            labelStyle: AppTextStyles.body(
                              color:
                                  priceSort == option
                                      ? theme.onAccent
                                      : theme.onSurface,
                              weight: FontWeight.w600,
                            ),
                            backgroundColor: theme.onSurface.withValues(
                              alpha: 0.06,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'State',
                      style: AppTextStyles.body(
                        color: theme.onSurface,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      value: selectedState,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: theme.onSurface.withValues(alpha: 0.06),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: AppTextStyles.body(color: theme.onSurface),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            'Any State',
                            style: AppTextStyles.body(color: theme.onSurface),
                          ),
                        ),
                        for (final state in nigerianStates)
                          DropdownMenuItem(
                            value: state,
                            child: Text(
                              state,
                              style: AppTextStyles.body(color: theme.onSurface),
                            ),
                          ),
                      ],
                      onChanged:
                          (value) => setSheetState(() {
                            selectedState = value;
                            if (value == null) locationController.clear();
                          }),
                    ),
                    if (selectedState != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Location in $selectedState',
                        style: AppTextStyles.body(
                          color: theme.onSurface,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: locationController,
                        style: AppTextStyles.body(color: theme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'e.g. Ikeja, Lekki, Yaba…',
                          filled: true,
                          fillColor: theme.onSurface.withValues(alpha: 0.06),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.accent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            if (categoryPrices.isEmpty) {
                              _minPrice = null;
                              _maxPrice = null;
                            } else {
                              _minPrice = priceRange.start;
                              _maxPrice = priceRange.end;
                            }
                            _priceSort = priceSort;
                            _selectedState = selectedState;
                            _locationQuery =
                                selectedState == null
                                    ? ''
                                    : locationController.text;
                          });
                          Navigator.of(context).pop();
                        },
                        child: Text(
                          'Apply',
                          style: AppTextStyles.button(color: theme.onAccent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    locationController.dispose();
    minPriceController.dispose();
    maxPriceController.dispose();
  }

  Future<void> _logOut(BuildContext context) async {
    await context.read<AppState>().logout();
    if (context.mounted) context.go('/get-started');
  }

  void _onNavTap(int index, DashboardTheme theme) {
    if (index == 1) {
      context.push('/marketplace');
      return;
    }
    if (index == 2) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TenancyAgreementsScreen(theme: theme),
        ),
      );
      return;
    }
    setState(() => _navIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppState>().dashboardTheme;
    final onProfileTab = _navIndex == 3;
    return DashboardTabScaffold(
      background: theme.background,
      navBar: DashboardBottomNav(
        currentIndex: _navIndex,
        onTap: (i) => _onNavTap(i, theme),
        theme: theme,
      ),
      body:
          onProfileTab
              ? ProfileScreen(onLogOut: () => _logOut(context))
              : _buildHomeFeed(theme),
    );
  }

  Widget _buildHomeFeed(DashboardTheme theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: RefreshIndicator(
          onRefresh: () => context.read<AppState>().loadProperties(),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                color: theme.locationPinColor,
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Ikeja, Lagos',
                                style: AppTextStyles.body(
                                  color: theme.foreground,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              GestureDetector(
                                onTap:
                                    () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder:
                                            (_) => MessagesScreen(theme: theme),
                                      ),
                                    ),
                                child: Icon(
                                  Icons.mail_outline_rounded,
                                  color: theme.foreground,
                                ),
                              ),
                              const SizedBox(width: 16),
                              NotificationBell(
                                color: theme.foreground,
                                showDot: context.watch<AppState>().unreadNotificationCount > 0,
                                onTap: () {
                                  context.read<AppState>().markAllNotificationsRead();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder:
                                          (_) =>
                                              NotificationsScreen(theme: theme),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.search,
                                    color: AppColors.navy,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      onChanged:
                                          (value) => setState(
                                            () => _searchQuery = value,
                                          ),
                                      style: AppTextStyles.body(
                                        color: AppColors.navy,
                                        size: 16,
                                        weight: FontWeight.w600,
                                      ),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        hintText:
                                            'Search by location or property',
                                        hintStyle: AppTextStyles.body(
                                          color: AppColors.hintGrey,
                                          size: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_searchQuery.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                      child: const Icon(
                                        Icons.close_rounded,
                                        color: AppColors.hintGrey,
                                        size: 20,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _openFilterSheet(theme),
                            child: Container(
                              padding: const EdgeInsets.all(17),
                              decoration: BoxDecoration(
                                color: theme.accent,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(
                                Icons.tune_rounded,
                                color: theme.onAccent,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Categories',
                        style: AppTextStyles.heading(
                          color: theme.foreground,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final selected = index == _selectedCategory;
                      return GestureDetector(
                        onTap: () => _selectCategory(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? theme.accent : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow:
                                selected
                                    ? []
                                    : [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                          ),
                          child: Text(
                            _categories[index],
                            style: AppTextStyles.body(
                              color: selected ? theme.onAccent : AppColors.navy,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (_filteredProperties.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: Text(
                        'No properties match your search',
                        style: AppTextStyles.body(
                          color: theme.foreground.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                  sliver: SliverToBoxAdapter(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = gridColumnsForWidth(
                          constraints.maxWidth,
                        );
                        if (columns <= 1) {
                          return Column(
                            children: [
                              for (final property in _filteredProperties)
                                PropertyCard(property: property, theme: theme),
                            ],
                          );
                        }
                        const spacing = 20.0;
                        final cardWidth =
                            (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: spacing,
                          children: [
                            for (final property in _filteredProperties)
                              SizedBox(
                                width: cardWidth,
                                child: PropertyCard(
                                  property: property,
                                  theme: theme,
                                ),
                              ),
                          ],
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
