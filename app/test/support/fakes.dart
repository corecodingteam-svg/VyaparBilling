import 'package:billing_app/core/api_client.dart';
import 'package:billing_app/core/change_bus.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:billing_app/data/models/accounting.dart';
import 'package:billing_app/data/models/app_user.dart';
import 'package:billing_app/data/models/cash_bank.dart';
import 'package:billing_app/data/models/extras.dart';
import 'package:billing_app/data/repositories/accounting_repository.dart';
import 'package:billing_app/data/repositories/auth_repository.dart';
import 'package:billing_app/data/models/team_location.dart';
import 'package:billing_app/features/lock/passcode_store.dart';
import 'package:billing_app/data/repositories/files_repository.dart';
import 'package:billing_app/data/repositories/location_repository.dart';
import 'package:billing_app/data/repositories/utilities_repository.dart';
import 'package:billing_app/data/models/integrations.dart';
import 'package:billing_app/data/repositories/integrations_repository.dart';
import 'package:billing_app/data/models/expense.dart';
import 'package:billing_app/data/models/firm.dart';
import 'package:billing_app/data/models/loan.dart';
import 'package:billing_app/data/models/report.dart';
import 'package:billing_app/data/repositories/firm_repository.dart';
import 'package:billing_app/data/repositories/loans_repository.dart';
import 'package:billing_app/data/repositories/reports_repository.dart';
import 'package:billing_app/data/repositories/cash_bank_repository.dart';
import 'package:billing_app/data/models/invoice.dart';
import 'package:billing_app/data/repositories/expenses_repository.dart';
import 'package:billing_app/data/models/payment.dart';
import 'package:billing_app/data/repositories/invoices_repository.dart';
import 'package:billing_app/data/repositories/payments_repository.dart';
import 'package:billing_app/data/models/dashboard_summary.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/data/models/party.dart';
import 'package:billing_app/data/repositories/dashboard_repository.dart';
import 'package:billing_app/data/repositories/items_repository.dart';
import 'package:billing_app/data/repositories/parties_repository.dart';

final _api = ApiClient(TokenStore());

Map<String, dynamic> partyJson(String id, String name, num balance, {String? phone}) => {
      'id': id, 'name': name, 'phone': phone, 'gstin': null, 'gstType': 'unregistered', 'stateCode': '07',
      'email': '$id@example.com', 'billingAddress': '12 Test Street, New Delhi', 'shippingAddress': null,
      'openingBalance': balance, 'openingBalanceDate': '2026-10-10', 'creditLimit': null,
      'additionalFields': <Map<String, dynamic>>[], 'balance': balance,
    };

Map<String, dynamic> itemJson(String id, String name, {String type = 'product', num stock = 50, num? minStock, num? gstRate}) => {
      'id': id, 'type': type, 'name': name, 'hsnCode': '1001', 'unit': 'PCS', 'categoryId': 'c1', 'categoryName': 'Grocery',
      'itemCode': null, 'salePrice': 100, 'salePriceIncludesTax': false, 'saleDiscount': 0, 'saleDiscountType': 'percent',
      'wholesalePrice': null, 'wholesaleMinQty': null, 'purchasePrice': 70, 'purchasePriceIncludesTax': false, 'gstRate': gstRate,
      'openingQty': stock, 'openingPrice': 70, 'openingDate': '2026-10-10', 'minStock': minStock, 'location': null,
      'stockQty': stock, 'stockValue': stock * 70, 'lowStock': minStock != null && stock <= minStock,
    };

/// In-memory parties repository; records saves and publishes changes like the real one.
class FakePartiesRepository extends PartiesRepository {
  FakePartiesRepository(List<Party> parties, [ChangeBus? bus]) : this._(parties, bus ?? ChangeBus());
  FakePartiesRepository._(this.parties, this.bus) : super(_api, bus);
  final ChangeBus bus;
  List<Party> parties;
  final saved = <Map<String, dynamic>>[];

  @override
  Future<List<Party>> list() async => parties;

  @override
  Future<Party> get(String id) async => parties.firstWhere((p) => p.id == id);

  @override
  Future<List<PartyGroup>> groups() async => [
        PartyGroup.fromJson({'id': 'pg1', 'name': 'Retailers', 'partyCount': 2}),
        PartyGroup.fromJson({'id': 'pg2', 'name': 'Wholesalers', 'partyCount': 1}),
      ];

  @override
  Future<List<PartyTxn>> transactions(String id) async {
    final p = parties.firstWhere((x) => x.id == id);
    return p.openingBalance == 0
        ? []
        : [PartyTxn.fromJson({'type': 'Opening Balance', 'number': null, 'date': p.openingBalanceDate, 'total': p.openingBalance.abs(), 'balance': p.openingBalance})];
  }

  @override
  Future<Party> save(String? id, Map<String, dynamic> body) async {
    saved.add(body);
    final p = Party.fromJson({...partyJson(id ?? 'new${saved.length}', body['name'] as String, body['openingBalance'] as num), ...body});
    parties = [...parties.where((x) => x.id != p.id), p];
    bus.publish(DataTopic.parties);
    return p;
  }

  @override
  Future<void> delete(String id) async {
    parties = parties.where((p) => p.id != id).toList();
    bus.publish(DataTopic.parties);
  }
}

class FakeItemsRepository extends ItemsRepository {
  FakeItemsRepository(this.items, [ChangeBus? bus]) : super(_api, bus ?? ChangeBus());
  List<Item> items;

  /// What the store, batch and serial lookups return.
  var storeList = <Godown>[
    Godown.fromJson({'id': null, 'name': 'Main Store', 'itemCount': 2, 'stockValue': 5000}),
    Godown.fromJson({'id': 'g1', 'name': 'Warehouse', 'itemCount': 1, 'stockValue': 700}),
  ];
  var batchList = <ItemBatch>[
    ItemBatch.fromJson({'batchNo': 'B-77', 'expiryDate': '2026-11-30', 'mrp': 120, 'quantity': 40}),
    ItemBatch.fromJson({'batchNo': 'B-90', 'expiryDate': '2027-03-31', 'mrp': 125, 'quantity': 10}),
  ];
  var serialList = <String>['IM1', 'IM2', 'IM3'];
  final transfers = <Map<String, dynamic>>[];
  String? lastBatchGodown;

  @override
  Future<List<Godown>> godowns() async => storeList;

  @override
  Future<List<ItemBatch>> batches(String id, {String? godownId}) async {
    lastBatchGodown = godownId;
    return batchList;
  }

  @override
  Future<List<String>> serials(String id) async => serialList;

  @override
  Future<List<GodownStock>> stockByGodown(String id) async => const [
        GodownStock(godownId: null, name: 'Main Store', quantity: 30),
        GodownStock(godownId: 'g1', name: 'Warehouse', quantity: 70),
      ];

  @override
  Future<void> transferStock(Map<String, dynamic> body) async => transfers.add(body);

  @override
  Future<List<Item>> list(String type) async => items.where((i) => type == 'all' || i.type == type).toList();

  @override
  Future<List<StockMovement>> movements(String id) async => [
        StockMovement.fromJson({'type': 'reduce', 'quantity': -5, 'pricePerUnit': null, 'date': '2026-10-10', 'notes': 'damaged'}),
        StockMovement.fromJson({'type': 'opening', 'quantity': 55, 'pricePerUnit': 70, 'date': '2026-10-10', 'notes': null}),
      ];

  @override
  Future<List<Category>> categories() async => [Category.fromJson({'id': 'c1', 'name': 'Grocery', 'itemCount': items.length})];

  @override
  Future<List<Unit>> units() async => [
        Unit.fromJson({'id': 'u1', 'name': 'Pieces', 'shortName': 'PCS'}),
        Unit.fromJson({'id': 'u2', 'name': 'Kilograms', 'shortName': 'KG'}),
      ];
}

class FakeDashboardRepository extends DashboardRepository {
  FakeDashboardRepository() : super(_api);

  @override
  Future<DashboardSummary> summary({String? from, String? to}) async => DashboardSummary.fromJson({
        'receivable': 590, 'receivableParties': 2, 'payable': 250, 'payableParties': 1, 'lowStockItems': 1,
        'sales': {
          'from': '2026-10-01', 'to': '2026-10-31', 'total': 3840,
          'daily': [
            {'date': '2026-10-03', 'amount': 600}, {'date': '2026-10-07', 'amount': 1240},
            {'date': '2026-10-08', 'amount': 400}, {'date': '2026-10-10', 'amount': 1600},
          ],
        },
      });
}

Map<String, dynamic> invoiceJson(String id, String number, String party, num total, num received,
        {String? partyId = 'a', bool isCash = false, String type = 'sale', String? status, String? convertedInvoiceId, Map<String, dynamic>? gst}) =>
    {
      'status': status, 'convertedInvoiceId': convertedInvoiceId,
      'id': id, 'type': type, 'number': number, 'invoiceDate': '2026-10-10', 'isCash': isCash, 'partyId': partyId,
      'partyName': party, 'total': total, 'received': received, 'balance': total - received, 'paymentMode': isCash ? 'cash' : 'upi',
      'phone': '9000000001', 'billingAddress': '12 Test Street, New Delhi', 'stateOfSupply': '07', 'subtotal': total, 'roundOff': 0,
      'description': null,
      'lines': [
        {'itemId': 'i1', 'name': 'Sample Item', 'quantity': 3, 'unit': 'PCS', 'price': 120, 'discountPct': 10, 'discountAmount': 36, 'amount': 324},
        {'itemId': 's1', 'name': 'Home Delivery', 'quantity': 1, 'unit': null, 'price': total - 324, 'discountPct': 0, 'discountAmount': 0, 'amount': total - 324},
      ],
      ...?gst,
    };

class FakeInvoicesRepository extends InvoicesRepository {
  FakeInvoicesRepository([ChangeBus? bus]) : this._(bus ?? ChangeBus());
  FakeInvoicesRepository._(this.bus) : super(_api, bus);
  final ChangeBus bus;
  final saved = <Map<String, dynamic>>[];
  var invoices = [
    Invoice.fromJson(invoiceJson('v2', '2', 'Walk-in Ravi', 240, 240, partyId: null, isCash: true)),
    Invoice.fromJson(invoiceJson('v1', '1', 'Test Customer', 1000, 500)),
  ];

  @override
  Future<List<InvoiceSummary>> list(String type, {required String from, required String to}) async => InvoiceKind.of(type).isQuote
      ? [
          Invoice.fromJson(invoiceJson('e2', '2', 'Sharma General Store', 2400, 0, partyId: 'c', type: type, status: 'open')),
          Invoice.fromJson(invoiceJson('e1', '1', 'Test Customer', 1000, 0, type: type, status: 'converted', convertedInvoiceId: 'v1')),
        ]
      : invoices;

  @override
  Future<Invoice> get(String id) async => id == 'g1'
      ? Invoice.fromJson(gstInvoiceJson())
      : id == 'e1'
      ? Invoice.fromJson(invoiceJson('e1', '7', 'Test Customer', 1000, 0, type: 'estimate', status: 'open'))
      : invoices.firstWhere((i) => i.id == id);

  /// What [unpaid] returns: a party's invoices that still have something to pay.
  var unpaidInvoices = <InvoiceSummary>[
    InvoiceSummary.fromJson({...invoiceJson('v1', '1', 'Test Customer', 1000, 500), 'invoiceDate': '2026-09-20'}),
    InvoiceSummary.fromJson({...invoiceJson('v5', '5', 'Test Customer', 1390, 0), 'invoiceDate': '2026-10-04'}),
  ];

  @override
  Future<List<InvoiceSummary>> unpaid(String type, String partyId) async => unpaidInvoices.where((i) => i.partyId == partyId && i.type == type).toList();

  @override
  Future<String> nextNumber(String type) async => '${invoices.length + 1}';

  @override
  Future<Invoice> save(String? id, Map<String, dynamic> body) async {
    saved.add(body);
    bus.publish(DataTopic.invoices);
    return Invoice.fromJson(invoiceJson(id ?? 'v${invoices.length + 1}', body['number'] as String, 'Test Customer', 1000, 0));
  }

  @override
  Future<void> delete(String id) async {
    invoices = invoices.where((i) => i.id != id).toList();
    bus.publish(DataTopic.invoices);
  }
}

Map<String, dynamic> paymentJson(String id, num amount, {String type = 'in', String partyId = 'a', List<Map<String, dynamic>> allocations = const []}) => {
      'id': id, 'type': type, 'number': '1', 'partyId': partyId, 'partyName': 'Test Customer', 'paymentDate': '2026-10-10',
      'amount': amount, 'paymentMode': 'cash', 'description': null,
      'linkedAmount': allocations.fold<num>(0, (s, a) => s + (a['amount'] as num)), 'allocations': allocations,
    };

class FakePaymentsRepository extends PaymentsRepository {
  FakePaymentsRepository([ChangeBus? bus]) : super(_api, bus ?? ChangeBus());
  final saved = <Map<String, dynamic>>[];

  /// Payments [get] can return, by id.
  final stored = <String, Payment>{};

  @override
  Future<Payment> get(String id) async => stored[id]!;

  @override
  Future<Payment> save(String? id, Map<String, dynamic> body) async {
    saved.add(body);
    return Payment.fromJson(paymentJson(id ?? 'new', body['amount'] as num, type: body['type'] as String, partyId: body['partyId'] as String));
  }

  @override
  Future<List<Payment>> list(String type, {required String from, required String to}) async => [
        Payment.fromJson({
          'id': 'p1', 'type': 'in', 'number': '1', 'partyId': 'a', 'partyName': 'Test Customer', 'paymentDate': '2026-10-10',
          'amount': 200, 'paymentMode': 'cash', 'description': null,
        }),
      ];

  @override
  Future<String> nextNumber(String type) async => '2';
}

class FakeExpensesRepository extends ExpensesRepository {
  FakeExpensesRepository([ChangeBus? bus]) : super(_api, bus ?? ChangeBus());
  final saved = <Map<String, dynamic>>[];

  @override
  Future<List<ExpenseCategory>> categories() async => [
        for (final (id, name, total) in [('x1', 'Petrol', 1200), ('x2', 'Rent', 15000), ('x3', 'Salary', 0), ('x4', 'Tea', 30), ('x5', 'Transport', 450)])
          ExpenseCategory.fromJson({'id': id, 'name': name, 'total': total}),
      ];

  @override
  Future<List<ExpenseItemDef>> itemDefs() async => [
        ExpenseItemDef.fromJson({'id': 'd1', 'name': 'Diesel', 'price': 90, 'hsnCode': '2710', 'gstRate': 18, 'total': 1200}),
        ExpenseItemDef.fromJson({'id': 'd2', 'name': 'Tea', 'price': 10, 'hsnCode': null, 'gstRate': null, 'total': 30}),
      ];

  Map<String, dynamic> _expense(String id, String date, num total, String mode, [String? number]) => {
        'id': id, 'categoryId': 'x1', 'categoryName': 'Petrol', 'number': number, 'expenseDate': date, 'total': total, 'paymentMode': mode,
        'subtotal': total, 'roundOff': 0, 'description': 'Delivery van',
        'lines': [{'name': 'Diesel', 'quantity': 8, 'price': total / 8, 'amount': total}],
      };

  @override
  Future<List<ExpenseSummary>> list({required String categoryId}) async => categoryId != 'x1'
      ? []
      : [
          ExpenseSummary.fromJson(_expense('ex2', '2026-10-09', 800, 'upi', '2')),
          ExpenseSummary.fromJson(_expense('ex1', '2026-10-03', 400, 'cash', '1')),
        ];

  @override
  Future<Expense> get(String id) async => Expense.fromJson(_expense(id, '2026-10-09', 800, 'upi', '2'));

  @override
  Future<Expense> save(String? id, Map<String, dynamic> body) async {
    saved.add(body);
    return Expense.fromJson(_expense(id ?? 'new', body['expenseDate'] as String, 100, body['paymentMode'] as String));
  }
}

Map<String, dynamic> bankJson(String id, String name, num balance) => {
      'id': id, 'name': name, 'openingBalance': 1000, 'openingDate': '2026-10-01', 'accountNumber': '50100123456789',
      'ifsc': 'HDFC0001234', 'bankName': 'HDFC Bank', 'holderName': 'Demo Traders', 'upiId': 'demo@hdfc', 'balance': balance,
    };

Map<String, dynamic> txnJson(String source, String type, String name, num amount, {String mode = 'cash', String? bank, String? status}) => {
      'source': source, 'id': '$source-$name-$amount', 'type': type, 'name': name, 'number': '1', 'date': '2026-10-10',
      'amount': amount, 'paymentMode': mode, 'bankAccountId': bank, 'status': status,
    };

class FakeCashBankRepository extends CashBankRepository {
  FakeCashBankRepository({this.bankAccounts = const ['HDFC Current', 'SBI Savings'], ChangeBus? bus}) : super(_api, bus ?? ChangeBus());

  /// Names of the accounts this fake starts with (ids are b1, b2, ...).
  final List<String> bankAccounts;
  final adjustments = <Map<String, dynamic>>[];

  @override
  Future<List<BankAccount>> accounts() async =>
      [for (var i = 0; i < bankAccounts.length; i++) BankAccount.fromJson(bankJson('b${i + 1}', bankAccounts[i], i == 0 ? 12450 : 3000))];

  @override
  Future<List<MoneyTxn>> accountTransactions(String id) async => [
        MoneyTxn.fromJson(txnJson('sale', 'Sale', 'Test Customer', 500, mode: 'upi', bank: id)),
        MoneyTxn.fromJson(txnJson('adjustment', 'Cash Withdraw', '', -300, mode: 'bank', bank: id)),
        MoneyTxn.fromJson(txnJson('expense', 'Expense', 'Rent', -15000, mode: 'bank', bank: id)),
        MoneyTxn.fromJson(txnJson('opening', 'Opening Balance', 'Opening Balance', 1000, mode: 'bank', bank: id)),
      ];

  @override
  Future<(num, List<MoneyTxn>)> cash() async => (
        620,
        [
          MoneyTxn.fromJson(txnJson('expense', 'Expense', 'Tea', -30)),
          MoneyTxn.fromJson(txnJson('payment_out', 'Payment-Out', 'Test Supplier', -50)),
          MoneyTxn.fromJson(txnJson('payment_in', 'Payment-In', 'Test Customer', 200)),
          MoneyTxn.fromJson(txnJson('sale', 'Sale', 'Test Customer', 500)),
        ],
      );

  @override
  Future<List<MoneyTxn>> cheques() async => [
        MoneyTxn.fromJson(txnJson('payment_in', 'Payment-In', 'Sharma General Store', 2400, mode: 'cheque', status: 'open')),
        MoneyTxn.fromJson(txnJson('payment_out', 'Payment-Out', 'Test Supplier', -900, mode: 'cheque', status: 'open')),
        MoneyTxn.fromJson(txnJson('sale', 'Sale', 'Test Customer', 1000, mode: 'cheque', bank: 'b1', status: 'closed')),
      ];

  @override
  Future<void> createAdjustment(Map<String, dynamic> body) async => adjustments.add(body);
}

/// A GST sale: 2 × 500 @18% + 1 × 200 @5%, intra-state, for the tax-invoice PDF.
Map<String, dynamic> gstInvoiceJson() => invoiceJson('g1', '12', 'Sharma General Store', 1390, 390, partyId: 'c', gst: {
      'partyGstin': '07AAGCS1234L1Z9', 'pricesIncludeTax': false, 'interState': false,
      'taxableAmount': 1200, 'cgst': 95, 'sgst': 95, 'igst': 0, 'subtotal': 1390,
      'lines': [
        {
          'itemId': 'i1', 'name': 'Sample Item', 'quantity': 2, 'unit': 'PCS', 'price': 500, 'discountPct': 0, 'discountAmount': 0,
          'hsnCode': '1001', 'gstRate': 18, 'taxableValue': 1000, 'cgst': 90, 'sgst': 90, 'igst': 0, 'amount': 1180,
        },
        {
          'itemId': 'i2', 'name': 'Basmati Rice 5kg', 'quantity': 1, 'unit': 'BAG', 'price': 200, 'discountPct': 0, 'discountAmount': 0,
          'hsnCode': '1006', 'gstRate': 5, 'taxableValue': 200, 'cgst': 5, 'sgst': 5, 'igst': 0, 'amount': 210,
        },
      ],
    });

Map<String, dynamic> firmJson({Map<String, dynamic> settings = const {}}) => {
      'id': 'f', 'name': 'Demo Traders', 'phone': '9650269758', 'gstin': '07AAACR5055K1Z5', 'email': 'demo@example.com',
      'booksStartDate': '2026-04-01', 'businessType': 'Retail', 'businessCategory': null, 'stateCode': '07', 'pincode': '110001',
      'address': '1 Main Road, New Delhi', 'logoFileId': null, 'signatureFileId': null, 'booksLockDate': null, 'settings': settings,
    };

class FakeFirmRepository extends FirmRepository {
  FakeFirmRepository({this.settings = const {}}) : super(_api, ChangeBus());
  Map<String, dynamic> settings;

  @override
  Future<Firm> get() async => Firm.fromJson(firmJson(settings: settings));

  @override
  Future<Firm> update(Map<String, dynamic> body) async {
    settings = {...settings, ...?(body['settings'] as Map<String, dynamic>?)};
    return get();
  }
}

class FakeLoansRepository extends LoansRepository {
  FakeLoansRepository() : super(_api, ChangeBus());

  @override
  Future<List<LoanAccount>> list() async => [
        LoanAccount.fromJson({
          'id': 'l1', 'name': 'Shop Loan', 'lender': 'HDFC Bank', 'accountNumber': 'LN-4411', 'openingBalance': 500000,
          'balanceDate': '2026-04-01', 'bankAccountId': 'b1', 'interestRate': 11.5, 'termMonths': 36, 'description': null, 'balance': 462000,
        }),
        LoanAccount.fromJson({
          'id': 'l2', 'name': 'Vehicle Loan', 'lender': 'SBI', 'accountNumber': null, 'openingBalance': 300000,
          'balanceDate': '2026-06-01', 'bankAccountId': null, 'interestRate': 9, 'termMonths': 48, 'description': null, 'balance': 281500,
        }),
      ];

  @override
  Future<List<LoanTxn>> transactions(String id) async => [
        for (final (kind, type, p, i, bal) in [
          ('charge', 'Charges', 2000, 0, 462000), ('payment', 'Loan Payment', 20000, 4600, 460000),
          ('payment', 'Loan Payment', 20000, 4790, 480000), ('opening', 'Opening Loan', 500000, 0, 500000),
        ])
          LoanTxn.fromJson({
            'id': kind == 'opening' ? null : '$kind-$bal', 'kind': kind, 'type': type, 'date': '2026-10-05', 'principal': p,
            'interest': i, 'total': p + i, 'balance': bal, 'description': null,
          }),
      ];
}

class FakeReportsRepository extends ReportsRepository {
  FakeReportsRepository() : super(_api);

  @override
  Future<List<ReportDef>> catalog() async => [
        for (final (id, title, group, params) in [
          ('sale', 'Sale Report', 'Transaction', ['period']), ('purchase', 'Purchase Report', 'Transaction', ['period']),
          ('day-book', 'Day Book', 'Transaction', ['period']), ('profit-loss', 'Profit & Loss', 'Transaction', ['period']),
          ('party-statement', 'Party Statement', 'Party', ['party', 'period']), ('all-parties', 'All Parties', 'Party', <String>[]),
          ('gstr1', 'GSTR-1 (Sales)', 'GST', ['period']), ('gstr3b', 'GSTR-3B Summary', 'GST', ['period']),
          ('stock-summary', 'Stock Summary', 'Item / Stock', <String>[]), ('expense', 'Expense Report', 'Business Status', ['period']),
        ])
          ReportDef.fromJson({'id': id, 'title': title, 'group': group, 'params': params}),
      ];

  @override
  Future<ReportData> run(String id, {String? from, String? to, String? partyId, String? bankAccountId, String? itemId}) async => ReportData.fromJson({
        'id': id, 'title': 'GSTR-1 (Sales)', 'subtitle': '01/10/2026 to 31/10/2026',
        'columns': [
          for (final (k, l, t) in [
            ('date', 'Date', 'date'), ('number', 'Invoice No', 'text'), ('party', 'Party', 'text'), ('gstin', 'GSTIN', 'text'),
            ('taxable', 'Taxable Value', 'money'), ('cgst', 'CGST', 'money'), ('sgst', 'SGST', 'money'), ('igst', 'IGST', 'money'),
            ('total', 'Invoice Value', 'money'),
          ])
            {'key': k, 'label': l, 'type': t},
        ],
        'rows': [
          {'date': '2026-10-03', 'number': 'INV-11', 'party': 'Test Customer', 'gstin': '', 'taxable': 600, 'cgst': 54, 'sgst': 54, 'igst': 0, 'total': 708},
          {'date': '2026-10-07', 'number': 'INV-12', 'party': 'Sharma General Store', 'gstin': '07AAGCS1234L1Z9', 'taxable': 1200, 'cgst': 95, 'sgst': 95, 'igst': 0, 'total': 1390},
          {'date': '2026-10-09', 'number': 'INV-13', 'party': 'Gupta Wholesale', 'gstin': '27AAACR5055K1Z5', 'taxable': 5000, 'cgst': 0, 'sgst': 0, 'igst': 900, 'total': 5900},
        ],
        'summary': [
          {'label': 'B2B taxable (with GSTIN)', 'value': 6200, 'type': 'money'}, {'label': 'B2C taxable (no GSTIN)', 'value': 600, 'type': 'money'},
          {'label': 'Total Tax', 'value': 1198, 'type': 'money'},
        ],
      });
}

/// Keeps uploads in memory.
class FakeFilesRepository extends FilesRepository {
  FakeFilesRepository() : super(_api);
  final uploaded = <String, Uint8List>{};
  final attached = <(String, String, String)>[];

  @override
  Future<StoredFile> upload({required String name, required String mimeType, required Uint8List bytes}) async {
    final id = 'file${uploaded.length + 1}';
    uploaded[id] = bytes;
    return StoredFile.fromJson({'id': id, 'name': name, 'mimeType': mimeType, 'size': bytes.length});
  }

  @override
  Future<Uint8List?> bytesOrNull(String? id) async => uploaded[id];

  @override
  Future<List<Attachment>> attachments(String ownerType, String ownerId) async => [
        for (final (i, a) in attached.indexed)
          if (a.$1 == ownerType && a.$2 == ownerId)
            Attachment.fromJson({'id': 'att$i', 'fileId': a.$3, 'name': '${a.$3}.png', 'mimeType': 'image/png', 'size': uploaded[a.$3]?.length ?? 0}),
      ];

  @override
  Future<List<Attachment>> attach(String ownerType, String ownerId, String fileId) async {
    attached.add((ownerType, ownerId, fileId));
    return attachments(ownerType, ownerId);
  }

  @override
  Future<void> detach(String attachmentId) async => attached.removeAt(int.parse(attachmentId.substring(3)));
}

class FakeAccountingRepository extends AccountingRepository {
  FakeAccountingRepository({this.currencyList = const [], ChangeBus? bus}) : super(_api, bus ?? ChangeBus());

  /// Currencies on offer, as (code, symbol, rate).
  final List<(String, String, num)> currencyList;
  final savedJournals = <Map<String, dynamic>>[];

  @override
  Future<List<Currency>> currencies() async =>
      [for (final (code, symbol, rate) in currencyList) Currency.fromJson({'id': code, 'code': code, 'symbol': symbol, 'rate': rate})];

  @override
  Future<List<LedgerAccount>> ledgerAccounts() async => [
        LedgerAccount.fromJson({'id': 'la1', 'name': 'Furniture', 'type': 'asset', 'balance': 12000}),
        LedgerAccount.fromJson({'id': 'la2', 'name': 'Capital', 'type': 'equity', 'balance': -50000}),
      ];

  @override
  Future<List<JournalEntry>> journals() async => [
        JournalEntry.fromJson({'id': 'j1', 'number': '1', 'date': '2026-10-05', 'description': 'Office chairs bought', 'amount': 12000}),
      ];

  @override
  Future<String> nextJournalNumber() async => '2';

  @override
  Future<JournalEntry> saveJournal(String? id, Map<String, dynamic> body) async {
    savedJournals.add(body);
    return JournalEntry.fromJson({'id': id ?? 'j2', 'number': body['number'], 'date': body['date'], 'description': body['description'], 'amount': 0});
  }
}

class FakeUtilitiesRepository extends UtilitiesRepository {
  FakeUtilitiesRepository({this.hits = const [], this.drive = const DriveStatus(configured: true)}) : super(_api, ChangeBus());
  DriveStatus drive;
  var backupList = <ServerBackup>[
    ServerBackup.fromJson({'id': 'b1', 'fileName': 'shop-1.json.gz', 'size': 52000, 'kind': 'auto', 'createdAt': '2026-10-10T20:00:00Z', 'onDrive': true}),
    ServerBackup.fromJson({'id': 'b2', 'fileName': 'shop-2.json.gz', 'size': 51000, 'kind': 'manual', 'createdAt': '2026-10-09T10:00:00Z', 'onDrive': false, 'driveError': 'token expired'}),
  ];

  @override
  Future<List<ServerBackup>> serverBackups() async => backupList;

  @override
  Future<List<ServerBackup>> createServerBackup() async => backupList;

  @override
  Future<DriveStatus> driveStatus() async => drive;

  @override
  Future<String> driveAuthUrl() async => 'https://accounts.google.com/o/oauth2/v2/auth?x=1';

  @override
  Future<void> driveDisconnect() async => drive = const DriveStatus(configured: true);

  final List<SearchHit> hits;
  final searches = <String>[];

  @override
  Future<List<SearchHit>> search(String text) async {
    searches.add(text);
    return hits.where((h) => h.title.toLowerCase().contains(text.toLowerCase())).toList();
  }

  @override
  Future<List<PaymentReminder>> paymentReminders() async => [
        PaymentReminder.fromJson({
          'partyId': 'a', 'name': 'Test Customer', 'phone': '9000000001', 'balance': 500, 'overdueAmount': 500, 'invoices': 1,
          'oldestDue': '2026-09-20', 'daysOverdue': 21,
        }),
        PaymentReminder.fromJson({
          'partyId': 'c', 'name': 'Sharma General Store', 'phone': null, 'balance': 2400, 'overdueAmount': 1390, 'invoices': 2,
          'oldestDue': '2026-10-01', 'daysOverdue': 10,
        }),
      ];

  @override
  Future<List<ServiceReminder>> serviceReminders() async => const [];

  @override
  Future<List<SetupStep>> setup() async => [
        for (final (id, title, done) in [
          ('profile', 'Complete your company profile', true), ('logo', 'Add your logo and signature', false), ('party', 'Add your first party', true),
          ('item', 'Add your first item', true), ('bank', 'Add a bank account', false), ('invoice', 'Create your first invoice', true),
        ])
          SetupStep.fromJson({'id': id, 'title': title, 'hint': 'Shown on printed invoices.', 'route': '/company', 'done': done}),
      ];

  @override
  Future<List<VerifyCheck>> verify() async => [
        VerifyCheck.fromJson({'id': 'stock', 'title': 'Stock quantities match stock movements', 'fixable': true, 'issues': [{'label': 'Sample Item', 'detail': 'Shows 50, movements add up to 48'}]}),
        VerifyCheck.fromJson({'id': 'totals', 'title': 'Invoice totals match their line items', 'fixable': false, 'issues': <Map<String, dynamic>>[]}),
      ];
}

/// Auth repository with in-memory companies and members.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository() : super(_api);

  @override
  Future<List<Company>> companies() async => [
        Company.fromJson({'id': 'f', 'name': 'Demo Traders', 'role': 'owner', 'current': true}),
        Company.fromJson({'id': 'f2', 'name': 'Demo Traders 2025-26', 'role': 'owner', 'current': false}),
      ];

  @override
  Future<List<Member>> members() async => [
        Member.fromJson({'id': 'u', 'fullName': 'Demo Owner', 'email': 'demo@example.com', 'role': 'owner'}),
        Member.fromJson({'id': 'u2', 'fullName': 'Asha Accountant', 'email': 'asha@example.com', 'role': 'accountant'}),
        Member.fromJson({'id': 'u3', 'fullName': 'Sam Salesman', 'email': 'sam@example.com', 'role': 'salesman'}),
      ];
}

/// A fixed device position, and a record of what was sent.
class FakeLocationRepository extends LocationRepository {
  FakeLocationRepository({this.fix = const GeoFix(19.07, 72.87, 10)}) : super(_api);
  GeoFix? fix;
  final sent = <(GeoFix, String, String?)>[];
  var members = <TeamMemberLocation>[];
  var trailPoints = <TrailPoint>[];

  /// What the phone reports while in the background; tests push positions into it.
  final background = StreamController<GeoFix>.broadcast();

  @override
  Stream<GeoFix> backgroundFixes() => background.stream;

  @override
  Future<GeoFix?> currentFix() async => fix;

  @override
  Future<void> record(GeoFix fix, {String context = 'ping', String? refId}) async => sent.add((fix, context, refId));

  @override
  Future<List<TeamMemberLocation>> latest() async => members;

  @override
  Future<List<TrailPoint>> trail(String userId, String date) async => trailPoints;
}

/// The PIN kept in memory instead of the device's secure storage.
class FakePasscodeStore extends PasscodeStore {
  FakePasscodeStore([this.pin]);
  String? pin;

  @override
  Future<bool> hasPin() async => pin != null;

  @override
  Future<void> setPin(String pin) async => this.pin = pin;

  @override
  Future<bool> check(String pin) async => this.pin == null || this.pin == pin;

  @override
  Future<void> clear() async => pin = null;
}


Map<String, dynamic> integrationJson(String provider, {bool connected = false, String? stored, String? location}) => {
      'provider': provider,
      'title': {'whatsapp': 'WhatsApp (Meta Cloud API)', 'sms': 'SMS', 'einvoice': 'e-Invoice / e-Way Bill (NIC IRP)', 'razorpay': 'Online payments (Razorpay)', 'google_profile': 'Google Business Profile'}[provider],
      'help': 'Where to get these details.',
      'connected': connected,
      'fields': provider == 'google_profile'
          ? <Map<String, dynamic>>[]
          : [
              {'key': 'phoneNumberId', 'label': 'Phone Number ID', 'secret': false, 'required': true, 'help': null, 'options': null, 'value': connected ? '555' : '', 'stored': null},
              {'key': 'accessToken', 'label': 'Access token', 'secret': true, 'required': true, 'help': null, 'options': null, 'value': null, 'stored': stored},
            ],
      'info': provider == 'google_profile' ? {'email': connected ? 'owner@example.com' : null, 'location': location} : null,
    };

Map<String, dynamic> einvoiceInfoJson({String status = 'none', List<String> problems = const [], List<String> ewayProblems = const [], bool portal = true, String? irn, String? eway}) => {
      'einvoiceStatus': status,
      'irn': irn,
      'ackNo': irn == null ? null : '1122',
      'ackDate': null,
      'signedQr': null,
      'ewayBillNo': eway,
      'ewayBillDate': null,
      'ewayValidUpto': eway == null ? null : '2026-10-14T18:29:00.000Z',
      'transport': {'mode': 'road', 'vehicleNo': 'MH12AB1234', 'distanceKm': 100},
      'einvoiceProblems': problems,
      'ewayProblems': ewayProblems,
      'portalConnected': portal,
    };

/// Outside services answered from memory; each call is recorded.
class FakeIntegrationsRepository extends IntegrationsRepository {
  FakeIntegrationsRepository() : super(_api, ChangeBus());
  final calls = <String>[];
  var providers = <Map<String, dynamic>>[for (final p in ['whatsapp', 'sms', 'einvoice', 'razorpay', 'google_profile']) integrationJson(p)];
  var einvoiceState = einvoiceInfoJson();
  Object? failure;
  var link = {'id': 'l1', 'invoiceId': 'i1', 'url': 'https://rzp.io/i/abc', 'amount': 236, 'status': 'created'};

  Future<T> _do<T>(String call, T Function() result) async {
    calls.add(call);
    if (failure != null) throw failure!;
    return result();
  }

  @override
  Future<List<Integration>> integrations() => _do('integrations', () => [for (final j in providers) Integration.fromJson(j)]);

  @override
  Future<List<Integration>> save(String provider, Map<String, String> values) => _do('save $provider ${values.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}=${e.value}').join(',')}', () {
        providers = [for (final j in providers) j['provider'] == provider ? integrationJson(provider, connected: true, stored: '••••1234') : j];
        return [for (final j in providers) Integration.fromJson(j)];
      });

  @override
  Future<void> disconnect(String provider) => _do('disconnect $provider', () {
        providers = [for (final j in providers) j['provider'] == provider ? integrationJson(provider) : j];
      });

  @override
  Future<String> webhookUrl() async => 'https://billing.example.com/api/v1/webhooks/razorpay/firm-1';

  @override
  Future<void> testMessage(String channel, String to) => _do('test $channel $to', () {});

  @override
  Future<void> sendInvoice(String id, String channel, {String? phone}) => _do('sendInvoice $id $channel ${phone ?? ''}', () {});

  @override
  Future<void> sendPayment(String id, String channel, {String? phone}) => _do('sendPayment $id $channel ${phone ?? ''}', () {});

  @override
  Future<void> sendReminder(String partyId, num amount, String channel, {String? phone}) => _do('sendReminder $partyId $amount $channel', () {});

  @override
  Future<({int recipients, int sent, List<String> failed})> marketing(String channel, String text, {String? groupId}) =>
      _do('marketing $channel $text', () => (recipients: 3, sent: 2, failed: ['Ravi: no phone']));

  @override
  Future<List<MessageEntry>> messages() => _do('messages', () => [
        MessageEntry.fromJson({'channel': 'whatsapp', 'kind': 'invoice', 'to': '919876543210', 'body': 'Dear Ravi, invoice INV-1 for ₹1180', 'status': 'sent', 'error': null, 'createdAt': '2026-10-13T05:30:00.000Z', 'partyName': 'Ravi Traders'}),
        MessageEntry.fromJson({'channel': 'sms', 'kind': 'reminder', 'to': '919000000001', 'body': 'Payment due', 'status': 'failed', 'error': 'Recipient not allowed', 'createdAt': '2026-10-13T04:00:00.000Z', 'partyName': null}),
      ]);

  @override
  Future<EinvoiceInfo> einvoice(String invoiceId) => _do('einvoice $invoiceId', () => EinvoiceInfo.fromJson(einvoiceState));

  @override
  Future<EinvoiceInfo> saveTransport(String invoiceId, Transport t) => _do('transport ${t.vehicleNo} ${t.distanceKm}', () => EinvoiceInfo.fromJson(einvoiceState));

  @override
  Future<EinvoiceInfo> generateEinvoice(String invoiceId) => _do('generate', () => einvoiceState = einvoiceInfoJson(status: 'generated', irn: 'a' * 64)).then(EinvoiceInfo.fromJson);

  @override
  Future<EinvoiceInfo> recordIrn(String invoiceId, {required String irn, String? ackNo, String? ackDate}) =>
      _do('recordIrn $irn', () => einvoiceState = einvoiceInfoJson(status: 'generated', irn: irn)).then(EinvoiceInfo.fromJson);

  @override
  Future<EinvoiceInfo> cancelEinvoice(String invoiceId, {required String reason, required String remark, required bool onPortal}) =>
      _do('cancel $reason $remark $onPortal', () => einvoiceState = einvoiceInfoJson(status: 'cancelled')).then(EinvoiceInfo.fromJson);

  @override
  Future<EinvoiceInfo> generateEway(String invoiceId) =>
      _do('eway', () => einvoiceState = einvoiceInfoJson(status: 'generated', irn: 'a' * 64, eway: '331234567890')).then(EinvoiceInfo.fromJson);

  @override
  Future<EinvoiceInfo> recordEway(String invoiceId, String no) => _do('recordEway $no', () => einvoiceState = einvoiceInfoJson(eway: no)).then(EinvoiceInfo.fromJson);

  @override
  Future<(String, Object)> einvoiceJson(String invoiceId) => _do('einvoiceJson', () => ('einvoice-INV-1.json', <Object>[{'Version': '1.1'}]));

  @override
  Future<(String, Object)> ewayJson(String invoiceId) => _do('ewayJson', () => ('ewaybill-INV-1.json', <String, Object>{'version': '1.0.0621'}));

  @override
  Future<PaymentLink> createPaymentLink(String invoiceId) => _do('link $invoiceId', () => PaymentLink.fromJson(link));

  @override
  Future<PaymentLink> refreshPaymentLink(String linkId) => _do('refreshLink', () => PaymentLink.fromJson({...link, 'status': 'paid'}));

  var googleLocationList = [
    {'account': 'accounts/1', 'location': 'locations/9', 'title': 'Acme Traders', 'address': '1 Main Rd, Pune, 411001'},
  ];

  @override
  Future<List<GoogleLocation>> googleLocations() => _do('googleLocations', () => [for (final j in googleLocationList) GoogleLocation.fromJson(j)]);

  @override
  Future<void> chooseGoogleLocation(GoogleLocation l) => _do('chooseLocation ${l.location}', () {
        providers = [for (final j in providers) j['provider'] == 'google_profile' ? integrationJson('google_profile', connected: true, location: l.title) : j];
      });

  @override
  Future<GoogleProfileInfo> googleProfile() => _do('googleProfile', () => GoogleProfileInfo.fromJson({'title': 'Acme Traders', 'description': 'Hardware since 1990', 'website': 'https://acme.example', 'phone': '+91 20 5550 1000'}));

  @override
  Future<GoogleProfileInfo> saveGoogleProfile({String? description, String? website}) =>
      _do('saveProfile $description $website', () => GoogleProfileInfo.fromJson({'title': 'Acme Traders', 'description': description, 'website': website, 'phone': ''}));

  @override
  Future<void> googlePost(String summary, {String? url}) => _do('post $summary ${url ?? ''}', () {});

  @override
  Future<GoogleReviews> googleReviews() => _do('reviews', () => GoogleReviews.fromJson({
        'average': 4.5,
        'total': 2,
        'reviews': [
          {'id': 'r1', 'name': 'Asha', 'stars': 5, 'comment': 'Great service', 'at': '2026-10-01T00:00:00Z', 'reply': null},
          {'id': 'r2', 'name': 'Vikram', 'stars': 4, 'comment': 'Good prices', 'at': '2026-09-01T00:00:00Z', 'reply': 'Thank you!'},
        ],
      }));

  @override
  Future<void> replyToReview(String reviewId, String comment) => _do('reply $reviewId $comment', () {});
}
