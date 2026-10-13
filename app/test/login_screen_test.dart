import 'package:billing_app/core/api_client.dart';
import 'package:billing_app/data/repositories/auth_repository.dart';
import 'package:billing_app/features/auth/bloc/auth_bloc.dart';
import 'package:billing_app/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login form validates empty and malformed input', (tester) async {
    final repo = AuthRepository(ApiClient(TokenStore()));
    await tester.pumpWidget(RepositoryProvider.value(
      value: repo,
      child: BlocProvider(
        create: (_) => AuthBloc(repo),
        child: const MaterialApp(home: LoginScreen()),
      ),
    ));

    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'not-an-email');
    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(find.text('Email must be a valid address, like name@example.com'), findsOneWidget);
  });

  testWidgets('password visibility toggle is driven by the cubit', (tester) async {
    final repo = AuthRepository(ApiClient(TokenStore()));
    await tester.pumpWidget(RepositoryProvider.value(
      value: repo,
      child: BlocProvider(create: (_) => AuthBloc(repo), child: const MaterialApp(home: LoginScreen())),
    ));

    EditableText password() => tester.widget<EditableText>(
        find.descendant(of: find.widgetWithText(TextFormField, 'Password'), matching: find.byType(EditableText)));
    expect(password().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(password().obscureText, isFalse);
  });
}
