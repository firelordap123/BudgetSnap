export const allowedCategoryIDs = [
  'cat_housing',
  'cat_groceries',
  'cat_dining',
  'cat_coffee',
  'cat_transit',
  'cat_utilities',
  'cat_shopping',
  'cat_subscriptions',
  'cat_entertainment',
  'cat_health',
  'cat_travel',
  'cat_misc',
];

// Plaid personal_finance_category.primary -> BudgetSnap category ID.
// null means skip this transaction because it is not spending.
export const PLAID_STATIC_MAP = {
  FOOD_AND_DRINK:             'cat_dining',
  GROCERY:                    'cat_groceries',
  RENT_AND_UTILITIES:         'cat_utilities',
  HOME_IMPROVEMENT:           'cat_housing',
  LOAN_PAYMENTS:              'cat_housing',
  ENTERTAINMENT:              'cat_entertainment',
  RECREATION:                 'cat_entertainment',
  PERSONAL_CARE:              'cat_health',
  MEDICAL:                    'cat_health',
  TRANSPORTATION:             'cat_transit',
  TRAVEL:                     'cat_travel',
  GOVERNMENT_AND_NON_PROFIT:  'cat_misc',
  BANK_FEES:                  'cat_misc',
  OTHER:                      'cat_misc',
  INCOME:                     null,
  TRANSFER_IN:                null,
  TRANSFER_OUT:               null,
};

export const NEEDS_AI = new Set(['GENERAL_MERCHANDISE', 'GENERAL_SERVICES', 'SUBSCRIPTION']);
