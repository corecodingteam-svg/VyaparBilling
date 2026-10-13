import 'package:equatable/equatable.dart';

/// A tax payment made at the bank with challan ITNS 281, which a TDS or TCS statement must quote.
class TaxChallan extends Equatable {
  TaxChallan.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      taxYear = j['taxYear'] as String,
      quarter = j['quarter'] as String,
      bsrCode = j['bsrCode'] as String,
      challanNo = j['challanNo'] as String,
      depositDate = j['depositDate'] as String,
      tax = j['tax'] as num,
      interest = j['interest'] as num,
      fee = j['fee'] as num,
      other = j['other'] as num;

  final String id;
  final String kind;
  final String taxYear;
  final String quarter;
  final String bsrCode;
  final String challanNo;
  final String depositDate;
  final num tax;
  final num interest;
  final num fee;
  final num other;

  @override
  List<Object?> get props => [id, kind, taxYear, quarter, bsrCode, challanNo, depositDate, tax, interest, fee, other];
}

/// One quarter's statement: what it covers, what stops it, and the file once nothing does.
class TaxStatement extends Equatable {
  TaxStatement.fromJson(Map<String, dynamic> j)
    : form = j['form'] as String,
      deductees = (j['deductees'] as num).toInt(),
      tax = j['tax'] as num,
      deposited = j['deposited'] as num,
      problems = (j['problems'] as List).cast<String>(),
      warnings = (j['warnings'] as List).cast<String>(),
      fileName = j['fileName'] as String,
      file = j['file'] as String?;

  final String form;
  final int deductees;
  final num tax;
  final num deposited;
  final List<String> problems;
  final List<String> warnings;
  final String fileName;
  final String? file;

  @override
  List<Object?> get props => [form, deductees, tax, deposited, problems, warnings, fileName, file];
}

/// Who answers for the deductions, as the statements print it; kept in the company's settings.
class Deductor extends Equatable {
  const Deductor({
    this.type = 'K',
    this.name = '',
    this.designation = '',
    this.pan = '',
    this.mobile = '',
    this.email = '',
    this.tdsSection = '1031',
    this.tcsCode = '',
    this.tdsPreviousToken = '',
    this.tcsPreviousToken = '',
  });

  factory Deductor.fromSettings(Map<String, dynamic> s) => Deductor(
    type: (s['deductorType'] as String?) ?? 'K',
    name: (s['responsibleName'] as String?) ?? '',
    designation: (s['responsibleDesignation'] as String?) ?? '',
    pan: (s['responsiblePan'] as String?) ?? '',
    mobile: (s['responsibleMobile'] as String?) ?? '',
    email: (s['responsibleEmail'] as String?) ?? '',
    tdsSection: (s['tdsDefaultSection'] as String?) ?? '1031',
    tcsCode: (s['tcsDefaultCode'] as String?) ?? '',
    tdsPreviousToken: (s['tdsPreviousToken'] as String?) ?? '',
    tcsPreviousToken: (s['tcsPreviousToken'] as String?) ?? '',
  );

  final String type;
  final String name;
  final String designation;
  final String pan;
  final String mobile;
  final String email;
  final String tdsSection;
  final String tcsCode;
  final String tdsPreviousToken;
  final String tcsPreviousToken;

  Map<String, dynamic> toSettings() => {
    'deductorType': type,
    'responsibleName': name,
    'responsibleDesignation': designation,
    'responsiblePan': pan.toUpperCase(),
    'responsibleMobile': mobile,
    'responsibleEmail': email,
    'tdsDefaultSection': tdsSection,
    'tcsDefaultCode': tcsCode,
    'tdsPreviousToken': tdsPreviousToken,
    'tcsPreviousToken': tcsPreviousToken,
  };

  @override
  List<Object?> get props => [type, name, designation, pan, mobile, email, tdsSection, tcsCode, tdsPreviousToken, tcsPreviousToken];
}

/// Deductor categories of the statements (Annexure 4), the ones a business is likely to be first.
const deductorTypes = {
  'K': 'Company',
  'M': 'Branch / division of a company',
  'F': 'Firm',
  'Q': 'Individual / HUF',
  'P': 'Association of persons',
  'T': 'Trust',
  'B': 'Body of individuals',
  'J': 'Artificial juridical person',
};

/// Form 143 collectee types (Annexure 8).
const collecteeTypes = {
  1: 'Company',
  2: 'Individual',
  3: 'Hindu undivided family',
  4: 'Association of persons',
  5: 'AOP of companies only',
  6: 'Co-operative society',
  7: 'Firm',
  8: 'Body of individuals',
  9: 'Artificial juridical person',
  10: 'Others',
};

/// The tax year a date is in, as the statements write it: 2026-08-14 → '202627'.
String taxYearOf(DateTime d) {
  final start = d.month >= 4 ? d.year : d.year - 1;
  return '$start${(start + 1).toString().substring(2)}';
}

/// The quarter of the tax year a date is in.
String quarterOfDate(DateTime d) => d.month >= 4 && d.month <= 6
    ? 'Q1'
    : d.month >= 7 && d.month <= 9
    ? 'Q2'
    : d.month >= 10
    ? 'Q3'
    : 'Q4';

/// '202627' → '2026-27'.
String taxYearLabel(String taxYear) => '${taxYear.substring(0, 4)}-${taxYear.substring(4)}';
