import unittest

from audit_thumbnail_integrity import paeth_predictor, unfilter_scanlines


def encode_row(decoded: bytes, previous: bytes, bytes_per_pixel: int, filter_type: int) -> bytes:
    encoded = bytearray()
    for column, value in enumerate(decoded):
        left = decoded[column - bytes_per_pixel] if column >= bytes_per_pixel else 0
        above = previous[column]
        upper_left = previous[column - bytes_per_pixel] if column >= bytes_per_pixel else 0
        if filter_type == 0:
            predictor = 0
        elif filter_type == 1:
            predictor = left
        elif filter_type == 2:
            predictor = above
        elif filter_type == 3:
            predictor = (left + above) // 2
        elif filter_type == 4:
            predictor = paeth_predictor(left, above, upper_left)
        else:
            raise AssertionError(f"unexpected test filter {filter_type}")
        encoded.append((value - predictor) & 0xFF)
    return bytes([filter_type]) + bytes(encoded)


class PngUnfilterTests(unittest.TestCase):
    def test_reconstructs_all_standard_png_filter_types(self) -> None:
        rows = [
            bytes([10, 20, 30, 255, 40, 50, 60, 255]),
            bytes([15, 25, 35, 255, 45, 55, 65, 255]),
            bytes([100, 80, 60, 255, 20, 40, 90, 255]),
            bytes([4, 8, 12, 255, 16, 32, 64, 255]),
            bytes([200, 100, 50, 255, 25, 75, 125, 255]),
        ]
        previous = bytes(len(rows[0]))
        encoded = bytearray()
        for filter_type, row in enumerate(rows):
            encoded.extend(encode_row(row, previous, 4, filter_type))
            previous = row

        self.assertEqual(
            unfilter_scanlines(bytes(encoded), width=2, height=5, bytes_per_pixel=4),
            b"".join(rows),
        )

    def test_rejects_unknown_filter_type(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported PNG filter type 5"):
            unfilter_scanlines(bytes([5, 0, 0, 0, 0]), width=1, height=1, bytes_per_pixel=4)


if __name__ == "__main__":
    unittest.main()
