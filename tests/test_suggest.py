import unittest
from interests.suggest import purchase_days, usual_due, sale_categories, best_sale, search_term


def row(promo, regular=5.49, **extra):
    return {'reported_price': regular, 'promotion': promo, 'sold_by': 'unit', 'availability': 'IN_STOCK', **extra}


class SuggestTests(unittest.TestCase):
    def test_purchase_days_merge_ledger_and_recorded_visits(self):
        entries = [{'category': 'Milk', 'spent_at': '2026-10-01T10:00:00-04:00', 'voided': False},
                   {'category': 'milk', 'spent_at': '2026-10-01T18:00:00-04:00', 'voided': False},
                   {'category': 'eggs', 'spent_at': '2026-10-02T10:00:00-04:00', 'voided': True}]
        visits = [{'items': [{'category': 'milk', 'bought_qty': 1, 'recorded_at': '2026-10-08T12:00:00-04:00'},
                             {'category': 'rice', 'bought_qty': 0, 'recorded_at': '2026-10-08T12:00:00-04:00'}]}]
        self.assertEqual(purchase_days(entries, visits), {'milk': ['2026-10-01', '2026-10-08']})

    def test_usual_gap_needs_two_trips_and_skips_listed_items(self):
        days = {'milk': ['2026-10-01', '2026-10-08'], 'rice': ['2026-10-01'], 'eggs': ['2026-10-20', '2026-10-21']}
        due = usual_due(days, '2026-10-16T09:00', [])
        self.assertEqual([(r['category'], r['every'], r['since']) for r in due], [('milk', 7, 8)])
        self.assertEqual(usual_due(days, '2026-10-12T09:00', []), [])
        self.assertEqual(usual_due(days, '2026-10-16T09:00', ['milk']), [])

    def test_sale_categories_prefer_recent_purchases_and_skip_the_list(self):
        days = {'milk': ['2026-10-01'], 'chips': ['2026-10-09']}
        self.assertEqual(sale_categories(days, ['yogurt', 'milk'], ['yogurt']), ['chips', 'milk'])

    def test_best_sale_requires_a_real_available_unit_discount(self):
        rows = [row(0), row(5.49), row(3.99, sold_by='weight'), row(2.99, availability='OUT'),
                row(4.49, name='a'), row(3.49, name='b')]
        self.assertEqual(best_sale(rows)['row']['name'], 'b')
        self.assertIsNone(best_sale(rows, lambda r: r.get('name') == 'missing'))
        self.assertIsNone(best_sale([row(None)]))

    def test_search_term_uses_the_saved_preferences(self):
        self.assertEqual(search_term({'type': 'chips', 'brand': "Lay's", 'variant': 'classic'}), "Lay's classic chips")


if __name__ == '__main__':
    unittest.main()
