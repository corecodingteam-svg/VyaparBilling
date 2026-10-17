import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'keyboard_prefs.dart';

/// A part of a page that Tab and Enter finish before moving on, so the customer's fields come before the invoice
/// details even when the two sit side by side. Inside an [OrderedFocus], parts are visited by [order]; elsewhere in
/// reading order.
class FocusSection extends StatelessWidget {
  const FocusSection({super.key, this.order, required this.child});
  final double? order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final group = FocusTraversalGroup(child: child);
    return order == null ? group : FocusTraversalOrder(order: NumericFocusOrder(order!), child: group);
  }
}

/// Visits the [FocusSection]s below it by their order rather than where they are on screen: a form before its top bar,
/// a page's content before the sidebar. Give every section in it an order.
class OrderedFocus extends StatelessWidget {
  const OrderedFocus({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: child);
}

/// Whether [node] is somewhere to type: an editable text input that is not read-only.
bool isTypingTarget(FocusNode node) {
  final context = node.context;
  if (context == null || !node.canRequestFocus || node.skipTraversal) return false;
  final editable = context.findAncestorStateOfType<EditableTextState>();
  return editable != null && !editable.widget.readOnly;
}

/// In Keyboard First and Keyboard Only modes, puts the cursor in the first text input below it when it appears, unless
/// something below it already has focus. In Standard mode it does nothing, so phones do not pop their keyboard open.
///
/// A new [page] (a different value) does it again, for an area whose content changes, such as the shell around each page.
class FocusFirstField extends StatefulWidget {
  const FocusFirstField({super.key, this.page, required this.child});
  final Object? page;
  final Widget child;

  @override
  State<FocusFirstField> createState() => _FocusFirstFieldState();
}

class _FocusFirstFieldState extends State<FocusFirstField> {
  final _node = FocusNode(debugLabel: 'FocusFirstField', skipTraversal: true, canRequestFocus: false);

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(FocusFirstField old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) _schedule(again: true);
  }

  void _schedule({bool again = false}) {
    final mode = context.read<KeyboardPrefsCubit?>()?.state.mode ?? KeyboardMode.standard;
    if (mode == KeyboardMode.standard) return;
    // After the next frame, when the fields are laid out and their positions known.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirst(again: again));
  }

  void _focusFirst({required bool again}) {
    // Focus left in the previous page's content does not count as already being here.
    if (!mounted || (_node.hasFocus && !again)) return;
    final fields = _node.traversalDescendants.where(isTypingTarget).toList();
    if (fields.isEmpty) return;
    // The top-left field in reading order. Rows are compared with a little slack, since inputs in one row differ by a pixel.
    fields.sort((a, b) {
      final dy = a.rect.top - b.rect.top;
      return dy.abs() > 4 ? dy.sign.toInt() : a.rect.left.compareTo(b.rect.left);
    });
    fields.first.requestFocus();
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _node, child: widget.child);
}
