import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/empty_state.dart';
import 'models/property.dart';
import 'widgets/property_card.dart';

class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final favoriteIds = context.select<AppState, Set<String>>((state) => state.favoritePropertyIds);
    final favorites = mockProperties.where((p) => favoriteIds.contains(p.id)).toList();

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('WishList', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
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
                  : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [for (final property in favorites) PropertyCard(property: property, theme: theme)],
                  ),
        ),
      ),
    );
  }
}
