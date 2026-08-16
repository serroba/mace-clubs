import shutil
import tempfile
import unittest
from pathlib import Path

from tools.validate_fit_schema import validate


ROOT = Path(__file__).resolve().parents[1]


class FitSchemaValidationTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        (self.root / "source").mkdir()
        (self.root / "resources" / "strings").mkdir(parents=True)
        shutil.copy(ROOT / "source" / "WorkoutSession.mc", self.root / "source")
        shutil.copy(ROOT / "resources" / "fitfields.xml", self.root / "resources")
        shutil.copy(ROOT / "resources" / "strings" / "strings.xml", self.root / "resources" / "strings")

    def tearDown(self):
        self.tempdir.cleanup()

    def test_repository_contract_is_valid(self):
        self.assertEqual([], validate(self.root))

    def test_chart_must_be_a_record_field(self):
        source_path = self.root / "source" / "WorkoutSession.mc"
        source = source_path.read_text()
        source_path.write_text(
            source.replace(
                '"accel_rms",\n                FIELD_ID_ACCEL_RMS,\n                FitContributor.DATA_TYPE_UINT16,\n                {:mesgType => FitContributor.MESG_TYPE_RECORD',
                '"accel_rms",\n                FIELD_ID_ACCEL_RMS,\n                FitContributor.DATA_TYPE_UINT16,\n                {:mesgType => FitContributor.MESG_TYPE_LAP',
            )
        )
        self.assertIn("chart field id 2 must use MESG_TYPE_RECORD", validate(self.root))

    def test_missing_string_reference_is_rejected(self):
        path = self.root / "resources" / "fitfields.xml"
        path.write_text(path.read_text().replace("@Strings.FitMotionPeakChart", "@Strings.DoesNotExist"))
        self.assertIn(
            "FIT field id 3 references missing string @Strings.DoesNotExist",
            validate(self.root),
        )

    def test_duplicate_chart_order_is_rejected(self):
        path = self.root / "resources" / "fitfields.xml"
        path.write_text(path.read_text().replace('id="3" displayInChart="true" sortOrder="31"', 'id="3" displayInChart="true" sortOrder="30"'))
        self.assertIn("duplicate displayInChart sortOrder 30", validate(self.root))


if __name__ == "__main__":
    unittest.main()
