"""Writes Mixpilot's String Catalogs (Localizable.xcstrings, InfoPlist.xcstrings).

    python3 Localization/localize.py              builds the app first
    python3 Localization/localize.py --no-build   uses the last build in build/DerivedData

The English keys come from the `.stringsdata` files the Swift compiler writes during the build
(SWIFT_EMIT_LOC_STRINGS), so they are exactly what the app looks up, placeholders included.
German comes from de.py. The catalogs are overwritten on every run: edit de.py, not the catalogs.

Fails (exit 1) if a key has no German translation or a translation changes the placeholders.
"""
import json, pathlib, plistlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Localization"))
from de import DE, INFOPLIST  # noqa: E402

RESOURCES = ROOT / "Mixpilot" / "Resources"
OBJECTS = ROOT / "build/DerivedData/Build/Intermediates.noindex/Mixpilot.build/Debug/Mixpilot.build/Objects-normal"
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[@dfsuxXc]")


def build():
    subprocess.run(
        ["xcodebuild", "-project", str(ROOT / "Mixpilot.xcodeproj"), "-scheme", "Mixpilot",
         "-configuration", "Debug", "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", str(ROOT / "build/DerivedData"),
         "-allowProvisioningUpdates", "-quiet", "build"],
        check=True,
    )


def extracted_keys():
    """Key → developer comment, from every .stringsdata file of the app target."""
    keys = {}
    files = sorted(OBJECTS.glob("*/*.stringsdata"))
    if not files:
        sys.exit("No .stringsdata files found: build the app first.")
    for path in files:
        data = json.loads(path.read_text())
        for entry in data.get("tables", {}).get("Localizable", []):
            comment = entry.get("comment") or ""
            if keys.get(entry["key"]):
                continue
            keys[entry["key"]] = comment
    return keys


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def write(path, catalog):
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : ")) + "\n")


def main():
    if "--no-build" not in sys.argv:
        build()
    ok = True
    keys = extracted_keys()

    strings = {}
    for key in sorted(keys):
        german = DE.get(key)
        if german is None:
            ok = False
            print(f"MISSING German: {key!r}")
            continue
        if sorted(PLACEHOLDER.findall(key)) != sorted(PLACEHOLDER.findall(german)):
            ok = False
            print(f"Placeholder mismatch: {key!r} → {german!r}")
        entry = {"localizations": {"de": unit(german)}}
        if keys[key]:
            entry["comment"] = keys[key]
        strings[key] = entry
    for unused in sorted(set(DE) - set(keys)):
        print(f"unused German entry (not in the code): {unused!r}")
    write(RESOURCES / "Localizable.xcstrings", {"sourceLanguage": "en", "strings": strings, "version": "1.0"})

    info = {}
    plist = plistlib.loads((ROOT / "Info.plist").read_bytes())
    for key, (english, german) in sorted(INFOPLIST.items()):
        if plist.get(key) != english:
            ok = False
            print(f"Info.plist {key} differs from the English text in de.py")
        info[key] = {
            "extractionState": "extracted_with_value",
            "localizations": {"en": unit(english, "new"), "de": unit(german)},
        }
    write(RESOURCES / "InfoPlist.xcstrings", {"sourceLanguage": "en", "strings": info, "version": "1.0"})

    print(f"{len(keys)} keys in the code, {len(DE)} German entries")
    sys.exit(0 if ok else 1)


main()
