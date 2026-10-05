import unittest
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "platform-build.yml"
CMAKE = (
    ROOT
    / "integrations"
    / "jev_flutter"
    / "apps"
    / "miaotou_app"
    / "windows"
    / "CMakeLists.txt"
)


class WindowsReleaseWorkflowTest(unittest.TestCase):
    def test_release_uses_flutter_not_the_retired_pyside_port(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        flutter_job = workflow.split("  flutter-windows:", 1)[1].split(
            "\n  mac:", 1
        )[0]

        self.assertIn("flutter build windows --release", flutter_job)
        self.assertIn("build/windows/x64/runner/Release", flutter_job)
        self.assertNotIn("pyinstaller --noconfirm --clean jev.spec", flutter_job)
        self.assertNotIn(
            "Windows packages include PySide6-Fluent-Widgets", flutter_job
        )

    def test_payload_is_copied_recursively_and_asserted_at_build_time(self):
        cmake = CMAKE.read_text(encoding="utf-8")

        self.assertIn('install(DIRECTORY "${MIAOTOU_REPOSITORY_ROOT}/miaotoujunshi"', cmake)
        self.assertIn('install(DIRECTORY "${MIAOTOU_REPOSITORY_ROOT}/goutoujunshi"', cmake)
        self.assertIn("validate_payload_keys.py", cmake)
        self.assertNotIn("references/data/*.json", cmake)

    def test_payload_assertion_expands_manifest_driven_case_files(self):
        validator = (
            ROOT
            / "integrations"
            / "jev_flutter"
            / "apps"
            / "miaotou_app"
            / "macos"
            / "Runner"
            / "validate_payload_keys.py"
        )
        with tempfile.TemporaryDirectory() as directory:
            packaged = Path(directory)
            shutil.copytree(ROOT / "miaotoujunshi", packaged / "miaotoujunshi")
            shutil.copytree(ROOT / "goutoujunshi", packaged / "goutoujunshi")
            missing = (
                packaged
                / "miaotoujunshi"
                / "examples"
                / "relationship_cases"
                / "mutual_warming.csv"
            )
            missing.unlink()

            result = subprocess.run(
                ["python3", str(validator), str(ROOT), str(packaged)],
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 1)
        self.assertIn("mutual_warming.csv", result.stderr)


if __name__ == "__main__":
    unittest.main()
