import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "platform-build.yml"


class MacosReleaseWorkflowTest(unittest.TestCase):
    def test_release_app_is_signed_notarized_and_stapled(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("flutter build macos --release", workflow)
        self.assertIn("codesign --force --deep --options runtime --timestamp", workflow)
        self.assertIn("xcrun notarytool submit", workflow)
        self.assertIn("xcrun stapler staple", workflow)
        self.assertIn("xcrun stapler validate", workflow)

    def test_release_artifact_is_the_application_not_the_retired_source_port(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("name: miaotoujunshi-mac", workflow)
        self.assertNotIn("miaotoujunshi-mac-source", workflow)
        self.assertNotIn("package_mac.py", workflow)
        self.assertNotIn("integrations/jev_mac", workflow)


if __name__ == "__main__":
    unittest.main()
