#!/usr/bin/env python3
"""Claude Code Stop hook: run tools/check.py before the agent finishes, and send back only the problems.

Configured in .claude/settings.json. Silent when the check passes. Skips the run when nothing changed
since the last passing run (a hash of git diff and the untracked files is kept in .git/), and never
blocks twice in a row (stop_hook_active), so an agent that cannot fix a problem is not stuck in a loop.
Exit 2 with the problems on stderr asks the agent to fix them before it stops.
"""
import hashlib
import json
import os
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True).stdout


def state():
    """Changed tracked files (diff) plus the content of untracked ones, which git diff leaves out."""
    h = hashlib.sha256((git('status', '--porcelain', '--untracked-files=all') + git('diff')).encode())
    for rel in git('ls-files', '--others', '--exclude-standard').splitlines():
        try:
            with open(os.path.join(ROOT, rel), 'rb') as f:
                h.update(rel.encode() + f.read())
        except OSError:
            pass
    return h.hexdigest()


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        event = {}
    if event.get('stop_hook_active'):
        return 0
    if not git('status', '--porcelain').strip():
        return 0
    digest = state()
    stamp = os.path.join(ROOT, '.git', 'stop-check-passed')
    try:
        if open(stamp).read().strip() == digest:
            return 0
    except OSError:
        pass
    env = {k: v for k, v in os.environ.items() if k not in ('SERVER_HOST', 'SERVER_IP')}
    r = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'check.py')], cwd=ROOT,
                       capture_output=True, text=True, env=env)
    if r.returncode == 0:
        # the check may rebuild generated files; remember the state after it ran
        digest = state()
        try:
            with open(stamp, 'w') as f:
                f.write(digest)
        except OSError:
            pass
        return 0
    problems = [l for l in r.stdout.splitlines() if l.strip() and not l.startswith('wrote ')]
    print('tools/check.py found problems; fix them before finishing:\n' + '\n'.join(problems[-40:]),
          file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main())
