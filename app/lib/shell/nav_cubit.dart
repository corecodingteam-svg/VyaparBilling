import 'package:flutter_bloc/flutter_bloc.dart';

import 'nav.dart';

/// Which sidebar groups are expanded.
class NavCubit extends Cubit<Set<String>> {
  NavCubit(String location)
    : super({
        for (final s in navSections)
          if (s.children.any((c) => location.startsWith(c.path))) s.label,
      });

  void toggle(String section) => emit(state.contains(section) ? ({...state}..remove(section)) : {...state, section});
}
