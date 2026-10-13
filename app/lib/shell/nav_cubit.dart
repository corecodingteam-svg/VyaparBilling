import 'package:flutter_bloc/flutter_bloc.dart';

import 'nav.dart';

/// Which sidebar groups are expanded.
class NavCubit extends Cubit<Set<String>> {
  NavCubit(String location)
    : super({
        for (final s in navSections)
          if (s.children.any((c) => navActive(location, c.path))) s.label,
      });

  String? _revealed;

  /// Opens [keys] (a menu and its group) once per page, so the sidebar shows where the current page is
  /// without fighting the user who closes it again.
  void reveal(String location, Iterable<String> keys) {
    if (_revealed == location) return;
    _revealed = location;
    emit({...state, ...keys});
  }

  void toggle(String section) => emit(state.contains(section) ? ({...state}..remove(section)) : {...state, section});
}
