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
ANDROID_PLUGIN = (
    ROOT
    / "integrations"
    / "jev_flutter"
    / "packages"
    / "miaotou_capabilities_android"
    / "android"
)
FROZEN_ANDROID = ROOT / "integrations" / "jev_android"
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
    def test_release_builds_the_promoted_flutter_android_app(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        android_job = workflow.split("  android:", 1)[1].split(
            "\n  flutter-windows:", 1
        )[0]

        self.assertIn(
            "working-directory: integrations/jev_flutter/apps/miaotou_app",
            android_job,
        )
        self.assertIn('flutter-version: "3.47.6"', android_job)
        self.assertIn("flutter build apk --debug", android_job)
        self.assertIn(
            "integrations/jev_flutter/apps/miaotou_app/build/app/outputs/"
            "flutter-apk/app-debug.apk",
            android_job,
        )
        self.assertNotIn("integrations/jev_android", android_job)

    def test_frozen_android_port_is_removed_after_promotion(self):
        self.assertFalse(FROZEN_ANDROID.exists())
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertNotIn("integrations/jev_android", workflow)

    def test_retained_capture_sources_live_inside_the_flutter_plugin(self):
        gradle = (ANDROID_PLUGIN / "build.gradle.kts").read_text(encoding="utf-8")
        retained = ANDROID_PLUGIN / "src" / "main" / "kotlin" / "com" / "jev" / "probe"

        for relative in (
            "core/ChatApps.kt",
            "core/ChatModels.kt",
            "capture/ChatAppAdapter.kt",
            "capture/ocr/MlKitOcr.kt",
            "capture/ocr/OcrEngine.kt",
            "capture/ocr/ScreenCapture.kt",
        ):
            self.assertTrue((retained / relative).is_file(), relative)

        self.assertNotIn("jev_android", gradle)
        self.assertNotIn("syncRetainedKotlin", gradle)

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
