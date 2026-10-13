import 'package:flutter_bloc/flutter_bloc.dart';

/// A single value a small piece of UI needs to remember (a picked date, a chosen tab).
class ValueCubit<T> extends Cubit<T> {
  ValueCubit(super.initial);
  void set(T value) => emit(value);
}
