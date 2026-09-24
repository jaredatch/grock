#!/usr/bin/env python3
"""Validate the actual app signature, entitlements, architecture, and OS floor."""
import argparse
import plistlib
import re
import subprocess
from pathlib import Path


def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


def verify(app, distribution=False, notarized=False):
    app = Path(app).resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "com.jaredatch.Grock":
        raise ValueError("Unexpected application bundle identifier")
    if info.get("LSMinimumSystemVersion") != "26.0":
        raise ValueError("The release must declare macOS 26.0 as its minimum")
    if not info.get("SUFeedURL", "").startswith("https://") or "PLACEHOLDER" in info.get("SUPublicEDKey", ""):
        raise ValueError("Sparkle feed URL or public key is missing; run generate_keys and fill project.yml")
    if not (app / "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc").is_dir():
        raise ValueError("Sparkle's installer XPC service is missing from the bundle")
    expected = plistlib.loads((Path(__file__).resolve().parent.parent / "Grock/Grock.entitlements").read_bytes())
    actual = plistlib.loads(run("codesign", "-d", "--entitlements", "-", "--xml", str(app)))
    if actual != expected or actual.get("com.apple.security.app-sandbox") is not True:
        raise ValueError("Embedded entitlements differ from the reviewed sandbox configuration")
    run("codesign", "--verify", "--deep", "--strict", str(app))
    executables = [app / "Contents/MacOS/Grock", app / "Contents/SharedSupport/grock"]
    teams = set()
    for binary in executables:
        run("codesign", "--verify", "--strict", str(binary))
        if run("lipo", "-archs", str(binary)).decode().strip() != "arm64":
            raise ValueError(f"Unexpected architecture in {binary.name}; current releases target Apple silicon")
        details = subprocess.run(["codesign", "-dvv", str(binary)], check=True, capture_output=True).stderr.decode()
        if "runtime" not in details:
            raise ValueError(f"Hardened runtime is missing from {binary.name}")
        if distribution and ("Authority=Developer ID Application:" not in details or "Timestamp=" not in details):
            raise ValueError(f"Developer ID signature/timestamp is missing from {binary.name}")
        if distribution:
            team = re.search(r"(?m)^TeamIdentifier=(\S+)$", details)
            if not team or team.group(1) == "not":
                raise ValueError(f"Developer team is missing from {binary.name}")
            teams.add(team.group(1))
        build = run("xcrun", "vtool", "-show-build", str(binary)).decode()
        if not re.search(r"(?m)^\s*minos\s+26\.0\s*$", build):
            raise ValueError(f"Unexpected deployment target in {binary.name}")
    if distribution and len(teams) != 1:
        raise ValueError("The app and CLI must be signed by the same developer team")
    cli_entitlements = run("codesign", "-d", "--entitlements", "-", "--xml", str(executables[1])).strip()
    if cli_entitlements and plistlib.loads(cli_entitlements):
        raise ValueError("The CLI must not acquire app/debug entitlements")
    if notarized:
        if not distribution:
            raise ValueError("Notarization verification requires --distribution")
        run("xcrun", "stapler", "validate", str(app))
        run("spctl", "--assess", "--type", "execute", str(app))
    print("RELEASE CHECK OK" if distribution and notarized else "SIGNED APP CHECK OK (not a notarization check)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--distribution", action="store_true")
    parser.add_argument("--notarized", action="store_true")
    args = parser.parse_args()
    try:
        verify(args.app, args.distribution, args.notarized)
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Release verification failed: {error}\n")
