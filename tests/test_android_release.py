import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "platform-build.yml"
GRADLE = (
    ROOT
    / "integrations"
    / "jev_flutter"
    / "apps"
    / "miaotou_app"
    / "android"
    / "app"
    / "build.gradle.kts"
)
VALIDATOR = (
    ROOT
    / "integrations"
    / "jev_flutter"
    / "apps"
    / "miaotou_app"
    / "macos"
    / "Runner"
    / "validate_payload_keys.py"
)


class AndroidReleaseWorkflowTest(unittest.TestCase):
    def test_release_keeps_the_frozen_port_until_device_acceptance(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        android_job = workflow.split("  android:", 1)[1].split(
            "\n  flutter-windows:", 1
        )[0]

        self.assertIn("working-directory: integrations/jev_android", android_job)
        self.assertIn(":app:testDebugUnitTest :app:assembleDebug", android_job)
        self.assertIn(
            "integrations/jev_android/app/build/outputs/apk/debug/*.apk",
            android_job,
        )
        self.assertNotIn("flutter build apk", android_job)

    def test_payload_is_synced_recursively_and_asserted_at_build_time(self):
        gradle = GRADLE.read_text(encoding="utf-8")

        self.assertIn("tasks.registering(Sync::class)", gradle)
        self.assertIn('from(File(repoRoot, "miaotoujunshi"))', gradle)
        self.assertIn('from(File(repoRoot, "goutoujunshi"))', gradle)
        self.assertIn("validate_payload_keys.py", gradle)
        self.assertIn(
            'sourceSets["main"].assets.srcDir(sharedAssets.get().asFile)',
            gradle,
        )
        self.assertNotIn("references/data/*.json", gradle)

    def test_payload_assertion_catches_a_missing_runtime_key(self):
        with tempfile.TemporaryDirectory() as directory:
            packaged = Path(directory)
            shutil.copytree(ROOT / "miaotoujunshi", packaged / "miaotoujunshi")
            shutil.copytree(ROOT / "goutoujunshi", packaged / "goutoujunshi")
            (
                packaged
                / "miaotoujunshi"
                / "references"
                / "data"
                / "trend-rules.json"
            ).unlink()

            result = subprocess.run(
                ["python3", str(VALIDATOR), str(ROOT), str(packaged)],
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 1)
        self.assertIn("trend-rules.json", result.stderr)


if __name__ == "__main__":
    unittest.main()
