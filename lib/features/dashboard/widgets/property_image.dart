import 'package:flutter/material.dart';
import '../../../widgets/upload_picker.dart';

/// Renders a property photo, falling back to the generic homepage photo if
/// it's ever missing. [path] is usually a bundled asset path (every seed
/// listing), but a landlord-added property carries whatever local file (or,
/// on web, blob URL) they picked in Add Property instead — anything that
/// isn't an `assets/` path is treated as one of those and loaded via
/// [imageProviderForPath] rather than [Image.asset].
class PropertyImage extends StatelessWidget {
  const PropertyImage({super.key, required this.path, this.fit = BoxFit.cover, this.width, this.height});

  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (!path.startsWith('assets/')) {
      return Image(
        image: imageProviderForPath(path),
        fit: fit,
        width: width,
        height: height,
        errorBuilder: _fallback,
      );
    }
    return Image.asset(path, fit: fit, width: width, height: height, errorBuilder: _fallback);
  }

  Widget _fallback(BuildContext context, Object error, StackTrace? stackTrace) =>
      Image.asset('assets/images/homepage.jpg', fit: fit, width: width, height: height);
}
