import 'package:flutter/material.dart';

import 'tokens.dart';
import '../theme.dart';

/// Validators for form fields. Every message names the field and says what is needed, so the user never has to guess
/// which field is meant or what to put in it. Use these instead of writing a message inline.
abstract final class Validators {
  /// A text value that must not be empty: "Party name is required".
  static String? Function(String?) required(String label) => (v) => (v ?? '').trim().isEmpty ? '$label is required' : null;

  /// A dropdown or picker that must have a choice: "Select the bank account".
  static String? Function(T?) choose<T>(String label) => (v) => v == null || (v is String && v.trim().isEmpty) ? 'Select the $label' : null;

  static String? Function(String?) minLength(String label, int n) => (v) => (v ?? '').trim().length < n ? '$label must be at least $n characters' : null;

  /// A number, optionally required, positive or non-negative. [label] is the field's name.
  static String? Function(String?) number(String label, {bool required = false, bool positive = false, bool nonNegative = false, num? max, bool whole = false}) => (v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return required ? '$label is required' : null;
    final n = num.tryParse(text.replaceAll(',', '').replaceAll('₹', '').trim());
    if (n == null) return '$label must be a number';
    if (whole && n != n.roundToDouble()) return '$label must be a whole number';
    if (positive && n <= 0) return '$label must be greater than 0';
    if (nonNegative && n < 0) return '$label cannot be negative';
    if (max != null && n > max) return '$label cannot be more than ${max == max.roundToDouble() ? max.round() : max}';
    return null;
  };

  /// An optional value that, when given, must match [pattern]; [hint] says what a valid one looks like.
  static String? Function(String?) pattern(String label, RegExp pattern, String hint, {bool required = false}) => (v) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return required ? '$label is required' : null;
    return pattern.hasMatch(text) ? null : '$label must be $hint';
  };

  static String? Function(String?) email({String label = 'Email', bool required = false}) =>
      pattern(label, RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$'), 'a valid address, like name@example.com', required: required);

  static String? Function(String?) pan({String label = 'PAN'}) => pattern(label, RegExp(r'^[A-Za-z]{5}[0-9]{4}[A-Za-z]$'), '5 letters, 4 digits and a letter, like ABCDE1234F');
  static String? Function(String?) tan({String label = 'TAN'}) => pattern(label, RegExp(r'^[A-Za-z]{4}[0-9]{5}[A-Za-z]$'), '4 letters, 5 digits and a letter, like PNEA12345B');
  static String? Function(String?) pincode({String label = 'Pincode'}) => pattern(label, RegExp(r'^[1-9][0-9]{5}$'), '6 digits and not start with 0');
  static String? Function(String?) hsn({String label = 'HSN/SAC code'}) => pattern(label, RegExp(r'^[0-9]{4,8}$'), '4 to 8 digits');
  static String? Function(String?) digits(String label, int count, {bool required = false}) => pattern(label, RegExp('^\\d{$count}\$'), '$count digits', required: required);

  /// A value that must equal [other()] (a repeated password).
  static String? Function(String?) matches(String label, String Function() other) => (v) => v == other() ? null : '$label does not match';

  /// The first message of several validators.
  static String? Function(String?) all(List<String? Function(String?)> validators) => (v) {
    for (final f in validators) {
      final m = f(v);
      if (m != null) return m;
    }
    return null;
  };
}

/// Runs the form's validators. When something is wrong it scrolls to the first invalid field, puts the cursor in it
/// and tells the user, in one message, how many fields need attention and what each needs. Returns whether the form is valid.
bool validateForm(BuildContext context, GlobalKey<FormState> key, {void Function(BuildContext, String)? report}) {
  final form = key.currentState;
  if (form == null || form.validate()) return true;
  final invalid = <FormFieldState<dynamic>>[];
  void visit(Element e) {
    if (e is StatefulElement && e.state is FormFieldState && (e.state as FormFieldState).hasError) invalid.add(e.state as FormFieldState);
    e.visitChildren(visit);
  }

  key.currentContext?.visitChildElements(visit);
  if (invalid.isEmpty) return false;
  final first = invalid.first;
  if (first.mounted) {
    Scrollable.ensureVisible(first.context, alignment: 0.15, duration: AppMotion.normal, curve: AppMotion.curve);
    _focusIn(first.context);
  }
  final messages = [for (final f in invalid) if (f.errorText != null) f.errorText!];
  final text = invalid.length == 1 ? messages.first : '${invalid.length} fields need attention: ${messages.take(3).join(' · ')}${messages.length > 3 ? ' · …' : ''}';
  if (report != null && context.mounted) report(context, text);
  return false;
}

/// Puts the cursor in the first text input inside [context].
void _focusIn(BuildContext context) {
  void visit(Element e) {
    final w = e.widget;
    if (w is EditableText) {
      w.focusNode.requestFocus();
      return;
    }
    e.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
}

/// What is wrong with one part of a form that is not a plain text field (a list of items, a payment split), and where.
class FormIssue {
  const FormIssue(this.field, this.message);

  /// Which part of the form: any string the form understands, e.g. 'party', 'items', 'row:3'.
  final String field;
  final String message;
}

/// Outlines a part of a form in red and writes what is wrong underneath it, when [issue] is for this [field]. It also scrolls
/// to the part the first time the issue appears. Used around dropdowns, date pickers, item tables and anything else that does not
/// draw its own error like a text field does.
class FieldHighlight extends StatefulWidget {
  const FieldHighlight({super.key, required this.field, this.also = const [], required this.issue, required this.child});
  final String field;
  /// Other field ids this wrapper also stands for (a section with several related fields).
  final List<String> also;
  final FormIssue? issue;
  final Widget child;

  @override
  State<FieldHighlight> createState() => _FieldHighlightState();
}

class _FieldHighlightState extends State<FieldHighlight> {
  bool _matches(FormIssue? i) => i != null && (i.field == widget.field || widget.also.contains(i.field));
  bool get _active => _matches(widget.issue);

  @override
  void didUpdateWidget(FieldHighlight old) {
    super.didUpdateWidget(old);
    final was = _matches(old.issue) && old.issue?.message == widget.issue?.message;
    if (_active && !was) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context, alignment: 0.15, duration: AppMotion.normal, curve: AppMotion.curve);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: AppMotion.fast,
    curve: AppMotion.curve,
    decoration: BoxDecoration(
      borderRadius: AppRadius.mdAll,
      border: Border.all(color: _active ? AppColors.dangerText : Colors.transparent, width: 1.5),
      color: _active ? AppColors.dangerSoft.withValues(alpha: 0.35) : Colors.transparent,
    ),
    padding: _active ? const EdgeInsets.all(AppSpace.xs) : EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.child,
        if (_active)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs, left: AppSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: AppIconSize.xs, color: AppColors.dangerText),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(widget.issue!.message, style: AppText.error)),
              ],
            ),
          ),
      ],
    ),
  );
}
