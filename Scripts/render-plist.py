#!/usr/bin/env python3
"""Expands the $(VAR) placeholders Xcode's build settings would have supplied."""

import plistlib
import sys

source, destination, *assignments = sys.argv[1:]
values = dict(item.split("=", 1) for item in assignments)


def expand(value):
    if isinstance(value, str):
        for key, replacement in values.items():
            value = value.replace("$(" + key + ")", replacement)
        return value
    if isinstance(value, list):
        return [expand(item) for item in value]
    if isinstance(value, dict):
        return {key: expand(item) for key, item in value.items()}
    return value


with open(source, "rb") as handle:
    plist = plistlib.load(handle)

plist = expand(plist)
for key, replacement in values.items():
    if key in plist and plist[key] == "$(" + key + ")":
        plist[key] = replacement

with open(destination, "wb") as handle:
    plistlib.dump(plist, handle, sort_keys=True)
