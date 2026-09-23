import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/upload_picker.dart';
import '../dashboard/models/property.dart';

const _categories = ['House', 'Shortlet', 'Self-Con', 'Apartment'];
const _minImages = 2;
const _maxImages = 6;

/// The landlord's "Add Property" form — reached from Profile Settings.
/// Uploads every picked photo (2-6, first one used as the cover) to
/// Supabase Storage, then creates the listing via `POST /properties` and
/// adds it to [AppState.landlordProperties], so the new listing actually
/// shows up in "My Properties" and the Home tab's Properties count.
class LandlordAddPropertyScreen extends StatefulWidget {
  const LandlordAddPropertyScreen({super.key});

  @override
  State<LandlordAddPropertyScreen> createState() => _LandlordAddPropertyScreenState();
}

class _LandlordAddPropertyScreenState extends State<LandlordAddPropertyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _price = TextEditingController();
  final _bedrooms = TextEditingController();
  final _bathrooms = TextEditingController();
  final _description = TextEditingController();

  String _category = _categories.first;
  String? _state;
  final List<PickedUpload> _images = [];
  String? _videoPath;
  String? _videoFileName;
  bool _pickingVideo = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _price.dispose();
    _bedrooms.dispose();
    _bathrooms.dispose();
    _description.dispose();
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

  Future<void> _pickVideo() async {
    setState(() => _pickingVideo = true);
    final picked = await pickVideoUpload();
    if (!mounted) return;
    setState(() {
      _pickingVideo = false;
      if (picked != null) {
        _videoPath = picked.path;
        _videoFileName = picked.fileName;
      }
    });
  }

  void _removeVideo() => setState(() {
    _videoPath = null;
    _videoFileName = null;
  });

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_state == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a state')));
      return;
    }
    if (_images.length < _minImages) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add at least $_minImages photos')));
      return;
    }
    setState(() => _saving = true);
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final landlordName = appState.fullName.trim().isEmpty ? 'You' : appState.fullName.trim();
    try {
      final imageUrls = <String>[];
      for (final image in _images) {
        imageUrls.add(await appState.uploads.upload(file: image, folder: 'properties'));
      }
      final property = Property(
        id: '',
        title: _title.text.trim(),
        location: _location.text.trim(),
        state: _state!,
        rating: 0,
        image: imageUrls.first,
        galleryImages: imageUrls.skip(1).toList(),
        category: _category,
        price: int.tryParse(_price.text.replaceAll(',', '')) ?? 0,
        priceUnit: _category == 'Shortlet' ? 'night' : 'year',
        bedrooms: int.tryParse(_bedrooms.text) ?? 0,
        bathrooms: int.tryParse(_bathrooms.text) ?? 0,
        description: _description.text.trim(),
        landlordName: landlordName,
        videoPath: _videoPath,
      );
      final created = await appState.addLandlordProperty(property);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('${created.title} added to My Properties')));
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.offWhite,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.navy),
        title: Text('Add Property', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                'Photos ($_minImages-$_maxImages) · ${_images.length}/$_maxImages',
                style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 84,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final image in _images)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _PickedPhotoTile(
                          isCover: image == _images.first,
                          onRemove: () => setState(() => _images.remove(image)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image(image: image.imageProvider, width: 84, height: 84, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    if (_images.length < _maxImages)
                      GestureDetector(
                        onTap: _addImages,
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: AppColors.navy.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.navy.withValues(alpha: 0.15)),
                          ),
                          child: const Icon(Icons.add_a_photo_outlined, color: AppColors.navy, size: 26),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _VideoPicker(
                fileName: _videoFileName,
                picking: _pickingVideo,
                onPick: _pickVideo,
                onRemove: _removeVideo,
              ),
              const SizedBox(height: 20),
              PillTextField(hint: 'Property title', controller: _title, validator: _required),
              const SizedBox(height: 14),
              PillTextField(hint: 'Location (e.g. Agege, Lagos)', controller: _location, validator: _required),
              const SizedBox(height: 14),
              _StateDropdown(value: _state, onChanged: (value) => setState(() => _state = value)),
              const SizedBox(height: 14),
              _CategoryChips(value: _category, onChanged: (value) => setState(() => _category = value)),
              const SizedBox(height: 14),
              PillTextField(
                hint: _category == 'Shortlet' ? 'Price per night (₦)' : 'Price per year (₦)',
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, ThousandsSeparatorInputFormatter()],
                validator: _required,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: PillTextField(
                      hint: 'Bedrooms',
                      controller: _bedrooms,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _required,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PillTextField(
                      hint: 'Bathrooms',
                      controller: _bathrooms,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              PillTextField(
                hint: 'Description',
                controller: _description,
                minLines: 3,
                maxLines: 6,
                borderRadius: 20,
                validator: _required,
              ),
              const SizedBox(height: 26),
              PillButton(
                label: _saving ? 'Adding…' : 'Add Property',
                backgroundColor: AppColors.navy,
                textColor: AppColors.gold,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) => (value == null || value.trim().isEmpty) ? 'Required' : null;
}

/// Optional walkthrough-video picker, shown between the cover photo and the
/// text fields. Picking is camera-roll-only — see `pickVideoUpload`'s doc
/// comment for why "Choose from Files" isn't offered here the way it is for
/// photos.
class _VideoPicker extends StatelessWidget {
  const _VideoPicker({required this.fileName, required this.picking, required this.onPick, required this.onRemove});

  final String? fileName;
  final bool picking;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (fileName != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.navy.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            const Icon(Icons.videocam_rounded, color: AppColors.navy, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fileName!,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(color: AppColors.navy, size: 13.5, weight: FontWeight.w600),
              ),
            ),
            InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, color: AppColors.hintGrey, size: 18),
              ),
            ),
          ],
        ),
      );
    }
    return InkWell(
      onTap: picking ? null : onPick,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.navy.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (picking)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy),
              )
            else
              const Icon(Icons.videocam_outlined, color: AppColors.navy, size: 20),
            const SizedBox(width: 10),
            Text(
              picking ? 'Picking video…' : 'Add a walkthrough video (optional)',
              style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// One thumbnail in the photo picker's horizontal strip — a remove button
/// and, on the first (cover) photo, a small badge so it's clear which one
/// becomes the listing's main image.
class _PickedPhotoTile extends StatelessWidget {
  const _PickedPhotoTile({required this.child, required this.isCover, required this.onRemove});

  final Widget child;
  final bool isCover;
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
          if (isCover)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                child: Text('Cover', style: AppTextStyles.body(color: Colors.white, size: 9.5, weight: FontWeight.w700)),
              ),
            ),
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

class _StateDropdown extends StatelessWidget {
  const _StateDropdown({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(28)),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: const InputDecoration(border: InputBorder.none),
          hint: Text('State', style: AppTextStyles.body(color: AppColors.hintGrey)),
          style: AppTextStyles.body(color: AppColors.navy),
          items: [
            for (final state in nigerianStates) DropdownMenuItem(value: state, child: Text(state)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final category in _categories)
          GestureDetector(
            onTap: () => onChanged(category),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: value == category ? AppColors.navy : AppColors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                category,
                style: AppTextStyles.body(
                  color: value == category ? AppColors.gold : AppColors.navy,
                  weight: FontWeight.w600,
                  size: 13.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
