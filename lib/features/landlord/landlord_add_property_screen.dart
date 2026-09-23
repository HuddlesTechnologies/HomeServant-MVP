import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/upload_picker.dart';
import '../dashboard/models/property.dart';

const _categories = ['House', 'Shortlet', 'Self-Con', 'Apartment'];

/// The landlord's "Add Property" form — reached from Profile Settings.
/// Builds a real [Property] and adds it to [AppState.landlordProperties],
/// so the new listing actually shows up in "My Properties" and the Home
/// tab's Properties count, rather than just acknowledging the tap.
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
  String? _photoPath;
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

  Future<void> _pickPhoto() async {
    final picked = await pickUpload(context);
    if (picked != null && picked.isImage) {
      setState(() => _photoPath = picked.path);
    }
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
    setState(() => _saving = true);
    final appState = context.read<AppState>();
    final landlordName = appState.fullName.trim().isEmpty ? 'You' : appState.fullName.trim();
    final property = Property(
      id: 'landlord-${DateTime.now().microsecondsSinceEpoch}',
      title: _title.text.trim(),
      location: _location.text.trim(),
      state: _state!,
      rating: 0,
      image: _photoPath ?? 'assets/images/homepage.jpg',
      category: _category,
      price: int.tryParse(_price.text.replaceAll(',', '')) ?? 0,
      priceUnit: _category == 'Shortlet' ? 'night' : 'year',
      bedrooms: int.tryParse(_bedrooms.text) ?? 0,
      bathrooms: int.tryParse(_bathrooms.text) ?? 0,
      description: _description.text.trim(),
      landlordName: landlordName,
      videoPath: _videoPath,
    );
    appState.addLandlordProperty(property);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${property.title} added to My Properties')));
    Navigator.of(context).pop();
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
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: Container(
                    width: double.infinity,
                    height: 160,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.navy.withValues(alpha: 0.15)),
                    ),
                    child: _photoPath != null
                        ? Image(image: imageProviderForPath(_photoPath!), fit: BoxFit.cover)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_a_photo_outlined, color: AppColors.navy, size: 28),
                              const SizedBox(height: 8),
                              Text(
                                'Add a cover photo',
                                style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600),
                              ),
                            ],
                          ),
                  ),
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
