#!/usr/bin/env python3
"""Copies one imageset's file out of the catalog, named the way `Image("…")` asks for it."""

import json
import os
import shutil
import sys

imageset, resources = sys.argv[1:]
name = os.path.basename(imageset).split(".imageset")[0]

with open(os.path.join(imageset, "Contents.json")) as handle:
    contents = json.load(handle)

candidates = [image for image in contents.get("images", []) if image.get("filename")]
if not candidates:
    sys.exit(0)

# A single vector file is the only case a catalog-free bundle can serve faithfully.
filename = candidates[0]["filename"]
source = os.path.join(imageset, filename)
destination = os.path.join(resources, name + os.path.splitext(filename)[1])
shutil.copyfile(source, destination)
