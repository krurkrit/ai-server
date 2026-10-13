# Agent Smith Analysis

**Project:** ai-server (`C:\Workspace\Private\Github\ai-server`)
**Type:** Documentation repo (Markdown guide + Bash helper scripts + Python tooling)
**Score:** 9.0/10 (— unchanged since 2026-10-13)
**Date:** 2026-10-13

---

## Summary

No actionable findings. Every item from earlier runs is done: server CA git-ignored, full deny list, `git push` denied, long rule bullets split, memory copied.
The remaining point per pillar reflects limits of the format, not gaps: Read denies do not cover shell reads, and `docs/agents/guide.md` stays dense by nature.

---

## Pillar Scores

| Pillar | Score | Notes |
|--------|:-----:|-------|
| Security Posture | 9/10 | Full reference deny list; ssh/scp/sftp/rsync/docker/git push denied; server CA ignored; no secrets, personal paths, dates, or hidden characters |
| Instruction Clarity | 9/10 | Map + topic docs + decision log + known gaps; no volatile markers |
| Configuration Quality | 9/10 | Valid JSON; 4 exact allows; 21 denies, no broad allows |
| Context Efficiency | 9/10 | Always-loaded ~1.3K tokens; generated export excluded; `.gitignore` patterns covered |
| Command & Extension Design | 9/10 | 5 path-scoped pointer rules, all targets exist |
| Hook Safety | N/A | No hooks |
| MCP Integration | N/A | No MCP servers |

Weighted: (9×20 + 9×20 + 9×15 + 9×15 + 9×15) / 85 = **9.0**

---

## Findings

### Critical (breaks functionality or security risk)
- None.

### Important (affects efficiency or maintainability)
- None.

### Suggestions (improvements, not problems)
- None. Longest remaining rule bullet is `docs/agents/scripts.md` line 7 (~840 chars, one topic: script placement), below the ~900-char split bar used in earlier runs.

---

## Action Plan

### Option A: Quick Wins (Low Effort)

None outstanding.

### Option B: Recommended (Medium Effort)

None outstanding.

### Option C: Advanced (High Effort)

None outstanding.

---

## .claudeignore Status

| Check | Status |
|-------|:------:|
| File exists | ✓ |
| `.git/` included | ✓ |
| Covers .gitignore patterns | ✓ (`settings.local.json` excepted; harmless) |
| Large binaries excluded | ✓ (generated md excluded; PNGs kept on purpose) |

---

## Optional Components

No hooks or MCP servers configured.

## Wiring Status

| Check | Status | Details |
|-------|:------:|---------|
| Cross-references valid | ✓ | 5 rules → 7 docs + `AGENTS.md` section; all `AGENTS.md`/topic-doc links resolve |
| No stale references | ✓ | — |
| No orphaned extensions | ✓ | Every `docs/agents/*.md` linked from `AGENTS.md` |
| No context conflicts | N/A | No contexts |
| Bidirectional consistency | N/A | No agents |

## Memory Status

| Check | Status | Details |
|-------|:------:|---------|
| Memory directory found | — | `~/.claude/` is outside the shared folder; not checked |
| Stale references | ✓ | Memory copied to the new folder path (confirmed by you) |

> Memory files are personal (not committed). These findings are suggestions.

---

## Content Overview

### File Inventory

| File | Lines | Characters | Est. Tokens |
|------|------:|----------:|-----------:|
| `CLAUDE.md` | 3 | 219 | ~55 |
| `AGENTS.md` | 54 | 4,865 | ~1,215 |
| `.claude/rules/agent-docs.md` | 6 | 131 | ~35 |
| `.claude/rules/diagrams.md` | 6 | 154 | ~40 |
| `.claude/rules/guide.md` | 8 | 245 | ~60 |
| `.claude/rules/scripts.md` | 6 | 108 | ~25 |
| `.claude/rules/tools.md` | 6 | 200 | ~50 |
| `docs/agents/guide.md` | 99 | 14,433 | ~3,610 |
| `docs/agents/compose.md` | 51 | 7,808 | ~1,950 |
| `docs/agents/scripts.md` | 40 | 5,364 | ~1,340 |
| `docs/agents/decisions.md` | 26 | 4,825 | ~1,205 |
| `docs/agents/caddy-and-ports.md` | 43 | 3,756 | ~940 |
| `docs/agents/diagrams.md` | 56 | 3,536 | ~885 |
| `docs/agents/known-gaps.md` | 28 | 2,810 | ~705 |

### Totals

| Category | Files | Est. Tokens | % of User Content |
|----------|------:|------------:|------------------:|
| Instructions | 2 | ~1,270 | 10% |
| Rules | 5 | ~210 | 2% |
| Agent topic docs (on demand) | 7 | ~10,630 | 88% |
| Commands / Agents / Skills | 0 | 0 | 0% |
| **Total user content** | 14 | **~12,110** | 100% |

---

## Cache Efficiency

### Token Budget

| File | Est. Tokens | Loaded | Cache Impact |
|------|------------:|--------|--------------|
| `CLAUDE.md` + `AGENTS.md` | ~1,270 | Always | High — in prefix every turn |
| `.claude/rules/*.md` | ~210 | On path match | Low |
| `docs/agents/*.md` | ~10,630 | On demand | Low |

**Always-loaded total:** ~1.3K tokens · **On-demand total:** ~10.8K tokens

### Volatile Content

| File | Volatile Markers | Position | Verdict |
|------|:----------------:|----------|---------|
| `AGENTS.md`, rules, `docs/agents/*` | 0 | — | Clean |

### CLAUDE.md Size

| Metric | Value | Verdict |
|--------|------:|---------|
| Estimated tokens (with import) | ~1,270 | Good (<5K) |

### Duplication Analysis

| Source | Target | Shared Phrases | Verdict |
|--------|--------|:--------------:|---------|
| `AGENTS.md` | `docs/agents/guide.md` | 3 | Intentional summary with links |
| `.claude/rules/*` | `docs/agents/*` | 0 | Clean (pointers only) |

---

## Instruction Quality Detail

| File | Clarity | Structure | Completeness | Efficiency | Usefulness | Overall |
|------|:-------:|:---------:|:------------:|:----------:|:----------:|:-------:|
| `CLAUDE.md` | 10 | 10 | 9 | 10 | 9 | 9.6 |
| `AGENTS.md` | 9 | 10 | 9 | 9 | 10 | 9.4 |
| `docs/agents/guide.md` | 8 | 9 | 10 | 7 | 10 | 8.8 |
| `docs/agents/compose.md` | 9 | 9 | 10 | 9 | 10 | 9.4 |
| `docs/agents/caddy-and-ports.md` | 9 | 9 | 9 | 9 | 10 | 9.2 |
| `docs/agents/scripts.md` | 9 | 9 | 9 | 9 | 10 | 9.2 |
| `docs/agents/diagrams.md` | 9 | 9 | 9 | 9 | 9 | 9.0 |
| `docs/agents/decisions.md` | 9 | 9 | 9 | 9 | 10 | 9.2 |
| `docs/agents/known-gaps.md` | 9 | 9 | 9 | 9 | 9 | 9.0 |

`docs/agents/guide.md` Models bullet and `docs/agents/compose.md` Infisical bullet are now split into sub-bullets.

---

## Extension Quality Detail

### Rules

| Rule | Scope (`paths:`) | Targets exist | Overall |
|------|------------------|:-------------:|:-------:|
| `agent-docs.md` | `docs/agents/*.md` | ✓ | 9/10 |
| `diagrams.md` | `diagrams/**/*.svg` | ✓ | 9/10 |
| `guide.md` | guide, `options/*.md`, team guide | ✓ | 9/10 |
| `scripts.md` | `scripts/*.sh` | ✓ | 9/10 |
| `tools.md` | `tools/*.py` | ✓ | 9/10 |

No commands, agents, or skills.

---

## Progress History

| Date | Score | Delta | Critical | Important | Suggestions |
|------|:-----:|:-----:|:--------:|:---------:|:-----------:|
| 2026-10-13 (run 7) | 9.0 | — | 0 | 0 | 0 |
| 2026-10-13 (run 6) | 9.0 | — | 0 | 0 | 1 |
| 2026-10-13 (run 5) | 9.0 | ↑ +0.2 | 0 | 0 | 2 |
| 2026-10-13 (run 4) | 8.8 | ↑ +0.2 | 0 | 2 | 2 |
| 2026-10-13 (run 3) | 8.6 | ↑ +0.5 | 0 | 2 | 3 |
| 2026-10-13 (run 2) | 8.1 | ↑ +2.4 | 0 | 2 | 8 |
| 2026-10-13 (run 1) | 5.7 | — | 1 | 4 | 5 |

---

## Limitations

This analysis covers user-configurable components only. Claude Code's system prompt, built-in tool schemas, and runtime behavior are outside this scope. User-level `~/.claude/` (rules, memory) was not reachable from the shared folder.

---

*Report generated by [Agent Smith](https://github.com/maxencemeloni/claude-code-agent-smith)*
*More plugins at https://agent-smith.mmapi.fr/*
