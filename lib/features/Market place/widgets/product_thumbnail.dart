import 'package:flutter/material.dart';
import '../../../widgets/upload_picker.dart';

/// A product's photo, clipped to rounded corners — or, if it has none (or
/// was picked locally and hasn't been uploaded yet), a tinted fallback icon
/// in its place. Shared by the Marketplace product grid, the cart sheet,
/// the vendor's own product list, and every order-item thumbnail (order
/// history, vendor notifications/messages/transactions, order detail), so
/// they all render identically and all go through [imageProviderForPath] —
/// a raw `Image.network` would otherwise render broken for an image that's
/// only a local file path so far.
class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    super.key,
    required this.imageUrl,
    required this.icon,
    required this.iconColor,
    this.backgroundColor,
    this.size,
    this.iconSize,
    this.borderRadius = 12,
  });

  /// The product/order-item's own photo, or null to show [icon] instead.
  final String? imageUrl;
  final IconData icon;
  final Color iconColor;
  final Color? backgroundColor;

  /// Fixed width/height for the thumbnail. Leave null to fill whatever box
  /// it's placed in instead (e.g. inside an [AspectRatio]).
  final double? size;

  /// Defaults to [size] * 0.5 when [size] is set, or 24 otherwise.
  final double? iconSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final content = url == null
        ? Container(
            alignment: Alignment.center,
            color: backgroundColor ?? iconColor.withValues(alpha: 0.12),
            child: Icon(icon, color: iconColor, size: iconSize ?? (size != null ? size! * 0.5 : 24)),
          )
        : Image(image: imageProviderForPath(url), fit: BoxFit.cover, width: size, height: size);

    final clipped = ClipRRect(borderRadius: BorderRadius.circular(borderRadius), child: content);
    return size == null ? clipped : SizedBox(width: size, height: size, child: clipped);
  }
}
