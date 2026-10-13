#!/usr/bin/env python3
"""Claude Code PreToolUse hook (Bash): block shell commands that read files agents must not read.

Configured in .claude/settings.json. The Read deny rules there stop the Read and Grep tools; this
closes the same files to cat, grep, sed, and similar commands. Prints nothing unless it blocks
(exit 2, reason on stderr), so it adds nothing to the context of allowed commands.
  ai-server-setup-guide.md   generated from guide/*.md; read the part you need
  outline-export/*.md        generated copy for Outline
  caddy-root-ca.crt          server-specific CA, holds the server name
The repo tools (python tools/...) still read them: they are not shell reads by the agent.
"""
import fnmatch
import json
import re
import shlex
import sys

PROTECTED = re.compile(r'(^|[\s/\'"])(ai-server-setup-guide\.md|outline-export/\S*\.md|caddy-root-ca\.crt)\b')
READERS = {'cat', 'head', 'tail', 'less', 'more', 'sed', 'awk', 'grep', 'egrep', 'rg', 'cut', 'tr', 'od',
           'xxd', 'strings', 'diff', 'cmp', 'type', 'nl', 'wc', 'sort', 'uniq', 'openssl', 'base64'}
GIT_READERS = {'show', 'diff', 'log', 'blame', 'grep', 'cat-file'}


def segments(command):
    """Each simple command of a pipeline or list, as its words."""
    for part in re.split(r'\|\||&&|[|;&\n]', command):
        try:
            words = shlex.split(part, posix=True)
        except ValueError:
            words = part.split()
        while words and re.match(r'^\w+=', words[0]):   # leading VAR=value assignments
            words = words[1:]
        if words:
            yield words


PROTECTED_PATH = re.compile(r'(.*/)?(ai-server-setup-guide\.md|caddy-root-ca\.crt|outline-export/.*\.md)')
PROTECTED_NAMES = ['ai-server-setup-guide.md', 'caddy-root-ca.crt', 'outline-export/x.md',
                   'outline-export/options/x.md']
# Commands whose first operand is a pattern or a script, not a file: `grep NAME file` only searches for NAME
PATTERN_FIRST = {'grep', 'egrep', 'rg', 'sed', 'awk'}


def operands(name, args):
    """The file arguments: options, option values, and a leading pattern or script left out."""
    out, skip, explicit = [], False, False
    for word in args:
        if skip:
            skip = False
            continue
        if word in ('-e', '--regexp', '-f', '--file', '--expression'):
            skip, explicit = True, True
            continue
        if word.startswith('-'):
            continue
        out.append(word)
    if name in PATTERN_FIRST and not explicit and out:
        out = out[1:]
    return out


def is_protected(word):
    word = word.replace('\\', '/').lstrip('./') if word.startswith('./') else word.replace('\\', '/')
    if PROTECTED_PATH.fullmatch(word):
        return True
    # a glob that would expand to a protected file: cat *.md, head outline-export/*
    return any(c in word for c in '*?[') and any(fnmatch.fnmatch(n, word) for n in PROTECTED_NAMES)


def reads_protected(command):
    if not (PROTECTED.search(command) or re.search(r'[*?\[]', command)):
        return False
    for words in segments(command):
        name = words[0].rsplit('/', 1)[-1]
        if name == 'git':
            if len(words) > 1 and words[1] in GIT_READERS:
                args = operands('grep' if words[1] == 'grep' else 'git', words[2:])
                if any(is_protected(w) for w in args):
                    return True
            continue
        if name in READERS and any(is_protected(w) for w in operands(name, words[1:])):
            return True
    # input redirected from a protected file: `python - < ai-server-setup-guide.md`
    return bool(re.search(r'<\s*[\'"]?(\S*/)?(ai-server-setup-guide\.md|outline-export/\S*\.md|caddy-root-ca\.crt)', command))


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    command = (event.get('tool_input') or {}).get('command', '')
    if reads_protected(command):
        print('Blocked: this reads a generated or server-specific file. Read the source instead: '
              'guide/NN-*.md for the guide, options/*.md for the export; leave caddy-root-ca.crt alone.',
              file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
