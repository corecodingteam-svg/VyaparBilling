import 'package:flutter_bloc/flutter_bloc.dart';

/// The set of things ticked in a pick-list dialog.
class SelectionCubit<T> extends Cubit<Set<T>> {
  SelectionCubit([Set<T> initial = const {}]) : super({...initial});

  void toggle(T value) => emit(state.contains(value) ? ({...state}..remove(value)) : {...state, value});
  void set(Iterable<T> values) => emit({...values});
}
