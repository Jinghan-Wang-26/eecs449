import jaclang  # Enable direct imports of the migrated .jac modules.
import unittest
from pricing import price_details


class UnitPriceTests(unittest.TestCase):
    def test_equal_mass_in_different_units(self):
        self.assertAlmostEqual(price_details(10, 1, "kg")["unit_price"], price_details(10, 1000, "g")["unit_price"])
        self.assertAlmostEqual(price_details(5, 1, "lb")["unit_price"], 11.0231, places=4)
        self.assertEqual(price_details(5, 16, "oz")["unit_price"], price_details(5, 1, "lb")["unit_price"])

    def test_volume_count_and_dimension_separation(self):
        self.assertEqual(price_details(3.785411784, 1, "gal")["unit_price"], 1)
        self.assertEqual(price_details(3, 12, "ct")["unit_price"], .25)
        self.assertEqual(price_details(10, 16, "fl oz")["unit"], "L")
        self.assertEqual(price_details(10, 16, "oz")["unit"], "kg")

    def test_missing_invalid_and_multipack_are_not_guessed(self):
        for price in (None, True, -1, float("nan"), float("inf"), "5"):
            self.assertIsNone(price_details(price, 1, "kg")["unit_price"])
        for size in (0, -1, True, float("nan")):
            self.assertIsNone(price_details(5, size, "kg")["unit_price"])
        self.assertIsNone(price_details(5, label="2 x 500 g")["unit_price"])
        self.assertIsNone(price_details(5, 1, "box")["unit_price"])
        self.assertEqual(price_details(0, 1, "kg")["unit_price"], 0)

    def test_simple_provider_labels_and_package_price(self):
        self.assertEqual(price_details(3, label="500 g")["unit_price"], 6)
        self.assertEqual(price_details(3, label="500 ML")["unit_price"], 6)
        details = price_details(3.49, 12, "ct")
        self.assertEqual(details["package_price"], 3.49)
        self.assertEqual(details["price_label"], "$3.49 / package")
        self.assertEqual(details["unit_price_label"], "$0.29 / piece")
