import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/keyboard/keyboard_prefs.dart';
import 'widgets.dart';

/// A box for a barcode scanner or a typed item code. A scanner is a keyboard that types the code and presses Enter, so
/// on Enter the code is handed to [onCode]. When that adds an item the box is emptied for the next scan and keeps the
/// cursor (Settings › Keyboard: return focus to the item/barcode box), or, with that setting off, [onAddedMoveTo] takes
/// it on (the new row's quantity). When nothing was added the code stays, selected, so the next scan replaces it.
class ScanField extends StatefulWidget {
  const ScanField({
    super.key,
    required this.onCode,
    this.onChanged,
    this.onAddedMoveTo,
    this.hint = 'Scan or type item code',
    this.notFound = _noSuchCode,
    this.autofocus = false,
  });

  /// Adds the item for the code; returns whether it did.
  final bool Function(String code) onCode;

  /// For a box that also filters a list as you type.
  final ValueChanged<String>? onChanged;
  final VoidCallback? onAddedMoveTo;
  final String hint;

  /// The message shown when nothing was added for a code.
  final String Function(String code) notFound;

  static String _noSuchCode(String code) => 'No item has the code "$code".';
  final bool autofocus;

  @override
  State<ScanField> createState() => _ScanFieldState();
}

/// Stateful only to own the box's text and focus.
class _ScanFieldState extends State<ScanField> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Scan');

  void _submit(String value) {
    final code = value.trim();
    if (code.isEmpty) return;
    if (!widget.onCode(code)) {
      _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      showError(context, widget.notFound(code));
      return;
    }
    _text.clear();
    widget.onChanged?.call('');
    final stay = context.read<KeyboardPrefsCubit?>()?.state.barcodeReturnFocus ?? true;
    if (stay || widget.onAddedMoveTo == null) {
      _focus.requestFocus();
    } else {
      widget.onAddedMoveTo!();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        // Enter is the end of a scan: look the code up, and keep the cursor here (not the usual "done, leave the box").
        onEditingComplete: () {},
        onSubmitted: _submit,
        decoration: InputDecoration(hintText: widget.hint, prefixIcon: const Icon(Icons.qr_code_scanner)),
      );
}
