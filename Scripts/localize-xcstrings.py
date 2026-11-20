#!/usr/bin/env python3
"""Turns the string catalog into .lproj folders, since xcstringstool ships only with Xcode."""

import json
import os
import plistlib
import re
import sys

catalog, resources = sys.argv[1:]

with open(catalog) as handle:
    data = json.load(handle)

strings = data["strings"]
languages = sorted({lang for entry in strings.values() for lang in entry.get("localizations", {})})

PLURAL = re.compile(r"%(?:\d+\$)?(?:lld|ld|d)")


def flatten(unit):
    """The single value a unit carries, ignoring plural or device variations."""
    if "stringUnit" in unit:
        return unit["stringUnit"].get("value")
    for variation in unit.get("variations", {}).values():
        for candidate in variation.values():
            value = flatten(candidate)
            if value:
                return value
    return None


def escape(value):
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def localized(entry, language):
    return entry.get("localizations", {}).get(language, {})


for language in languages:
    folder = os.path.join(resources, language + ".lproj")
    os.makedirs(folder, exist_ok=True)

    table = {}
    plurals = {}
    for key, entry in strings.items():
        unit = localized(entry, language)
        if not unit:
            continue
        variations = unit.get("variations", {})
        plural = variations.get("plural")
        if plural:
            values = {category: flatten(item) for category, item in plural.items()}
            if values.get("other"):
                plurals[key] = values
            continue
        value = flatten(unit)
        if value:
            table[key] = value

    with open(os.path.join(folder, "Localizable.strings"), "w") as handle:
        for key, value in sorted(table.items()):
            handle.write('"{}" = "{}";\n'.format(escape(key), escape(value)))

    if plurals:
        document = {}
        for key, values in plurals.items():
            match = PLURAL.search(key)
            if not match:
                document[key] = {"NSStringLocalizedFormatKey": values.get("other", key)}
                continue
            format_key = key[: match.start()] + "%#@count@" + key[match.end() :]
            spec = match.group(0)
            kind = spec[-3:] if spec.endswith("lld") else spec[-1]
            entry = {
                "NSStringLocalizedFormatKey": format_key,
                "count": {
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                    "NSStringFormatValueTypeKey": kind,
                },
            }
            for category, value in values.items():
                if value:
                    entry["count"][category] = value
            document[key] = entry
        with open(os.path.join(folder, "Localizable.stringsdict"), "wb") as handle:
            plistlib.dump(document, handle)
