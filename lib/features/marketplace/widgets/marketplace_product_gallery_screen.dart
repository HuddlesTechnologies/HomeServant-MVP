import 'package:flutter/material.dart';

/// Full-screen swipeable viewer for a product's photos — opened from the
/// hero image or any thumbnail on [MarketplaceProductDetailScreen]. Mirrors
/// the dashboard's `PropertyGalleryScreen`, but takes [ImageProvider]s
/// directly since a product's photos may be bundled assets or files a
/// vendor picked at runtime.
class MarketplaceProductGalleryScreen extends StatefulWidget {
  const MarketplaceProductGalleryScreen({super.key, required this.images, required this.initialIndex, required this.title});

  final List<ImageProvider> images;
  final int initialIndex;
  final String title;

  @override
  State<MarketplaceProductGalleryScreen> createState() => _MarketplaceProductGalleryScreenState();
}

class _MarketplaceProductGalleryScreenState extends State<MarketplaceProductGalleryScreen> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_index + 1}/${widget.images.length} · ${widget.title}',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: Image(
                image: widget.images[index],
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.images.length, (i) {
              final active = i == _index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
