"""Rewrite the Related list at the end of every options/*.md: the guide sections
(and subsections) and other option pages that link to it. Run after changing
where the guide links an option: python tools/update-option-related.py
With --check, change nothing and exit 1 if a list is out of date (used by tools/check.py)."""
import re, glob, os, subprocess, sys
CHECK = '--check' in sys.argv
stale = []
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '')
# The guide is joined from guide/*.md; join it first so this reads the current text
subprocess.run([sys.executable, ROOT + 'tools/build-guide.py'], check=True)
guide = open(ROOT + 'ai-server-setup-guide.md', encoding='utf-8').read()


def slug(h):
    h = h.strip().lower()
    h = re.sub(r'[^\w\- ]', '', h)
    return h.replace(' ', '-')


# where each option is linked from in the guide: (H2, H3)
refs = {}
h2 = h3 = None
in_code = False
for line in guide.splitlines():
    if line.startswith('```'):
        in_code = not in_code
        continue
    if in_code:
        continue
    if line.startswith('## '):
        h2, h3 = line[3:].strip(), None
        continue
    if line.startswith('### '):
        h3 = line[4:].strip()
        continue
    for f in re.findall(r'\]\(options/([\w\-]+)\.md', line):
        lst = refs.setdefault(f, [])
        if (h2, h3) not in lst:
            lst.append((h2, h3))

titles = {}
for p in glob.glob(ROOT + 'options/*.md'):
    name = os.path.basename(p)[:-3]
    first = open(p, encoding='utf-8').readline()
    titles[name] = first[2:].strip()

# option-to-option links
orefs = {}
for p in glob.glob(ROOT + 'options/*.md'):
    src = os.path.basename(p)[:-3]
    t = open(p, encoding='utf-8').read()
    t = t.split('\n---\n\n**Related:**')[0]
    for f in set(re.findall(r'\]\(([\w\-]+)\.md', t)):
        if f != src:
            orefs.setdefault(f, []).append(src)

for p in sorted(glob.glob(ROOT + 'options/*.md')):
    name = os.path.basename(p)[:-3]
    t = open(p, encoding='utf-8').read()
    t = t.split('\n---\n\n**Related:**')[0].rstrip('\n') + '\n'
    items = []
    groups = {}
    for a, b in refs.get(name, []):
        groups.setdefault(a, [])
        if b and b not in groups[a]:
            groups[a].append(b)
    for a, subs in groups.items():
        link = f'[{a}](../ai-server-setup-guide.md#{slug(a)})'
        items.append(f'- {link} → {", ".join(subs)}' if subs else f'- {link}')
    for src in sorted(set(orefs.get(name, []))):
        items.append(f'- [{titles[src]}]({src}.md)')
    assert items, name
    t += '\n---\n\n**Related:**\n' + '\n'.join(items) + '\n'
    if CHECK:
        if open(p, encoding='utf-8').read() != t:
            stale.append(name)
        continue
    open(p, 'w', encoding='utf-8', newline='\n').write(t)
    print(name, len(items))

if CHECK and stale:
    print('Related lists out of date: ' + ', '.join(stale) + ' (run python tools/update-option-related.py)')
    sys.exit(1)
