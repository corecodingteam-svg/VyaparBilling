import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billing_app/shared/period.dart';

void main() {
  testWidgets('range picker is a small dialog, not a full screen, and returns the range', (t) async {
    (String, String)? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(onPressed: () async => result = await showCompactRangePicker(context, from: '2026-10-01', to: '2026-10-31'), child: const Text('open'))),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final size = t.getSize(find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first);
    expect(size.width, lessThan(500));
    expect(size.height, lessThan(400));
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    expect(result, ('2026-10-01', '2026-10-31'));
  });
}
