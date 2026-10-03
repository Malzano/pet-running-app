#!/usr/bin/env python3
"""Check release resources and, optionally, the contents of a built app/archive.

This is a local packaging check, not App Store validation or upload.
"""

from __future__ import annotations

import argparse
import json
import math
import plistlib
import re
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
USER_DEFAULTS = "NSPrivacyAccessedAPICategoryUserDefaults"
CLUB_DATA_TYPES = {"NSPrivacyCollectedDataTypeUserID", "NSPrivacyCollectedDataTypeFitness",
                   "NSPrivacyCollectedDataTypeHealth", "NSPrivacyCollectedDataTypeOtherUserContent"}
LEGACY_SPECIES = {"corgi", "bunny", "penguin"}


def species_names() -> list[str]:
    """Read persisted asset identifiers from the authoritative Swift catalogue."""
    source = (ROOT / "Shared/PawPaceShared.swift").read_text()
    cases = source.split("enum PetSpecies:", 1)[1].split("var id:", 1)[0]
    result = [raw or name for name, raw in re.findall(
        r'^\s*case\s+(\w+)(?:\s*=\s*"([^"]+)")?\s*$', cases, re.MULTILINE)]
    require(len(result) >= 3 and len(result) == len(set(result)), "Cannot read the species catalogue.")
    return result


def validate_motion_profile(path: Path, joint_names: set[str] | None = None) -> None:
    require(path.is_file(), f"Missing species motion profile: {path}")
    profile = json.loads(path.read_text())
    require(profile.get("gait") in {"quadruped", "bounding", "biped", "crawling"},
            f"Invalid gait in {path}")
    required: set[str] = set()
    legs = profile.get("legs", [])
    require(bool(legs), f"No articulated legs in {path}")
    for leg in legs:
        require(len(leg.get("pivots", [])) >= 2 and bool(leg.get("foot")), f"Incomplete leg chain: {path}")
        require(type(leg.get("front")) is bool and type(leg.get("left")) is bool, f"Missing leg side: {path}")
        require(isinstance(leg.get("phase"), (int, float)) and math.isfinite(leg["phase"]),
                f"Invalid leg phase: {path}")
        required.update(leg["pivots"] + [leg["foot"]])
    for part in ("head", "torso", "tail", "ears", "leftWing", "rightWing"):
        require(isinstance(profile.get(part), list), f"Missing {part} mapping: {path}")
        for joint in profile[part]:
            require(bool(joint.get("name")) and isinstance(joint.get("weight"), (int, float))
                    and math.isfinite(joint["weight"]), f"Invalid {part} joint: {path}")
            required.add(joint["name"])
    require(bool(profile["head"]), f"No articulated head: {path}")
    if profile.get("jaw") is not None:
        required.add(profile["jaw"])
    muzzle = profile.get("muzzleOffset")
    require(isinstance(muzzle, list) and len(muzzle) == 3 and all(
        isinstance(value, (int, float)) and math.isfinite(value) for value in muzzle),
        f"Invalid muzzle offset: {path}")
    model_yaw = profile.get("modelYawDegrees")
    require(model_yaw is None or isinstance(model_yaw, (int, float)) and math.isfinite(model_yaw),
            f"Invalid model orientation: {path}")
    if joint_names is not None:
        missing = required - joint_names
        require(not missing, f"Motion profile references missing bones {sorted(missing)}: {path}")


def validate_animal_sources() -> None:
    animals = ROOT / "PawPace/Resources/Animals"
    portraits = ROOT / "SharedUI/AnimalPortraits.xcassets"
    for species in species_names():
        require((animals / f"{species}.scn").is_file(), f"Missing runtime animal: {species}")
        report_path = animals / f"{species}.rig.json"
        require(report_path.is_file(), f"Missing conversion report: {species}")
        report = json.loads(report_path.read_text())
        require(any(mesh.get("bones", 0) > 0 for mesh in report.get("meshes", [])),
                f"Companion is not skinned: {species}")
        if species not in LEGACY_SPECIES:
            triangles = sum(mesh.get("triangles", 0) for mesh in report["meshes"])
            require(0 < triangles <= 35_000, f"Companion exceeds the mobile triangle budget: {species} ({triangles})")
            require(all(mesh.get("maximumDroppedWeight", 1) <= 0.0000001 for mesh in report["meshes"]),
                    f"Skin influences were dropped during conversion: {species}")
            validate_motion_profile(animals / f"{species}.motion.json", {joint["name"] for joint in report["joints"]})
        image_set = portraits / f"pet-{species}.imageset"
        contents_path = image_set / "Contents.json"
        require(contents_path.is_file(), f"Missing Watch/widget portrait catalogue: {species}")
        images = json.loads(contents_path.read_text()).get("images", [])
        files = [image_set / image["filename"] for image in images if image.get("filename")]
        require(bool(files) and all(path.is_file() for path in files), f"Missing portrait image: {species}")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def plist(path: Path) -> dict:
    require(path.is_file(), f"Missing property list: {path}")
    with path.open("rb") as handle:
        result = plistlib.load(handle)
    require(isinstance(result, dict), f"Expected a property-list dictionary: {path}")
    return result


def validate_manifest(path: Path, watch: bool = False, club: bool = False) -> None:
    manifest = plist(path)
    require(manifest.get("NSPrivacyTracking") is False, f"Review tracking declaration: {path}")
    require(manifest.get("NSPrivacyTrackingDomains") == [], f"Review tracking domains: {path}")
    collected = manifest.get("NSPrivacyCollectedDataTypes")
    if club:
        require(isinstance(collected, list) and len(collected) == len(CLUB_DATA_TYPES)
                and {entry.get("NSPrivacyCollectedDataType") for entry in collected} == CLUB_DATA_TYPES,
                f"Club collection declarations do not match the service data inventory: {path}")
        for entry in collected:
            require(entry.get("NSPrivacyCollectedDataTypeLinked") is True
                    and entry.get("NSPrivacyCollectedDataTypeTracking") is False
                    and entry.get("NSPrivacyCollectedDataTypePurposes") == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"],
                    f"Review Club collection purpose, linking and tracking: {path}")
    else:
        require(collected == [], f"Review collected data declaration: {path}")
    categories = manifest.get("NSPrivacyAccessedAPITypes", [])
    entries = [entry for entry in categories if entry.get("NSPrivacyAccessedAPIType") == USER_DEFAULTS]
    require(len(entries) == 1, f"Missing or duplicated UserDefaults category: {path}")
    expected = {"CA92.1"} if watch else {"CA92.1", "1C8F.1"}
    require(set(entries[0].get("NSPrivacyAccessedAPITypeReasons", [])) == expected,
            f"UserDefaults reasons do not match this bundle's storage: {path}")


def validate_icon(catalog: Path) -> None:
    contents = json.loads((catalog / "Contents.json").read_text())
    for entry in contents["images"]:
        path = catalog / entry["filename"]
        raw = path.read_bytes()
        require(raw[:8] == b"\x89PNG\r\n\x1a\n", f"Icon is not PNG: {path}")
        width, height, _, color_type = struct.unpack(">IIBB", raw[16:26])
        require((width, height) == (1024, 1024), f"Icon must be 1024×1024: {path}")
        require(color_type in (0, 2), f"Default store icon has an alpha channel or palette: {path}")
        cursor = 8
        while cursor + 12 <= len(raw):
            length = struct.unpack(">I", raw[cursor:cursor + 4])[0]
            require(raw[cursor + 4:cursor + 8] != b"tRNS", f"Default store icon has transparency: {path}")
            cursor += length + 12


def validate_sources() -> None:
    validate_manifest(ROOT / "Config/Privacy/Phone/PrivacyInfo.xcprivacy", club=True)
    validate_manifest(ROOT / "Config/Privacy/iOS/PrivacyInfo.xcprivacy")
    validate_manifest(ROOT / "Config/Privacy/watchOS/PrivacyInfo.xcprivacy", watch=True)
    validate_animal_sources()
    project = (ROOT / "project.yml").read_text()
    require(project.count("path: Config/Privacy/Phone/PrivacyInfo.xcprivacy") == 1,
            "The phone must package its Club collection privacy manifest.")
    require(project.count("path: Config/Privacy/iOS/PrivacyInfo.xcprivacy") == 2,
            "Both extensions must package their local-only privacy manifest.")
    require(project.count("path: Config/Privacy/watchOS/PrivacyInfo.xcprivacy") == 1,
            "The Watch must package its privacy manifest.")
    for relative in ("PawPace/Resources/Assets.xcassets", "PawPaceWatch/Assets.xcassets"):
        validate_icon(ROOT / relative / "AppIcon.appiconset")
    phone_entitlements = plist(ROOT / "Config/PawPace.entitlements")
    widget_entitlements = plist(ROOT / "Config/PawPaceWidgets.entitlements")
    groups = phone_entitlements.get("com.apple.security.application-groups")
    require(groups == widget_entitlements.get("com.apple.security.application-groups") and bool(groups),
            "Phone and extensions must share the same registered App Group.")
    shared = (ROOT / "Shared/PawPaceShared.swift").read_text()
    require(f'static let suiteName = "{groups[0]}"' in shared,
            "PawPaceShared.suiteName must match the App Group entitlements.")
    for name in ("PawPace", "PawPaceWatch"):
        info = plist(ROOT / f"Config/{name}-Info.plist")
        for key in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"):
            require(bool(info.get(key)), f"Missing {key} for {name}.")
        require(plist(ROOT / f"Config/{name}.entitlements").get("com.apple.developer.healthkit") is True,
                f"Missing HealthKit entitlement for {name}.")


def validate_bundle(path: Path, require_signing: bool) -> None:
    archive = path if path.suffix == ".xcarchive" else None
    app = path / "Products/Applications/PawPace.app" if archive else path
    info = plist(app / "Info.plist")
    identifier = info["CFBundleIdentifier"]
    version = (info["CFBundleShortVersionString"], info["CFBundleVersion"])
    require(info.get("UIDeviceFamily") == [1], "This release is configured for iPhone.")
    require(info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon"), "Phone has no compiled primary icon.")
    bundles = [app, app / "Watch/PawPaceWatch.app",
               app / "PlugIns/PawPaceWidgets.appex", app / "PlugIns/PawPaceLiveActivity.appex"]
    for bundle in bundles:
        metadata = plist(bundle / "Info.plist")
        require((metadata.get("CFBundleShortVersionString"), metadata.get("CFBundleVersion")) == version,
                f"Embedded version mismatch: {bundle}")
        require((bundle / metadata["CFBundleExecutable"]).is_file(), f"Missing executable: {bundle}")
        require(bool(metadata.get("MinimumOSVersion")), f"Missing deployment target: {bundle}")
        require((bundle / "Assets.car").is_file(), f"Missing compiled assets: {bundle}")
        watch = bundle.name == "PawPaceWatch.app"
        validate_manifest(bundle / "PrivacyInfo.xcprivacy", watch=watch, club=bundle == app)
        if bundle != app:
            require(metadata["CFBundleIdentifier"].startswith(identifier + "."),
                    f"Embedded bundle ID must extend phone bundle ID: {bundle}")
        if watch:
            require(metadata.get("WKCompanionAppBundleIdentifier") == identifier,
                    "Watch companion bundle ID does not match phone.")
        if require_signing:
            require((bundle / "embedded.mobileprovision").is_file(), f"Missing device provisioning: {bundle}")
            subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True, capture_output=True)
            signature = subprocess.run(["codesign", "-dv", str(bundle)], check=True, capture_output=True, text=True)
            require("TeamIdentifier=" in signature.stderr and "TeamIdentifier=not set" not in signature.stderr,
                    f"No developer team in signature: {bundle}")
    for species in species_names():
        require(any(app.rglob(f"{species}.scn")), f"Missing runtime animal: {species}")
        if species not in LEGACY_SPECIES:
            profiles = list(app.rglob(f"{species}.motion.json"))
            require(len(profiles) == 1, f"Missing or duplicate runtime motion profile: {species}")
            validate_motion_profile(profiles[0])
    require(not list(app.rglob("*.xctest")), "Tests are embedded in the release app.")
    if archive:
        archive_info = plist(archive / "Info.plist")
        require(bool(archive_info.get("ApplicationProperties")), "Archive is generic, not an application archive.")
        require((archive / "dSYMs/PawPace.app.dSYM").is_dir(), "Archive has no phone debug symbols.")
    print(f"Validated {len(bundles)} built bundles, matching versions, icons, models and privacy resources.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="A .xcarchive or built PawPace.app to inspect")
    parser.add_argument("--require-signing", action="store_true", help="Also require device provisioning and valid team signatures")
    args = parser.parse_args()
    require(not args.require_signing or args.archive is not None, "--require-signing needs --archive.")
    validate_sources()
    print("Release source resources validated. Signing, public URLs, and physical-device checks remain separate.")
    if args.archive:
        validate_bundle(args.archive.expanduser().resolve(), args.require_signing)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Release validation failed: {error}") from error
