import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../shared/theme.dart';
import 'lock_cubit.dart';

/// Covers the app until the PIN is entered. [onForgot] signs out (which clears the lock).
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onForgot});
  final VoidCallback onForgot;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

/// Stateful only to own the PIN field's controller; whether the app is locked lives in [LockCubit].
class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _pin.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<LockCubit>().unlock(_pin.text);
    _pin.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: pageBg,
      child: Center(
        child: SizedBox(
          width: 320,
          child: BlocBuilder<LockCubit, AppLockState>(
            builder: (context, s) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 44, color: brandBlue),
                const SizedBox(height: 12),
                const Text('Enter your PIN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                TextField(
                  controller: _pin,
                  focusNode: _focus,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: LockCubit.maxLength,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: const InputDecoration(counterText: ''),
                  onSubmitted: (_) => _submit(),
                  onChanged: (v) {
                    // A PIN of the longest length is tried as soon as it is typed.
                    if (v.length == LockCubit.maxLength) _submit();
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: s.message == null
                      ? null
                      : Text(
                          s.message!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: payRed),
                        ),
                ),
                FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: const Text('Unlock'),
                ),
                TextButton(onPressed: widget.onForgot, child: const Text('Forgot PIN? Sign out')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts the lock screen over [child] whenever the app is locked, and locks when the app has been away.
class AppLock extends StatefulWidget {
  const AppLock({super.key, required this.child, required this.onForgot});
  final Widget child;
  final VoidCallback onForgot;

  @override
  State<AppLock> createState() => _AppLockState();
}

/// Stateful only to listen to the app's lifecycle (backgrounded / back) for the lock cubit.
class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = context.read<LockCubit>();
    if (state == AppLifecycleState.resumed) {
      lock.back();
    } else {
      lock.away();
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<LockCubit, AppLockState>(
    builder: (context, s) => Stack(
      children: [
        // Nothing of the app is built while it is locked.
        if (s.ready && !s.locked) widget.child,
        if (!s.ready) const Center(child: CircularProgressIndicator()),
        if (s.ready && s.locked) LockScreen(onForgot: widget.onForgot),
      ],
    ),
  );
}

/// Set, change or remove the PIN (Settings → App lock). Changing or removing asks for the current one.
Future<void> showPinDialog(BuildContext context, {required bool hasPin, required bool remove}) {
  final lock = context.read<LockCubit>();
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      String? error;
      return _PinDialog(
        title: remove ? 'Remove PIN' : (hasPin ? 'Change PIN' : 'Set PIN'),
        askCurrent: hasPin,
        askNew: !remove,
        current: current,
        next: next,
        confirm: confirm,
        onSubmit: () async {
          error = remove ? await lock.removePin(current.text) : await lock.setPin(next.text, current: current.text);
          return error;
        },
      );
    },
  );
}

class _PinDialog extends StatelessWidget {
  const _PinDialog({
    required this.title,
    required this.askCurrent,
    required this.askNew,
    required this.current,
    required this.next,
    required this.confirm,
    required this.onSubmit,
  });

  final String title;
  final bool askCurrent;
  final bool askNew;
  final TextEditingController current;
  final TextEditingController next;
  final TextEditingController confirm;

  /// Returns an error message, or null when it worked.
  final Future<String?> Function() onSubmit;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => _PinFormCubit(),
    child: BlocConsumer<_PinFormCubit, String?>(
      listener: (context, error) {},
      builder: (context, error) {
        InputDecoration deco(String label) => InputDecoration(labelText: label, counterText: '');
        final digits = [FilteringTextInputFormatter.digitsOnly];
        Future<void> submit() async {
          final form = context.read<_PinFormCubit>();
          if (askNew && next.text != confirm.text) return form.fail('The two PINs do not match.');
          final problem = await onSubmit();
          if (!context.mounted) return;
          problem == null ? Navigator.pop(context) : form.fail(problem);
        }

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (askCurrent) ...[
                  TextField(
                    controller: current,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: LockCubit.maxLength,
                    inputFormatters: digits,
                    decoration: deco('Current PIN'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (askNew) ...[
                  TextField(
                    controller: next,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: LockCubit.maxLength,
                    inputFormatters: digits,
                    decoration: deco('New PIN (${LockCubit.minLength}–${LockCubit.maxLength} digits)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirm,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: LockCubit.maxLength,
                    inputFormatters: digits,
                    decoration: deco('Confirm new PIN'),
                    onSubmitted: (_) => submit(),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error, style: const TextStyle(color: payRed)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: Text(title.startsWith('Remove') ? 'Remove' : 'Save')),
          ],
        );
      },
    ),
  );
}

/// The dialog's error message.
class _PinFormCubit extends Cubit<String?> {
  _PinFormCubit() : super(null);
  void fail(String message) => emit(message);
}
