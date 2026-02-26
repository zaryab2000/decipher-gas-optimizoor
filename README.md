# decipher-gas-optimizoor

> Automated, continuous gas optimization for Foundry-based Solidity projects — built as a Claude Code plugin.

![version](https://img.shields.io/badge/version-1.0.0-blue)
![solidity](https://img.shields.io/badge/solidity-0.8.4%2B-lightgrey)
![forge](https://img.shields.io/badge/requires-foundry-orange)
![evm](https://img.shields.io/badge/EVM-Cancun-green)

11 domain-specific optimization skills fire automatically as you write Solidity — struct packing analysis when you define storage, custom error suggestions when you write `require` strings, calldata advice on external function parameters. A bash hook watches every `.sol` save and runs `forge snapshot --diff` to catch regressions the instant they are introduced. No TypeScript. No MCP server. No npm. The entire plugin is markdown skill files, slash command files, and one 42-line bash script.

---

## Table of Contents

- [Installation](#installation)
- [Quickstart](#quickstart)
- [Commands](#commands)
- [Skills — Auto-Applied](#skills--auto-applied)
- [Agents](#agents)
- [Regression Hook](#regression-hook)
- [Configuration](#configuration)
- [Chain Compatibility](#chain-compatibility)
- [Requirements](#requirements)
- [Contributing](#contributing)

---

## Installation

1. Add the marketplace

```
/plugin marketplace add zaryab2000/decipher-gas-optimizoor
```


2. Install the Plugin
```
/plugin install decipher-gas-optimizoor@decipher-gas-optimizoor-marketplace
````

---

## Quickstart

From zero to your first gas analysis in under 3 minutes.

### 1. Establish a gas baseline

Run this once in your Foundry project (requires at least one test):

```
/decipher-gas-optimizoor:baseline --update
```



Then commit the snapshot file:

```bash
git add .gas-snapshot && git commit -m "chore: gas baseline"
```

> **Important:** Do NOT add `.gas-snapshot` to your `.gitignore`. It must be committed for the regression guard to work.


## Commands

| Command                                                   | What it does                                                                                                                                                     |      Forge      |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | :-------------: |
| `/decipher-gas-optimizoor:analyze [path] [--threshold N]` | Full analysis of a contract or directory. Builds, snapshots, inspects storage layouts, and reports all findings sorted by gas saving.                            |        ✅        |
| `/decipher-gas-optimizoor:compare [ref1] [ref2]`          | Compares gas snapshots between two git refs (default: `HEAD~1` vs `HEAD`). Shows per-function delta and percent change, split into regressions and improvements. |        ✅        |
| `/decipher-gas-optimizoor:baseline [--update\|--show X]`  | Manages the `.gas-snapshot` baseline. `--update` regenerates it; `--show X` filters to matching functions; no args prints the full summary table.                | `--update` only |
| `/decipher-gas-optimizoor:explain <pattern>`              | EVM mechanic, exact gas numbers, before/after code, and when NOT to apply for any listed pattern.                                                                |        ❌        |
| `/decipher-gas-optimizoor:watch [--off]`                  | Toggles per-edit gas annotation mode. While active, Claude appends a gas impact note after every Solidity edit. Session-scoped.                                  |        ❌        |

### `--threshold` option for `/decipher-gas-optimizoor:analyze`

Suppress findings below a minimum estimated gas saving. Useful on large codebases to focus on high-impact issues only:

```
/decipher-gas-optimizoor:analyze src/ --threshold 500
```

Default threshold is 100 gas — findings below this are suppressed unless overridden.

### Accepted patterns for `/decipher-gas-optimizoor:explain`

`cold-sload` · `slot-packing` · `unchecked` · `custom-errors` · `calldata` · `external-vs-public` · `immutable` · `loop-caching` · `unbounded-loop`

---


### 2. Run your first analysis

```
/decipher-gas-optimizoor:analyze src/Vault.sol
```

```markdown
## Gas Analysis Report
**Target:** src/Vault.sol | **Contracts:** Vault, VaultLib

### Summary
| Severity | Count | Estimated Saving |
| -------- | ----- | ---------------- |
| High     | 2     | ~48,100 gas      |
| Medium   | 3     | ~720 gas         |
| Low      | 1     | ~30 gas          |

### Findings (sorted by gas saving, highest first)

#### HIGH: Unpacked storage struct — 2 wasted slots
**File:** src/Vault.sol, line 14
**Estimated saving:** ~44,200 gas per write

**Current code:**
struct Position { uint128 amount; uint256 principal; address owner; bool active; }

**Optimized code:**
struct Position { uint256 principal; uint128 amount; address owner; bool active; }

**Why:** uint128 alone on slot 0 wastes 16 bytes, forcing uint256 into slot 1 and
pushing address and bool into separate slots — 5 slots total when 3 suffice.
Reordering eliminates 2 cold SSTOREs (44,200 gas) on first write.

### Top 3 Actions
1. **Repack Position struct** — src/Vault.sol:14 — ~44,200 gas saved per write.
   Reorder to: uint256 first, then uint128 pair, then address+bool packed.
2. **Cache rewardRate before loop** — src/Vault.sol:88 — ~3,880 gas saved per call.
   Read into a local uint256 once before the loop; replace N warm SLOADs with MLOADs.
3. **Convert require strings to custom errors** — src/Vault.sol:31,47 — ~48 gas per revert.
   Replace require(cond, "string") with if (!cond) revert CustomError().
```

### 3. Enable real-time gas annotations while editing

```
/decipher-gas-optimizoor:watch
```

After activation, every Solidity edit Claude makes gets an annotation at the end of the response:

```
---
Gas note: Replaced require(msg.sender == owner, "Not owner") with custom error
NotOwner() — eliminates ABI-encoded string revert data.
Estimated: -20 gas per revert; -~40,000 gas at deployment.
```

Turn it off with `/decipher-gas-optimizoor:watch --off`.

## Skills — Auto-Applied

Skills activate automatically when relevant code patterns appear in the context. You never invoke them directly — they fire as Claude writes or reviews Solidity. Each covers a specific optimization domain and includes a full pattern catalog, checklist, and worked example.

| Skill                    | Code  | Catches                                                                                                  | Fires when                                                  |
| ------------------------ | :---: | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `storage-layout`         |  SL   | Unpacked structs, wasted slots, suboptimal field ordering, redundant SLOADs, expensive reentrancy guards | Writing `struct` definitions or state variable declarations |
| `loop-optimization`      |  LO   | Storage reads inside loops, uncached array lengths, missing unchecked counters, suboptimal loop patterns | Writing `for`/`while` loops                                 |
| `calldata`               |  CD   | `memory` params on `external` functions that should be `calldata`, calldata encoding waste               | Writing external function parameters                        |
| `deployment`             |  DP   | Suboptimal `optimizer_runs`, proxy pattern opportunities, payable admin savings, bytecode size           | Writing constructors, factories, or `foundry.toml`          |
| `type-optimization`      |  TY   | Unnecessary downcasting overhead, `string` where `bytes32` fits, bool bitmap opportunities               | Writing variable declarations and type usage                |
| `custom-errors`          |  CE   | Every `require(cond, "string")` and `revert("string")` without exception                                 | Writing any `require` with a string message                 |
| `compiler-optimizer`     |  CO   | `optimizer_runs` not tuned for usage, missing `via_ir`, outdated Solidity version                        | Writing or reviewing `foundry.toml`                         |
| `immutable-and-constant` |  IC   | Constructor-set state variables that should be `immutable`; runtime `keccak256` of a literal             | Writing constructor-set state variables                     |
| `unchecked-arithmetic`   |  UA   | Arithmetic in bounded loops where overflow is provably impossible                                        | Writing arithmetic in loops                                 |
| `visibility`             |  VI   | `public` functions only called externally; duplicate public getters                                      | Writing function declarations                               |
| `event-logging`          |  EV   | Storage used for historical data that should be events; wrong indexed parameter choices                  | Writing storage-backed history or audit arrays              |

Each skill lives in `skills/<domain>/` with supporting files:

```
skills/storage-layout/
  SKILL.md                    ← trigger conditions, workflow, output format
  resources/PATTERNS.md       ← all SL-001–SL-010 patterns with exact gas numbers
  resources/CHECKLIST.md      ← pre-completion verification checklist
  resources/EXAMPLE_FINDING.md ← worked finding on a real DeFi vault contract
```

---

## Agents

Two agents extend the plugin for longer or more complex sessions.

### `gas-optimizer`

Full-codebase audit agent. Applies all 11 skill domains systematically across every contract in `src/`, deduplicates findings, and produces a prioritized report with a suggested fix sequence ("patch these 3 first — highest impact, lowest risk"). Use before a mainnet deployment or a pre-audit gas pass.

---

## Regression Hook

The regression guard fires automatically after every Write or Edit on `src/**/*.sol`. No manual invocation needed.

### How it works

On every `.sol` save, the hook runs `forge snapshot --diff` against the committed `.gas-snapshot` baseline. If any test function's gas cost increases by more than the configured threshold, it emits a warning.

**No regression:**
```
GAS_GUARD: No regressions above 500 gas
```

**Regression detected:**
```
GAS_GUARD: REGRESSION DETECTED
GAS_GUARD: -----------------------------------------
  ↑ VaultTest::testDeposit() (gas: 38400 → 39640 | 1240 3.228%)
GAS_GUARD: -----------------------------------------
GAS_GUARD: Threshold: 500 gas | Run /decipher-gas-optimizoor:analyze to investigate
```

The hook **always exits 0** — it never breaks or interrupts your Claude Code session. If forge is not found or no baseline exists, it exits silently.

---

## Configuration

All configuration is through environment variables. Full reference at [`docs/configuration.md`](docs/configuration.md).

### `GAS_REGRESSION_THRESHOLD`

Controls when the regression guard emits a warning. Default: `500`.

| Scenario                             | Recommended value |
| ------------------------------------ | ----------------- |
| Production DeFi — every unit counts  | `100`–`200`       |
| Standard contracts with stable tests | `500` (default)   |
| Active refactoring with noisy tests  | `1000`–`2000`     |
| Early development                    | `2000`+           |

```bash
export GAS_REGRESSION_THRESHOLD=200
```

### `GAS_SNAPSHOT_PATH`

Path to the baseline snapshot file. Default: `.gas-snapshot`. Change only for monorepos where the snapshot lives in a subdirectory.

```bash
export GAS_SNAPSHOT_PATH=packages/core/.gas-snapshot
```

### Persist config with `.claude/settings.json`

```json
{
  "env": {
    "GAS_REGRESSION_THRESHOLD": "200",
    "GAS_SNAPSHOT_PATH": ".gas-snapshot"
  }
}
```

Both vars are non-sensitive. Safe to commit this file.

### `optimizer_runs` in `foundry.toml`

```toml
[profile.default]
optimizer = true
optimizer_runs = 200         # balanced — good for most contracts

[profile.production]
optimizer = true
optimizer_runs = 1000000     # minimize runtime gas — DeFi hot paths
```

```bash
FOUNDRY_PROFILE=production forge build
```

---

## Chain Compatibility

Most of the 44 patterns in this plugin work on any EVM chain. A small subset require Cancun EVM support.

| Pattern group                      | Requires                        | Notes                                                |
| ---------------------------------- | ------------------------------- | ---------------------------------------------------- |
| Transient storage (SL-005, SL-006) | Cancun EVM + Solidity `^0.8.24` | Check your chain's Cancun activation before applying |
| All other patterns (42 of 44)      | Any EVM version                 | Safe on pre-Cancun chains                            |

The `storage-layout` skill checks your `evm_version` in `foundry.toml` and Solidity pragma before recommending transient storage. On unsupported chains it skips those techniques and notes the constraint.

```bash
# Check your configured EVM version
grep "evm_version" foundry.toml
```

**Tested on:** Ethereum mainnet · Arbitrum One · Optimism · Base · Polygon PoS

---

## Requirements

- [Foundry](https://getfoundry.sh) installed (`forge` on PATH)
- Claude Code installed
- A Solidity project with `foundry.toml`
- Solidity `^0.8.4` or higher (for custom error support)
- A committed `.gas-snapshot` baseline — created with `/decipher-gas-optimizoor:baseline --update`

The three commands that require forge are `analyze`, `compare`, and `baseline --update`. The `/decipher-gas-optimizoor:explain` and `/decipher-gas-optimizoor:watch` commands and all 11 skills work without forge.

---

## Contributing

Found a gas figure that's wrong or missing an EIP citation? Open an issue.

Want to add a pattern to an existing skill domain? PRs are welcome. Every new pattern must include:

1. An exact gas number with an EVM opcode reference or EIP citation
2. A before/after code example in ≤20 lines
3. A concrete "When NOT to apply" condition

Found a bug in the regression hook? The script is 42 lines at `hooks/scripts/gas-regression-guard.sh` — straightforward to read and patch.

[Open an issue →](https://github.com/zaryab2000/decipher-gas-optimizoor/issues)
