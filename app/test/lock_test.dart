import 'package:billing_app/features/lock/lock_cubit.dart';
import 'package:billing_app/features/lock/lock_screen.dart';
import 'package:billing_app/features/lock/passcode_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late DateTime now;
  late FakePasscodeStore store;

  Future<LockCubit> build({String? pin}) async {
    now = DateTime(2026, 10, 12, 10);
    store = FakePasscodeStore(pin);
    final c = LockCubit(store, clock: () => now);
    await c.load();
    return c;
  }

  test('no PIN: never locked', () async {
    final c = await build();
    expect([c.state.ready, c.state.hasPin, c.state.locked], [true, false, false]);
    c.away();
    now = now.add(const Duration(hours: 1));
    c.back();
    c.lockNow();
    expect(c.state.locked, isFalse);
  });

  test('a saved PIN locks the app on start, and the right PIN opens it', () async {
    final c = await build(pin: '1234');
    expect(c.state.locked, isTrue);
    await c.unlock('0000');
    expect([c.state.locked, c.state.message], [true, 'Wrong PIN. 4 attempts left before a wait.']);
    await c.unlock('1234');
    expect([c.state.locked, c.state.message, c.state.failures], [false, null, 0]);
  });

  test('after five wrong attempts each further one has to wait, even for the right PIN', () async {
    final c = await build(pin: '1234');
    for (var i = 0; i < 5; i++) {
      await c.unlock('9999');
    }
    expect(c.state.message, 'Wrong PIN. Wait 30 seconds before trying again.');
    await c.unlock('1234'); // right PIN, but too soon
    expect([c.state.locked, c.state.message], [true, contains('Too many wrong attempts')]);
    now = now.add(const Duration(seconds: 31));
    await c.unlock('1234');
    expect(c.state.locked, isFalse);

    c.lockNow();
    for (var i = 0; i < 6; i++) {
      await c.unlock('9999');
      now = now.add(const Duration(minutes: 5));
    }
    expect(c.state.message, 'Wrong PIN. Wait 60 seconds before trying again.'); // the wait grows
  });

  test('locks again only after the app has been away long enough', () async {
    final c = await build(pin: '1234');
    await c.unlock('1234');
    c.away();
    now = now.add(const Duration(seconds: 30));
    c.back();
    expect(c.state.locked, isFalse);
    c.away();
    now = now.add(const Duration(minutes: 2));
    c.back();
    expect(c.state.locked, isTrue);
    await c.unlock('1234');
    c.lockNow();
    expect(c.state.locked, isTrue);
  });

  test('setting, changing and removing the PIN', () async {
    final c = await build();
    expect(await c.setPin('12'), 'Use 4 to 6 digits.');
    expect(await c.setPin('12ab'), 'Use 4 to 6 digits.');
    expect(await c.setPin('1234'), isNull);
    expect([c.state.hasPin, c.state.locked, store.pin], [true, false, '1234']); // setting it does not lock you out

    expect(await c.setPin('5678', current: '0000'), 'The current PIN is wrong.');
    expect(await c.setPin('5678', current: '1234'), isNull);
    expect(await c.removePin('1234'), 'The PIN is wrong.');
    expect(await c.removePin('5678'), isNull);
    expect([c.state.hasPin, store.pin], [false, null]);
  });

  test('forgetting the PIN clears it (the caller signs the user out)', () async {
    final c = await build(pin: '1234');
    await c.forgot();
    expect([c.state.hasPin, c.state.locked, store.pin], [false, false, null]);
  });

  test('only a salted hash is stored', () {
    expect(PasscodeStore.hash('1234', 'a'), isNot(PasscodeStore.hash('1234', 'b')));
    expect(PasscodeStore.hash('1234', 'a'), isNot(contains('1234')));
  });

  testWidgets('the lock screen hides the app until the PIN is right', (t) async {
    final store = FakePasscodeStore('4321');
    var forgot = false;
    await t.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => LockCubit(store, awayBeforeLock: Duration.zero)..load(),
          child: AppLock(onForgot: () => forgot = true, child: const Scaffold(body: Text('the books'))),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('the books'), findsNothing);
    expect(find.text('Enter your PIN'), findsOneWidget);

    await t.enterText(find.byType(TextField), '1111');
    await t.tap(find.text('Unlock'));
    await t.pumpAndSettle();
    expect(find.text('the books'), findsNothing);
    expect(find.textContaining('Wrong PIN'), findsOneWidget);

    await t.enterText(find.byType(TextField), '4321');
    await t.tap(find.text('Unlock'));
    await t.pumpAndSettle();
    expect(find.text('the books'), findsOneWidget);

    // Locked again after the app was sent to the background and came back.
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('the books'), findsNothing);
    expect(find.text('Enter your PIN'), findsOneWidget);

    await t.tap(find.text('Forgot PIN? Sign out'));
    expect(forgot, isTrue);
  });
}
