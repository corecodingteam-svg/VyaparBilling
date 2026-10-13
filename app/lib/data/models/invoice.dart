import 'package:equatable/equatable.dart';

/// Everything that differs between the documents sharing the invoice screens: wording, which side
/// of the business they are on, and whether they are quotation-like (no stock, balance or payment).
class InvoiceKind {
  const InvoiceKind._({
    required this.type,
    required this.title,
    required this.singular,
    required this.numberLabel,
    required this.numberColumn,
    required this.documentTitle,
    required this.pdfPartyTitle,
    required this.basePath,
    this.partyLabel = 'Party',
    this.paidLabel = 'Received',
    this.unpaidLabel = 'Balance',
    this.dateLabel = 'Date',
    this.purchaseSide = false,
    this.isQuote = false,
    this.convertsTo = const [],
  });

  final String type;
  final String title;
  final String singular;
  final String partyLabel;
  final String paidLabel;
  final String unpaidLabel;
  final String numberLabel;

  /// Number column heading in lists.
  final String numberColumn;
  final String dateLabel;

  /// Heading on the printed document.
  final String documentTitle;

  /// Heading of the party box on the printed document.
  final String pdfPartyTitle;
  final String basePath;

  /// Bought from a supplier (uses purchase prices) rather than sold to a customer.
  final bool purchaseSide;

  /// Quotation-like: open until converted; no stock, balance or payment.
  final bool isQuote;

  /// Types this document can be converted into.
  final List<String> convertsTo;

  bool get isSale => type == 'sale';
  bool get hasPayment => !isQuote;

  /// Sale-side documents quote the item's sale price and default discount; purchase-side ones the purchase price.
  bool get usesSalePrice => !purchaseSide;

  /// Only a sale can be a walk-in cash sale.
  bool get supportsCash => isSale;

  /// We number everything ourselves except purchase bills, which carry the supplier's (optional) number.
  bool get numberRequired => type != 'purchase';
  bool get showBillingAddress => isSale;

  List<InvoiceKind> get convertTargets => [for (final t in convertsTo) of(t)];

  static const sale = InvoiceKind._(
    type: 'sale', title: 'Sale Invoices', singular: 'Sale', partyLabel: 'Customer',
    numberLabel: 'Invoice Number', numberColumn: 'Invoice no', dateLabel: 'Invoice Date',
    documentTitle: 'Invoice', pdfPartyTitle: 'Bill To', basePath: '/sale-invoices',
  );
  static const purchase = InvoiceKind._(
    type: 'purchase', title: 'Purchase Bills', singular: 'Purchase', paidLabel: 'Paid', unpaidLabel: 'Unpaid',
    numberLabel: 'Bill Number', numberColumn: 'Bill no', dateLabel: 'Bill Date',
    documentTitle: 'Purchase Bill', pdfPartyTitle: 'Bill From', basePath: '/purchase-bills', purchaseSide: true,
  );
  static const estimate = InvoiceKind._(
    type: 'estimate', title: 'Estimate/Quotation', singular: 'Estimate',
    numberLabel: 'Ref No.', numberColumn: 'Reference no',
    documentTitle: 'Estimate', pdfPartyTitle: 'Estimate For', basePath: '/estimates',
    isQuote: true, convertsTo: ['sale', 'sale_order'],
  );
  static const saleOrder = InvoiceKind._(
    type: 'sale_order', title: 'Sale Orders', singular: 'Sale Order',
    numberLabel: 'Order No.', numberColumn: 'Order no', dateLabel: 'Order Date',
    documentTitle: 'Sale Order', pdfPartyTitle: 'Order From', basePath: '/sale-orders',
    isQuote: true, convertsTo: ['sale'],
  );
  static const deliveryChallan = InvoiceKind._(
    type: 'delivery_challan', title: 'Delivery Challans', singular: 'Delivery Challan',
    numberLabel: 'Challan No.', numberColumn: 'Challan no', dateLabel: 'Challan Date',
    documentTitle: 'Delivery Challan', pdfPartyTitle: 'Delivery To', basePath: '/delivery-challans',
    isQuote: true, convertsTo: ['sale'],
  );
  static const proforma = InvoiceKind._(
    type: 'proforma', title: 'Proforma Invoices', singular: 'Proforma Invoice',
    numberLabel: 'Ref No.', numberColumn: 'Reference no',
    documentTitle: 'Proforma Invoice', pdfPartyTitle: 'Bill To', basePath: '/proforma-invoices',
    isQuote: true, convertsTo: ['sale'],
  );
  static const creditNote = InvoiceKind._(
    type: 'credit_note', title: 'Sale Return / Credit Note', singular: 'Credit Note', partyLabel: 'Customer',
    paidLabel: 'Paid', numberLabel: 'Return No.', numberColumn: 'Return no',
    documentTitle: 'Credit Note', pdfPartyTitle: 'Return From', basePath: '/credit-notes',
  );
  static const purchaseOrder = InvoiceKind._(
    type: 'purchase_order', title: 'Purchase Orders', singular: 'Purchase Order',
    numberLabel: 'Order No.', numberColumn: 'Order no', dateLabel: 'Order Date',
    documentTitle: 'Purchase Order', pdfPartyTitle: 'Order To', basePath: '/purchase-orders',
    purchaseSide: true, isQuote: true, convertsTo: ['purchase'],
  );
  static const debitNote = InvoiceKind._(
    type: 'debit_note', title: 'Purchase Return / Debit Note', singular: 'Debit Note',
    numberLabel: 'Return No.', numberColumn: 'Return no',
    documentTitle: 'Debit Note', pdfPartyTitle: 'Return To', basePath: '/debit-notes', purchaseSide: true,
  );

  static const all = [sale, purchase, estimate, saleOrder, deliveryChallan, proforma, creditNote, purchaseOrder, debitNote];

  static InvoiceKind of(String type) => all.firstWhere((k) => k.type == type, orElse: () => sale);

  /// The kind for [type], or null when it is not an invoice-like document.
  static InvoiceKind? maybeOf(String type) => all.where((k) => k.type == type).firstOrNull;
}

const paymentModes = {'cash': 'Cash', 'bank': 'Bank', 'upi': 'UPI', 'cheque': 'Cheque', 'card': 'Card'};

class InvoiceSummary extends Equatable {
  InvoiceSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        type = j['type'] as String,
        number = j['number'] as String,
        invoiceDate = j['invoiceDate'] as String,
        isCash = j['isCash'] as bool,
        partyId = j['partyId'] as String?,
        partyName = j['partyName'] as String,
        total = j['total'] as num,
        received = j['received'] as num,
        balance = j['balance'] as num,
        paymentMode = j['paymentMode'] as String,
        bankAccountId = j['bankAccountId'] as String?,
        dueDate = j['dueDate'] as String?,
        linkedAmount = (j['linkedAmount'] as num?) ?? 0,
        paymentLabel = (j['paymentLabel'] as String?) ?? (paymentModes[j['paymentMode']] ?? ''),
        currencyCode = j['currencyCode'] as String?,
        fxTotal = j['fxTotal'] as num?,
        fxBalance = j['fxBalance'] as num?,
        tdsAmount = (j['tdsAmount'] as num?) ?? 0,
        tcsAmount = (j['tcsAmount'] as num?) ?? 0,
        loyaltyAmount = (j['loyaltyAmount'] as num?) ?? 0,
        godownId = j['godownId'] as String?,
        einvoiceStatus = (j['einvoiceStatus'] as String?) ?? 'none',
        irn = j['irn'] as String?,
        ewayBillNo = j['ewayBillNo'] as String?,
        status = j['status'] as String?,
        convertedInvoiceId = j['convertedInvoiceId'] as String?,
        convertedType = j['convertedType'] as String?;

  final String id;
  final String type;
  final String number;
  final String invoiceDate;
  final bool isCash;
  final String? partyId;
  final String partyName;
  final num total;
  final num received;
  final num balance;
  final String paymentMode;
  final String? bankAccountId;
  final String? dueDate;

  /// Paid later through Payment-In/Out entries linked to this document; [balance] already excludes it.
  final num linkedAmount;

  /// How it was paid, e.g. "Cash + UPI" when the bill was paid in parts.
  final String paymentLabel;

  /// Currency the document is made out in; null = rupees. [fxTotal] and [fxBalance] are in it.
  final String? currencyCode;
  final num? fxTotal;
  final num? fxBalance;

  /// TDS the payer holds back, TCS collected on top, and the value of loyalty points redeemed.
  final num tdsAmount;
  final num tcsAmount;
  final num loyaltyAmount;

  /// Store the stock moved through; null = main store.
  final String? godownId;

  /// E-invoice state (none, generated, cancelled), its IRN, and the e-way bill number.
  final String einvoiceStatus;
  final String? irn;
  final String? ewayBillNo;

  bool get isForeign => currencyCode != null;

  /// Everything paid so far: with the document plus linked payments.
  num get paid => received + linkedAmount;

  /// Quotation-like documents only: 'open' or 'converted'.
  final String? status;

  /// Quotation-like documents only: the document created from this one, and its type.
  final String? convertedInvoiceId;
  final String? convertedType;

  bool get isOpen => status == 'open';

  @override
  List<Object?> get props =>
      [id, type, number, invoiceDate, isCash, partyId, partyName, total, received, balance, paymentMode, bankAccountId, dueDate, linkedAmount, paymentLabel, status, convertedInvoiceId, convertedType, currencyCode, fxTotal, fxBalance, tdsAmount, tcsAmount, loyaltyAmount, godownId, einvoiceStatus, irn, ewayBillNo];
}

class InvoiceLine extends Equatable {
  InvoiceLine.fromJson(Map<String, dynamic> j)
      : itemId = j['itemId'] as String?,
        name = j['name'] as String,
        quantity = j['quantity'] as num,
        unit = j['unit'] as String?,
        price = j['price'] as num,
        discountPct = j['discountPct'] as num,
        discountAmount = j['discountAmount'] as num,
        hsnCode = j['hsnCode'] as String?,
        gstRate = (j['gstRate'] as num?) ?? 0,
        taxableValue = (j['taxableValue'] as num?) ?? j['amount'] as num,
        cgst = (j['cgst'] as num?) ?? 0,
        sgst = (j['sgst'] as num?) ?? 0,
        igst = (j['igst'] as num?) ?? 0,
        cessRate = (j['cessRate'] as num?) ?? 0,
        cess = (j['cess'] as num?) ?? 0,
        billDiscount = (j['billDiscount'] as num?) ?? 0,
        batchNo = j['batchNo'] as String?,
        mfgDate = j['mfgDate'] as String?,
        expiryDate = j['expiryDate'] as String?,
        mrp = j['mrp'] as num?,
        serialNos = j['serialNos'] as String?,
        fxPrice = j['fxPrice'] as num?,
        fxAmount = j['fxAmount'] as num?,
        amount = j['amount'] as num;

  final String? itemId;
  final String name;
  final num quantity;
  final String? unit;
  final num price;
  final num discountPct;
  final num discountAmount;
  final String? hsnCode;

  /// GST %; 0 = no tax.
  final num gstRate;
  final num taxableValue;
  final num cgst;
  final num sgst;
  final num igst;

  final num cessRate;
  final num cess;

  /// This line's share of the bill-level discount.
  final num billDiscount;
  final String? batchNo;
  final String? mfgDate;
  final String? expiryDate;
  final num? mrp;

  /// Comma-separated serial numbers, one per unit.
  final String? serialNos;

  /// Foreign-currency documents: the price and line amount in that currency.
  final num? fxPrice;
  final num? fxAmount;

  /// Taxable value + tax.
  final num amount;

  num get tax => cgst + sgst + igst + cess;

  @override
  List<Object?> get props =>
      [itemId, name, quantity, unit, price, discountPct, discountAmount, hsnCode, gstRate, taxableValue, cgst, sgst, igst, amount, cessRate, cess, billDiscount, batchNo, mfgDate, expiryDate, mrp, serialNos, fxPrice, fxAmount];
}

/// One part of the money taken with a document: an invoice can be paid part cash, part UPI, and so on.
class PaymentPart extends Equatable {
  const PaymentPart({required this.mode, this.bankAccountId, required this.amount, this.fxAmount});
  PaymentPart.fromJson(Map<String, dynamic> j)
      : mode = j['mode'] as String,
        bankAccountId = j['bankAccountId'] as String?,
        amount = j['amount'] as num,
        fxAmount = j['fxAmount'] as num?;

  final String mode;
  final String? bankAccountId;
  final num amount;

  /// On a foreign-currency document: the part in that currency.
  final num? fxAmount;

  @override
  List<Object?> get props => [mode, bankAccountId, amount, fxAmount];
}

/// A Payment-In/Out entry (or part of one) set against this document.
class LinkedPayment extends Equatable {
  LinkedPayment.fromJson(Map<String, dynamic> j)
      : paymentId = j['paymentId'] as String,
        number = j['number'] as String,
        date = j['date'] as String,
        amount = j['amount'] as num;

  final String paymentId;
  final String number;
  final String date;
  final num amount;

  @override
  List<Object?> get props => [paymentId, number, date, amount];
}

class Invoice extends InvoiceSummary {
  Invoice.fromJson(super.j)
      : phone = j['phone'] as String?,
        billingAddress = j['billingAddress'] as String?,
        shippingAddress = j['shippingAddress'] as String?,
        ackNo = j['ackNo'] as String?,
        signedQr = j['signedQr'] as String?,
        exchangeRate = j['exchangeRate'] as num?,
        fxReceived = j['fxReceived'] as num?,
        discountPct = (j['discountPct'] as num?) ?? 0,
        discountAmount = (j['discountAmount'] as num?) ?? 0,
        charges = [for (final c in (j['charges'] as List?) ?? const []) ((c as Map)['name'] as String, c['amount'] as num)],
        chargesTotal = (j['chargesTotal'] as num?) ?? 0,
        cess = (j['cess'] as num?) ?? 0,
        tcsRate = (j['tcsRate'] as num?) ?? 0,
        tdsRate = (j['tdsRate'] as num?) ?? 0,
        loyaltyEarned = ((j['loyaltyEarned'] as num?) ?? 0).toInt(),
        loyaltyRedeemed = ((j['loyaltyRedeemed'] as num?) ?? 0).toInt(),
        payments = [for (final p in (j['payments'] as List?) ?? const []) PaymentPart.fromJson(p as Map<String, dynamic>)],
        linkedPayments = [for (final p in (j['linkedPayments'] as List?) ?? const []) LinkedPayment.fromJson(p as Map<String, dynamic>)],
        stateOfSupply = j['stateOfSupply'] as String?,
        pricesIncludeTax = (j['pricesIncludeTax'] as bool?) ?? false,
        interState = (j['interState'] as bool?) ?? false,
        partyGstin = j['partyGstin'] as String?,
        taxableAmount = (j['taxableAmount'] as num?) ?? j['subtotal'] as num,
        cgst = (j['cgst'] as num?) ?? 0,
        sgst = (j['sgst'] as num?) ?? 0,
        igst = (j['igst'] as num?) ?? 0,
        subtotal = j['subtotal'] as num,
        roundOff = j['roundOff'] as num,
        description = j['description'] as String?,
        lines = [for (final l in j['lines'] as List) InvoiceLine.fromJson(l as Map<String, dynamic>)],
        super.fromJson();

  final String? phone;
  final String? billingAddress;
  final String? shippingAddress;

  /// The e-invoice portal's acknowledgement number and signed QR, once the invoice has an IRN.
  final String? ackNo;
  final String? signedQr;

  /// Value of one unit of [currencyCode] in rupees when the document was made.
  final num? exchangeRate;
  final num? fxReceived;

  /// Bill-level discount, already spread over the lines before tax.
  final num discountPct;
  final num discountAmount;

  /// Freight, packing and the like: (name, amount), added after tax.
  final List<(String, num)> charges;
  final num chargesTotal;
  final num cess;
  final num tcsRate;
  final num tdsRate;
  final int loyaltyEarned;
  final int loyaltyRedeemed;

  /// How the amount received with the document was paid.
  final List<PaymentPart> payments;
  final List<LinkedPayment> linkedPayments;
  final String? stateOfSupply;
  final bool pricesIncludeTax;

  /// Supply to another state: IGST instead of CGST + SGST.
  final bool interState;
  final String? partyGstin;
  final num taxableAmount;
  final num cgst;
  final num sgst;
  final num igst;

  /// Sum of line amounts (tax included), before round-off.
  final num subtotal;
  final num roundOff;
  final String? description;
  final List<InvoiceLine> lines;

  num get totalTax => cgst + sgst + igst + cess;

  @override
  List<Object?> get props => [
        ...super.props, phone, billingAddress, shippingAddress, ackNo, signedQr, exchangeRate, fxReceived, discountPct, discountAmount, charges, chargesTotal, cess, tcsRate,
        tdsRate, loyaltyEarned, loyaltyRedeemed, payments, linkedPayments, stateOfSupply, pricesIncludeTax, interState, partyGstin,
        taxableAmount, cgst, sgst, igst, subtotal, roundOff, description, lines,
      ];
}
