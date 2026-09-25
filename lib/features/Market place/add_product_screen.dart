import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/payout_required_dialog.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/upload_picker.dart';
import 'models/order_options.dart';
import 'vendor_bank_details_screen.dart';

const _minImages = 2;
const _maxImages = 5;

/// The vendor's "List a Product" form — name, description, at least 2
/// photos, an optional video, and a price. Pops `true` on success so
/// [VendorProductsScreen] knows to refresh its list.
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  final List<PickedUpload> _images = [];
  PickedUpload? _video;
  final Set<FulfillmentMethod> _fulfillmentOptions = {};
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _addImages() async {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You can add up to $_maxImages photos')));
      return;
    }
    final picked = await pickMultipleImageUploads(context, maxCount: remaining);
    if (!mounted || picked.isEmpty) return;
    setState(() => _images.addAll(picked.take(remaining)));
  }

  Future<void> _addVideo() async {
    final picked = await pickUpload(context);
    if (picked == null || !mounted) return;
    setState(() => _video = picked);
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final description = _description.text.trim();
    final price = int.tryParse(_price.text.replaceAll(',', '').trim());
    final stock = int.tryParse(_stock.text.replaceAll(',', '').trim());
    final messenger = ScaffoldMessenger.of(context);

    if (name.isEmpty || description.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter a product name and description')));
      return;
    }
    if (_images.length < _minImages) {
      messenger.showSnackBar(SnackBar(content: Text('Add at least $_minImages photos')));
      return;
    }
    if (price == null || price <= 0) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter a valid price')));
      return;
    }
    if (stock == null || stock < 0) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter how many are in stock')));
      return;
    }
    if (_fulfillmentOptions.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Select whether this item is available for delivery, pickup, or both')),
      );
      return;
    }

    setState(() => _submitting = true);
    final appState = context.read<AppState>();
    try {
      final vendor = await appState.vendors.me();
      if (!vendor.hasPayoutDetails) {
        if (!mounted) return;
        final proceed = await showPayoutRequiredDialog(
          context,
          body: 'Please add your Payout Account details in Settings before listing a product. '
              'Orders are held in escrow and released to your bank account once a buyer confirms receipt.',
        );
        if (proceed == true && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => VendorBankDetailsScreen(theme: widget.theme)),
          );
        }
        return;
      }
      final imageUrls = <String>[];
      for (final image in _images) {
        imageUrls.add(await appState.uploads.upload(file: image, folder: 'marketplace-products'));
      }
      final videoUrl = _video != null ? await appState.uploads.upload(file: _video!, folder: 'marketplace-products') : null;

      await appState.marketplaceProducts.create(
        name: name,
        description: description,
        price: price,
        stock: stock,
        category: vendor.category,
        imageUrls: imageUrls,
        fulfillmentOptions: _fulfillmentOptions,
        videoUrl: videoUrl,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
        title: Text('List a Product', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: ResponsiveCenter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Label(theme: theme, text: 'Product Name'),
                const SizedBox(height: 8),
                PillTextField(hint: 'e.g. 3-Seater Leather Sofa', controller: _name, fillColor: theme.surface, textColor: theme.onSurface),
                const SizedBox(height: 18),
                _Label(theme: theme, text: 'Description'),
                const SizedBox(height: 8),
                PillTextField(
                  hint: "Describe the product's condition, materials, dimensions...",
                  controller: _description,
                  minLines: 3,
                  maxLines: 5,
                  borderRadius: 20,
                  fillColor: theme.surface,
                  textColor: theme.onSurface,
                ),
                const SizedBox(height: 18),
                _Label(theme: theme, text: 'Photos ($_minImages-$_maxImages) · ${_images.length}/$_maxImages'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 84,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final image in _images)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _PickedTile(
                            theme: theme,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image(image: image.imageProvider, width: 84, height: 84, fit: BoxFit.cover),
                            ),
                            onRemove: () => setState(() => _images.remove(image)),
                          ),
                        ),
                      if (_images.length < _maxImages)
                        GestureDetector(
                          onTap: _addImages,
                          child: Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color: theme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: theme.onSurface.withValues(alpha: 0.2), width: 1.2),
                            ),
                            child: Icon(Icons.add_photo_alternate_outlined, color: theme.onSurface.withValues(alpha: 0.5), size: 26),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _Label(theme: theme, text: 'Video (optional)'),
                const SizedBox(height: 8),
                if (_video == null)
                  GestureDetector(
                    onTap: _addVideo,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.onSurface.withValues(alpha: 0.2), width: 1.2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam_outlined, color: theme.onSurface.withValues(alpha: 0.5), size: 20),
                          const SizedBox(width: 8),
                          Text('Add a Video', style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 13.5)),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Icon(Icons.videocam_rounded, color: theme.accent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _video!.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body(color: theme.onSurface, size: 13.5, weight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _video = null),
                          icon: Icon(Icons.close_rounded, color: theme.onSurface.withValues(alpha: 0.5), size: 18),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                _Label(theme: theme, text: 'Price'),
                const SizedBox(height: 8),
                PillTextField(
                  hint: '0',
                  controller: _price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsSeparatorInputFormatter()],
                  fillColor: theme.surface,
                  textColor: theme.onSurface,
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('₦', style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), weight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 18),
                _Label(theme: theme, text: 'Quantity in Stock'),
                const SizedBox(height: 8),
                PillTextField(
                  hint: '0',
                  controller: _stock,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  fillColor: theme.surface,
                  textColor: theme.onSurface,
                ),
                const SizedBox(height: 18),
                _Label(theme: theme, text: 'Fulfillment'),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, color: theme.accent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'List this item accurately as delivery only, pickup only, or both — customers can only '
                          "choose from what you select here, so make sure it matches what you can actually fulfil.",
                          style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.75), size: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final method in FulfillmentMethod.values) ...[
                      Expanded(
                        child: _FulfillmentCheckbox(
                          theme: theme,
                          method: method,
                          selected: _fulfillmentOptions.contains(method),
                          onTap: () => setState(() {
                            if (!_fulfillmentOptions.remove(method)) _fulfillmentOptions.add(method);
                          }),
                        ),
                      ),
                      if (method != FulfillmentMethod.values.last) const SizedBox(width: 10),
                    ],
                  ],
                ),
                const SizedBox(height: 28),
                PillButton(
                  label: _submitting ? 'Listing…' : 'List Product',
                  backgroundColor: theme.accent,
                  textColor: theme.onAccent,
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.theme, required this.text});

  final DashboardTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.body(color: theme.foreground, weight: FontWeight.w600, size: 13.5));
  }
}

class _FulfillmentCheckbox extends StatelessWidget {
  const _FulfillmentCheckbox({required this.theme, required this.method, required this.selected, required this.onTap});

  final DashboardTheme theme;
  final FulfillmentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? theme.accent.withValues(alpha: 0.14) : theme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? theme.accent : theme.onSurface.withValues(alpha: 0.15), width: 1.2),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              color: selected ? theme.accent : theme.onSurface.withValues(alpha: 0.4),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                method.label,
                style: AppTextStyles.body(color: theme.onSurface, size: 13, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedTile extends StatelessWidget {
  const _PickedTile({required this.theme, required this.child, required this.onRemove});

  final DashboardTheme theme;
  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
