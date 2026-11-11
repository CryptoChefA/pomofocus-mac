#!/usr/bin/env python3
"""Writes Metadata.appintents for the widget's buttons, the file Xcode makes at build time.

macOS only runs an App Intent (a widget button, a Shortcuts action) it has metadata for.
Xcode's appintentsmetadataprocessor writes that metadata, but this project builds with the
Command Line Tools alone, so this script does the same job for the simple case the widget
needs: intents with a title, a description and no parameters.

    appintents-metadata.py <unstripped binary> <swift sources dir> <output Metadata.appintents dir>

It reads each `struct X: AppIntent` with its title and description from the sources, finds
the type's mangled name in the binary (so it must run before `strip`), and fails loudly if
any intent is missing, rather than shipping a button that silently does nothing.
"""
import json
import pathlib
import re
import subprocess
import sys

binary, sources, output = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])

intents = []
for source in sorted(sources.glob("*.swift")):
    text = source.read_text()
    for match in re.finditer(r"^struct (\w+): AppIntent \{(.*?)^\}", text, re.S | re.M):
        name, body = match.group(1), match.group(2)
        title = re.search(r'static let title: LocalizedStringResource = "([^"]+)"', body)
        description = re.search(r'IntentDescription\("([^"]+)"\)', body)
        if not title:
            sys.exit(f"{name} needs a `static let title: LocalizedStringResource = \"…\"`")
        intents.append((name, title.group(1), description.group(1) if description else ""))
if not intents:
    sys.exit("no App Intents found")

# Nominal type descriptors end in "Mn"; dropping the "_$s" prefix and that suffix leaves the
# type's mangled name, which is what the system uses to find it at run time.
symbols = subprocess.run(["nm", "-j", binary], capture_output=True, text=True, check=True).stdout.split()
descriptors = [s[3:-2] for s in symbols if s.startswith("_$s") and s.endswith("VMn")]
demangled = subprocess.run(["xcrun", "swift-demangle", "--compact"],
                           input="\n".join("$s" + d + "Mn" for d in descriptors),
                           capture_output=True, text=True, check=True).stdout.splitlines()
by_name = {}
for mangled, readable in zip(descriptors, demangled):
    # "nominal type descriptor for PomofocusWidget.PauseTimerIntent"
    by_name[readable.rsplit(" ", 1)[-1]] = mangled

module = next((n.split(".")[0] for n in by_name if n.split(".")[-1] == intents[0][0]), None)
if module is None:
    sys.exit(f"{intents[0][0]} isn't in {binary}; build first, and run this before strip")


def text(value):
    return {"alternatives": [], "key": value}


actions = {}
for name, title, description in intents:
    qualified = f"{module}.{name}"
    mangled = by_name.get(qualified)
    if mangled is None:
        sys.exit(f"{qualified} isn't in the binary (is it private?)")
    actions[name] = {
        "assistantDefinedSchemaTraits": [],
        "assistantDefinedSchemas": [],
        "authenticationPolicy": 0,
        "availabilityAnnotations": {"LNPlatformNameWildcard": {"introducedVersion": "*"}},
        "descriptionMetadata": {"descriptionText": text(description), "searchKeywords": []},
        "effectiveBundleIdentifiers": [],
        "fullyQualifiedTypeName": qualified,
        "identifier": name,
        "isAuthPolExplicit": False,
        "isDiscoverable": True,
        "mangledTypeName": mangled,
        "mangledTypeNameByBundleIdentifier": {},
        "mangledTypeNameByBundleIdentifierV2": {},
        "mangledTypeNameV2": mangled,
        "openAppWhenRun": False,
        "outputFlags": 0,
        "parameters": [],
        "presentationStyle": 0,
        "requiredCapabilities": [],
        "supportedModes": 1,
        "systemProtocolMetadata": [],
        "systemProtocolMetadataV2": [],
        "systemProtocols": [],
        "title": text(title),
        "typeSpecificMetadata": [],
        "visibilityMetadata": {"assistantOnly": False, "isDiscoverable": True},
    }

metadata = {
    "actions": actions,
    "assistantEntities": [],
    "assistantIntentNegativePhrases": [],
    "assistantIntents": [],
    "autoShortcuts": [],
    "entities": {},
    "enums": [],
    # The format Xcode 26's tools write, which macOS 14 and later read.
    "generator": {"name": "xcode-tools", "version": "17F42"},
    "negativePhrases": [],
    "queries": {},
    "shortcutTileColor": 14,
    "version": 1,
}
output.mkdir(parents=True, exist_ok=True)
(output / "extract.actionsdata").write_text(json.dumps(metadata, indent=2, sort_keys=True))
(output / "version.json").write_text(json.dumps({"toolsVersion": "17F42", "version": "3.0"}, indent=2))
print(f"{len(actions)} widget actions: " + ", ".join(f"{n} ({by_name[module + '.' + n]})" for n, _, _ in intents))
