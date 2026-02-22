# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

`decipher-gas-optimizoor` is a Claude Code plugin for automated Solidity gas optimization. Zero TypeScript, zero MCP, zero npm. The entire plugin is markdown skill files, markdown command files, and one bash hook script.

**Source of truth for all implementation:** `PRD_DEV.md` (phases 1–5) and `PRD_TEST.md` (phases 6–8). Read these fully before making any changes.

## Validation

```bash
claude plugin validate .
```

No build step. No compilation. This is the only automated check.

## Plugin Structure

```
.claude-plugin/          # plugin.json, marketplace.json
commands/                # 5 slash command files (analyze, compare, baseline, explain, watch)
skills/                  # 11 skill domains, each in its own subdirectory
  <domain>/SKILL.md      # ≤250 lines — the skill file
  <domain>/resources/    # PATTERNS.md, CHECKLIST.md, EXAMPLE_FINDING.md
hooks/
  hooks.json             # PostToolUse triggers on src/**/*.sol Write/Edit
  scripts/gas-regression-guard.sh
agents/                  # editor.md, gas-optimizer.md
docs/                    # configuration.md, evm-gas-reference.md
```

## Skill File Structure

Every `skills/*/SKILL.md` must follow this exact 9-section structure:
1. YAML frontmatter — name, description, allowed-tools
2. Purpose
3. When to Use
4. When NOT to Use
5. Rationalizations to Reject (high-stakes skills only)
6. Platform Detection
7. Quick Reference — decision table or tree
8. Workflow — numbered steps with checkboxes
9. Output Format — with a filled-in concrete example finding

Supporting files per domain: `resources/PATTERNS.md`, `resources/CHECKLIST.md`, `resources/EXAMPLE_FINDING.md`.

Depth goes in `resources/`, not in `SKILL.md`. Keep SKILL.md ≤250 lines.

## Hook Constraints (non-negotiable)

- Always exits 0 — never breaks the Claude Code session
- Never writes any file — read-only
- Silent when no regression
- Timeout: 60 seconds
- Trigger: PostToolUse on Write/Edit matching `src/**/*.sol`

## Commands

| Command | File | Forge required |
|---|---|---|
| `/gas:analyze [path]` | `commands/analyze.md` | Yes |
| `/gas:compare [ref1] [ref2]` | `commands/compare.md` | Yes |
| `/gas:baseline [--update\|--show X]` | `commands/baseline.md` | Yes |
| `/gas:explain <pattern>` | `commands/explain.md` | No |
| `/gas:watch [--off]` | `commands/watch.md` | No |

## Skill Domains

11 domains, each a separate skill: `storage-layout` (SL), `loop-optimization` (LO), `calldata` (CD), `deployment` (DP), `type-optimization` (TY), `custom-errors` (CE), `compiler-optimizer` (CO), `immutable-and-constant` (IC), `unchecked-arithmetic` (UA), `visibility` (VI), `event-logging` (EV).

Do not invent gas rules. All content must be derived from `skills/GAS_OPTIMIZATION_KNOWLEDGE_BASE.md`.

## Testing Gates (PRD_TEST.md)

Six gates must all pass before distribution:
- **G1** — `claude plugin validate .` zero errors
- **G2** — Hook exits 0 in all 4 conditions (no forge, no baseline, no regression, regression detected)
- **G3** — All 5 commands produce output matching their format templates
- **G4** — Each skill fires on its anti-pattern, does not fire when domain is absent
- **G5** — Complex `GasAntiPatterns.sol` fixture triggers ≥6 distinct domain findings with gas estimates
- **G6** — Regression guard fires on every `.sol` save, clears after fix

## Current State

Implementation has not started. Git has only 3 files committed: `README.md`, `PRD_DEV.md`, `PRD_TEST.md`. Execute PRD_DEV phases 1–5 to build the plugin, then PRD_TEST phases 6–8 to validate and release.
