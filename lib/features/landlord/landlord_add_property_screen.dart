import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../state/app_state.dart';
import '../../widgets/dashboard_page_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/payout_required_dialog.dart';
import '../../widgets/upload_picker.dart';
import '../../core/date_format.dart';
import '../dashboard/models/property.dart';
import '../../widgets/bank_details_screen.dart';

const _categories = ['House', 'Shortlet', 'Self-Con', 'Apartment'];
const _minImages = 2;
const _maxImages = 6;

/// The landlord's "Add Property" form — reached from Profile Settings.
/// Uploads every picked photo (2-6, first one used as the cover) to
/// Supabase Storage, then creates the listing via `POST /properties` and
/// adds it to [AppState.landlordProperties], so the new listing actually
/// shows up in "My Properties" and the Home tab's Properties count.
///
/// Also doubles as the property-edit screen when [initial] is set (from
/// "My Properties") — same form, prefilled, saving via `PATCH
/// /properties/:id` instead of creating a new listing. Already-hosted
/// photos are re-used as-is rather than re-uploaded (see [_save]).
class LandlordAddPropertyScreen extends StatefulWidget {
  const LandlordAddPropertyScreen({super.key, this.initial});

  final Property? initial;

  @override
  State<LandlordAddPropertyScreen> createState() => _LandlordAddPropertyScreenState();
}

/// Largest walkthrough video accepted — Supabase's Free-plan limit per
/// file. Raise it if the project's storage limit is raised.
const _maxVideoBytes = 50 * 1024 * 1024;

class _LandlordAddPropertyScreenState extends State<LandlordAddPropertyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _price = TextEditingController();
  final _bedrooms = TextEditingController();
  final _bathrooms = TextEditingController();
  final _description = TextEditingController();
  final _unitAddress = TextEditingController();
  final _roomNumber = TextEditingController();

  String _category = _categories.first;
  String? _state;
  final List<PickedUpload> _images = [];
  String? _videoPath;
  String? _videoFileName;
  bool _pickingVideo = false;
  bool _saving = false;
  int _rentDurationMonths = 12;
  bool _messagingEnabled = true;

  /// Non-Shortlet only: let tenants pay month by month.
  bool _allowMonthlyPayment = false;

  bool get _isEditing => widget.initial != null;

  /// Editing a listing whose photo changes are used up: the photos can't be
  /// changed until the lock ends (see backend PropertiesService.update).
  bool get _photosLocked => widget.initial?.imagesLocked ?? false;

  /// Whether the photos (or their order) differ from what's saved.
  bool get _photosChanged {
    final initial = widget.initial;
    if (initial == null) return false;
    final before = [initial.image, ...initial.galleryImages];
    final now = _images.map((i) => i.path).toList();
    if (before.length != now.length) return true;
    for (var i = 0; i < now.length; i++) {
      if (before[i] != now[i]) return true;
    }
    return false;
  }

  /// Asks before a save that uses the listing's last photo change.
  Future<bool> _confirmLastPhotoChange() async {
    final initial = widget.initial;
    if (initial == null || !_photosChanged || initial.imageChangesLeft != 1) return true;
    final days = initial.imageLockDays ?? 14;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: Colors.white,
            title: Text('Last photo change', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
            content: Text(
              "This is the last time you can change this listing's photos for now. After saving, they'll be locked for $days days.",
              style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.8), size: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text('Go back', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600)),
              ),
              TextButton(
                style: TextButton.styleFrom(backgroundColor: AppColors.navy),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text('Save photos', style: AppTextStyles.body(color: Colors.white, weight: FontWeight.w700)),
              ),
            ],
          ),
    );
    return ok == true;
  }

  @override
  void initState() {
    super.initState();
    // Keeps the monthly-payment card's "₦…/month" in step with the price.
    _price.addListener(_onPriceChanged);
    final initial = widget.initial;
    if (initial == null) return;
    _title.text = initial.title;
    _location.text = initial.location;
    _price.text = initial.price.toString();
    _bedrooms.text = initial.bedrooms.toString();
    _bathrooms.text = initial.bathrooms.toString();
    _description.text = initial.description;
    _unitAddress.text = initial.unitAddress ?? '';
    _roomNumber.text = initial.roomNumber ?? '';
    _category = initial.category;
    _state = initial.state;
    _rentDurationMonths = initial.rentDurationMonths ?? 12;
    _messagingEnabled = initial.messagingEnabled;
    _allowMonthlyPayment = initial.allowMonthlyPayment;
    _images.addAll([
      PickedUpload(path: initial.image, fileName: 'cover', isImage: true),
      for (final url in initial.galleryImages) PickedUpload(path: url, fileName: 'photo', isImage: true),
    ]);
    _videoPath = initial.videoPath;
    _videoFileName = initial.videoPath?.split('/').last;
  }

  void _onPriceChanged() {
    if (mounted && _category != 'Shortlet') setState(() {});
  }

  @override
  void dispose() {
    _price.removeListener(_onPriceChanged);
    _title.dispose();
    _location.dispose();
    _price.dispose();
    _bedrooms.dispose();
    _bathrooms.dispose();
    _description.dispose();
    _unitAddress.dispose();
    _roomNumber.dispose();
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

  /// Returns true if payout details are already on file, or the landlord
  /// just set them up from the popup below (in which case the caller
  /// should still stop this submit attempt and let them tap "Add
  /// Property" again — [AppState] is refreshed either way). The server
  /// enforces this for real on `POST /properties`; this is only the
  /// friendly client-side steer so a submit doesn't sail straight into a
  /// guaranteed 400.
  Future<bool> _ensurePayoutDetails() async {
    final appState = context.read<AppState>();
    if (appState.accountNumber != null && appState.accountNumber!.isNotEmpty) return true;
    final proceed = await showPayoutRequiredDialog(
      context,
      body:
          'Please add your Payout Account details in Settings before listing a property. '
          'Tenant rent payments are held in escrow and released to your bank account.',
    );
    if (proceed == true && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BankDetailsScreen.landlord()));
    }
    return false;
  }

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
    if (_category == 'Shortlet' && (_unitAddress.text.trim().isEmpty || _roomNumber.text.trim().isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unit address and room number are required for a Shortlet')));
      return;
    }
    if (!_isEditing && !await _ensurePayoutDetails()) return;
    if (!mounted || !await _confirmLastPhotoChange() || !mounted) return;
    setState(() => _saving = true);
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final landlordName = appState.fullName.trim().isEmpty ? 'You' : appState.fullName.trim();
    try {
      final imageUrls = <String>[];
      for (final image in _images) {
        // Already-hosted photos (editing an existing listing) are reused
        // as-is rather than re-uploaded.
        if (image.path.startsWith('http://') || image.path.startsWith('https://')) {
          imageUrls.add(image.path);
        } else {
          imageUrls.add(await appState.uploads.upload(file: image, folder: 'properties'));
        }
      }
      // A newly picked walkthrough video is uploaded like the photos; an
      // unchanged one is already a hosted URL.
      String? videoUrl = _videoPath;
      if (videoUrl != null && !videoUrl.startsWith('http')) {
        videoUrl = await appState.uploads.upload(
          file: PickedUpload(path: videoUrl, fileName: _videoFileName ?? videoUrl.split('/').last, isImage: false),
          folder: 'property-videos',
          maxBytes: _maxVideoBytes,
        );
      }
      final isShortlet = _category == 'Shortlet';
      final basis = widget.initial;
      final property =
          (basis?.copyWith(
            clearVideo: videoUrl == null,
            title: _title.text.trim(),
            location: _location.text.trim(),
            state: _state!,
            image: imageUrls.first,
            galleryImages: imageUrls.skip(1).toList(),
            category: _category,
            price: int.tryParse(_price.text.replaceAll(',', '')) ?? 0,
            priceUnit: isShortlet ? 'night' : 'year',
            bedrooms: int.tryParse(_bedrooms.text) ?? 0,
            bathrooms: int.tryParse(_bathrooms.text) ?? 0,
            description: _description.text.trim(),
            videoPath: videoUrl,
            rentDurationMonths: isShortlet ? null : _rentDurationMonths,
            messagingEnabled: _messagingEnabled,
            allowMonthlyPayment: !isShortlet && _allowMonthlyPayment,
            unitAddress: isShortlet ? _unitAddress.text.trim() : null,
            roomNumber: isShortlet ? _roomNumber.text.trim() : null,
          )) ??
          Property(
            id: '',
            title: _title.text.trim(),
            location: _location.text.trim(),
            state: _state!,
            rating: 0,
            image: imageUrls.first,
            galleryImages: imageUrls.skip(1).toList(),
            category: _category,
            price: int.tryParse(_price.text.replaceAll(',', '')) ?? 0,
            priceUnit: isShortlet ? 'night' : 'year',
            bedrooms: int.tryParse(_bedrooms.text) ?? 0,
            bathrooms: int.tryParse(_bathrooms.text) ?? 0,
            description: _description.text.trim(),
            landlordName: landlordName,
            videoPath: videoUrl,
            rentDurationMonths: isShortlet ? null : _rentDurationMonths,
            messagingEnabled: _messagingEnabled,
            allowMonthlyPayment: !isShortlet && _allowMonthlyPayment,
            unitAddress: isShortlet ? _unitAddress.text.trim() : null,
            roomNumber: isShortlet ? _roomNumber.text.trim() : null,
          );
      final saved =
          _isEditing ? await appState.updateLandlordProperty(property) : await appState.addLandlordProperty(property);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_isEditing ? '${saved.title} updated' : '${saved.title} added to My Properties')),
      );
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashboardPageScaffold(
      background: AppColors.offWhite,
      foreground: AppColors.navy,
      title: _isEditing ? 'Edit Property' : 'Add Property',
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
              if (_isEditing && widget.initial!.imageChangesAllowed != null) ...[
                const SizedBox(height: 4),
                _PhotoAllowanceNote(property: widget.initial!),
              ],
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
                          onRemove: _photosLocked ? null : () => setState(() => _images.remove(image)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image(image: image.imageProvider, width: 84, height: 84, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    if (_images.length < _maxImages && !_photosLocked)
                      Tooltip(message: 'Add photos', child: Semantics(button: true, child: GestureDetector(
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
                      ))),
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
              if (_isEditing)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Text(
                    'Changing the price or lease length notifies tenants who have booked this property. '
                    "It doesn't change what anyone has already paid; current tenants pay the new rent if they renew.",
                    // Darker than hintGrey, which is under 4.5:1 on offWhite.
                    style: AppTextStyles.body(color: const Color(0xFF5B6170), size: 11.5),
                  ),
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
              const SizedBox(height: 14),
              if (_category == 'Shortlet') ...[
                PillTextField(hint: 'Unit address', controller: _unitAddress, validator: _required),
                const SizedBox(height: 14),
                PillTextField(hint: 'Room number', controller: _roomNumber, validator: _required),
              ] else
                _RentDurationPicker(
                  months: _rentDurationMonths,
                  onChanged: (value) => setState(() => _rentDurationMonths = value),
                ),
              const SizedBox(height: 18),
              _MessagingToggle(
                value: _messagingEnabled,
                onChanged: (value) => setState(() => _messagingEnabled = value),
              ),
              if (_category != 'Shortlet') ...[
                const SizedBox(height: 12),
                _MonthlyPaymentToggle(
                  value: _allowMonthlyPayment,
                  yearlyPrice: int.tryParse(_price.text.replaceAll(',', '')),
                  onChanged: (value) => setState(() => _allowMonthlyPayment = value),
                ),
              ],
              const SizedBox(height: 26),
              PillButton(
                label: _saving ? (_isEditing ? 'Saving…' : 'Adding…') : (_isEditing ? 'Save Changes' : 'Add Property'),
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
            Tooltip(message: 'Remove file', child: Semantics(button: true, child: InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, color: AppColors.hintGrey, size: 18),
              ),
            ))),
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
/// "2 of 3 photo changes left" — or, once they're used up, until when the
/// photos are locked and that deleting the listing is the way round it.
/// Navy on the offWhite page background.
class _PhotoAllowanceNote extends StatelessWidget {
  const _PhotoAllowanceNote({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final allowed = property.imageChangesAllowed!;
    final left = property.imageChangesLeft ?? allowed;
    final days = property.imageLockDays ?? 14;
    final text =
        property.imagesLocked
            ? "Photos locked until ${formatShortDate(property.imagesLockedUntil!.toLocal())} — you've used all $allowed photo "
                "changes for this listing. You can still edit everything else. To use different photos sooner, delete the "
                "listing and list it again (not possible while it's occupied)."
            : '$left of $allowed photo changes left. Each save that changes the photos uses one; after the last one, '
                'photos lock for $days days.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (property.imagesLocked ? const Color(0xFFB54708) : AppColors.navy).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            property.imagesLocked ? Icons.lock_clock_outlined : Icons.photo_library_outlined,
            size: 18,
            color: property.imagesLocked ? const Color(0xFF93370D) : AppColors.navy,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body(
                color: property.imagesLocked ? const Color(0xFF93370D) : AppColors.navy,
                size: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickedPhotoTile extends StatelessWidget {
  const _PickedPhotoTile({required this.child, required this.isCover, required this.onRemove});

  final Widget child;
  final bool isCover;

  /// Null hides the remove button (photos locked).
  final VoidCallback? onRemove;

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
                child: Text(
                  'Cover',
                  style: AppTextStyles.body(color: Colors.white, size: 9.5, weight: FontWeight.w700),
                ),
              ),
            ),
          if (onRemove != null)
            Positioned(
              top: -6,
              right: -6,
              child: Tooltip(message: 'Remove photo', child: Semantics(button: true, child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                ),
              ))),
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
          items: [for (final state in nigerianStates) DropdownMenuItem(value: state, child: Text(state))],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Lease-length picker (6-24 months, steps of 6) — required for every
/// non-Shortlet category, since a Shortlet has no fixed-term lease at all.
class _RentDurationPicker extends StatelessWidget {
  const _RentDurationPicker({required this.months, required this.onChanged});

  final int months;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rent duration: $months month${months == 1 ? '' : 's'}',
            style: AppTextStyles.body(color: AppColors.navy, size: 13.5, weight: FontWeight.w600),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(activeTrackColor: AppColors.navy, thumbColor: AppColors.navy),
            child: Slider(
              value: months.toDouble(),
              min: 6,
              max: 24,
              divisions: 3,
              label: '$months months',
              onChanged: (value) => onChanged(value.round()),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Allow Tenant Messages" for this listing: sets
/// `Property.messagingEnabled`, which hides the Message button and blocks
/// new chats about it when off.
class _MessagingToggle extends StatelessWidget {
  const _MessagingToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.navy, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Allow Tenant Messages',
                  style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w600),
                ),
                Text(
                  'Off means tenants pay rent directly — no messaging or inspection booking for this listing',
                  style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged, activeColor: AppColors.navy),
        ],
      ),
    );
  }
}

/// "Allow monthly payments" — white card, navy text (same as the messaging
/// toggle above it). Shows what a month would cost at the price entered.
class _MonthlyPaymentToggle extends StatelessWidget {
  const _MonthlyPaymentToggle({required this.value, required this.yearlyPrice, required this.onChanged});

  final bool value;
  final int? yearlyPrice;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final perMonth = yearlyPrice != null && yearlyPrice! > 0 ? ' (₦${formatNaira((yearlyPrice! / 12).ceil())}/month)' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined, color: AppColors.navy, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Allow Monthly Payments',
                  style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w600),
                ),
                Text(
                  'Tenants can pay a twelfth of the yearly rent each month$perMonth: the first month up front, held '
                  "until they move in, then each month as it's due. You're told if a month is missed.",
                  style: AppTextStyles.body(color: const Color(0xFF5B6170), size: 11.5),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged, activeColor: AppColors.navy),
        ],
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
