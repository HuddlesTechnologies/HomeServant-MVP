import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'upload_picker.dart';

/// Opens [photoPath] full size in a pop-up over a dark scrim — pinch/scroll
/// to zoom, tap outside or the close button to dismiss. [name], if given,
/// is shown under the photo. White text/icons on the fixed near-black
/// scrim, the same in every theme.
Future<void> showProfilePhoto(BuildContext context, {required String photoPath, String? name}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    barrierLabel: 'Close photo',
    builder: (context) => _ProfilePhotoDialog(photoPath: photoPath, name: name),
  );
}

/// Makes [child] (an avatar) open [photoPath] in [showProfilePhoto] when
/// tapped. Does nothing — just returns [child] — when there's no photo, so
/// a placeholder icon never opens an empty pop-up.
class ProfilePhotoTapTarget extends StatelessWidget {
  const ProfilePhotoTapTarget({super.key, required this.photoPath, this.name, required this.child});

  final String? photoPath;
  final String? name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = photoPath;
    if (path == null || path.isEmpty) return child;
    return Semantics(
      button: true,
      label: name == null || name!.isEmpty ? 'View profile photo' : "View $name's profile photo",
      child: MouseRegion(
        cursor: SystemMouseCursors.zoomIn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showProfilePhoto(context, photoPath: path, name: name),
          child: child,
        ),
      ),
    );
  }
}

class _ProfilePhotoDialog extends StatelessWidget {
  const _ProfilePhotoDialog({required this.photoPath, this.name});

  final String photoPath;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final side = (size.shortestSide * 0.86).clamp(200.0, 520.0);
    final caption = name?.trim() ?? '';
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      elevation: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: AppColors.white, size: 28),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: side,
              height: side,
              child: ColoredBox(
                color: AppColors.navyDark,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image(
                    image: imageProviderForPath(photoPath),
                    fit: BoxFit.contain,
                    loadingBuilder:
                        (context, child, progress) =>
                            progress == null ? child : const Center(child: CircularProgressIndicator(color: AppColors.white)),
                    errorBuilder:
                        (context, _, __) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.broken_image_outlined, color: AppColors.white, size: 40),
                              const SizedBox(height: 8),
                              Text("Couldn't load this photo", style: AppTextStyles.body(color: AppColors.white, size: 13)),
                            ],
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: AppColors.white, size: 16, weight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}
