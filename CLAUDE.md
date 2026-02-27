# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

`decipher-gas-optimizoor` is a Claude Code plugin for automated Solidity gas optimization. Zero TypeScript, zero MCP, zero npm. The entire plugin is markdown skill files, markdown command files, and one bash hook script.

**Implementation history:** `docs-internal/PRD_DEV.md` (phases 1–5) and `docs-internal/PRD_TEST.md` (phases 6–8). These are read-only references — implementation is complete.

## Resources

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins)
- [Agent Skills](https://code.claude.com/docs/en/skills)
- [Skill Authoring Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

For plugin/skill questions, use the `claude-code-guide` subagent — it has access to official documentation.

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

## Technical Reference

### Frontmatter

Every `skills/*/SKILL.md` requires three frontmatter fields:

```yaml
name: <domain-name>
description: <trigger description — see Quality Standards below>
allowed-tools: Read Bash
```

`allowed-tools` is a space-delimited string, not a YAML list.

### Skill File Structure

Every `skills/*/SKILL.md` must follow this exact 9-section structure (unnumbered headings):

- YAML frontmatter — `name`, `description`, `allowed-tools`
- `## Purpose`
- `## When to Use`
- `## When NOT to Use`
- `## Rationalizations to Reject` (high-stakes skills only)
- `## Platform Detection`
- `## Quick Reference` — decision table or tree
- `## Workflow` — numbered steps with checkboxes
- `## Output Format` — with a filled-in concrete example finding

Supporting files per domain: `resources/PATTERNS.md`, `resources/CHECKLIST.md`, `resources/EXAMPLE_FINDING.md`.

### Naming Conventions

- Plugin and skill names: kebab-case, ≤64 characters
- Skill `name` frontmatter must match the parent directory name exactly
- Avoid vague names: `helper`, `utils`, `misc`

## Quality Standards

### Skill Description

The `description` frontmatter field is what triggers the skill. It must be:

- **Third-person voice**: "Detects X" not "I help with X"
- **Trigger-specific**: "Use when writing struct definitions" not just "storage tool"
- **Specific**: "Detects cold SLOAD from unbounded loops" not "helps with gas"

### Content Organization

- Keep SKILL.md ≤250 lines — depth goes in `resources/`, not in `SKILL.md`
- Use progressive disclosure: quick reference and workflow first, full patterns on demand
- `resources/` files are loaded only when explicitly needed — do not load all three by default
- One level deep: SKILL.md links to resources files; resources files do not chain further

### Gas Accuracy

Do not invent gas rules. Every gas figure must be grounded in documented EVM mechanics
(EIP-2929, EIP-1153, EIP-3529) and must be verifiable with `forge snapshot --diff`.

## Hook Constraints (non-negotiable)

- Always exits 0 — never breaks the Claude Code session
- Never writes any file — read-only
- Silent when no regression
- Timeout: 60 seconds
- Trigger: PostToolUse on Write/Edit matching `src/**/*.sol`

## Commands

| Command | File | Forge required |
|---|---|---|
| `/decipher-gas-optimizoor:analyze [path]` | `commands/analyze.md` | Yes |
| `/decipher-gas-optimizoor:compare [ref1] [ref2]` | `commands/compare.md` | Yes |
| `/decipher-gas-optimizoor:baseline [--update\|--show X]` | `commands/baseline.md` | Yes |
| `/decipher-gas-optimizoor:explain <pattern>` | `commands/explain.md` | No |
| `/decipher-gas-optimizoor:watch [--off]` | `commands/watch.md` | No |

## Skill Domains

11 domains, each a separate skill: `storage-layout` (SL), `loop-optimization` (LO), `calldata` (CD), `deployment` (DP), `type-optimization` (TY), `custom-errors` (CE), `compiler-optimizer` (CO), `immutable-and-constant` (IC), `unchecked-arithmetic` (UA), `visibility` (VI), `event-logging` (EV).

## Contribution Checklist

**Technical (validator checks these):**
- [ ] `claude plugin validate .` passes with zero errors
- [ ] Valid YAML frontmatter with `name`, `description`, `allowed-tools`
- [ ] `name` matches the parent skill directory name
- [ ] All referenced files exist (no broken `resources/` paths)

**Quality (reviewer checks these):**
- [ ] Description triggers correctly (third-person, trigger-specific, no vague language)
- [ ] `## When to Use` and `## When NOT to Use` sections present
- [ ] `## Rationalizations to Reject` present for high-stakes skills
- [ ] Gas figures have EVM opcode or EIP citations
- [ ] SKILL.md is ≤250 lines

**Documentation:**
- [ ] Supporting Docs table in SKILL.md lists all three resources files with load conditions
- [ ] Hook changes: always exits 0, never writes files, tested in all 5 conditions

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
