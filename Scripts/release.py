#!/usr/bin/env python3
"""Bump Poké Binder's patch/build numbers, build an unsigned IPA, and send it."""
from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_FILE = ROOT / "PokeBinder.xcodeproj" / "project.pbxproj"
DERIVED_DATA = ROOT / "build" / "ReleaseDerivedData"
STAGE = ROOT / "build" / "ipa-stage"
IPA = ROOT / "build" / "PokeBinder-unsigned.ipa"
BUNDLE_ID = "com.example.PokeBinder"
EXPECTED_CONFIG_COPIES = 2  # Debug and Release


def command(args: list[str], *, quiet: bool = False) -> None:
    if not quiet:
        print("$", " ".join(str(arg) for arg in args), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)


def setting_values(text: str, key: str) -> list[str]:
    pattern = re.compile(rf"(?m)^[ \t]*{re.escape(key)}[ \t]*=[ \t]*([^;\r\n]+);")
    return [match.group(1).strip() for match in pattern.finditer(text)]


def replace_setting(text: str, key: str, value: str) -> str:
    pattern = re.compile(rf"(?m)^([ \t]*{re.escape(key)}[ \t]*=[ \t]*)[^;\r\n]+;")
    updated, count = pattern.subn(lambda match: f"{match.group(1)}{value};", text)
    if count != EXPECTED_CONFIG_COPIES:
        raise RuntimeError(f"Expected {EXPECTED_CONFIG_COPIES} {key} settings; found {count}.")
    return updated


def next_numbers(text: str) -> tuple[str, str]:
    marketing_values = setting_values(text, "MARKETING_VERSION")
    build_values = setting_values(text, "CURRENT_PROJECT_VERSION")
    if len(marketing_values) != EXPECTED_CONFIG_COPIES or len(set(marketing_values)) != 1:
        raise RuntimeError("Debug/Release MARKETING_VERSION settings are missing or inconsistent.")
    if len(build_values) != EXPECTED_CONFIG_COPIES or len(set(build_values)) != 1:
        raise RuntimeError("Debug/Release CURRENT_PROJECT_VERSION settings are missing or inconsistent.")

    parts = marketing_values[0].split(".")
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise RuntimeError(f"Expected a three-part marketing version, found {marketing_values[0]!r}.")
    major, minor, patch = (int(part) for part in parts)
    if not build_values[0].isdigit():
        raise RuntimeError(f"Expected an integer build number, found {build_values[0]!r}.")
    return f"{major}.{minor}.{patch + 1}", str(int(build_values[0]) + 1)


def telegram_target() -> tuple[str, str]:
    override = os.environ.get("POKEBINDER_TELEGRAM_TARGET", "").strip()
    if override:
        match = re.fullmatch(r"telegram:(-?\d+)", override)
        if not match:
            raise RuntimeError("POKEBINDER_TELEGRAM_TARGET must be telegram:<numeric-chat-id>.")
        return override, match.group(1)

    result = subprocess.run(
        ["hermes", "send", "--list", "telegram", "--json"],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    directory = json.loads(result.stdout)
    matches = [
        channel for channel in directory.get("platforms", {}).get("telegram", [])
        if channel.get("name") == "Fat Fatty Fatter" and channel.get("type") == "group"
    ]
    if len(matches) != 1:
        raise RuntimeError("Could not uniquely resolve the Fat Fatty Fatter Telegram group.")
    chat_id = str(matches[0].get("id", ""))
    if not re.fullmatch(r"-?\d+", chat_id):
        raise RuntimeError("Telegram returned an invalid chat ID for Fat Fatty Fatter.")
    return f"telegram:{chat_id}", chat_id


def send_ipa(target: str, expected_chat_id: str, message: str) -> None:
    args = ["hermes", "send", "--to", target, "--json", message]
    print(f"$ hermes send --to {target} --json <versioned IPA>", flush=True)
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"Telegram send failed: {detail or f'exit {result.returncode}'}")
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("Telegram send returned an unreadable result; verify delivery before retrying.") from error
    if payload.get("success") is not True:
        raise RuntimeError(f"Telegram did not confirm delivery: {payload.get('error', 'unknown error')}")
    if str(payload.get("chat_id")) != expected_chat_id:
        raise RuntimeError(f"Telegram acknowledged chat {payload.get('chat_id')}, not the configured group.")
    if not payload.get("message_id"):
        raise RuntimeError("Telegram did not return a message ID; verify delivery before retrying.")
    if payload.get("warnings"):
        raise RuntimeError(f"Telegram reported incomplete delivery: {payload['warnings']}")
    print(f"Telegram delivery confirmed for chat {expected_chat_id}; message {payload['message_id']}.")


def ensure_clean_worktree() -> None:
    result = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=all"],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    if result.stdout.strip():
        raise RuntimeError("Commit or stash all tracked/untracked source changes before releasing. The ignored build/ and auto-sync-code.txt files are not included in this check.")


def private_sync_code() -> bytes | None:
    path = ROOT / "PokeBinder" / "auto-sync-code.txt"
    if not path.is_file():
        return None
    # Read only in memory for the artifact privacy check; never print or copy it.
    normalized = "".join(char for char in path.read_text(encoding="utf-8").upper() if char.isalnum())
    return normalized.encode("utf-8") if len(normalized) >= 20 else None


def verify_app_privacy(app: Path, secret: bytes | None) -> None:
    included = [path for path in app.rglob("*") if path.is_file()]
    named = [path for path in included if path.name == "auto-sync-code.txt"]
    matches = []
    if secret:
        for path in included:
            try:
                if secret in path.read_bytes():
                    matches.append(path.name)
            except OSError:
                continue
    if named or matches:
        raise RuntimeError("Privacy check failed: the automatic sync code appears in the app bundle.")
    print("Privacy check: automatic sync code is not in the app bundle.")


def verify_ipa(ipa: Path, marketing: str, build: str, secret: bytes | None) -> None:
    with zipfile.ZipFile(ipa) as archive:
        bad_member = archive.testzip()
        if bad_member:
            raise RuntimeError(f"IPA ZIP integrity failed at {bad_member}.")
        plist_name = "Payload/PokeBinder.app/Info.plist"
        if plist_name not in archive.namelist():
            raise RuntimeError("IPA is missing Payload/PokeBinder.app/Info.plist.")
        if any(Path(name).name == "auto-sync-code.txt" for name in archive.namelist()):
            raise RuntimeError("Privacy check failed: auto-sync-code.txt is in the IPA.")
        if secret:
            for name in archive.namelist():
                if name.startswith("Payload/PokeBinder.app/") and secret in archive.read(name):
                    raise RuntimeError("Privacy check failed: automatic sync code is embedded in the IPA.")
        info = plistlib.loads(archive.read(plist_name))
        if info.get("CFBundleIdentifier") != BUNDLE_ID:
            raise RuntimeError(f"Unexpected bundle identifier: {info.get('CFBundleIdentifier')!r}.")
        if info.get("CFBundleShortVersionString") != marketing:
            raise RuntimeError("IPA marketing version does not match the project settings.")
        if str(info.get("CFBundleVersion")) != build:
            raise RuntimeError("IPA build number does not match the project settings.")
        print(f"Verified IPA: {BUNDLE_ID}, version {marketing} (build {build}), ZIP valid, sync code excluded.")


def build_ipa(marketing: str, build: str) -> None:
    app = DERIVED_DATA / "Build" / "Products" / "Release-iphoneos" / "PokeBinder.app"
    secret = private_sync_code()
    command([
        "xcodebuild", "clean", "build", "-quiet",
        "-project", "PokeBinder.xcodeproj",
        "-scheme", "PokeBinder",
        "-configuration", "Release",
        "-destination", "generic/platform=iOS",
        "-derivedDataPath", str(DERIVED_DATA),
        "CODE_SIGNING_ALLOWED=NO",
        "EXCLUDED_SOURCE_FILE_NAMES=auto-sync-code.txt",
        f"MARKETING_VERSION={marketing}",
        f"CURRENT_PROJECT_VERSION={build}",
    ])
    if not app.is_dir():
        raise RuntimeError(f"Xcode did not produce the expected app bundle: {app}")
    verify_app_privacy(app, secret)

    if STAGE.exists():
        shutil.rmtree(STAGE)
    if IPA.exists():
        IPA.unlink()
    payload = STAGE / "Payload"
    payload.mkdir(parents=True, exist_ok=True)
    command(["ditto", str(app), str(payload / "PokeBinder.app")])
    command(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(payload), str(IPA)])
    verify_ipa(IPA, marketing, build, secret)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="show the next version without changing files or sending")
    args = parser.parse_args()

    original = PROJECT_FILE.read_text(encoding="utf-8")
    marketing, build = next_numbers(original)
    target, expected_chat_id = telegram_target()
    if args.dry_run:
        print(f"Next release: Poké Binder v{marketing} (build {build}); Telegram target: {target}.")
        return 0

    ensure_clean_worktree()
    updated = replace_setting(original, "MARKETING_VERSION", marketing)
    updated = replace_setting(updated, "CURRENT_PROJECT_VERSION", build)
    PROJECT_FILE.write_text(updated, encoding="utf-8")

    try:
        build_ipa(marketing, build)
    except Exception:
        PROJECT_FILE.write_text(original, encoding="utf-8")
        raise

    message = (
        f"Poké Binder v{marketing} (build {build}) — unsigned IPA attached.\n"
        "Automatic binder sync is disabled in this group build; link phones manually in Sync settings.\n"
        f"MEDIA:{IPA}"
    )
    try:
        send_ipa(target, expected_chat_id, message)
    except Exception:
        PROJECT_FILE.write_text(original, encoding="utf-8")
        raise

    try:
        command(["git", "add", "--", str(PROJECT_FILE.relative_to(ROOT))])
        command(["git", "commit", "-m", f"chore(release): v{marketing} build {build}"])
    except Exception as exc:
        print(f"IPA was sent, but the version bump commit failed: {exc}", file=sys.stderr)
        return 1

    print(f"Release delivered: version {marketing}, build {build}.")
    print(f"IPA: {IPA}")
    print("No GitHub push was performed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Release failed: {error}", file=sys.stderr)
        raise SystemExit(1)
