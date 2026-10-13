# Agent Smith Analysis

**Project:** ai-server
**Type:** Documentation repo (Markdown guide, Bash helper scripts, Python tooling)
**Score:** 9.2/10 (— unchanged since 2026-10-13, previous run)
**Date:** 2026-10-13

---

## Summary

Every finding from the last run is fixed: subfolder `.env` files are denied, and your memory now has the current step numbers, sign-in choice, SERVER_HOST and link slugs. `tools/check.py` passes. Two small things remain: the shell-read guard blocks a bare `*.md` glob even outside the repo, and your memory's port list is missing two newer slots.

---

## Pillar Scores

| Pillar | Score | Notes |
|--------|:-----:|-------|
| Security Posture | 9/10 | Thorough deny list (27 rules, `.env` at any depth); server access (ssh/scp/docker/git push) denied |
| Instruction Clarity | 9/10 | Map plus topic docs, one rule in one place, no volatile markers |
| Configuration Quality | 10/10 | Valid JSON with `$schema`, exact-command allows, no broad patterns |
| Context Efficiency | 9/10 | ~1.5K tokens always loaded; generated copies excluded by `.claudeignore`, `.ignore`, deny rules and a hook |
| Command & Extension Design | 9/10 | Five thin path-scoped rules; no commands, agents or skills (none needed) |
| Hook Safety | 9/10 | Both hooks have timeouts, are silent on success, and the Stop hook cannot loop (`stop_hook_active`) |
| MCP Integration | N/A | No project MCP servers |

---

## Findings

### Critical (breaks functionality or security risk)
- None.

### Important (affects efficiency or maintainability)
- None.

### Suggestions (improvements, not problems)
- **The shell-read guard blocks a bare `*.md` glob in any folder** (`tools/block-shell-reads.py`, `is_protected`). It matches the glob against the protected names without knowing the folder, so `grep x *.md` run in another folder (here, the memory folder) is blocked. In the repo root this is correct, since `*.md` would include `ai-server-setup-guide.md`. Outside the repo it is a false positive. It is harmless, but it costs a retry.
- **Your local memory's port list is out of date** (`architecture_decisions.md`, "Port scheme"). It lists AI Agents at 9480. `docs/agents/caddy-and-ports.md` now marks 9480 free (OpenHands stays on port 3000) and adds AI Chat 9485 (Open WebUI) and App monitoring 9475 (GlitchTip, option).

---

## Action Plan

### Option A: Quick Wins (Low Effort)

| # | Action |
|---|--------|
| A1 | Add `Read(./**/.env)` and `Read(./**/.env.*)` to the deny list in `.claude/settings.json` |
| A2 | Fix the memory files: step numbers, the Dex sign-in, SERVER_HOST (keep only the current value), and the wiki-link slugs |

### Option B: Recommended (Medium Effort)

| # | Action |
|---|--------|
| — | None needed |

### Option C: Advanced (High Effort)

| # | Action |
|---|--------|
| — | None needed |

---

## .claudeignore Status

| Check | Status |
|-------|:------:|
| File exists | ✓ |
| `.git/` included | ✓ |
| Covers .gitignore patterns | ✓ |
| Large binaries excluded | N/A (only diagram PNGs, kept visible on purpose) |

---

## Hooks Status

| Hook Event | Command | Safe? |
|------------|---------|:-----:|
| PreToolUse (Bash) | `tools/block-shell-reads.py`, timeout 10 s; blocks shell reads of generated or server-specific files, prints nothing otherwise | ✓ |
| Stop | `tools/stop-check.py`, timeout 180 s; runs `tools/check.py`, skips when nothing changed, never blocks twice in a row | ✓ |

Neither hook injects dynamic content into the prompt, and neither writes to `CLAUDE.md`. The guard can block a bare `*.md` glob outside the repo (see Suggestions).

---

## MCP Status

No project MCP servers configured (not required).

---

## Wiring Status

| Check | Status | Details |
|-------|:------:|---------|
| Cross-references valid | ✓ | Every `docs/agents/*.md` and `AGENTS.md` reference in the five rules exists; `tools/check.py` also checks the knowledge-base links |
| No stale references | ✓ | None |
| No orphaned extensions | ✓ | No commands, agents or skills |
| No context conflicts | N/A | No contexts |
| Bidirectional consistency | N/A | No routing tables |

---

## Memory Status

| Check | Status | Details |
|-------|:------:|---------|
| Memory directory found | ✓ | `~/.claude/projects/C--Workspace-Private-Github-ai-server/memory/` |
| Memory files count | — | 4 files indexed in `MEMORY.md` |
| Conflicts with config | ⚠ | 1 (port list in `architecture_decisions.md`) |
| Stale references | ✓ | Wiki-links match the `name:` slugs |

- **Stale:** `architecture_decisions.md` lists AI Agents 9480 and lacks 9485 (AI Chat) and 9475 (GlitchTip).

> **Note:** Memory files are personal (not committed to the repo). These findings help keep your local memory aligned with the project.

---

## Content Overview

### File Inventory

| File | Lines | Characters | Est. Tokens |
|------|------:|----------:|-----------:|
| `CLAUDE.md` | 3 | 219 | ~55 |
| `AGENTS.md` | 57 | 5,385 | ~1,350 |
| `.claude/rules/agent-docs.md` | 6 | 131 | ~35 |
| `.claude/rules/diagrams.md` | 6 | 154 | ~40 |
| `.claude/rules/guide.md` | 8 | 473 | ~120 |
| `.claude/rules/scripts.md` | 6 | 108 | ~30 |
| `.claude/rules/tools.md` | 6 | 307 | ~75 |
| `docs/agents/caddy-and-ports.md` | 43 | 3,756 | ~940 |
| `docs/agents/compose.md` | 51 | 7,828 | ~1,960 |
| `docs/agents/decisions.md` | 27 | 5,414 | ~1,350 |
| `docs/agents/diagrams.md` | 56 | 3,536 | ~880 |
| `docs/agents/guide.md` | 55 | 7,640 | ~1,910 |
| `docs/agents/guide-structure.md` | 56 | 8,174 | ~2,040 |
| `docs/agents/known-gaps.md` | 28 | 2,810 | ~700 |
| `docs/agents/scripts.md` | 40 | 5,374 | ~1,340 |

### Totals

| Category | Files | Est. Tokens | % of User Content |
|----------|------:|------------:|------------------:|
| Instructions (CLAUDE.md, AGENTS.md) | 2 | ~1,400 | 11% |
| Rules (path-scoped) | 5 | ~300 | 2% |
| Topic docs (read on demand) | 8 | ~11,100 | 87% |
| Commands / Agents / Skills | 0 | 0 | 0% |
| **Total user content** | 15 | **~12,800** | 100% |

No meaningful savings left: the topic docs are read only for the files being edited.

---

## Cache Efficiency

### Token Budget

| File | Est. Tokens | Loaded | Cache Impact |
|------|------------:|--------|--------------|
| `CLAUDE.md` + `AGENTS.md` | ~1,400 | Always | High — in prefix every turn |
| Memory index `MEMORY.md` | ~115 | Always | High — personal, not in repo |
| `.claude/rules/*.md` | ~300 | When a matching path is touched | Low |
| `docs/agents/*.md` | ~11,100 | When read | None when unused |

**Always-loaded total:** ~1,500 tokens
**On-demand total:** ~11,400 tokens

### Volatile Content

| File | Volatile Markers | Position | Verdict |
|------|:----------------:|----------|---------|
| `AGENTS.md`, `CLAUDE.md`, rules, `docs/agents/*.md` | 0 | — | Clean |

### CLAUDE.md Size

| Metric | Value | Verdict |
|--------|------:|---------|
| Estimated tokens (with import) | ~1,400 | Good (<5K) |

### Duplication Analysis

| Source | Target | Shared Phrases | Verdict |
|--------|--------|:--------------:|---------|
| `.claude/rules/guide.md` | `AGENTS.md` "Read before editing" | 2 | Clean — intentional thin pointer |

No significant cross-file duplication detected.

---

## Instruction Quality Detail

| File | Clarity | Structure | Completeness | Efficiency | Usefulness | Overall |
|------|:-------:|:---------:|:------------:|:----------:|:----------:|:-------:|
| `AGENTS.md` | 9/10 | 10/10 | 9/10 | 9/10 | 10/10 | 9/10 |
| `CLAUDE.md` | 10/10 | 10/10 | 9/10 | 10/10 | 9/10 | 10/10 |
| `.claude/rules/*.md` | 9/10 | 9/10 | 9/10 | 10/10 | 9/10 | 9/10 |

- `AGENTS.md`: a true map; each rule points to one topic doc, and the "before finishing" list matches what the Stop hook enforces.
- Rules: one sentence each, scoped by `paths:`, no repeated rule text.

---

## Extension Quality Detail

No commands, agents or skills configured. Rules are rated above.

---

## Progress History

| Date | Score | Delta | Critical | Important | Suggestions |
|------|:-----:|:-----:|:--------:|:---------:|:-----------:|
| 2026-10-13 | 9.2 | — | 0 | 0 | 2 |
| 2026-10-13 | 9.2 | — | 0 | 0 | 3 |
| 2026-10-13 | 9.2 | — | 0 | 0 | 4 |

---

## Limitations

This analysis covers user-configurable components only. Claude Code's system prompt, built-in tool schemas, and runtime behavior are outside this scope.

---

*Report generated by [Agent Smith](https://github.com/maxencemeloni/claude-code-agent-smith)*
*More plugins at https://agent-smith.mmapi.fr/*
