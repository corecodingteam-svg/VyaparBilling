import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/change_bus.dart';
import '../../data/models/firm.dart';
import '../../data/repositories/firm_repository.dart';
import '../auth/bloc/auth_bloc.dart';

/// The company the session is working in, with its settings. Null until loaded or when signed out.
/// Screens read it to honour settings (which columns to show, which modules are on, ...).
class FirmCubit extends Cubit<Firm?> {
  FirmCubit(this._repo, ChangeBus bus, AuthBloc auth) : super(null) {
    _busSub = bus.on({DataTopic.firm}).listen((_) => load());
    // Signing in, signing out and switching company all change which company this is.
    _authSub = auth.stream.map((s) => s.user?.firmId).distinct().listen((firmId) => firmId == null ? emit(null) : load());
    if (auth.state.user != null) load();
  }

  final FirmRepository _repo;
  late final StreamSubscription<void> _busSub;
  late final StreamSubscription<String?> _authSub;

  Future<void> load() async {
    try {
      final firm = await _repo.get();
      if (!isClosed) emit(firm);
    } catch (_) {
      // Screens fall back to the default settings; the next change or sign-in tries again.
    }
  }

  @override
  Future<void> close() {
    _busSub.cancel();
    _authSub.cancel();
    return super.close();
  }
}

/// The current company's settings, or the defaults while they load (or where no [FirmCubit] is provided).
FirmSettings settingsOf(BuildContext context, {bool listen = false}) {
  try {
    return (listen ? context.watch<FirmCubit>() : context.read<FirmCubit>()).state?.settings ?? const FirmSettings();
  } on ProviderNotFoundException {
    return const FirmSettings();
  }
}
