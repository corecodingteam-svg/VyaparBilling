// The shared validation pattern: field-naming messages, scrolling to and focusing the first invalid field, and outlining
// the element a form-level problem is about.
import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/data/models/party.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/features/invoices/bloc/invoice_form_cubit.dart';
import 'package:billing_app/data/models/invoice.dart';
import 'package:billing_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('Validators name the field and say what is needed', () {
    test('required, choose, length and number', () {
      expect(Validators.required('Party name')(''), 'Party name is required');
      expect(Validators.required('Party name')('  '), 'Party name is required');
      expect(Validators.required('Party name')('Ravi'), isNull);
      expect(Validators.choose<String>('bank account')(null), 'Select the bank account');
      expect(Validators.minLength('Password', 8)('abc'), 'Password must be at least 8 characters');
      final price = Validators.number('Price', required: true, positive: true);
      expect([price(''), price('abc'), price('0'), price('12.5')], ['Price is required', 'Price must be a number', 'Price must be greater than 0', null]);
      expect(Validators.number('Quantity', whole: true)('2.5'), 'Quantity must be a whole number');
      expect(Validators.number('Rate', nonNegative: true, max: 100)('-1'), 'Rate cannot be negative');
      expect(Validators.number('Rate', max: 100)('101'), 'Rate cannot be more than 100');
      expect(Validators.number('Optional')(''), isNull);
    });

    test('formats tell the user what a valid value looks like', () {
      expect(Validators.pan()('abc'), 'PAN must be 5 letters, 4 digits and a letter, like ABCDE1234F');
      expect(Validators.pan()('abcde1234f'), isNull);
      expect(Validators.pan()(''), isNull); // optional unless asked
      expect(Validators.email(required: true)(''), 'Email is required');
      expect(Validators.email()('nope'), 'Email must be a valid address, like name@example.com');
      expect(Validators.pincode()('012345'), 'Pincode must be 6 digits and not start with 0');
      expect(Validators.digits('BSR code', 7, required: true)('123'), 'BSR code must be 7 digits');
      expect(Validators.matches('Passwords', () => 'secret')('other'), 'Passwords does not match');
      expect(Validators.all([Validators.required('Name'), Validators.minLength('Name', 3)])('ab'), 'Name must be at least 3 characters');
    });
  });

  group('validateForm', () {
    Widget app(GlobalKey<FormState> key, {required List<String> messages}) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: key,
                    child: Column(
                      children: [
                        TextFormField(key: const Key('name'), decoration: const InputDecoration(labelText: 'Name'), validator: Validators.required('Name')),
                        for (var i = 0; i < 12; i++) const SizedBox(height: 80),
                        TextFormField(key: const Key('email'), decoration: const InputDecoration(labelText: 'Email'), validator: Validators.email(required: true)),
                        TextFormField(key: const Key('phone'), decoration: const InputDecoration(labelText: 'Phone'), validator: Validators.digits('Phone', 10, required: true)),
                      ],
                    ),
                  ),
                ),
              ),
              TextButton(onPressed: () => validateForm(context, key, report: (_, m) => messages.add(m)), child: const Text('Save')),
            ],
          ),
        ),
      ),
    );

    testWidgets('puts the cursor in the first invalid field and reports every problem in words', (t) async {
      final key = GlobalKey<FormState>();
      final messages = <String>[];
      await t.pumpWidget(app(key, messages: messages));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(messages.single, '3 fields need attention: Name is required · Email is required · Phone is required');
      // The error appears under each invalid field, in words, with the field outlined in red.
      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Phone is required'), findsOneWidget);
      final field = t.widget<EditableText>(find.descendant(of: find.byKey(const Key('name')), matching: find.byType(EditableText)));
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('scrolls to the first invalid field when it is off screen', (t) async {
      final key = GlobalKey<FormState>();
      await t.pumpWidget(app(key, messages: []));
      await t.enterText(find.byKey(const Key('name')), 'Ravi'); // the first field is fine; the next two are not
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Email is required'), findsOneWidget); // scrolled into view
      expect(find.text('Name is required'), findsNothing);
    });

    testWidgets('a valid form passes without a message, and a fixed field stops being red as the user types', (t) async {
      final key = GlobalKey<FormState>();
      final messages = <String>[];
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Form(
              key: key,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(children: [
                TextFormField(key: const Key('name'), validator: Validators.required('Name')),
                TextButton(onPressed: () => validateForm(context, key, report: (_, m) => messages.add(m)), child: const Text('Save')),
              ]),
            ),
          ),
        ),
      ));
      await t.tap(find.text('Save'));
      await t.pump();
      expect(find.text('Name is required'), findsOneWidget);
      await t.enterText(find.byKey(const Key('name')), 'Ravi');
      await t.pump();
      expect(find.text('Name is required'), findsNothing); // cleared at once, not at the next Save
      await t.tap(find.text('Save'));
      expect(messages, hasLength(1)); // only the first, failed attempt reported
    });
  });

  group('FieldHighlight', () {
    Widget host(FormIssue? issue) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: FieldHighlight(field: 'party', also: const ['number'], issue: issue, child: const Text('Party field'))),
    );

    testWidgets('outlines the element and writes the problem under it only when the issue is about it', (t) async {
      await t.pumpWidget(host(null));
      expect(find.byIcon(Icons.error_outline), findsNothing);
      await t.pumpWidget(host(const FormIssue('party', 'Select the customer.')));
      await t.pumpAndSettle();
      expect(find.text('Select the customer.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      await t.pumpWidget(host(const FormIssue('number', 'Enter the invoice no.'))); // a related field it stands for
      await t.pumpAndSettle();
      expect(find.text('Enter the invoice no.'), findsOneWidget);
      await t.pumpWidget(host(const FormIssue('items', 'Add at least one item.'))); // somebody else's problem
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });

  group('invoice form says which element is wrong', () {
    Future<InvoiceFormCubit> form() async {
      final bus = ChangeBus();
      final c = InvoiceFormCubit(
        invoices: FakeInvoicesRepository(bus),
        parties: FakePartiesRepository([Party.fromJson(partyJson('a', 'Test Customer', 0))], bus),
        items: FakeItemsRepository([Item.fromJson(itemJson('i1', 'Sample Item'))], bus),
        accounts: FakeCashBankRepository(),
        firm: FakeFirmRepository(),
        accounting: FakeAccountingRepository(),
        bus: bus,
        kind: InvoiceKind.sale,
      );
      await c.load();
      return c;
    }

    test('each problem names its part of the form, and the old message is unchanged', () async {
      final c = await form();
      expect(c.firstIssue()?.field, 'party');
      expect(c.validate(), c.firstIssue()!.message);
      c.partySelected(c.state.parties.first);
      expect(c.firstIssue()?.field, 'items');
      final uid = c.state.lines.first.uid;
      c.itemSelected(uid, c.state.items.first);
      c.lineQtyChanged(uid, '0');
      expect(c.firstIssue()?.field, 'row:$uid');
      expect(c.firstIssue()?.message, 'Row 1: enter a quantity greater than 0.');
      c.lineQtyChanged(uid, '2');
      expect(c.firstIssue(), isNull);
      await c.close();
    });

    test('saving with a problem keeps the form open, and the issue is gone as soon as the user changes anything', () async {
      final c = await form();
      await c.save(andNew: false);
      expect([c.state.issue?.field, c.state.error], ['party', c.state.issue?.message]);
      c.partySelected(c.state.parties.first);
      expect(c.state.issue, isNull); // cleared by the very next change
      await c.close();
    });
  });
}
