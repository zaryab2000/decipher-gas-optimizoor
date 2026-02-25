# decipher-gas-optimizoor

A Claude Code plugin for automated, continuous gas optimization of Foundry-based Solidity projects. It brings 11 domain-specific optimization skills that fire automatically when you write relevant code patterns — storage layout analysis when you define structs, custom error suggestions when you write `require` strings, calldata advice when you write external function parameters — so optimization knowledge is applied at the moment it is relevant rather than remembered later. A bash hook watches every `.sol` save and runs `forge snapshot --diff` to catch gas regressions the instant they are introduced, before they compound. No TypeScript, no MCP server, no npm. The entire plugin is markdown skill files, slash command files, and one bash script.

---

## Installation

```
/plugin install https://github.com/zaryab2000/decipher-gas-optimizoor
```

---

## Setup

Establish a gas baseline so the regression guard has something to compare against:

```
/gas:baseline --update
git add .gas-snapshot && git commit -m "chore: gas baseline"
```

---

## Commands

| Command | What it does | Example |
| ------- | ------------ | ------- |
| `/gas:analyze [path]` | Full gas optimization analysis of a contract or directory. Runs forge build + snapshot + storage layout inspection, then reports findings sorted by gas saving. | `/gas:analyze src/Vault.sol` |
| `/gas:compare [ref1] [ref2]` | Compares gas costs between two git refs. Defaults to `HEAD~1` vs `HEAD`. Shows per-function delta and percent change. | `/gas:compare HEAD~1 HEAD` |
| `/gas:baseline [--update\|--show X]` | Creates or queries the `.gas-snapshot` baseline. `--update` regenerates it; `--show X` filters to matching functions; no args prints a summary table. | `/gas:baseline --update` |
| `/gas:explain <pattern>` | Plain-English explanation of a gas optimization pattern with EVM mechanics, exact numbers, and before/after code examples. No forge required. | `/gas:explain cold-sload` |
| `/gas:watch [--off]` | Enables per-edit gas impact annotations for the current session. After each Solidity edit, Claude appends a gas note with the estimated cost impact. | `/gas:watch` |

---

## Skills (Auto-Applied)

Skills are injected automatically when relevant code patterns appear. You do not invoke them manually — they fire as Claude writes or reviews Solidity code.

| Skill | Abbreviation | What it catches | When it fires |
| ----- | ------------ | --------------- | ------------- |
| storage-layout | SL | Unpacked structs, wasted slots, suboptimal variable ordering | Writing struct definitions or state variable declarations |
| loop-optimization | LO | Storage reads inside loops, uncached array lengths, missing unchecked counters | Writing `for`/`while` loops |
| calldata | CD | `memory` parameters that should be `calldata` on external functions, calldata size waste | Writing external function parameters |
| deployment | DP | Suboptimal optimizer_runs, proxy pattern opportunities, bytecode size issues | Writing constructors, factories, or deploy configuration |
| type-optimization | TY | Unnecessary type downcasting overhead, `string` where `bytes32` fits, bitmap opportunities | Writing variable declarations and type usage |
| custom-errors | CE | `require(condition, "string")` that should be custom errors | Writing any `require` with a string message |
| compiler-optimizer | CO | optimizer_runs not tuned for usage pattern, missing via-ir flag | Writing or reviewing `foundry.toml` |
| immutable-and-constant | IC | State variables set in the constructor and never changed that should be `immutable` | Writing constructor-set state variables |
| unchecked-arithmetic | UA | Arithmetic loops where overflow is provably impossible but `unchecked` is missing | Writing arithmetic in bounded loops |
| visibility | VI | `public` functions that are only called externally and should be `external` | Writing function declarations |
| event-logging | EV | Storage used for historical data that could be events instead | Writing storage-backed history arrays or audit logs |

---

## Regression Hook

The regression guard runs automatically after every Write or Edit on `src/**/*.sol`.

**What fires it:** PostToolUse on Write or Edit matching `src/**/*.sol`

**What it outputs:**

When no regression is detected:
```
GAS_GUARD: No regressions above 500 gas
```

When a regression is detected:
```
GAS_GUARD: REGRESSION DETECTED
GAS_GUARD: -----------------------------------------
  ↑ VaultTest::testDeposit() (gas: 38400 → 39640 | 1240 3.228%)
GAS_GUARD: -----------------------------------------
GAS_GUARD: Threshold: 500 gas | Run /gas:analyze to investigate
```

**Configuration:** Set `GAS_REGRESSION_THRESHOLD` to control the warning threshold (default: 500 gas). The hook always exits 0 and never writes any file — it will not break your Claude Code session.

```bash
# Tighter threshold for production contracts
export GAS_REGRESSION_THRESHOLD=200
```

---

## Configuration

See [docs/configuration.md](docs/configuration.md) for full details on:

- `GAS_REGRESSION_THRESHOLD` — regression warning threshold (default: 500)
- `GAS_SNAPSHOT_PATH` — path to the baseline snapshot file (default: `.gas-snapshot`)
- `optimizer_runs` tuning guide for different contract usage patterns
- How to set env vars persistently via `.claude/settings.json`

---

## Requirements

- Foundry installed (`forge` command available in PATH)
- Claude Code installed
- A Solidity project with `foundry.toml`
- A committed `.gas-snapshot` baseline (created by `/gas:baseline --update`)

The 5 commands that run forge (`analyze`, `compare`, `baseline`) require Foundry. The `/gas:explain` and `/gas:watch` commands and all 11 skills work without forge.
