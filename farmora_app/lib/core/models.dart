enum AccountRole {
  buyer('Buyer', 'Purchase agricultural products in bulk'),
  supplier('Supplier', 'Sell produce and find reliable buyers'),
  logistics('Logistics Provider', 'Move agricultural goods');

  const AccountRole(this.label, this.description);
  final String label, description;
  static AccountRole parse(String value) =>
      values.firstWhere((r) => r.name == value);
}

const categories = [
  'Maize and grains',
  'Vegetables',
  'Fruits',
  'Livestock',
  'Poultry',
  'Dairy',
  'Legumes',
  'Oilseeds',
  'Other',
];
const units = ['kg', 'tonne', 'litre', 'crate', 'head'];
const provinces = [
  'Harare',
  'Bulawayo',
  'Manicaland',
  'Mashonaland Central',
  'Mashonaland East',
  'Mashonaland West',
  'Masvingo',
  'Matabeleland North',
  'Matabeleland South',
  'Midlands',
];

/// International digits for a phone number, defaulting to Zimbabwe (+263), so
/// 0771 234 567 and +263 77 123 4567 are one account. Null if not plausible.
String? normalizePhone(String input) {
  final raw = input.replaceAll(RegExp(r'[\s().-]'), '');
  if (!RegExp(r'^\+?\d+$').hasMatch(raw)) return null;
  var digits = raw.replaceFirst('+', '');
  if (raw.startsWith('+')) {
    // Already international.
  } else if (digits.startsWith('00')) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0')) {
    digits = '263${digits.substring(1)}';
  } else if (digits.length == 9) {
    digits = '263$digits';
  }
  if (digits.startsWith('2630')) digits = '263${digits.substring(4)}';
  return digits.length >= 10 && digits.length <= 15 ? digits : null;
}

/// Firebase password accounts need an email, so phone accounts use a reserved
/// address that can never receive mail and is never shown to the user.
String phoneLoginEmail(String normalizedPhone) =>
    '$normalizedPhone@phone.farmora.invalid';

double positiveNumber(String input) {
  final value = double.tryParse(input);
  if (value == null || !value.isFinite || value <= 0) {
    throw const FormatException('Enter a number greater than zero.');
  }
  return value;
}

String money(num amount, [String currency = 'USD']) =>
    '$currency ${amount.toStringAsFixed(2)}';
double transportEstimate({
  required double roadKm,
  required double baseFee,
  required double rate,
  double additional = 0,
}) {
  if ([roadKm, baseFee, rate, additional].any((v) => !v.isFinite || v < 0)) {
    throw ArgumentError('Invalid transport values');
  }
  return baseFee + roadKm * rate + additional;
}
