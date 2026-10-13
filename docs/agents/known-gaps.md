# Known gaps

What the guide, scripts, and repo tooling do not cover yet, so nobody mistakes a gap for a decision or fixes one twice. Generic gaps only; what a particular server still lacks belongs in agent memory.

How to use it:

- Found a gap and not fixing it now? Add a row. Fixed one? Delete the row in the same change; if closing it meant choosing between options, add the choice to [decisions.md](decisions.md).
- A gap that turns out to be on purpose moves to [decisions.md](decisions.md) with its reason.
- Before starting a gap, ask the user; most need a choice or input only they can give.

## Guide and scripts

| Gap | Why it matters | Possible next step | Where |
|---|---|---|---|
| No pipeline fills Qdrant | Retrieval (RAG) has an empty database until someone writes the indexer | A script that chunks files, embeds through LiteLLM `local-embed`, and upserts; or an app such as Flowise as its own step | Step 14 → "Not included" |
| OpenHands and the CI runner get the full Docker socket | Anything running there can control every container on the host | A docker-socket-proxy in front of each, allowing only the calls they need | Steps 16, 18 |
| Dex keeps no login between apps | Apps with a Dex button ask for the password again; only gated apps share one sign-in | An outside sign-in provider (documented), or Dex sessions once they leave experimental | Step 6 → single sign-on note; `options/dex-outside-sign-in.md` |
| Configuration backups stay on the server disk | A disk failure loses the data and its backup together | A documented copy of `/opt/backups/config` to another machine | `scripts/backup-config.sh`; Step 20 |
| GlitchTip compose follows upstream by hand | Upstream changes its worker command between versions; the copy here can go stale | Compare with GlitchTip `compose.sample.yml` on every upgrade | `options/glitchtip.md` |
| Model suggestions date quickly | Sizes, tags, and "best that fits" change within months | Re-check sizes and tags when revisiting the model pages | `options/litellm-models.md`; Step 12 |

## Repo tooling

| Gap | Why it matters | Possible next step | Where |
|---|---|---|---|
| Diagrams are compared with the guide by hand | A new service or port can be missing from a diagram unnoticed | `tools/check.py` compares service names and ports in the SVG text with the guide's step table | `docs/agents/diagrams.md` |
| "No step edits an earlier step's file" is checked by hand | A later step quietly editing an earlier file breaks clean reinstalls | `tools/check.py` collects each step's written paths and flags a later write to them | `docs/agents/guide.md` |
| No regular clean-up of stale docs | Rules and pages drift from each other over time | Run `/doctor prompt-audit` in Claude Code now and then, and walk this file | `AGENTS.md` |
