#!/usr/bin/env python3
"""Exercise the actual URL/file loader across a signed macOS sandbox boundary."""

import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unicodedata
import uuid
from urllib.parse import urlencode, urlsplit, urlunsplit


REPO = Path(__file__).resolve().parent.parent
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


def run(args):
    # Do not include argv in errors: an open argument may carry a file grant.
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True, timeout=60)
    if result.returncode:
        if str(args[0]) == "xcrun":
            print(result.stderr, file=sys.stderr)
        raise RuntimeError(f"{Path(args[0]).name} failed ({result.returncode})")
    return result.stdout.strip()


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    token = uuid.uuid4().hex
    bundle_id = f"com.grock.file-access-test.{token}"
    scheme = f"grock-file-test-{token}"
    container = Path.home() / "Library/Containers" / bundle_id
    fixtures = Path.home() / "Library/Application Support" / bundle_id
    fixtures.mkdir(parents=True)
    receiver_pid = None
    root = Path(tempfile.mkdtemp(prefix="grock-file-access-"))
    app = root / "Receiver.app"
    try:
        executable = app / "Contents/MacOS/Receiver"
        executable.parent.mkdir(parents=True)
        info = {
            "CFBundleIdentifier": bundle_id, "CFBundleExecutable": "Receiver",
            "CFBundleName": "Grock File Access Test", "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1", "LSUIElement": True,
            "CFBundleURLTypes": [{"CFBundleURLSchemes": [scheme]}],
        }
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        source = [REPO / path for path in [
            "script/fixtures/FileAccessProbe.swift", "Grock/App/GrockURL.swift",
            "Grock/App/GrockCommand.swift", "Grock/App/FileIntake.swift", "Grock/Web/QuickChatPayload.swift",
        ]]
        maker = root / "maker"
        run(["xcrun", "swiftc", "-parse-as-library", "-o", maker, *source])
        shutil.copy2(maker, executable)
        entitlements = root / "entitlements.plist"
        entitlements.write_bytes(plistlib.dumps({
            "com.apple.security.app-sandbox": True,
            "com.apple.security.files.user-selected.read-only": True,
            "com.apple.security.files.downloads.read-write": True,
        }))
        run(["codesign", "--force", "--sign", "-", "--options", "runtime", "--entitlements", entitlements, app])
        run(["codesign", "--verify", "--strict", app])
        run([LSREGISTER, "-f", app])
        files = [fixtures / "café + report.txt", fixtures / "second file.txt "]
        files += [fixtures / f"report-{i}.txt" for i in range(2, 20)]
        for i, file in enumerate(files):
            file.write_text(f"fixture {i}")

        def make(command, selected):
            args = [maker, "make", command, "Summarize + compare & explain"]
            for file in selected:
                args += ["-f", file]
            return run(args)  # The sender has exited before open delivers its URL.

        def deliver(label, url):
            nonlocal receiver_pid
            parts = urlsplit(url)
            query = parts.query + ("&" if parts.query else "") + urlencode({"case": label})
            incoming = urlunsplit((scheme, parts.netloc, parts.path, query, ""))
            report_file = container / "Data" / (label + ".json")
            try:
                run(["/usr/bin/open", "-g", "-a", app, incoming])
            except RuntimeError as error:
                raise RuntimeError(f"{label}: {error}") from None
            deadline = time.monotonic() + 20
            while not report_file.exists() and time.monotonic() < deadline:
                time.sleep(0.1)
            check(report_file.exists(), f"{label}: receiver did not report within 20 seconds")
            report = json.loads(report_file.read_text())
            receiver_pid = report["pid"]
            return report

        def accepted(label, command, selected):
            report = deliver(label, make(command, selected))
            check(report.get("success"), f"{label}: handoff failed: {report.get('error')}")
            check(report["command"] == command, f"{label}: destination changed")
            check(report["text"] == "Summarize + compare & explain", f"{label}: prompt changed")
            names = [unicodedata.normalize("NFC", name) for name in report["names"]]
            check(names == [file.name for file in selected], f"{label}: filenames changed: {names}")
            check(report["contents"] == [file.read_text() for file in selected], f"{label}: contents changed")
            check(not any(report["readBefore"]), f"{label}: resolution implicitly granted access")
            check(not any(report["readAfter"]), f"{label}: access was not released")
            return report

        plain = "grock://ask?" + urlencode({"text": "keep me", "file": str(files[0])})
        report = deliver("plain", plain)
        check(report.get("permissionDenied") and not report["success"], "Plain paths unexpectedly have access")
        warm_pid = receiver_pid
        accepted("warm-ask", "ask", files[:2])
        check(receiver_pid == warm_pid, "Warm handoff relaunched the receiver")
        accepted("warm-new", "new", files[:2])
        accepted("twenty-files", "ask", files)

        os.kill(receiver_pid, signal.SIGTERM)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                os.kill(receiver_pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("Receiver did not exit before cold handoff")
        receiver_pid = None
        cold = accepted("cold-new", "new", files[:2])
        check(cold["pid"] != warm_pid, "Cold handoff reused the receiver")

        malformed = deliver("malformed", "grock://ask?text=keep+me&bookmark=bm90LWEtYm9va21hcms=")
        check(malformed.get("invalid") and not malformed["success"], "Malformed bookmark was accepted")
        many = deliver("too-many", "grock://ask?" + urlencode([("file", str(files[0]))] * 21))
        check(many.get("invalid") and not many["success"], "Attachment limit was ignored")

        oversized_file = fixtures / "oversized.txt"
        with oversized_file.open("wb") as handle:
            handle.truncate(12_000_001)
        oversized = deliver("oversized", make("ask", [oversized_file]))
        check(not oversized["success"] and "12 MB" in oversized["error"], "Size limit was ignored")
        check(oversized["readAfter"] == [False], "Access was not released after a failed read")

        deleted_url = make("ask", [files[0]])
        files[0].unlink()
        deleted = deliver("deleted", deleted_url)
        check(not deleted["success"], "A deleted attachment was silently accepted")
        print("FILE ACCESS CHECK OK (raw path denied; warm/cold CLI handoff; 20 files; scope released; invalid requests rejected)")
    finally:
        if receiver_pid:
            try:
                os.kill(receiver_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        subprocess.run([LSREGISTER, "-u", str(app)], capture_output=True)
        shutil.rmtree(fixtures, ignore_errors=True)
        shutil.rmtree(container, ignore_errors=True)
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        # TimeoutExpired includes argv; never print it.
        message = "A subprocess timed out" if isinstance(error, subprocess.TimeoutExpired) else str(error)
        raise SystemExit(f"FILE ACCESS CHECK FAILED: {message}") from None
