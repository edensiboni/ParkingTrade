import 'package:flutter/material.dart';

import '../services/address_autocomplete_service.dart';

/// Result returned when the user selects an address suggestion.
class AddressResult {
  /// Full formatted address string (e.g. "12 Herzl St, Tel Aviv, Israel").
  final String address;

  /// Latitude, or null if geocoding was not available.
  final double? latitude;

  /// Longitude, or null if geocoding was not available.
  final double? longitude;

  const AddressResult({
    required this.address,
    this.latitude,
    this.longitude,
  });
}

/// A [TextFormField]-style widget that shows a Google Places Autocomplete
/// dropdown as the user types.
///
/// When the user picks a suggestion, [onAddressSelected] is called with the
/// full [AddressResult] (address + optional lat/lng).
///
/// Falls back gracefully to a plain text field when the Places API key is not
/// configured or when running on web without an Edge Function.
class AddressAutocompleteField extends StatefulWidget {
  /// Initial text to pre-populate the field with.
  final String? initialValue;

  /// Hint shown inside the field.
  final String hintText;

  /// Label shown above the field.
  final String labelText;

  /// Validator — receives the current address text.
  final String? Function(String?)? validator;

  /// Called when the user selects a suggestion from the dropdown.
  final void Function(AddressResult result)? onAddressSelected;

  /// Called when the text changes (for plain-text fallback scenarios).
  final void Function(String value)? onChanged;

  const AddressAutocompleteField({
    super.key,
    this.initialValue,
    this.hintText = 'e.g. 12 Herzl St, Tel Aviv',
    this.labelText = 'Building Address',
    this.validator,
    this.onAddressSelected,
    this.onChanged,
  });

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _service = AddressAutocompleteService();

  List<AddressSuggestion> _suggestions = [];
  bool _loading = false;
  bool _showDropdown = false;
  OverlayEntry? _overlayEntry;
  final _fieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _service.cancel();
    _removeOverlay();
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      // Small delay so taps on suggestions register before we hide.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _hideDropdown();
      });
    }
  }

  // ── Suggestion fetching ───────────────────────────────────────────────────────

  Future<void> _onTextChanged(String value) async {
    widget.onChanged?.call(value);

    if (!AddressAutocompleteService.isAvailable || value.trim().length < 3) {
      _hideDropdown();
      return;
    }

    setState(() => _loading = true);
    final suggestions = await _service.suggest(value);
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
      _loading = false;
    });

    if (suggestions.isNotEmpty) {
      _showSuggestions();
    } else {
      _hideDropdown();
    }
  }

  Future<void> _onSuggestionTapped(AddressSuggestion suggestion) async {
    _controller.text = suggestion.displayText;
    _hideDropdown();
    _focusNode.unfocus();

    LatLng? latLng;
    if (suggestion.placeId != null) {
      latLng = await _service.fetchLatLng(suggestion.placeId!);
    }

    widget.onAddressSelected?.call(AddressResult(
      address: suggestion.displayText,
      latitude: latLng?.lat,
      longitude: latLng?.lng,
    ));
  }

  // ── Overlay management ────────────────────────────────────────────────────────

  void _showSuggestions() {
    _removeOverlay();
    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy + size.height + 4,
        width: size.width,
        child: _SuggestionDropdown(
          suggestions: _suggestions,
          onTap: _onSuggestionTapped,
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _showDropdown = true);
  }

  void _hideDropdown() {
    _removeOverlay();
    if (mounted) setState(() => _showDropdown = false);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: _fieldKey,
      controller: _controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.done,
      onChanged: _onTextChanged,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.location_on_rounded),
        suffixIcon: _loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _showDropdown
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Clear',
                    onPressed: () {
                      _controller.clear();
                      _hideDropdown();
                      widget.onChanged?.call('');
                    },
                  )
                : null,
      ),
    );
  }
}

// ── Dropdown widget ───────────────────────────────────────────────────────────

class _SuggestionDropdown extends StatelessWidget {
  final List<AddressSuggestion> suggestions;
  final void Function(AddressSuggestion) onTap;

  const _SuggestionDropdown({
    required this.suggestions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: colorScheme.surface,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: colorScheme.outlineVariant,
            ),
            itemBuilder: (context, index) {
              final s = suggestions[index];
              return InkWell(
                onTap: () => onTap(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.place_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.displayText,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
