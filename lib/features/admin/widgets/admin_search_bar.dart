import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Debounced search field shared by every admin list tab — waits for a
/// short pause in typing before calling [onChanged], so each keystroke
/// doesn't fire its own network request.
class AdminSearchBar extends StatefulWidget {
  const AdminSearchBar({super.key, required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<AdminSearchBar> createState() => _AdminSearchBarState();
}

class _AdminSearchBarState extends State<AdminSearchBar> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => widget.onChanged(value));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: TextField(
        controller: _controller,
        onChanged: _onChanged,
        style: AppTextStyles.body(color: AppColors.navy, size: 14),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.hintGrey),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}
