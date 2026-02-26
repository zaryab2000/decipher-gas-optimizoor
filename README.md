# decipher-gas-optimizoor

![version](https://img.shields.io/badge/version-1.0.0-blue)
![solidity](https://img.shields.io/badge/solidity-0.8.4%2B-lightgrey)
![forge](https://img.shields.io/badge/requires-foundry-orange)

Dedicated Solidity Smart Contract Gas optimizoor for your Solidity projects.
- 11 domain-specific EVM gas-optimization skills,
- 5 slash commands,
- 1 agent
- and a per-save regression guard

All you need to optimize your smart contracts.


---

## Installation

Inside Claude Code, run:

**Step 1: Add the marketplace**
```
/plugin marketplace add zaryab2000/decipher-gas-optimizoor
```

**Step 2: Install the marketplace**

```
/plugin install decipher-gas-optimizoor@decipher-gas-optimizoor-marketplace
```

---

## Quickstart

**Prerequisites:** [Foundry](https://getfoundry.sh) installed · Claude Code installed · a Solidity project with `foundry.toml` and at least one test

### Step 1 — Create a gas baseline

The regression guard compares every future save against this snapshot. Run once, then commit it.

```
/decipher-gas-optimizoor:baseline --update
```

```bash
git add .gas-snapshot && git commit -m "chore: gas baseline"
```

> Do not add `.gas-snapshot` to `.gitignore` — it must be committed for the regression guard to work.

### Step 2 — Run your first analysis

```
/decipher-gas-optimizoor:analyze src/
```

You'll get a prioritized findings report: severity, file + line, estimated gas saving, before/after code, and a top-3 action list.

### Step 3 — Enable real-time annotations while editing

```
/decipher-gas-optimizoor:watch
```

After activation, every Solidity edit Claude makes gets a gas impact note appended to the response. Turn it off with `/decipher-gas-optimizoor:watch --off`.

---

## Commands

| Command                                                   | What it does                                                                                                                                 |      Forge      |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | :-------------: |
| `/decipher-gas-optimizoor:analyze [path] [--threshold N]` | Full gas analysis of a contract or directory. Reports all findings sorted by estimated gas saving.                                           |        ✅        |
| `/decipher-gas-optimizoor:compare [ref1] [ref2]`          | Compares gas snapshots between two git refs (default: `HEAD~1` vs `HEAD`). Shows per-function delta split into regressions and improvements. |        ✅        |
| `/decipher-gas-optimizoor:baseline [--update\|--show X]`  | Manages the `.gas-snapshot` baseline. `--update` regenerates it; `--show X` filters to matching functions; no args prints the full summary.  | `--update` only |
| `/decipher-gas-optimizoor:explain <pattern>`              | EVM mechanic, exact gas numbers, before/after code, and when NOT to apply — for any listed pattern.                                          |        ❌        |
| `/decipher-gas-optimizoor:watch [--off]`                  | Toggles per-edit gas annotation mode. Session-scoped.                                                                                        |        ❌        |

**`--threshold`** — suppress findings below a minimum gas saving. Default is 100:

```
/decipher-gas-optimizoor:analyze src/ --threshold 500
```

**Patterns for `:explain`** — `cold-sload` · `slot-packing` · `unchecked` · `custom-errors` · `calldata` · `external-vs-public` · `immutable` · `loop-caching` · `unbounded-loop`

---

## Skills — Auto-Applied

Skills fire automatically as you write Solidity. You never invoke them directly.

| Skill                    | Code  | Catches                                                                                                  | Fires when                                                  |
| ------------------------ | :---: | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| `storage-layout`         |  SL   | Unpacked structs, wasted slots, suboptimal field ordering, redundant SLOADs, expensive reentrancy guards | Writing `struct` definitions or state variable declarations |
| `loop-optimization`      |  LO   | Storage reads inside loops, uncached array lengths, missing unchecked counters                           | Writing `for`/`while` loops                                 |
| `calldata`               |  CD   | `memory` params on `external` functions that should be `calldata`                                        | Writing external function parameters                        |
| `deployment`             |  DP   | Suboptimal `optimizer_runs`, proxy pattern opportunities, payable admin savings, bytecode size           | Writing constructors, factories, or `foundry.toml`          |
| `type-optimization`      |  TY   | Unnecessary downcasting, `string` where `bytes32` fits, bool bitmap opportunities                        | Writing variable declarations                               |
| `custom-errors`          |  CE   | Every `require(cond, "string")` and `revert("string")` without exception                                 | Writing any `require` with a string message                 |
| `compiler-optimizer`     |  CO   | `optimizer_runs` not tuned for usage, missing `via_ir`, outdated Solidity version                        | Writing or reviewing `foundry.toml`                         |
| `immutable-and-constant` |  IC   | Constructor-set variables that should be `immutable`; runtime `keccak256` of a literal                   | Writing constructor-set state variables                     |
| `unchecked-arithmetic`   |  UA   | Arithmetic in bounded loops where overflow is provably impossible                                        | Writing arithmetic in loops                                 |
| `visibility`             |  VI   | `public` functions only called externally; duplicate manual getters                                      | Writing function declarations                               |
| `event-logging`          |  EV   | Storage used for historical data that should be events; wrong `indexed` parameter choices                | Writing storage-backed history arrays                       |

---

## Agents & Hook

### `gas-optimizer` agent

Full-codebase audit. Applies all 11 skill domains across every contract in `src/`, deduplicates findings, and produces a prioritized fix sequence. Use before mainnet deployment or a pre-audit gas pass.

### Regression hook

Fires automatically on every `.sol` save. Runs `forge snapshot --diff` against the committed baseline and warns on any regression above the threshold:

```
GAS_GUARD: REGRESSION DETECTED
  ↑ VaultTest::testDeposit() (gas: 38400 → 39640 | +1240 3.2%)
GAS_GUARD: Threshold: 500 gas | Run /decipher-gas-optimizoor:analyze to investigate
```

Always exits 0 — never interrupts your session. Silently skips if forge is missing or no baseline exists. Threshold configurable via `GAS_REGRESSION_THRESHOLD` env var (default: `500`). Full config reference: [`docs/configuration.md`](docs/configuration.md).

---

## Contributing

Every new pattern must include an exact gas number with an EVM opcode reference or EIP citation, a before/after code example in ≤20 lines, and a concrete "When NOT to apply" condition.

[Open an issue →](https://github.com/zaryab2000/decipher-gas-optimizoor/issues)
