import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/design/keyboard_nav.dart';
import 'app_command.dart';
import 'focus_order.dart';
import 'keyboard_scope.dart';

/// Keys for a list or table whose rows take focus (list tiles, table rows). ↑ and ↓ are Flutter's own and move a row at a
/// time; this adds Home and End (first and last row), Page Up and Page Down (previous and next page, when there are
/// pages), and the First record / Last record shortcuts (Ctrl+Home / Ctrl+End: the very first and last row, across pages).
/// A text box inside (the search box) keeps these keys for its text.
///
/// Rows are table rows and list tiles (or, in a list of anything else, each band of focusable things across it), and the
/// leftmost focusable part of a row (the row itself, before any menu button on it) is where focus goes.
class RowNavigation extends StatefulWidget {
  const RowNavigation({super.key, this.onNextPage, this.onPreviousPage, this.onFirstPage, this.onLastPage, required this.child});

  /// Turn the page; null when there is no such page.
  final VoidCallback? onNextPage, onPreviousPage, onFirstPage, onLastPage;
  final Widget child;

  @override
  State<RowNavigation> createState() => _RowNavigationState();
}

class _RowNavigationState extends State<RowNavigation> {
  final _node = FocusNode(debugLabel: 'RowNavigation', skipTraversal: true, canRequestFocus: false);

  /// The first focusable thing of each row, top to bottom. Only rows that are built (on screen or near it) are found.
  List<FocusNode> _rows() {
    var nodes = _node.traversalDescendants.where((n) => n.context != null && !isTypingTarget(n) && n.rect.height > 0).toList();
    // Table rows and list tiles, when there are any, so the column headings above them (which sort) are not rows.
    final rowParts = nodes.where(_inRowWidget).toList();
    if (rowParts.isNotEmpty) nodes = rowParts;
    nodes.sort((a, b) => a.rect.top.compareTo(b.rect.top));
    final rows = <FocusNode>[];
    var bottom = double.negativeInfinity;
    for (final n in nodes) {
      if (n.rect.top >= bottom - 1) {
        rows.add(n);
        bottom = n.rect.bottom;
      } else if (n.rect.left < rows.last.rect.left) {
        rows[rows.length - 1] = n;
      }
    }
    return rows;
  }

  static bool _inRowWidget(FocusNode n) =>
      n.context!.findAncestorWidgetOfExactType<TableRowInkWell>() != null || n.context!.findAncestorWidgetOfExactType<ListTile>() != null;

  bool get _onRow {
    final focus = FocusManager.instance.primaryFocus;
    return focus != null && _node.hasFocus && !isTypingTarget(focus);
  }

  /// The list's own scrolling (not the page around it), so the rows at its ends get built before focus goes there.
  ScrollPosition? _ownScroll(FocusNode row) {
    final scrollable = row.context == null ? null : Scrollable.maybeOf(row.context!);
    if (scrollable == null || scrollable.context.findAncestorStateOfType<_RowNavigationState>() != this) return null;
    return scrollable.position;
  }

  void _goTo({required bool first}) {
    final rows = _rows();
    if (rows.isEmpty) return;
    final scroll = _ownScroll(rows.first);
    if (scroll == null) {
      (first ? rows.first : rows.last).requestFocus();
      return;
    }
    scroll.jumpTo(first ? scroll.minScrollExtent : scroll.maxScrollExtent);
    afterNextFrame(() {
      final now = _rows();
      if (mounted && now.isNotEmpty) (first ? now.first : now.last).requestFocus();
    });
  }

  void _turn(VoidCallback? page, {required bool first}) {
    if (page == null) return _goTo(first: first);
    page();
    afterNextFrame(() {
      if (mounted) _goTo(first: first);
    });
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || !_onRow) return KeyEventResult.ignored;
    final k = HardwareKeyboard.instance;
    if (k.isControlPressed || k.isMetaPressed || k.isAltPressed || k.isShiftPressed) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.home) {
      _goTo(first: true);
    } else if (key == LogicalKeyboardKey.end) {
      _goTo(first: false);
    } else if (key == LogicalKeyboardKey.pageDown && widget.onNextPage != null) {
      _turn(widget.onNextPage, first: true);
    } else if (key == LogicalKeyboardKey.pageUp && widget.onPreviousPage != null) {
      _turn(widget.onPreviousPage, first: true);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyboardScope(
        name: 'List',
        commands: {
          AppCommand.firstRecord: () => _turn(widget.onFirstPage, first: true),
          AppCommand.lastRecord: () => _turn(widget.onLastPage, first: false),
        },
        child: Focus(focusNode: _node, onKeyEvent: _key, child: widget.child),
      );
}
