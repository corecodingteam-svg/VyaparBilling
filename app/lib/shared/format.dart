import 'package:intl/intl.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 2);
final _qty = NumberFormat('#,##,##0.###', 'en_IN');
final _date = DateFormat('dd/MM/yyyy');

String money(num? v) => v == null ? '-' : _money.format(v);
String qty(num? v) => v == null ? '-' : _qty.format(v);

/// API dates are 'YYYY-MM-DD'.
String displayDate(String? iso) => iso == null ? '-' : _date.format(DateTime.parse(iso));
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Parses user-typed numbers; blank → null.
num? parseNum(String text) {
  final t = text.trim().replaceAll(',', '');
  return t.isEmpty ? null : num.tryParse(t);
}

/// Shows a number in an input without a pointless ".0".
String numText(num? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// An amount in a foreign currency, e.g. "$ 1,250.00"; rupees (null or ₹) use [money].
String moneyIn(String? symbol, num? v) => symbol == null || symbol == '₹' ? money(v) : (v == null ? '-' : '$symbol ${NumberFormat('#,##0.00').format(v)}');
