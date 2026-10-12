"""Checks for the item thumbnail maker. No database, share or network is used."""
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from io import BytesIO
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PIL import Image

from shinerutils.updates.item_images import ItemMatcher
from shinerutils.updates.item_thumbnails import (
    CANDIDATE_SQL,
    ThumbnailSettings,
    _Photo,
    _File,
    copy_new_nas_thumbnails,
    scan_pictures,
    make_thumbnail,
    plan_thumbnails,
    thumbnail_file_name,
)


def picture(size, colour="red", mode="RGB", image_format="JPEG", **save):
    output = BytesIO()
    Image.new(mode, size, colour).save(output, image_format, **save)
    return output.getvalue()


class ThumbnailPictureTests(unittest.TestCase):
    def test_a_wide_photo_is_centred_on_a_white_square(self):
        with Image.open(BytesIO(make_thumbnail(picture((3000, 1500))))) as image:
            self.assertEqual((image.format, image.size, image.mode), ("JPEG", (450, 450), "RGB"))
            top, middle = image.getpixel((225, 20)), image.getpixel((225, 225))
        self.assertTrue(all(value > 240 for value in top))               # white above the picture
        self.assertTrue(middle[0] > 200 and middle[1] < 60)              # the picture itself

    def test_a_small_picture_is_not_enlarged(self):
        with Image.open(BytesIO(make_thumbnail(picture((100, 100), "blue")))) as image:
            self.assertEqual(image.size, (450, 450))
            self.assertTrue(all(value > 240 for value in image.getpixel((100, 100))))
            self.assertTrue(image.getpixel((225, 225))[2] > 200)

    def test_transparent_areas_become_white(self):
        content = picture((800, 800), (0, 0, 0, 0), mode="RGBA", image_format="PNG")
        with Image.open(BytesIO(make_thumbnail(content))) as image:
            self.assertTrue(all(value > 240 for value in image.getpixel((225, 225))))

    def test_a_photo_stored_on_its_side_is_turned_upright(self):
        exif = Image.Exif()
        exif[0x0112] = 6                                                 # rotate 90 degrees to view
        content = picture((1200, 600), exif=exif.tobytes())
        with Image.open(BytesIO(make_thumbnail(content))) as image:
            # Upright it is tall: red runs top to bottom in the middle, white at the sides.
            self.assertTrue(image.getpixel((225, 20))[1] < 60)
            self.assertTrue(all(value > 240 for value in image.getpixel((20, 225))))

    def test_something_that_is_not_a_picture_gives_nothing(self):
        self.assertIsNone(make_thumbnail(b"not a picture"))
        self.assertIsNone(make_thumbnail(b""))


class ThumbnailNameTests(unittest.TestCase):
    def test_names_follow_marketings_pattern(self):
        self.assertEqual(thumbnail_file_name("SCA-TEE-10860"), "SCA-TEE-10860_THUMB.jpg")
        # The morning refresh must match the file back to the same item.
        self.assertEqual(ItemMatcher({"SCA-TEE-10860", "SCA-TEE-1086"}).from_file_name("SCA-TEE-10860_THUMB.jpg"), "SCA-TEE-10860")

    def test_an_item_number_that_cannot_be_a_file_name_is_skipped(self):
        for item_id in ["", "A/B", "A\\B", "A:B", "A*", " A", "A.", "A\tB"]:
            self.assertIsNone(thumbnail_file_name(item_id), item_id)


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path("thumbnails")
        self.matcher = ItemMatcher({"AAA-1", "BBB-2", "CCC-3", "DDD-4", "EEE-5"})

    def file(self, name, modified):
        return _File(self.folder / name, 1, modified.timestamp())

    def test_only_items_without_a_thumbnail_get_one(self):
        old, new = datetime(2026, 1, 1), datetime(2026, 6, 1)
        files = {
            "aaa-1_thumb.jpg": self.file("AAA-1_THUMB.jpg", new),          # marketing's
            "bbb-2-front.jpg": self.file("BBB-2-front.jpg", new),          # marketing's, under another name
            "ccc-3_thumb.jpg": self.file("CCC-3_THUMB.jpg", new),          # generated, newer than its photo
            "ddd-4_thumb.jpg": self.file("DDD-4_THUMB.jpg", new),          # generated, older than its photo
        }
        nas = {"aaa-1_thumb.jpg", "bbb-2-front.jpg"}
        # File times are UTC in the catalogue.
        utc = lambda value: datetime.utcfromtimestamp(value.timestamp())
        photos = [
            _Photo("AAA-1", Path("a.jpg"), utc(new) + timedelta(days=30)),  # newer photo, but the thumbnail is marketing's
            _Photo("BBB-2", Path("b.jpg"), utc(old)),
            _Photo("CCC-3", Path("c.jpg"), utc(old)),
            _Photo("DDD-4", Path("d.jpg"), utc(new) + timedelta(days=1)),
            _Photo("EEE-5", Path("e.jpg"), None),
            _Photo("BAD/1", Path("f.jpg"), None),
        ]
        create, refresh = plan_thumbnails(photos, files, nas, self.matcher)
        self.assertEqual([(photo.item_id, name) for photo, name in create], [("EEE-5", "EEE-5_THUMB.jpg")])
        self.assertEqual([(photo.item_id, name) for photo, name in refresh], [("DDD-4", "DDD-4_THUMB.jpg")])


class CopyTests(unittest.TestCase):
    def test_new_and_changed_files_are_copied_and_the_nas_is_left_alone(self):
        with tempfile.TemporaryDirectory() as root:
            nas, sql18 = Path(root, "nas"), Path(root, "sql18")
            nas.mkdir(); sql18.mkdir()
            (nas / "A_THUMB.jpg").write_bytes(b"same")
            (nas / "B_THUMB.jpg").write_bytes(b"marketing made this")
            (nas / "C_THUMB.jpg").write_bytes(b"new")
            (nas / "notes.txt").write_bytes(b"not a picture")
            import shutil
            shutil.copy2(nas / "A_THUMB.jpg", sql18 / "A_THUMB.jpg")
            (sql18 / "B_THUMB.jpg").write_bytes(b"generated")
            (sql18 / "D_THUMB.jpg").write_bytes(b"generated, no NAS file")
            settings = ThumbnailSettings(nas, sql18)
            before = {path.name: path.read_bytes() for path in nas.iterdir()}

            copy = lambda **options: copy_new_nas_thumbnails(settings, scan_pictures(nas), scan_pictures(sql18), **options)
            self.assertEqual(sorted(scan_pictures(nas)), ["a_thumb.jpg", "b_thumb.jpg", "c_thumb.jpg"])   # pictures only
            planned = copy(dry_run=True)
            self.assertEqual(sorted(path.name for path in planned), ["B_THUMB.jpg", "C_THUMB.jpg"])
            self.assertEqual((sql18 / "B_THUMB.jpg").read_bytes(), b"generated")      # a dry run writes nothing

            copied = copy()
            self.assertEqual(sorted(path.name for path in copied), ["B_THUMB.jpg", "C_THUMB.jpg"])
            self.assertEqual((sql18 / "B_THUMB.jpg").read_bytes(), b"marketing made this")
            self.assertEqual((sql18 / "D_THUMB.jpg").read_bytes(), b"generated, no NAS file")
            self.assertEqual(sorted(path.name for path in sql18.iterdir()), ["A_THUMB.jpg", "B_THUMB.jpg", "C_THUMB.jpg", "D_THUMB.jpg"])
            self.assertEqual({path.name: path.read_bytes() for path in nas.iterdir()}, before)
            self.assertEqual(copy(), [])                   # a second run has nothing to do


class EligibilityTests(unittest.TestCase):
    def test_the_rules_the_user_chose_are_in_the_query(self):
        sql = " ".join(CANDIDATE_SQL.split())
        self.assertIn("i.[ltd_blocked] = 0 OR i.[bv_blocked] = 0 OR EXISTS (SELECT 1 FROM sold", sql)
        self.assertNotIn("llc_blocked", sql)                              # unblocked for nearly every item
        self.assertIn("DATEADD(MONTH, -1, CAST(SYSDATETIME() AS DATE))", sql)
        self.assertIn("il.[source_code] = N'NAS_ITEM_DOCS'", sql)         # network photos only, not SharePoint
        self.assertIn("i.[is_placeholder] = 0", sql)
        self.assertNotRegex(sql.upper(), r"\b(INSERT|UPDATE|DELETE|MERGE|DROP|TRUNCATE|EXEC)\b")


if __name__ == "__main__":
    unittest.main()
