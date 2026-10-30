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
