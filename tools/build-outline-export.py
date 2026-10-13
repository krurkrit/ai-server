#!/usr/bin/env python3
"""Build the Outline export from the guide, its option files, and the repo's scripts.

Usage (from the repo root): python tools/build-outline-export.py

outline-export/ai-server-setup-guide.md is the guide with:
  - the H1 title replaced by a note (Outline takes the title from the document name),
  - each SVG diagram replaced by a "drag the PNG here" placeholder,
  - "copy from this repo" instructions pointing at the appendix instead,
  - links to options/*.md replaced by the name of that option's own Outline document,
  - an "Appendix: Scripts" section, where each script is a paste-ready heredoc block.
Each options/*.md is exported to outline-export/options/ as its own document, to import next to
(or under) the guide, with the same link handling.
Fails loudly if the guide's wording no longer matches, so the export never silently drifts.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GUIDE = ROOT / "ai-server-setup-guide.md"
OUT = ROOT / "outline-export" / "ai-server-setup-guide.md"
OPTIONS = ROOT / "options"
OPTIONS_OUT = ROOT / "outline-export" / "options"
GUIDE_TITLE = "Self-Hosted AI Server Setup Guide"
DEV = ROOT / "ai-setup-for-software-development.md"
DEV_OUT = ROOT / "outline-export" / "ai-setup-for-software-development.md"
DEV_TITLE = "AI setup for software development"

# (script, directory it lives in on the server), in the order the guide first uses them
SCRIPTS = [
    ("server-status.sh", "~/ai-server"),
    ("server-test.sh", "~/ai-server"),
    ("sync-shared-env.sh", "~/ai-server"),
    ("docker-veth-name.sh", "~/ai-server"),
    ("pull-secrets.sh", "~/ai-server"),
    ("switch-llm.sh", "~/ai-server"),
    ("graphdb.sh", "~/ai-server"),
    ("update-stack.sh", "~/ai-server"),
    ("restore-stack.sh", "~/ai-server"),
    ("backup-config.sh", "~/ai-server"),
    ("reset-stack.sh", "~/ai-server"),
    ("docker-cleanup.sh", "~/ai-server"),
]

DIAGRAMS = {
    "architecture-access-map": "access and entry points",
    "architecture-ai-pipeline": "AI pipeline and data flow",
}
DEV_DIAGRAMS = {
    "development-workflow": "software development workflow",
}

# Optional: the real server name and IP, from the environment, filled into the export so commands
# and addresses in Outline are ready to use. Unset (the default, and what tools/check.py uses), the
# export keeps the placeholders and stays generic.
SERVER = {k: os.environ.get(k, "").strip() for k in ("SERVER_HOST", "SERVER_IP")}

TITLE = "# " + GUIDE_TITLE
NOTE = ("*Copied from `ai-server-setup-guide.md` in the ai-server repo. "
        "The helper scripts are at the end, under **Appendix: Scripts**; "
        "each option is its own document (see the `options` folder of the export).*")

# Exact text in the guide -> export text. Each must match exactly once.
REPLACEMENTS = [
    ("2. On your PC, in this repo's folder, copy all scripts from this repo (its `scripts` folder) to it:\n"
     "   ```bash\n"
     "   scp scripts/*.sh <user>@${SERVER_HOST}:ai-server/\n"
     "   ```\n",
     "2. Paste each block from Appendix: Scripts into a shell on the server; each writes its script into "
     "`~/ai-server`.\n"),
]

DELIM = "SCRIPT_EOF"


def fail(msg):
    sys.exit(f"build-outline-export: {msg}")


def appendix():
    parts = [
        "## Appendix: Scripts",
        "",
        "Paste each block into a shell on the server. It writes the script and makes it executable. "
        f"The quoted `'{DELIM}'` keeps the shell from expanding anything while pasting, "
        "so the file lands exactly as shown.",
    ]
    for name, where in SCRIPTS:
        body = (ROOT / "scripts" / name).read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n")
        if re.search(rf"^{DELIM}$", body, re.M):
            fail(f"{name} contains a line equal to the heredoc delimiter {DELIM}")
        if "```" in body:
            fail(f"{name} contains ``` and would break the code block")
        path = f"{where}/{name}"
        block = ["", f"### {name}", "", "```bash"]
        if where != "~":
            block.append(f"mkdir -p {where}")
        block += [f"cat > {path} <<'{DELIM}'", body, DELIM, f"chmod +x {path}", "```"]
        parts += block
    return "\n".join(parts) + "\n"


def check_server():
    host, ip = SERVER["SERVER_HOST"], SERVER["SERVER_IP"]
    if host and not re.fullmatch(r"[A-Za-z0-9.-]+", host):
        fail(f"SERVER_HOST={host!r} is not a host name")
    if ip and not re.fullmatch(r"(\d{1,3}\.){3}\d{1,3}", ip):
        fail(f"SERVER_IP={ip!r} is not an IPv4 address")


def fill_server(text):
    """Put the real server name and IP in place of the placeholders, where the reader would type them:
    <SERVER_HOST> / <SERVER_IP> everywhere (they are always filled in by hand), and ${SERVER_HOST} /
    ${SERVER_IP} in prose and shell commands. In compose, .env, and config files, and in files a
    shell heredoc writes, ${...} stays: there it is a variable the file reads from its .env."""
    if not any(SERVER.values()):
        return text
    out, fence, heredoc = [], None, None
    for line in text.split("\n"):
        m = re.match(r"^\s*```(\S*)", line)
        if m:
            fence, heredoc = (m.group(1) if fence is None else None), None
        elif heredoc is not None:
            if line.strip() == heredoc:
                heredoc = None
        elif fence in ("bash", "sh", ""):
            h = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", line)
            if h:
                heredoc = h.group(1)
        shell = fence is None or (fence in ("bash", "sh", "") and heredoc is None)
        for key, value in SERVER.items():
            if value:
                line = line.replace(f"<{key}>", value)
                if shell:
                    line = line.replace("${" + key + "}", value)
        out.append(line)
    return "\n".join(out)


def diagrams(text, names):
    for name, what in names.items():
        text, n = re.subn(rf"^!\[[^\]]*\]\(diagrams/{name}\.svg\)$",
                          f"*Diagram: {what} — drag `{name}.png` here.*", text, flags=re.M)
        if n != 1:
            fail(f"expected 1 image line for {name}.svg, found {n}")
    if re.search(r"\]\(diagrams/", text):
        fail("an image in diagrams/ has no entry in DIAGRAMS or DEV_DIAGRAMS")
    return text


def option_titles():
    """Map each options/<file>.md to its H1 title, which is also its Outline document name."""
    titles = {}
    for f in sorted(OPTIONS.glob("*.md")):
        first = f.read_text(encoding="utf-8").split("\n", 1)[0]
        if not first.startswith("# "):
            fail(f"options/{f.name} must start with an H1 title")
        titles[f.name] = first[2:].strip()
    return titles


def plain_links(text, titles, prefix):
    """Links between repo files don't resolve in Outline; name the target document instead."""
    def to_option(m):
        name = m.group(2)
        if name not in titles:
            fail(f"link to a missing option file: {prefix}{name}")
        return f'**{m.group(1)}** (document "{titles[name]}")'

    text = re.sub(r"\[([^\]]+)\]\(" + re.escape(prefix) + r"([a-z0-9-]+\.md)(?:#[^)]*)?\)", to_option, text)
    text = re.sub(r"\[([^\]]+)\]\((?:\.\./)?ai-server-setup-guide\.md(?:#[^)]*)?\)",
                  lambda m: f'{m.group(1)} (document "{GUIDE_TITLE}")', text)
    text = re.sub(r"\[([^\]]+)\]\((?:\.\./)?ai-setup-for-software-development\.md(?:#[^)]*)?\)",
                  lambda m: f'{m.group(1)} (document "{DEV_TITLE}")', text)
    if re.search(r"\]\([^)]*\.md", text):
        fail("a link to a .md file has no export rule")
    return text


def export_options(titles):
    OPTIONS_OUT.mkdir(parents=True, exist_ok=True)
    for old in OPTIONS_OUT.glob("*.md"):
        old.unlink()
    for name, title in titles.items():
        text = (OPTIONS / name).read_text(encoding="utf-8").replace("\r\n", "\n")
        note = (f"*Copied from `options/{name}` in the ai-server repo; "
                f"import it as a document named \"{title}\".*")
        text = note + text[text.index("\n"):]
        text = fill_server(plain_links(text, titles, ""))
        (OPTIONS_OUT / name).write_text(text.rstrip("\n") + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {OPTIONS_OUT.relative_to(ROOT)}/ ({len(titles)} option documents)")


def main():
    # The guide is joined from guide/*.md; join it first so the export reads the current text
    subprocess.run([sys.executable, str(ROOT / "tools" / "build-guide.py")], check=True)
    text = GUIDE.read_text(encoding="utf-8").replace("\r\n", "\n")
    titles = option_titles()

    if not text.startswith(TITLE + "\n"):
        fail(f"guide doesn't start with '{TITLE}'")
    text = NOTE + re.sub(r"^\n<!-- Generated from guide/.*?-->", "", text[len(TITLE):], count=1)

    check_server()
    text = diagrams(text, DIAGRAMS)

    for old, new in REPLACEMENTS:
        n = text.count(old)
        if n != 1:
            fail(f"expected 1 match, found {n}: {old[:70]}…")
        text = text.replace(old, new)

    text = plain_links(text, titles, "options/")

    if "from this repo" in text:
        fail("a 'from this repo' reference has no export replacement; add one to REPLACEMENTS")

    text = fill_server(text)
    OUT.write_text(text.rstrip("\n") + "\n\n" + appendix(), encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)}")
    export_options(titles)
    export_dev(titles)
    filled = ", ".join(f"{k}={v}" for k, v in SERVER.items() if v)
    if filled:
        print(f"filled in {filled}: this export is for your server only; do not share or commit it. "
              "Run without these variables for the generic export.")


def export_dev(titles):
    """The team guide: its own Outline document, links named like the others."""
    text = DEV.read_text(encoding="utf-8").replace("\r\n", "\n")
    if not text.startswith("# " + DEV_TITLE + "\n"):
        fail(f"{DEV.name} must start with '# {DEV_TITLE}'")
    text = ("*Copied from `ai-setup-for-software-development.md` in the ai-server repo.*"
            + text[len("# " + DEV_TITLE):])
    text = fill_server(plain_links(diagrams(text, DEV_DIAGRAMS), titles, "options/"))
    DEV_OUT.write_text(text.rstrip("\n") + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {DEV_OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
