import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/responsive.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/dashboard_page_scaffold.dart';
import '../../widgets/empty_state.dart';
import 'models/property.dart';
import 'widgets/property_card.dart';

class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final favorites = context.select<AppState, List<Property>>((state) => state.favoriteProperties);

    return DashboardPageScaffold(
      background: theme.background,
      foreground: theme.foreground,
      title: 'WishList',
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child:
              favorites.isEmpty
                  ? EmptyState(
                    theme: theme,
                    icon: Icons.favorite_border_rounded,
                    title: 'No favorites yet',
                    message: 'Tap the heart on any property to save it here for later.',
                  )
                  // Previously had no reload path at all — a favorite
                  // removed/changed elsewhere (another session, or a
                  // property update) only ever showed up on next login.
                  : RefreshIndicator(
                    onRefresh: () => context.read<AppState>().loadFavorites(),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [for (final property in favorites) PropertyCard(property: property, theme: theme)],
                    ),
                  ),
        ),
      ),
    );
  }
}
