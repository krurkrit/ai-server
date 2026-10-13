"""Check the repo against the rules agents must follow before finishing a change.
Run from anywhere: python tools/check.py   (exit 1 when something fails)
First time: python -m pip install -r tools/requirements.txt

Covers what can be checked mechanically. Still by hand: the diagrams match what the guide wires up,
and no step edits an earlier step's file."""
import glob
import os
import re
import shutil
import subprocess
import sys
import textwrap

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
DOCS = ['ai-server-setup-guide.md', 'ai-setup-for-software-development.md'] + sorted(
    os.path.relpath(p, ROOT).replace('\\', '/') for p in glob.glob(os.path.join(ROOT, 'options', '*.md')))
SCRIPTS = sorted(glob.glob(os.path.join(ROOT, 'scripts', '*.sh')))
# IP addresses allowed in the docs: placeholders for "any" and loopback, and the private
# example networks the guide uses on purpose
IP_OK = re.compile(r'^(0\.0\.0\.0|127\.0\.0\.1|192\.168\.1\.0|10\.0\.0\.0)$')
DESTRUCTIVE = re.compile(r'(\brm -rf\b|\bdocker volume rm\b|\bdocker (image )?rm -f\b|\bdocker rmi\b|'
                         r'\bvolume prune\b|\bsystem prune\b|\bufw disable\b|\bdropdb\b)')
failures = []
G, S = 'docs/agents/guide.md', 'docs/agents/scripts.md'


def fail(where, msg, rule=None):
    """rule: the doc that explains the rule, so the fix is one read away"""
    failures.append(f'{where}: {msg}' + (f'  [see {rule}]' if rule else ''))


def read(rel):
    return open(os.path.join(ROOT, rel), encoding='utf-8').read()


def slug(h):
    h = h.strip().lower()
    h = re.sub(r'[^\w\- ]', '', h)
    return h.replace(' ', '-')


def anchors(text):
    """Heading anchors as GitHub makes them, duplicates numbered -1, -2, ..."""
    seen, out, in_code = {}, set(), False
    for line in text.splitlines():
        if line.startswith('```'):
            in_code = not in_code
        if in_code or not line.startswith('#'):
            continue
        m = re.match(r'^#+\s+(.*)$', line)
        if not m:
            continue
        a = slug(m.group(1))
        n = seen.get(a, 0)
        out.add(a if n == 0 else f'{a}-{n}')
        seen[a] = n + 1
    return out


# ---- documents
for rel in DOCS:
    text = read(rel)
    in_code, lang, h2 = False, '', None
    for no, line in enumerate(text.splitlines(), 1):
        where = f'{rel}:{no}'
        stripped = line.strip()
        if stripped.startswith('```'):
            in_code = not in_code
            lang = stripped[3:].strip() if in_code else ''
            continue
        if in_code:
            if re.search(r'\bStep \d', line):
                fail(where, '"Step N" inside a code block (name the service or file instead)', G)
            if re.search(r"[A-Za-z]'[a-z]", line):
                fail(where, 'apostrophe inside a code block (write "does not", "of the")', G)
            if lang in ('bash', 'sh') and DESTRUCTIVE.search(line) and 'confirm' not in line:
                fail(where, 'destructive command without confirm on the same line (confirm "..." && cmd)', S)
            continue
        if re.match(r'^\s*- \[[ xX]\] ', line):
            fail(where, 'checklist item: make it a script check (server-test.sh) or a numbered Test item', G)
        m = re.match(r'^(#{2,4}) (.*)$', line)
        if m:
            level, title = len(m.group(1)), m.group(2)
            limit = 32 - 2 * (level - 2)
            if len(title) > limit:
                fail(where, f'H{level} longer than {limit} characters: "{title}"', G)
        for ip in re.findall(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', line):
            if not IP_OK.match(ip):
                fail(where, f'IP address {ip}: use ${{SERVER_IP}} or a generic example', 'AGENTS.md')
    # links to option pages and anchors
    base = os.path.dirname(rel)
    own = anchors(text)
    guide_anchors = anchors(read('ai-server-setup-guide.md'))
    for target, frag in re.findall(r'\]\(([^)#\s]*\.md)?(?:#([^)\s]+))?\)', text):
        if not target and not frag:
            continue
        if target:
            path = os.path.normpath(os.path.join(ROOT, base, target))
            if not os.path.exists(path):
                fail(rel, f'link to a missing file: {target}')
                continue
            if frag:
                name = os.path.relpath(path, ROOT).replace('\\', '/')
                if frag not in anchors(read(name)):
                    fail(rel, f'link to a missing heading: {target}#{frag}')
        elif frag not in own:
            fail(rel, f'link to a missing heading: #{frag}')
    if rel.startswith('options/'):
        if not text.startswith('# Option: '):
            fail(rel, 'must start with "# Option: <Title>"', G)
        if '\n---\n\n**Related:**\n' not in text:
            fail(rel, 'no Related list at the end (run python tools/update-option-related.py)', G)

# ---- scripts
bash = shutil.which('bash')
for path in SCRIPTS:
    rel = os.path.relpath(path, ROOT).replace('\\', '/')
    text = open(path, encoding='utf-8').read()
    if not text.startswith('#!/usr/bin/env bash\n# NAME\n'):
        fail(rel, 'no manual header (shebang, then "# NAME")', S)
    if '-h / --help' not in text:
        fail(rel, 'no -h / --help snippet', S)
    if re.search(r'^SCRIPT_EOF$', text, re.M) or '```' in text:
        fail(rel, 'contains SCRIPT_EOF or ``` (breaks the Outline export)', S)
    for no, line in enumerate(text.splitlines(), 1):
        if re.search(r'\bStep \d', line):
            fail(f'{rel}:{no}', '"Step N" in a script', S)
        if re.search(r"[A-Za-z]'[a-z]", line) and line.lstrip().startswith('#'):
            fail(f'{rel}:{no}', 'apostrophe in a comment', S)
    if bash:
        r = subprocess.run([bash, '-n', path], capture_output=True, text=True)
        if r.returncode:
            fail(rel, 'bash -n: ' + (r.stderr.strip() or 'syntax error'))
if not bash:
    fail('scripts', 'bash not found; bash -n not run')

# ---- ports: every host port has one owner across the guide and the option pages
# Published ports come from compose `ports:` lists (commented-out ones too: uncommenting publishes them),
# owned by the service the list belongs to. Caddy sites are owned by the file they are written to.
# Alternatives that rewrite the same service or Caddy file share an owner, so they never clash.
P = 'docs/agents/caddy-and-ports.md'
published, sites = {}, {}
for rel in DOCS:
    in_code, lang, keys, target = False, '', [], None
    in_ports = None
    for no, line in enumerate(read(rel).splitlines(), 1):
        where = f'{rel}:{no}'
        stripped = line.strip()
        if stripped.startswith('```'):
            in_code = not in_code
            lang, keys, target, in_ports = (stripped[3:].strip() if in_code else ''), [], None, None
            continue
        if not in_code:
            continue
        m = re.search(r'cat > (\S+\.caddy|\S*Caddyfile)\b', line)
        if m:
            target = m.group(1)
        elif lang == 'caddy' and target is None:
            target = 'Caddyfile'
        if stripped.startswith('https://') and stripped.endswith('{') and '<' not in stripped:   # skip templates
            for addr in stripped[:-1].split(','):
                port = re.search(r'\}:(\d+)$', addr.strip())
                sites.setdefault(int(port.group(1)) if port else 443, []).append((target or where, where))
            continue
        if lang not in ('yaml', 'yml'):
            continue
        yl = re.sub(r'^(\s*)# ?', r'\1', line)   # read commented-out lines as if uncommented
        if yl != line and not re.match(r'^\s*(-\s|[\w.-]+:(\s|$))', yl):
            continue                             # a plain comment, not commented-out YAML
        m = re.match(r'^(\s*)([\w.-]+):\s*(#.*)?$', yl)
        if m:
            indent = len(m.group(1))
            keys = [k for k in keys if k[0] < indent]
            if m.group(2) == 'ports':
                in_ports = (indent, keys[-1][1] if keys else where)
            else:
                in_ports = None
                keys.append((indent, m.group(2)))
            continue
        if in_ports:
            p = re.match(r'^\s*-\s*"?(?:[\d.]+:)?(\d+)(?:-(\d+))?:\d+', yl)
            if p:
                lo = int(p.group(1))
                for port in range(lo, int(p.group(2) or lo) + 1):
                    published.setdefault(port, []).append((in_ports[1], where))
            elif yl.strip() and not yl.strip().startswith('-'):
                in_ports = None
for kind, table in (('published by', published), ('served by the Caddy sites in', sites)):
    for port, owners in sorted(table.items()):
        names = sorted({o for o, _ in owners})
        if len(names) > 1:
            first = {o: w for o, w in reversed(owners)}
            fail(f'port {port}', f'{kind} more than one: ' + ', '.join(f'{n} ({first[n]})' for n in names), P)
for port, owners in sorted(sites.items()):
    if 'caddy' not in {o for o, _ in published.get(port, [])}:
        fail(owners[0][1], f'Caddy serves port {port} but the caddy service does not publish it '
                           '(add it to the Caddy ports list)', P)

# ---- YAML: every yaml code block parses, with no tabs and no repeated key in one mapping
# (PyYAML keeps the last of two equal keys without a word; Docker Compose refuses the file)
try:
    import yaml

    class NoDuplicates(yaml.SafeLoader):
        def construct_mapping(self, node, deep=False):
            seen = set()
            for key_node, _ in node.value:
                if key_node.tag == 'tag:yaml.org,2002:merge':
                    continue                     # << merge keys; overriding a merged key is fine
                key = self.construct_object(key_node, deep=deep)
                if key in seen:
                    raise yaml.constructor.ConstructorError(
                        None, None, f'key "{key}" appears twice in one mapping', key_node.start_mark)
                seen.add(key)
            return super().construct_mapping(node, deep)
except ImportError:
    yaml = None
    fail('yaml', 'PyYAML not installed (python -m pip install -r tools/requirements.txt); YAML blocks not checked')
if yaml:
    C = 'docs/agents/compose.md'
    for rel in DOCS:
        text = read(rel)
        for m in re.finditer(r'^([ \t]*)```ya?ml[^\n]*\n(.*?)^\1```', text, re.M | re.S):
            first = text[:m.start()].count('\n') + 2   # file line of the block's first line
            body = textwrap.dedent(m.group(2))
            for i, line in enumerate(body.splitlines()):
                if '\t' in line[:len(line) - len(line.lstrip())]:
                    fail(f'{rel}:{first + i}', 'tab in YAML indentation (use spaces)', C)
            try:
                for _ in yaml.load_all(body, Loader=NoDuplicates):
                    pass
            except yaml.YAMLError as e:
                mark = getattr(e, 'problem_mark', None) or getattr(e, 'context_mark', None)
                at = f'{rel}:{first + mark.line}' if mark else rel
                fail(at, 'YAML does not parse: ' + (getattr(e, 'problem', None) or str(e).splitlines()[0]), C)

# ---- knowledge base: AGENTS.md stays a map, every topic doc is reachable and summarised
agents = read('AGENTS.md')
if len(agents.splitlines()) > 60:
    fail('AGENTS.md', f'{len(agents.splitlines())} lines; keep it a map under 60, move detail to docs/agents/')
def rels(*parts):
    return sorted(os.path.relpath(p, ROOT).replace(os.sep, '/') for p in glob.glob(os.path.join(ROOT, *parts)))


for rel in rels('docs', 'agents', '*.md'):
    lines = read(rel).splitlines()
    if f']({rel})' not in agents:
        fail(rel, 'not linked from AGENTS.md "Read before editing"', 'AGENTS.md')
    if len(lines) < 3 or not lines[0].startswith('# ') or lines[1] or not lines[2] or lines[2].startswith('#'):
        fail(rel, 'needs a one-line summary right under the title', 'AGENTS.md')
for rel in ['AGENTS.md', 'CLAUDE.md'] + rels('docs', 'agents', '*.md') + rels('.claude', 'rules', '*.md'):
    text = read(rel)
    # markdown links resolve from the file; `path/file.ext` mentions resolve from the repo root
    prose = re.sub(r'```.*?```|`[^`\n]*`', '', text, flags=re.S)
    refs = [os.path.join(os.path.dirname(rel), r) for r in re.findall(r'\]\(([^)#\s]+)', prose) if not r.startswith('http')]
    refs += re.findall(r'`((?:docs|tools|scripts|options|diagrams)/[\w./-]+\.\w+)`', text)
    for ref in refs:
        if '*' not in ref and not os.path.exists(os.path.normpath(os.path.join(ROOT, ref))):
            fail(rel, f'points to a missing file: {ref}', 'AGENTS.md')
    if rel.startswith('.claude/rules/'):
        for glob_pat in re.findall(r'^  - "([^"]+)"', text, re.M):
            if not glob.glob(os.path.join(ROOT, glob_pat), recursive=True):
                fail(rel, f'paths: entry matches no file: {glob_pat}', 'AGENTS.md')

# ---- generated files
for cmd, what in (([sys.executable, os.path.join(ROOT, 'tools', 'update-option-related.py'), '--check'], 'Related lists'),
                  ([sys.executable, os.path.join(ROOT, 'tools', 'build-outline-export.py')], 'Outline export')):
    # Without SERVER_HOST / SERVER_IP, so the export in the repo stays generic
    env = {k: v for k, v in os.environ.items() if k not in ('SERVER_HOST', 'SERVER_IP')}
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT, env=env)
    if r.returncode:
        fail(what, (r.stdout + r.stderr).strip().splitlines()[-1])

if failures:
    print('\n'.join(failures))
    print(f'\n{len(failures)} problem(s). Fix each as its [see ...] doc says; if the rule itself changed, '
          'update that doc and this check together.')
    sys.exit(1)
print('OK: docs, scripts, agent knowledge base, Related lists, and the Outline export pass. '
      'By hand: diagrams match the guide; no step edits an earlier step\'s file.')
