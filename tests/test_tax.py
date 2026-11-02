import unittest
from planning.tax import estimate, state_of, taxable


def line(category, amount, address='', aisles=()):
    return {'category': category, 'current_amount': amount, 'store': {'address': address},
            'quote': {'categories': list(aisles)}}


class TaxTests(unittest.TestCase):
    def test_state_from_geocoder_and_retailer_addresses(self):
        self.assertEqual(state_of('Ann Arbor, MI 48105, United States of America'), 'MI')
        self.assertEqual(state_of('3235 Washtenaw Ave, Ann Arbor, MI, 48104'), 'MI')
        self.assertEqual(state_of('Toledo, OH 43604-1234'), 'OH')
        self.assertEqual(state_of('Somewhere without a zip'), '')

    def test_food_words_that_look_like_household_goods_stay_food(self):
        for food in ['tortilla wraps', 'yogurt cups', 'tea bags', 'hot dog buns', 'chips', 'milk']:
            self.assertFalse(taxable(food), food)
        for goods in ['laundry detergent', 'shampoo', 'paper towels', 'cat litter']:
            self.assertTrue(taxable(goods), goods)
        self.assertTrue(taxable('wipes'))
        self.assertTrue(taxable('soap'))
        self.assertTrue(taxable('Fresh Scent 64oz', ['Cleaning Products']))

    def test_michigan_rules_tax_only_non_food_and_set_item_amounts(self):
        items = [line('milk', 2.39, 'Ann Arbor, MI 48104'), line('laundry detergent', 10.0, 'Ann Arbor, MI 48104')]
        result = estimate(items, [], -1)
        self.assertEqual((result['tax'], result['basis']), (0.6, 'STATE_RULES'))
        self.assertEqual([i['tax_amount'] for i in items], [0.0, 0.6])
        self.assertIn('Michigan', result['note'])

    def test_other_states_use_the_shoppers_rate_or_stay_unknown(self):
        self.assertEqual(estimate([line('milk', 10.0, 'Toledo, OH 43604')], [], 0.07)['tax'], 0.7)
        self.assertEqual(estimate([line('milk', 10.0, 'Toledo, OH 43604')], [], 0.07)['basis'], 'YOUR_RATE')
        unknown = estimate([line('milk', 10.0, 'Toledo, OH 43604')], [], -1)
        self.assertIsNone(unknown['tax'])
        self.assertIn('OH', unknown['note'])

    def test_store_address_wins_and_home_address_is_the_fallback(self):
        self.assertEqual(estimate([line('soap', 10.0)], ['', 'Ann Arbor, MI 48105'], -1)['tax'], 0.6)
        self.assertEqual(estimate([line('soap', 10.0, 'Toledo, OH 43604')], ['Ann Arbor, MI 48105'], 0.07)['tax'], 0.7)

    def test_unpriced_and_delivery_items_are_skipped(self):
        items = [line('soap', None, 'Ann Arbor, MI 48104'), dict(line('soap', 5.0), fulfillment='DELIVERY')]
        result = estimate(items, ['Toledo, OH 43604'], -1)
        self.assertEqual((result['tax'], result['basis']), (0.0, 'NONE'))


if __name__ == '__main__':
    unittest.main()
