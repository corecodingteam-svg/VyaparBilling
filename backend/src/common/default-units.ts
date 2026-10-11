/** Expense categories every new firm starts with (also seeded for existing firms by the migration). */
export const DEFAULT_EXPENSE_CATEGORIES = ['Petrol', 'Rent', 'Salary', 'Tea', 'Transport'];

/** Units every new firm starts with; firms can add their own. */
export const DEFAULT_UNITS: Array<[name: string, shortName: string]> = [
  ['Bags', 'BAG'], ['Bottles', 'BTL'], ['Box', 'BOX'], ['Bundles', 'BDL'], ['Cans', 'CAN'],
  ['Cartons', 'CTN'], ['Dozens', 'DZN'], ['Grammes', 'GM'], ['Kilograms', 'KG'], ['Litre', 'LTR'],
  ['Meters', 'MTR'], ['Millilitre', 'ML'], ['Numbers', 'NOS'], ['Packs', 'PAC'], ['Pairs', 'PRS'],
  ['Pieces', 'PCS'], ['Quintal', 'QTL'], ['Rolls', 'ROL'], ['Square Feet', 'SQF'], ['Square Meters', 'SQM'],
  ['Tablets', 'TBS'],
];
