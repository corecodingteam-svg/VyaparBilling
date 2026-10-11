const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen',
  'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _below100(int n) => n < 20 ? _ones[n] : [_tens[n ~/ 10], _ones[n % 10]].where((s) => s.isNotEmpty).join(' ');

String _below1000(int n) =>
    [if (n >= 100) '${_ones[n ~/ 100]} Hundred', if (n % 100 > 0) _below100(n % 100)].join(' ');

/// Whole number in the Indian system (thousand, lakh, crore), e.g. 125000 → "One Lakh Twenty Five Thousand".
String _integerWords(int n) {
  if (n == 0) return 'Zero';
  final parts = <String>[];
  final crore = n ~/ 10000000;
  if (crore > 0) parts.add('${_integerWords(crore)} Crore');
  final lakh = (n ~/ 100000) % 100;
  if (lakh > 0) parts.add('${_below100(lakh)} Lakh');
  final thousand = (n ~/ 1000) % 100;
  if (thousand > 0) parts.add('${_below100(thousand)} Thousand');
  if (n % 1000 > 0) parts.add(_below1000(n % 1000));
  return parts.join(' ');
}

/// "Three Hundred Seventy Four Rupees and Fifty Paise only".
String amountInWords(num amount) {
  final paiseTotal = (amount.abs() * 100).round();
  final rupees = paiseTotal ~/ 100;
  final paise = paiseTotal % 100;
  final words = StringBuffer('${_integerWords(rupees)} Rupees');
  if (paise > 0) words.write(' and ${_below100(paise)} Paise');
  return '$words only';
}
