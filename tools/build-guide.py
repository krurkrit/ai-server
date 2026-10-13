#!/usr/bin/env python3
"""Join guide/*.md into ai-server-setup-guide.md, the one-document guide people read and the export uses.

Usage (from anywhere): python tools/build-guide.py [--check]
  --check   change nothing; exit 1 if ai-server-setup-guide.md is out of date

guide/ holds one file per part, joined in file-name order: 00-overview.md, 00-prerequisite.md,
NN-<step>.md for Step NN, 99-design-decisions.md. Edit those files, never the joined guide.
Links inside the parts are written as in the joined guide (repo-root paths, its own #anchors).
The other tools run this first, so the joined guide is always current when they read it.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PARTS = ROOT / "guide"
OUT = ROOT / "ai-server-setup-guide.md"
TITLE = "# Self-Hosted AI Server Setup Guide"
MARK = "<!-- Generated from guide/*.md by tools/build-guide.py: edit those files, not this one. -->"


def parts():
    files = sorted(PARTS.glob("*.md"))
    if not files:
        sys.exit("build-guide: no files in guide/")
    return files


def joined():
    text = "".join(f.read_text(encoding="utf-8").replace("\r\n", "\n") for f in parts())
    if not text.startswith(TITLE + "\n"):
        sys.exit(f"build-guide: guide/00-overview.md must start with '{TITLE}'")
    return TITLE + "\n" + MARK + text[len(TITLE):]


def line_map():
    """(first line in the joined guide, part file) for each part, to point problems at the part."""
    out, line = [], 2   # line 2 is MARK
    for f in parts():
        n = f.read_text(encoding="utf-8").replace("\r\n", "\n").count("\n")
        out.append((line if out else 1, f"guide/{f.name}"))
        line += n
    return out


def main():
    text = joined()
    current = OUT.read_text(encoding="utf-8").replace("\r\n", "\n") if OUT.exists() else ""
    if "--check" in sys.argv:
        if current != text:
            sys.exit("ai-server-setup-guide.md is out of date: run python tools/build-guide.py")
        return
    if current != text:
        OUT.write_text(text, encoding="utf-8", newline="\n")
        print(f"wrote {OUT.name} from {len(parts())} files in guide/")


if __name__ == "__main__":
    main()
