import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/change_bus.dart';
import '../../../core/status.dart';
import '../../../data/models/expense.dart';
import '../../../data/repositories/expenses_repository.dart';

sealed class ExpensesEvent {
  const ExpensesEvent();
}

class ExpensesRequested extends ExpensesEvent {
  const ExpensesRequested();
}

class ExpenseCategorySelected extends ExpensesEvent {
  const ExpenseCategorySelected(this.id);
  final String id;
}

class ExpenseCategorySearchChanged extends ExpensesEvent {
  const ExpenseCategorySearchChanged(this.query);
  final String query;
}

class ExpenseDeleted extends ExpensesEvent {
  const ExpenseDeleted(this.id);
  final String id;
}

class ExpenseCategoryDeleted extends ExpensesEvent {
  const ExpenseCategoryDeleted(this.id);
  final String id;
}

class ExpensesState extends Equatable {
  const ExpensesState({
    this.status = LoadStatus.initial,
    this.categories = const [],
    this.search = '',
    this.selectedId,
    this.expensesStatus = LoadStatus.initial,
    this.expenses = const [],
    this.error,
  });

  final LoadStatus status;
  final List<ExpenseCategory> categories;
  final String search;
  final String? selectedId;
  final LoadStatus expensesStatus;

  /// Expenses of the selected category.
  final List<ExpenseSummary> expenses;

  /// Set when a load or delete fails; shown once by the screen.
  final String? error;

  ExpenseCategory? get selected => categories.where((c) => c.id == selectedId).firstOrNull;

  List<ExpenseCategory> get visible {
    final term = search.trim().toLowerCase();
    return term.isEmpty ? categories : categories.where((c) => c.name.toLowerCase().contains(term)).toList();
  }

  num get total => categories.fold<num>(0, (s, c) => s + c.total);

  ExpensesState copyWith({
    LoadStatus? status,
    List<ExpenseCategory>? categories,
    String? search,
    String? Function()? selectedId,
    LoadStatus? expensesStatus,
    List<ExpenseSummary>? expenses,
    String? error,
  }) =>
      ExpensesState(
        status: status ?? this.status,
        categories: categories ?? this.categories,
        search: search ?? this.search,
        selectedId: selectedId != null ? selectedId() : this.selectedId,
        expensesStatus: expensesStatus ?? this.expensesStatus,
        expenses: expenses ?? this.expenses,
        error: error,
      );

  @override
  List<Object?> get props => [status, categories, search, selectedId, expensesStatus, expenses, error];
}

/// Expense categories with totals, the selected category and its expenses.
class ExpensesBloc extends Bloc<ExpensesEvent, ExpensesState> {
  ExpensesBloc(this._repo, ChangeBus bus) : super(const ExpensesState()) {
    on<ExpensesRequested>((_, emit) => _load(emit));
    on<ExpenseCategorySearchChanged>((e, emit) => emit(state.copyWith(search: e.query)));
    on<ExpenseCategorySelected>((e, emit) async {
      emit(state.copyWith(selectedId: () => e.id, expensesStatus: LoadStatus.loading, expenses: const []));
      await _loadExpenses(emit);
    });
    // Deletes go through the repository; the bus then triggers a reload.
    on<ExpenseDeleted>((e, emit) => _guard(emit, () => _repo.delete(e.id)));
    on<ExpenseCategoryDeleted>((e, emit) => _guard(emit, () => _repo.deleteCategory(e.id)));
    _sub = bus.on({DataTopic.expenses}).listen((_) => add(const ExpensesRequested()));
  }

  final ExpensesRepository _repo;
  late final StreamSubscription<void> _sub;

  Future<void> _guard(Emitter<ExpensesState> emit, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      emit(state.copyWith(error: ApiException.from(e).message));
    }
  }

  Future<void> _load(Emitter<ExpensesState> emit) async {
    if (state.categories.isEmpty) emit(state.copyWith(status: LoadStatus.loading));
    try {
      final categories = await _repo.categories();
      final keep = categories.any((c) => c.id == state.selectedId);
      emit(state.copyWith(
        status: LoadStatus.success,
        categories: categories,
        selectedId: () => keep ? state.selectedId : categories.firstOrNull?.id,
      ));
      await _loadExpenses(emit);
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> _loadExpenses(Emitter<ExpensesState> emit) async {
    final id = state.selectedId;
    if (id == null) return emit(state.copyWith(expensesStatus: LoadStatus.success, expenses: const []));
    try {
      final expenses = await _repo.list(categoryId: id);
      if (state.selectedId == id) emit(state.copyWith(expensesStatus: LoadStatus.success, expenses: expenses));
    } catch (e) {
      emit(state.copyWith(expensesStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
