import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billing_app/shared/theme.dart';

void main() {
  tearDown(() => AppColors.applyAccent(AppColors.defaultAccent));

  test('parses and prints hex colours', () {
    expect(parseAccent('#2563eb'), const Color(0xFF2563EB));
    expect(parseAccent('2563EB'), const Color(0xFF2563EB));
    expect(parseAccent('#12345'), isNull);
    expect(parseAccent('blue'), isNull);
    expect(accentHex(const Color(0xFF0F766E)), '#0F766E');
  });

  test('choice applies to the tokens and is remembered per user', () async {
    SharedPreferences.setMockInitialValues({});
    final users = StreamController<String?>();
    final cubit = ThemeCubit(userIds: users.stream);
    await cubit.loadFor('u1');
    await cubit.choose(const Color(0xFFDC2626));
    expect(AppColors.primary, const Color(0xFFDC2626));
    expect(AppColors.primaryDark, isNot(AppColors.primary));

    // Another user starts from the last choice, changes it, and u1 still gets their own.
    await cubit.loadFor('u2');
    await cubit.choose(const Color(0xFF16A34A));
    await cubit.loadFor('u1');
    expect(cubit.state, const Color(0xFFDC2626));
    expect(AppColors.primary, const Color(0xFFDC2626));

    await cubit.reset();
    expect(cubit.state, AppColors.defaultAccent);
    await users.close();
    await cubit.close();
  });
}
