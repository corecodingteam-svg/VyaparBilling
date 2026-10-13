import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billing_app/shared/theme.dart';

void main() {
  testWidgets('gradient progress bar animates and stops cleanly', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: GradientProgressBar())));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).gradient != null), findsOneWidget);
    await t.pumpWidget(const SizedBox()); // removing it leaves no running ticker
    expect(t.takeException(), isNull);
  });

  testWidgets('with reduce-motion it is a still band', (t) async {
    await t.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: Scaffold(body: GradientProgressBar())),
    ));
    await t.pump(const Duration(seconds: 2)); // would never settle if it animated
    await t.pumpAndSettle();
  });
}
