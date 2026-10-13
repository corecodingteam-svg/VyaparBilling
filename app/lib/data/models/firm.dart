import 'package:equatable/equatable.dart';

/// The wording of customer messages until the company writes its own; {customer} {number} {amount} {balance} {business} {link} are filled in.
const defaultInvoiceMessage = 'Dear {customer}, your invoice {number} for ₹{amount} from {business} is ready. Balance due: ₹{balance}. {link}';
const defaultPaymentMessage = 'Dear {customer}, we received ₹{amount} (receipt {number}). Thank you! — {business}';
const defaultReminderMessage = 'Dear {customer}, a payment of ₹{amount} to {business} is overdue. Please pay at your earliest. {link}';
/// A custom party field defined once for the business and filled in per party.
class PartyFieldDef extends Equatable {
  const PartyFieldDef(this.name, {this.showInPrint = false});
  final String name;
  final bool showInPrint;

  Map<String, dynamic> toJson() => {'name': name, 'showInPrint': showInPrint};

  @override
  List<Object?> get props => [name, showInPrint];
}

const invoiceThemes = {'classic': 'Classic', 'modern': 'Modern', 'minimal': 'Minimal'};

/// Documents that carry their own number prefix, with the wording used in settings.
const prefixTypes = {
  'sale': 'Sale Invoice',
  'estimate': 'Estimate',
  'sale_order': 'Sale Order',
  'delivery_challan': 'Delivery Challan',
  'proforma': 'Proforma Invoice',
  'credit_note': 'Credit Note',
  'purchase_order': 'Purchase Order',
  'debit_note': 'Debit Note',
  'payment_in': 'Payment-In',
  'payment_out': 'Payment-Out',
};

/// Per-business settings (defaults live on the server: backend/src/firm/firm-settings.ts).
class FirmSettings extends Equatable {
  const FirmSettings({
    this.gstEnabled = true,
    this.invoicePrefix = '',
    this.prefixes = const {},
    this.defaultRoundOff = true,
    this.defaultCashSale = false,
    this.blockNegativeStock = false,
    this.showInvoicePreview = true,
    this.dueDatesEnabled = false,
    this.defaultCreditDays = 15,
    this.invoiceTerms = '',
    this.signatureLabel = 'Authorized Signatory',
    this.invoiceTheme = 'classic',
    this.themeColor = '#1E5EFF',
    this.thermalWidth = 80,
    this.shippingAddressEnabled = true,
    this.partyFields = const [],
    this.paymentReminderDays = 7,
    this.stockMaintenance = true,
    this.itemWiseDiscount = true,
    this.quantityDecimals = 2,
    this.defaultUnit = '',
    this.wholesalePriceEnabled = true,
    this.accountingEnabled = false,
    this.serviceRemindersEnabled = false,
    this.salesmanOwnDataOnly = true,
    this.locationTrackingEnabled = false,
    this.godownsEnabled = false,
    this.batchTrackingEnabled = false,
    this.serialTrackingEnabled = false,
    this.mrpEnabled = false,
    this.cessEnabled = false,
    this.billDiscountEnabled = false,
    this.additionalChargesEnabled = false,
    this.tcsEnabled = false,
    this.tdsEnabled = false,
    this.loyaltyEnabled = false,
    this.partyGroupsEnabled = false,
    this.chargeNames = const ['Shipping', 'Packaging'],
    this.loyaltyEarnPer = 100,
    this.loyaltyPointValue = 1,
    this.autoBackup = 'off',
    this.autoBackupKeep = 7,
    this.autoSendInvoices = 'off',
    this.autoSendPayments = 'off',
    this.invoiceMessage = defaultInvoiceMessage,
    this.paymentMessage = defaultPaymentMessage,
    this.reminderMessage = defaultReminderMessage,
    this.einvoiceEnabled = false,
    this.ewayEnabled = false,
    this.upiId = '',
    this.upiQrOnInvoice = false,
    this.creditLimitMode = 'warn',
    this.itemImagesOnInvoice = false,
  });

  FirmSettings.fromJson(Map<String, dynamic> j)
      : gstEnabled = (j['gstEnabled'] as bool?) ?? true,
        invoicePrefix = (j['invoicePrefix'] as String?) ?? '',
        prefixes = {
          for (final e in ((j['prefixes'] as Map?) ?? const {}).entries)
            if ((e.value as String?)?.isNotEmpty ?? false) e.key as String: e.value as String,
        },
        defaultRoundOff = (j['defaultRoundOff'] as bool?) ?? true,
        defaultCashSale = (j['defaultCashSale'] as bool?) ?? false,
        blockNegativeStock = (j['blockNegativeStock'] as bool?) ?? false,
        showInvoicePreview = (j['showInvoicePreview'] as bool?) ?? true,
        dueDatesEnabled = (j['dueDatesEnabled'] as bool?) ?? false,
        defaultCreditDays = ((j['defaultCreditDays'] as num?) ?? 15).toInt(),
        invoiceTerms = (j['invoiceTerms'] as String?) ?? '',
        signatureLabel = (j['signatureLabel'] as String?) ?? 'Authorized Signatory',
        invoiceTheme = (j['invoiceTheme'] as String?) ?? 'classic',
        themeColor = (j['themeColor'] as String?) ?? '#1E5EFF',
        thermalWidth = ((j['thermalWidth'] as num?) ?? 80).toInt(),
        shippingAddressEnabled = (j['shippingAddressEnabled'] as bool?) ?? true,
        partyFields = [
          for (final f in (j['partyFields'] as List?) ?? const [])
            PartyFieldDef((f as Map)['name'] as String, showInPrint: (f['showInPrint'] as bool?) ?? false),
        ],
        paymentReminderDays = j.containsKey('paymentReminderDays') ? (j['paymentReminderDays'] as num?)?.toInt() : 7,
        stockMaintenance = (j['stockMaintenance'] as bool?) ?? true,
        itemWiseDiscount = (j['itemWiseDiscount'] as bool?) ?? true,
        quantityDecimals = ((j['quantityDecimals'] as num?) ?? 2).toInt(),
        defaultUnit = (j['defaultUnit'] as String?) ?? '',
        wholesalePriceEnabled = (j['wholesalePriceEnabled'] as bool?) ?? true,
        accountingEnabled = (j['accountingEnabled'] as bool?) ?? false,
        serviceRemindersEnabled = (j['serviceRemindersEnabled'] as bool?) ?? false,
        salesmanOwnDataOnly = (j['salesmanOwnDataOnly'] as bool?) ?? true,
        locationTrackingEnabled = (j['locationTrackingEnabled'] as bool?) ?? false,
        godownsEnabled = (j['godownsEnabled'] as bool?) ?? false,
        batchTrackingEnabled = (j['batchTrackingEnabled'] as bool?) ?? false,
        serialTrackingEnabled = (j['serialTrackingEnabled'] as bool?) ?? false,
        mrpEnabled = (j['mrpEnabled'] as bool?) ?? false,
        cessEnabled = (j['cessEnabled'] as bool?) ?? false,
        billDiscountEnabled = (j['billDiscountEnabled'] as bool?) ?? false,
        additionalChargesEnabled = (j['additionalChargesEnabled'] as bool?) ?? false,
        tcsEnabled = (j['tcsEnabled'] as bool?) ?? false,
        tdsEnabled = (j['tdsEnabled'] as bool?) ?? false,
        loyaltyEnabled = (j['loyaltyEnabled'] as bool?) ?? false,
        partyGroupsEnabled = (j['partyGroupsEnabled'] as bool?) ?? false,
        chargeNames = [for (final c in (j['chargeNames'] as List?) ?? const ['Shipping', 'Packaging']) c as String],
        loyaltyEarnPer = (j['loyaltyEarnPer'] as num?) ?? 100,
        loyaltyPointValue = (j['loyaltyPointValue'] as num?) ?? 1,
        autoBackup = (j['autoBackup'] as String?) ?? 'off',
        autoBackupKeep = ((j['autoBackupKeep'] as num?) ?? 7).toInt(),
        autoSendInvoices = (j['autoSendInvoices'] as String?) ?? 'off',
        autoSendPayments = (j['autoSendPayments'] as String?) ?? 'off',
        invoiceMessage = (j['invoiceMessage'] as String?) ?? defaultInvoiceMessage,
        paymentMessage = (j['paymentMessage'] as String?) ?? defaultPaymentMessage,
        reminderMessage = (j['reminderMessage'] as String?) ?? defaultReminderMessage,
        einvoiceEnabled = (j['einvoiceEnabled'] as bool?) ?? false,
        ewayEnabled = (j['ewayEnabled'] as bool?) ?? false,
        upiId = (j['upiId'] as String?) ?? '',
        upiQrOnInvoice = (j['upiQrOnInvoice'] as bool?) ?? false,
        creditLimitMode = (j['creditLimitMode'] as String?) ?? 'warn',
        itemImagesOnInvoice = (j['itemImagesOnInvoice'] as bool?) ?? false;

  /// Show GST fields and tax columns.
  final bool gstEnabled;

  /// Older single prefix for sale invoices; [prefixes] takes precedence.
  final String invoicePrefix;

  /// Number prefix per document type (see [prefixTypes]).
  final Map<String, String> prefixes;
  final bool defaultRoundOff;
  final bool defaultCashSale;

  /// Refuse sales that would take stock below zero.
  final bool blockNegativeStock;

  /// Open the printable preview right after saving a document.
  final bool showInvoicePreview;

  /// Show a due date on credit invoices, defaulting to [defaultCreditDays] after the invoice date.
  final bool dueDatesEnabled;
  final int defaultCreditDays;

  /// Printed at the bottom of invoices.
  final String invoiceTerms;
  final String signatureLabel;

  /// classic | modern | minimal
  final String invoiceTheme;

  /// Accent colour of the modern and minimal themes, as #RRGGBB.
  final String themeColor;

  /// Thermal receipt paper width in mm: 58 or 80.
  final int thermalWidth;
  final bool shippingAddressEnabled;
  final List<PartyFieldDef> partyFields;

  /// Remind about dues older than this many days; null = reminders off.
  final int? paymentReminderDays;

  /// Track stock quantities for products.
  final bool stockMaintenance;

  /// Show the per-line discount columns on documents.
  final bool itemWiseDiscount;

  /// Decimal places allowed in quantities (0–3).
  final int quantityDecimals;

  /// Unit preselected for new items.
  final String defaultUnit;
  final bool wholesalePriceEnabled;

  /// Own ledger accounts and journal entries.
  final bool accountingEnabled;
  final bool serviceRemindersEnabled;

  /// A salesman sees only the parties assigned to them and the documents they entered.
  final bool salesmanOwnDataOnly;

  /// Record where salesmen are while they use the app.
  final bool locationTrackingEnabled;

  /// Several stores; every stock movement belongs to one.
  final bool godownsEnabled;

  /// Batch number and expiry per line.
  final bool batchTrackingEnabled;

  /// Serial numbers / IMEIs per unit.
  final bool serialTrackingEnabled;

  /// MRP on items and lines.
  final bool mrpEnabled;

  /// Compensation cess per line.
  final bool cessEnabled;

  /// A discount on the whole bill, taken off before tax.
  final bool billDiscountEnabled;

  /// Freight, packing and the like on a bill.
  final bool additionalChargesEnabled;

  /// TCS collected on top of the bill.
  final bool tcsEnabled;

  /// TDS held back by the payer.
  final bool tdsEnabled;

  /// Customers earn points on sales and redeem them against bills.
  final bool loyaltyEnabled;

  /// Parties can be put in groups.
  final bool partyGroupsEnabled;

  /// Names offered for additional charges on a bill.
  final List<String> chargeNames;

  /// Rupees of sale that earn one loyalty point, and what a point is worth when redeemed.
  final num loyaltyEarnPer;
  final num loyaltyPointValue;

  /// off | daily | weekly — backups the server makes by itself.
  final String autoBackup;
  final int autoBackupKeep;

  /// Documents sent to the customer automatically: off, whatsapp or sms.
  final String autoSendInvoices;
  final String autoSendPayments;
  final String invoiceMessage;
  final String paymentMessage;
  final String reminderMessage;
  final bool einvoiceEnabled;
  final bool ewayEnabled;

  /// Shown as a scannable QR on printed invoices.
  final String upiId;
  final bool upiQrOnInvoice;

  /// Going past a customer's credit limit: 'warn' asks first, 'block' refuses.
  final String creditLimitMode;

  /// Print each item's picture on invoices.
  final bool itemImagesOnInvoice;

  /// The prefix for new documents of [type] ('sale', 'payment_in', ...).
  String prefixFor(String type) => prefixes[type] ?? (type == 'sale' ? invoicePrefix : '');

  Map<String, dynamic> toJson() => {
        'gstEnabled': gstEnabled,
        'invoicePrefix': invoicePrefix,
        // Every type is sent so that clearing a prefix overwrites the stored one.
        'prefixes': {for (final t in prefixTypes.keys) t: prefixes[t] ?? ''},
        'defaultRoundOff': defaultRoundOff,
        'defaultCashSale': defaultCashSale,
        'blockNegativeStock': blockNegativeStock,
        'showInvoicePreview': showInvoicePreview,
        'dueDatesEnabled': dueDatesEnabled,
        'defaultCreditDays': defaultCreditDays,
        'invoiceTerms': invoiceTerms,
        'signatureLabel': signatureLabel,
        'invoiceTheme': invoiceTheme,
        'themeColor': themeColor,
        'thermalWidth': thermalWidth,
        'shippingAddressEnabled': shippingAddressEnabled,
        'partyFields': [for (final f in partyFields) f.toJson()],
        'paymentReminderDays': paymentReminderDays,
        'stockMaintenance': stockMaintenance,
        'itemWiseDiscount': itemWiseDiscount,
        'quantityDecimals': quantityDecimals,
        'defaultUnit': defaultUnit,
        'wholesalePriceEnabled': wholesalePriceEnabled,
        'accountingEnabled': accountingEnabled,
        'serviceRemindersEnabled': serviceRemindersEnabled,
        'salesmanOwnDataOnly': salesmanOwnDataOnly,
        'locationTrackingEnabled': locationTrackingEnabled,
        'godownsEnabled': godownsEnabled,
        'batchTrackingEnabled': batchTrackingEnabled,
        'serialTrackingEnabled': serialTrackingEnabled,
        'mrpEnabled': mrpEnabled,
        'cessEnabled': cessEnabled,
        'billDiscountEnabled': billDiscountEnabled,
        'additionalChargesEnabled': additionalChargesEnabled,
        'tcsEnabled': tcsEnabled,
        'tdsEnabled': tdsEnabled,
        'loyaltyEnabled': loyaltyEnabled,
        'partyGroupsEnabled': partyGroupsEnabled,
        'chargeNames': [for (final c in chargeNames) if (c.trim().isNotEmpty) c.trim()],
        'loyaltyEarnPer': loyaltyEarnPer,
        'loyaltyPointValue': loyaltyPointValue,
        'autoBackup': autoBackup,
        'autoBackupKeep': autoBackupKeep,
        'autoSendInvoices': autoSendInvoices,
        'autoSendPayments': autoSendPayments,
        'invoiceMessage': invoiceMessage,
        'paymentMessage': paymentMessage,
        'reminderMessage': reminderMessage,
        'einvoiceEnabled': einvoiceEnabled,
        'ewayEnabled': ewayEnabled,
        'upiId': upiId,
        'upiQrOnInvoice': upiQrOnInvoice,
        'creditLimitMode': creditLimitMode,
        'itemImagesOnInvoice': itemImagesOnInvoice,
      };

  FirmSettings copyWith({
    bool? gstEnabled,
    String? invoicePrefix,
    Map<String, String>? prefixes,
    bool? defaultRoundOff,
    bool? defaultCashSale,
    bool? blockNegativeStock,
    bool? showInvoicePreview,
    bool? dueDatesEnabled,
    int? defaultCreditDays,
    String? invoiceTerms,
    String? signatureLabel,
    String? invoiceTheme,
    String? themeColor,
    int? thermalWidth,
    bool? shippingAddressEnabled,
    List<PartyFieldDef>? partyFields,
    int? Function()? paymentReminderDays,
    bool? stockMaintenance,
    bool? itemWiseDiscount,
    int? quantityDecimals,
    String? defaultUnit,
    bool? wholesalePriceEnabled,
    bool? accountingEnabled,
    bool? serviceRemindersEnabled,
    bool? salesmanOwnDataOnly,
    bool? locationTrackingEnabled,
    bool? godownsEnabled,
    bool? batchTrackingEnabled,
    bool? serialTrackingEnabled,
    bool? mrpEnabled,
    bool? cessEnabled,
    bool? billDiscountEnabled,
    bool? additionalChargesEnabled,
    bool? tcsEnabled,
    bool? tdsEnabled,
    bool? loyaltyEnabled,
    bool? partyGroupsEnabled,
    List<String>? chargeNames,
    num? loyaltyEarnPer,
    num? loyaltyPointValue,
    String? autoBackup,
    int? autoBackupKeep,
    String? autoSendInvoices,
    String? autoSendPayments,
    String? invoiceMessage,
    String? paymentMessage,
    String? reminderMessage,
    bool? einvoiceEnabled,
    bool? ewayEnabled,
    String? upiId,
    bool? upiQrOnInvoice,
    String? creditLimitMode,
    bool? itemImagesOnInvoice,
  }) =>
      FirmSettings(
        gstEnabled: gstEnabled ?? this.gstEnabled,
        invoicePrefix: invoicePrefix ?? this.invoicePrefix,
        prefixes: prefixes ?? this.prefixes,
        defaultRoundOff: defaultRoundOff ?? this.defaultRoundOff,
        defaultCashSale: defaultCashSale ?? this.defaultCashSale,
        blockNegativeStock: blockNegativeStock ?? this.blockNegativeStock,
        showInvoicePreview: showInvoicePreview ?? this.showInvoicePreview,
        dueDatesEnabled: dueDatesEnabled ?? this.dueDatesEnabled,
        defaultCreditDays: defaultCreditDays ?? this.defaultCreditDays,
        invoiceTerms: invoiceTerms ?? this.invoiceTerms,
        signatureLabel: signatureLabel ?? this.signatureLabel,
        invoiceTheme: invoiceTheme ?? this.invoiceTheme,
        themeColor: themeColor ?? this.themeColor,
        thermalWidth: thermalWidth ?? this.thermalWidth,
        shippingAddressEnabled: shippingAddressEnabled ?? this.shippingAddressEnabled,
        partyFields: partyFields ?? this.partyFields,
        paymentReminderDays: paymentReminderDays != null ? paymentReminderDays() : this.paymentReminderDays,
        stockMaintenance: stockMaintenance ?? this.stockMaintenance,
        itemWiseDiscount: itemWiseDiscount ?? this.itemWiseDiscount,
        quantityDecimals: quantityDecimals ?? this.quantityDecimals,
        defaultUnit: defaultUnit ?? this.defaultUnit,
        wholesalePriceEnabled: wholesalePriceEnabled ?? this.wholesalePriceEnabled,
        accountingEnabled: accountingEnabled ?? this.accountingEnabled,
        serviceRemindersEnabled: serviceRemindersEnabled ?? this.serviceRemindersEnabled,
        salesmanOwnDataOnly: salesmanOwnDataOnly ?? this.salesmanOwnDataOnly,
        locationTrackingEnabled: locationTrackingEnabled ?? this.locationTrackingEnabled,
        godownsEnabled: godownsEnabled ?? this.godownsEnabled,
        batchTrackingEnabled: batchTrackingEnabled ?? this.batchTrackingEnabled,
        serialTrackingEnabled: serialTrackingEnabled ?? this.serialTrackingEnabled,
        mrpEnabled: mrpEnabled ?? this.mrpEnabled,
        cessEnabled: cessEnabled ?? this.cessEnabled,
        billDiscountEnabled: billDiscountEnabled ?? this.billDiscountEnabled,
        additionalChargesEnabled: additionalChargesEnabled ?? this.additionalChargesEnabled,
        tcsEnabled: tcsEnabled ?? this.tcsEnabled,
        tdsEnabled: tdsEnabled ?? this.tdsEnabled,
        loyaltyEnabled: loyaltyEnabled ?? this.loyaltyEnabled,
        partyGroupsEnabled: partyGroupsEnabled ?? this.partyGroupsEnabled,
        chargeNames: chargeNames ?? this.chargeNames,
        loyaltyEarnPer: loyaltyEarnPer ?? this.loyaltyEarnPer,
        loyaltyPointValue: loyaltyPointValue ?? this.loyaltyPointValue,
        autoBackup: autoBackup ?? this.autoBackup,
        autoBackupKeep: autoBackupKeep ?? this.autoBackupKeep,
        autoSendInvoices: autoSendInvoices ?? this.autoSendInvoices,
        autoSendPayments: autoSendPayments ?? this.autoSendPayments,
        invoiceMessage: invoiceMessage ?? this.invoiceMessage,
        paymentMessage: paymentMessage ?? this.paymentMessage,
        reminderMessage: reminderMessage ?? this.reminderMessage,
        einvoiceEnabled: einvoiceEnabled ?? this.einvoiceEnabled,
        ewayEnabled: ewayEnabled ?? this.ewayEnabled,
        upiId: upiId ?? this.upiId,
        upiQrOnInvoice: upiQrOnInvoice ?? this.upiQrOnInvoice,
        creditLimitMode: creditLimitMode ?? this.creditLimitMode,
        itemImagesOnInvoice: itemImagesOnInvoice ?? this.itemImagesOnInvoice,
      );

  @override
  List<Object?> get props => [
        gstEnabled, invoicePrefix, prefixes, defaultRoundOff, defaultCashSale, blockNegativeStock, showInvoicePreview, dueDatesEnabled,
        defaultCreditDays, invoiceTerms, signatureLabel, invoiceTheme, themeColor, thermalWidth, shippingAddressEnabled, partyFields,
        paymentReminderDays, stockMaintenance, itemWiseDiscount, quantityDecimals, defaultUnit, wholesalePriceEnabled, accountingEnabled,
        serviceRemindersEnabled, salesmanOwnDataOnly, locationTrackingEnabled, godownsEnabled, batchTrackingEnabled, serialTrackingEnabled, mrpEnabled, cessEnabled, billDiscountEnabled, additionalChargesEnabled, tcsEnabled, tdsEnabled, loyaltyEnabled, partyGroupsEnabled, chargeNames, loyaltyEarnPer, loyaltyPointValue, autoBackup, autoBackupKeep, autoSendInvoices, autoSendPayments, invoiceMessage, paymentMessage, reminderMessage, einvoiceEnabled, ewayEnabled, upiId, upiQrOnInvoice, creditLimitMode, itemImagesOnInvoice,
      ];
}

class Firm extends Equatable {
  Firm.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        phone = j['phone'] as String?,
        gstin = j['gstin'] as String?,
        email = j['email'] as String?,
        booksStartDate = j['booksStartDate'] as String,
        businessType = j['businessType'] as String?,
        businessCategory = j['businessCategory'] as String?,
        stateCode = j['stateCode'] as String?,
        pincode = j['pincode'] as String?,
        address = j['address'] as String?,
        city = j['city'] as String?,
        tan = j['tan'] as String?,
        pan = j['pan'] as String?,
        logoFileId = j['logoFileId'] as String?,
        signatureFileId = j['signatureFileId'] as String?,
        booksLockDate = j['booksLockDate'] as String?,
        settings = j['settings'] is Map<String, dynamic> ? FirmSettings.fromJson(j['settings'] as Map<String, dynamic>) : const FirmSettings();

  final String id;
  final String name;
  final String? phone;
  final String? gstin;
  final String? email;
  final String booksStartDate;
  final String? businessType;
  final String? businessCategory;
  final String? stateCode;
  final String? pincode;
  final String? address;
  final String? city;

  /// Tax deduction account number and the company's PAN, for TDS / TCS statements.
  final String? tan;
  final String? pan;

  /// Uploaded images printed on documents.
  final String? logoFileId;
  final String? signatureFileId;

  /// Nothing dated on or before this day can be added or changed ("books closed").
  final String? booksLockDate;
  final FirmSettings settings;

  @override
  List<Object?> get props => [
        id, name, phone, gstin, email, booksStartDate, businessType, businessCategory, stateCode, pincode, address, city, tan, pan, logoFileId, signatureFileId,
        booksLockDate, settings,
      ];
}

const businessTypes = ['Retail', 'Wholesale', 'Distributor', 'Service', 'Manufacturing', 'Others'];

const businessCategories = [
  'Accounting & CA', 'Agriculture', 'Automobile', 'Electronics', 'Fashion & Apparel', 'FMCG', 'Furniture',
  'Grocery', 'Hardware', 'Healthcare & Pharmacy', 'Jewellery', 'Restaurant & Food', 'Stationery', 'Others',
];
