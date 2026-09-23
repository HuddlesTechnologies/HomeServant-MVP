import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import 'chat_thread_screen.dart';
import 'models/property.dart';
import 'property_gallery_screen.dart';
import 'widgets/property_image.dart';
import 'widgets/property_video_player.dart';

class PropertyDetailScreen extends StatefulWidget {
  const PropertyDetailScreen({super.key, required this.property, required this.theme});

  final Property property;
  final DashboardTheme theme;

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  bool _descriptionExpanded = false;

  List<String> get _allPhotos => [widget.property.image, ...widget.property.galleryImages];

  void _openGallery(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyGalleryScreen(images: _allPhotos, initialIndex: index, title: widget.property.title),
      ),
    );
  }

  void _messageLandlord() {
    final property = widget.property;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChatThreadScreen(
              theme: widget.theme,
              contactName: property.landlordName,
              property: property,
              initialMessages: [
                ChatMessage(
                  text: "Hi, I'm interested in ${property.title} in ${property.location}. Is it still available?",
                  fromMe: true,
                ),
              ],
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final property = widget.property;
    final theme = widget.theme;
    final favorited = context.select<AppState, bool>((state) => state.isFavorite(property.id));
    final messagingEnabled = context.select<AppState, bool>((state) => state.landlordMessagesEnabled);
    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Hero(
                    property: property,
                    favorited: favorited,
                    onToggleFavorite: () => context.read<AppState>().toggleFavorite(property.id),
                    onBack: () => Navigator.of(context).pop(),
                    onOpenGallery: () => _openGallery(0),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -28),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.background,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _FeatureIcon(
                                theme: theme,
                                icon: Icons.bed_outlined,
                                label: '${property.bedrooms} Bedroom${property.bedrooms == 1 ? '' : 's'}',
                              ),
                              _FeatureIcon(
                                theme: theme,
                                icon: Icons.bathtub_outlined,
                                label: '${property.bathrooms} Bathroom${property.bathrooms == 1 ? '' : 's'}',
                              ),
                              _FeatureIcon(theme: theme, icon: Icons.kitchen_outlined, label: 'Kitchen'),
                            ],
                          ),
                          const SizedBox(height: 26),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      property.title,
                                      style: AppTextStyles.heading(color: theme.foreground, size: 20),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      property.location,
                                      style: AppTextStyles.body(color: theme.accent, size: 14, weight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    children: [
                                      ..._stars(property.rating, theme),
                                      const SizedBox(width: 4),
                                      Text(
                                        property.rating.toString(),
                                        style: AppTextStyles.body(color: theme.foreground, size: 13),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    property.priceLabel,
                                    style: AppTextStyles.body(color: theme.foreground, size: 16, weight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text('Description', style: AppTextStyles.heading(color: theme.foreground, size: 16)),
                          const SizedBox(height: 8),
                          _ExpandableDescription(
                            theme: theme,
                            text: property.description,
                            expanded: _descriptionExpanded,
                            onToggle: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
                          ),
                          if (property.galleryImages.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(
                              'Details Preview',
                              style: AppTextStyles.body(
                                color: theme.foreground.withValues(alpha: 0.55),
                                size: 13,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (var i = 0; i < property.galleryImages.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: GestureDetector(
                                      // Gallery index 0 is the hero photo, so the
                                      // preview strip's photos start at index 1.
                                      onTap: () => _openGallery(i + 1),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: PropertyImage(path: property.galleryImages[i], width: 72, height: 72),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (property.videoPath != null) ...[
                            const SizedBox(height: 24),
                            Text(
                              'Property Tour',
                              style: AppTextStyles.body(
                                color: theme.foreground.withValues(alpha: 0.55),
                                size: 13,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            PropertyVideoPlayer(path: property.videoPath!),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.accent,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              ),
                              onPressed: () {
                                final isShortlet = property.category == 'Shortlet';
                                context.read<AppState>().recordRentalOrBooking(property.id, isShortlet: isShortlet);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${isShortlet ? 'Booking' : 'Rent'} request sent for ${property.title}',
                                    ),
                                  ),
                                );
                              },
                              child: Text(
                                property.category == 'Shortlet' ? 'Book Now' : 'Rent Now',
                                style: AppTextStyles.button(color: theme.onAccent),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (messagingEnabled)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  side: BorderSide(color: theme.accent, width: 1.4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                onPressed: _messageLandlord,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.chat_bubble_outline_rounded, color: theme.accent, size: 18),
                                    const SizedBox(width: 10),
                                    Text(
                                      property.category == 'Shortlet' ? 'Message Owner' : 'Message Landlord',
                                      style: AppTextStyles.button(color: theme.accent, size: 15),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'This landlord accepts direct rent payments only — messaging is turned off.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.5), size: 12.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Stars sit directly on `theme.background`, same as PropertyCard — using
  // theme.accent instead of a fixed gold avoids the gold-on-sand contrast
  // problem on the Sand theme.
  List<Widget> _stars(double rating, DashboardTheme theme) {
    final fullStars = rating.floor();
    final hasHalf = rating - fullStars >= 0.5;
    return List.generate(5, (index) {
      if (index < fullStars) return Icon(Icons.star_rounded, color: theme.accent, size: 16);
      if (index == fullStars && hasHalf) return Icon(Icons.star_half_rounded, color: theme.accent, size: 16);
      return Icon(Icons.star_rounded, color: theme.accent.withValues(alpha: 0.3), size: 16);
    });
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.property,
    required this.favorited,
    required this.onToggleFavorite,
    required this.onBack,
    required this.onOpenGallery,
  });

  final Property property;
  final bool favorited;
  final VoidCallback onToggleFavorite;
  final VoidCallback onBack;
  final VoidCallback onOpenGallery;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(onTap: onOpenGallery, child: PropertyImage(path: property.image)),
          Positioned(top: 16, left: 16, child: _CircleButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack)),
          Positioned(
            top: 16,
            right: 16,
            child: _CircleButton(
              icon: favorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              iconColor: favorited ? Colors.redAccent : Colors.white,
              onTap: onToggleFavorite,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap, this.iconColor = Colors.white});

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: 18,
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        child: Icon(icon, color: iconColor, size: 18),
      ),
    );
  }
}

class _FeatureIcon extends StatelessWidget {
  const _FeatureIcon({required this.theme, required this.icon, required this.label});

  final DashboardTheme theme;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: theme.accent, size: 26),
        const SizedBox(height: 6),
        Text(label, style: AppTextStyles.body(color: theme.foreground, size: 12, weight: FontWeight.w600)),
      ],
    );
  }
}

class _ExpandableDescription extends StatelessWidget {
  const _ExpandableDescription({required this.theme, required this.text, required this.expanded, required this.onToggle});

  final DashboardTheme theme;
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          maxLines: expanded ? null : 3,
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.7), size: 14).copyWith(height: 1.5),
        ),
        GestureDetector(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              expanded ? 'Read less' : 'Read more',
              style: AppTextStyles.body(color: theme.accent, size: 14, weight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
