#!/usr/bin/env python3
"""Remove only a marked, owned Brisa snapshot directly below the OS temp dir."""
from pathlib import Path
import os
import re
import shutil
import stat
import sys
import tempfile

snapshot = Path(sys.argv[1])
parent = Path(tempfile.gettempdir()).resolve()
if snapshot.is_symlink() or snapshot.resolve().parent != parent or not re.fullmatch(r"BrisaBuild\.[A-Za-z0-9]{6}", snapshot.name):
    raise SystemExit("Refusing cleanup: not a Brisa temporary snapshot")
attributes = snapshot.stat()
marker = snapshot / ".brisa-build"
if attributes.st_uid != os.getuid() or not stat.S_ISDIR(attributes.st_mode) or stat.S_IMODE(attributes.st_mode) != 0o700:
    raise SystemExit("Refusing cleanup: snapshot ownership or mode changed")
if marker.is_symlink() or marker.read_text() != "Brisa disposable build snapshot v1\n":
    raise SystemExit("Refusing cleanup: missing snapshot marker")
if not shutil.rmtree.avoids_symlink_attacks:
    raise SystemExit("Refusing cleanup: descriptor-based traversal is unavailable")
shutil.rmtree(snapshot)
