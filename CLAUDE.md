# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

`decipher-gas-optimizoor` is a Claude Code plugin for automated Solidity gas optimization. Zero TypeScript, zero MCP, zero npm. The entire plugin is markdown skill files, markdown command files, and one bash hook script.

**Implementation history:** `docs-internal/PRD_DEV.md` (phases 1–5) and `docs-internal/PRD_TEST.md` (phases 6–8). These are read-only references — implementation is complete.

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
agents/                  # gas-optimizer.md
docs/                    # configuration.md, evm-gas-reference.md
```

## Skill File Structure

Every `skills/*/SKILL.md` must follow this exact 9-section structure (unnumbered headings):
- YAML frontmatter — `name`, `description`, `allowed-tools` (space-delimited string, e.g. `allowed-tools: Read Bash`)
- `## Purpose`
- `## When to Use`
- `## When NOT to Use`
- `## Rationalizations to Reject` (high-stakes skills only)
- `## Platform Detection`
- `## Quick Reference` — decision table or tree
- `## Workflow` — numbered steps with checkboxes
- `## Output Format` — with a filled-in concrete example finding

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

Do not invent gas rules. All gas optimization content must be grounded in documented EVM mechanics (EIP-2929, EIP-1153, EIP-3529) and verifiable with `forge snapshot --diff`.

## Testing Gates

All gates passed. See `docs/TEST_LOGS.md` for full results.

| Gate | What | Status |
|------|------|--------|
| G1 | `claude plugin validate .` zero errors | ✅ PASS |
| G2 | Hook exits 0 in all 5 conditions | ✅ PASS |
| G3 | All 5 commands produce correct output | ✅ PASS |
| G4 | Each skill fires on its anti-pattern | ✅ PASS |
| G5 | `GasAntiPatterns.sol` triggers ≥6 domain findings | ✅ PASS (8 findings) |
| G6 | Regression guard fires and clears correctly | ✅ PASS |

## Current State

Implementation and testing complete. Awaiting author sign-off before Phase 8 (publish).
