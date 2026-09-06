#!/usr/bin/env python3
# Copyright 2026 The DirStat Authors.
# Modified 2026-09-05.

"""Exercise release success/failure handling without signing keys or uploads."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parent.parent
IDENTITY = "Developer ID Application: Test Developer (ABC1234567)"
PASSWORD = "test password $literal & punctuation"
ENV = f"""CODE_SIGN_IDENTITY='{IDENTITY}'
APPLE_TEAM_ID='ABC1234567'
APPLE_ID='release@example.com'
APPLE_APP_SPECIFIC_PASSWORD='{PASSWORD}'
DIX_BUILD_DIR='build with spaces'
"""

# Only mock tools that would build, sign, mount a disk, or contact Apple.
# File copying, symlinks, JSON/plist parsing, and release promotion are real.
TOOL = r'''
import json
import os
from pathlib import Path
import plistlib
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
mode = os.environ["DIRSTAT_TEST_MODE"]
with open(os.environ["DIRSTAT_TEST_CALLS"], "a") as output:
    output.write(json.dumps([name, *args]) + "\n")

if name == "security":
    if mode == "missing-certificate":
        print("0 valid identities found")
    else:
        print('1) FAKEHASH "Developer ID Application: Test Developer (ABC1234567)"')
elif name == "xcodebuild":
    if mode == "build-failure":
        sys.exit(65)
    directory = next(arg.split("=", 1)[1] for arg in args
                     if arg.startswith("CONFIGURATION_BUILD_DIR="))
    contents = Path(directory) / "DirStat.app/Contents"
    contents.mkdir(parents=True)
    with (contents / "Info.plist").open("wb") as output:
        plistlib.dump({"CFBundleShortVersionString": "2.0",
                      "CFBundleIdentifier": "com.dirstat.DirStat"}, output)
elif name == "hdiutil" and args[0] == "create":
    root = Path(args[args.index("-srcfolder") + 1])
    assert (root / "DirStat.app/Contents/Info.plist").is_file()
    assert os.readlink(root / "Applications") == "/Applications"
    assert sorted(item.name for item in root.iterdir()) == ["Applications", "DirStat.app"]
    Path(args[-1]).write_text("new disk image")
elif name == "codesign" and mode == "signing-failure":
    sys.exit(1)
elif name == "spctl" and mode == "gatekeeper-failure":
    sys.exit(1)
elif name == "xcrun":
    if args[0] == "--find":
        print("/fake/" + args[1])
    elif args[:2] == ["notarytool", "submit"]:
        if mode == "malformed-response":
            print("not JSON")
        elif mode == "submission-failure":
            sys.exit(1)
        else:
            status = {"rejected": "Invalid", "rejected-nonzero": "Invalid",
                      "timeout": "In Progress"}.get(mode, "Accepted")
            print(json.dumps({"id": "test-submission-id", "status": status}))
            if mode in ("timeout", "rejected-nonzero"):
                sys.exit(1)
    elif args[:2] == ["notarytool", "log"]:
        if mode in ("timeout", "log-unavailable"):
            sys.exit(1)
        Path(args[3]).write_text(json.dumps({"issues": []}))
    elif args[:2] == ["stapler", "staple"]:
        if mode == "staple-failure":
            sys.exit(65)
        with Path(args[2]).open("a") as output:
            output.write(" with ticket")
    elif args[:2] == ["stapler", "validate"] and mode == "validation-failure":
        sys.exit(65)
'''


class BuildDMGTests(unittest.TestCase):
    def run_release(self, mode="accepted", env_text=ENV):
        with tempfile.TemporaryDirectory(prefix="dirstat dmg tests ") as directory:
            root = Path(directory)
            project = root / "project with spaces"
            project.mkdir()
            shutil.copy2(PROJECT / "BuildDMG.sh", project)
            if env_text is not None:
                (project / ".env").write_text(env_text)
            binaries = root / "bin"
            binaries.mkdir()
            shim = binaries / "tool"
            shim.write_text(f"#!{sys.executable}\n" + TOOL)
            shim.chmod(0o755)
            for tool in ("security", "xcodebuild", "codesign", "hdiutil", "spctl", "xcrun"):
                (binaries / tool).symlink_to(shim)
            calls_file = root / "calls.jsonl"
            env = dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                       DIRSTAT_TEST_MODE=mode, DIRSTAT_TEST_CALLS=str(calls_file),
                       CODE_SIGN_IDENTITY="inherited identity", APPLE_TEAM_ID="ZZZ9999999",
                       APPLE_ID="inherited@example.com", APPLE_APP_SPECIFIC_PASSWORD="inherited")
            output_dir = project / "build with spaces/Notarized"
            output_dir.mkdir(parents=True)
            final = output_dir / "DirStat-2.0.dmg"
            final.write_text("previous release")
            result = subprocess.run(["sh", "-x", str(project / "BuildDMG.sh")],
                                    cwd=root, env=env, text=True, capture_output=True)
            output = result.stdout + result.stderr
            self.assertNotIn(PASSWORD, output)
            calls = [json.loads(line) for line in calls_file.read_text().splitlines()] \
                if calls_file.exists() else []
            logs = list(output_dir.glob("run.*/notary-log.json"))
            if mode in ("accepted", "log-unavailable") and env_text == ENV:
                self.assertEqual(result.returncode, 0, output)
                self.assertEqual(final.read_text(), "new disk image with ticket")
                self.assertIn("Notarized DMG:", output)
            else:
                self.assertNotEqual(result.returncode, 0, output)
                self.assertEqual(final.read_text(), "previous release")
                self.assertNotIn("Notarized DMG:", output)
            return calls, output, bool(logs)

    def test_success_uses_file_credentials_and_checks_ticket_before_promotion(self):
        calls, _, has_log = self.run_release()
        build = next(call for call in calls if call[0] == "xcodebuild")
        for setting in (f"CODE_SIGN_IDENTITY={IDENTITY}", "DEVELOPMENT_TEAM=ABC1234567",
                        "ENABLE_HARDENED_RUNTIME=YES", "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO",
                        "OTHER_CODE_SIGN_FLAGS=--timestamp", "ARCHS=arm64 x86_64"):
            self.assertIn(setting, build)
        notary_calls = [call for call in calls if call[:2] == ["xcrun", "notarytool"]]
        self.assertEqual([call[2] for call in notary_calls], ["submit", "log"])
        for call in notary_calls:
            for flag, value in (("--apple-id", "release@example.com"),
                                ("--team-id", "ABC1234567"), ("--password", PASSWORD)):
                self.assertEqual(call[call.index(flag) + 1], value)
        self.assertTrue(has_log)
        self.assertEqual(calls[-1][0], "spctl")
        self.assertTrue(any(call[:3] == ["xcrun", "stapler", "validate"] for call in calls))

    def test_bad_configuration_stops_before_external_tools(self):
        missing_id = ENV.replace("APPLE_ID='release@example.com'\n", "")
        for text in (None, (PROJECT / ".env.example").read_text(), missing_id):
            with self.subTest(env=text is not None):
                calls, _, _ = self.run_release(env_text=text)
                self.assertEqual(calls, [])

    def test_local_failures_do_not_upload(self):
        for mode in ("missing-certificate", "build-failure", "signing-failure"):
            with self.subTest(mode=mode):
                calls, _, _ = self.run_release(mode)
                self.assertFalse(any(call[:2] == ["xcrun", "notarytool"] for call in calls))

    def test_notarization_failures_do_not_staple_or_replace_release(self):
        for mode in ("rejected", "rejected-nonzero", "timeout", "malformed-response", "submission-failure"):
            with self.subTest(mode=mode):
                calls, _, has_log = self.run_release(mode)
                self.assertFalse(any(call[:2] == ["xcrun", "stapler"] for call in calls))
                if mode.startswith("rejected"):
                    self.assertTrue(has_log)
                if mode in ("malformed-response", "submission-failure"):
                    self.assertFalse(any(call[:3] == ["xcrun", "notarytool", "log"] for call in calls))

    def test_failed_distribution_checks_preserve_previous_release(self):
        for mode in ("staple-failure", "validation-failure", "gatekeeper-failure"):
            with self.subTest(mode=mode):
                self.run_release(mode)

    def test_accepted_submission_can_finish_when_log_is_unavailable(self):
        _, output, has_log = self.run_release("log-unavailable")
        self.assertFalse(has_log)
        self.assertIn("log is not available", output)


if __name__ == "__main__":
    unittest.main()
