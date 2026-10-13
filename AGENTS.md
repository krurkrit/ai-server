# AGENTS.md

This repo holds a reusable self-hosted AI server setup guide, a guide for the software team that uses the server, the helper scripts, and three diagrams (two architecture, one development workflow). The user runs every server command themselves. Agents only prepare and edit files in this folder; never run anything against the server.

This file is a map, not the rulebook. Read the topic doc for the files you are about to touch, then run the check before finishing.

## Repo map

| Path | What it is |
|---|---|
| `ai-server-setup-guide.md` | The guide: Prerequisite, then Steps 1…N; every service step has the same layout (Clean reinstall, Install, Test). About 3.9K lines: grep `^## ` for the section, then read that line range |
| `ai-setup-for-software-development.md` | How the software team (product, developers, QA, release) uses the finished server: stack, workflow, tests, deploy, models, third-party AI, optional tools |
| `options/*.md` | Optional or alternative paths for a step, linked from the guide; each ends with a generated Related list |
| `scripts/*.sh` | Helper scripts the user copies to `~/ai-server` on the server |
| `diagrams/*.svg` | Architecture diagrams (must match what the guide wires up) and the development workflow (must match the team guide) |
| `outline-export/` | Generated copy for Outline (guide, options, team guide, scripts appended); never edit by hand |
| `tools/` | `check.py` (all mechanical checks), `build-outline-export.py`, `update-option-related.py`; install their packages once with `python -m pip install -r tools/requirements.txt` |
| `docs/agents/` | Agent rules, one file per topic, plus the decision log |
| `AGENT_SMITH_REPORT.md`, `.claude/agent-smith-history.json` | Agent Smith config report and score history; not part of the guide |

## Read before editing

| Editing… | Read |
|---|---|
| The guide, `options/*.md`, or `ai-setup-for-software-development.md` | [docs/agents/guide.md](docs/agents/guide.md) |
| Any compose file, `.env`, or config file in the guide | [docs/agents/compose.md](docs/agents/compose.md) |
| Caddy files, or anything that picks or publishes a port | [docs/agents/caddy-and-ports.md](docs/agents/caddy-and-ports.md) |
| `scripts/*.sh` | [docs/agents/scripts.md](docs/agents/scripts.md) |
| `diagrams/*.svg` | [docs/agents/diagrams.md](docs/agents/diagrams.md) |
| Anything that changes how something works, not only how it is written | [docs/agents/decisions.md](docs/agents/decisions.md): why it is the way it is |
| Planning new work, or finding something missing | [docs/agents/known-gaps.md](docs/agents/known-gaps.md): what is not covered yet |

## Rules that always apply

- **Keep it generic.** No hostnames, IPs, usernames, subnets, or "current state" of any particular server in the repo. Server-specific facts belong in agent memory.
- **Step numbers live only in prose.** Files the guide writes out and the scripts never mention `Step N`.
- **List things in step order.** Ports, services, and similar lists follow the guide's step order.
- **Gate every destructive command with `confirm`.** No step edits an earlier step's file.
- **Free versions only.** Mark paid features with 💲 and don't depend on them.
- **Ask, don't guess,** when a diagram and the guide disagree, a rule does not cover the case, or a change would reverse a logged decision.

## Before finishing any change

1. `python tools/check.py` passes. It checks the docs (no `Step N` or apostrophes in code blocks, heading lengths, links and anchors, IP addresses, `confirm` on destructive commands, port clashes, YAML that parses), the scripts (manual, `-h`, `bash -n`), this knowledge base (links, summaries, length), the Related lists, and rebuilds the Outline export. Each problem names the doc that explains the fix.
2. By hand: no server-specific names in the repo, no step edits an earlier step's file, and the diagrams still match the guide.

## Keeping these docs healthy

- Keep this file a map (under ~60 lines). Detail goes into the matching `docs/agents/*.md`; a new topic gets its own file, a summary line under its title, and a row in "Read before editing".
- One rule, one place. Link to it instead of repeating it.
- A rule that can be checked mechanically belongs in `tools/check.py` too; when you change such a rule, change the check with it.
- A new choice with a reason worth keeping goes into the decision log; a gap you find but do not fix goes into known gaps, and closing one deletes its row.
- When the user corrects you on something generic, put the rule in the repo (topic doc, check, or decision log), not only in memory; the next agent sees only the repo.
- Claude Code gets thin pointer files in `.claude/rules/` (scoped by `paths:`); `CLAUDE.md` imports this file. In Claude Code, `/doctor prompt-audit` finds outdated or conflicting instructions.
