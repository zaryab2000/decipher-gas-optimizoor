---
name: compiler-optimizer
description: >
  Analyzes foundry.toml optimizer configuration for Foundry-based Solidity
  projects. Detects suboptimal optimizer_runs settings relative to contract call
  frequency, missing via_ir flag for complex contracts, and outdated Solidity
  versions missing built-in optimizer gains. Covers CO-001 (optimizer_runs tuning),
  CO-002 (via_ir for Yul-level optimization), CO-003 (Solidity version selection
  for 0.8.22 auto-unchecked loops and 0.8.24 transient storage). Use when writing
  or reviewing foundry.toml or pragma declarations.
allowed-tools: Read Bash
---

## Purpose

Identify misconfigured or absent Solidity compiler optimizer settings in
`foundry.toml` and pragma declarations. Mismatched `optimizer_runs`, missing
`via_ir`, and outdated compiler versions are free gas savings requiring only
configuration changes.

## When to Use

- Writing or reviewing `foundry.toml`
- Starting a new Foundry project
- Pre-deployment audit of build configuration
- After reviewing pragma versions in `.sol` files
- When `forge test --gas-report` shows unexpectedly high gas costs

## When NOT to Use

- Non-Foundry projects (Hardhat, Truffle): configuration format differs
- When optimizer is intentionally disabled for faster test iteration
  (flag for production build profile, not dev profile)
- When the project has recently passed a security audit on a specific version
  and re-audit is not feasible

## Platform Detection

Trigger fires when:
- `foundry.toml` is present in the project root, **or**
- A `pragma solidity` declaration is being reviewed in a `.sol` file

Read `foundry.toml` with the `Read` tool. Use `Bash` to run
`forge build --sizes` or `forge test --gas-report` when measurements are
needed to quantify savings.

## Quick Reference

### optimizer_runs by contract type

| Contract type | Recommended `optimizer_runs` | Reason |
|---|---|---|
| DeFi hot path (AMM, lending, swap router) | `1_000_000` | Runtime savings outweigh bytecode size |
| Factory / deployer contract | `1` | Minimize deployment cost; called rarely |
| General purpose (default) | `200` | Balanced — Foundry default |
| Library deployed once, called by many | `1_000_000` | Amortized deployment cost is negligible |

All profiles should have `optimizer = true`. Never deploy with optimizer disabled.

### via_ir

| Condition | Recommendation |
|---|---|
| Complex DeFi contract (tight loops, heavy structs, multi-call) | `via_ir = true` |
| Simple contract (< 5 functions, minimal logic) | optional |
| Rapid development iteration | `via_ir = false` (5–50× slower to compile) |
| Production build profile | `via_ir = true` always recommended |

### Solidity version

| Version | Key gain |
|---|---|
| `0.8.22+` | Auto-unchecked simple loop counters (~30 gas/iter saved automatically) |
| `0.8.24+` | Native `tstore`/`tload` syntax for transient storage (SL-005, SL-006) |
| latest stable | Look up the current release at https://github.com/ethereum/solidity/releases before recommending a specific version — do not assume from memory |

Always pin to an exact version (`pragma solidity X.Y.Z;`), not a floating
range (`^0.8.0`). When recommending a version upgrade, check the Solidity
release page for the current stable release and any breaking changes since
the project's current pragma.

## Workflow

1. **Read `foundry.toml` and check optimizer settings.**
   Confirm `optimizer = true`. Check `optimizer_runs` value. Identify whether
   the project is a DeFi protocol (high-frequency), a deployment-only factory,
   or a general-purpose contract. Compare the current `optimizer_runs` to the
   table above. Check whether `via_ir` is set, especially for complex contracts
   with nested internal calls or heavy loop bodies.

2. **Check pragma version in `.sol` files.**
   Scan key contracts for `pragma solidity` declarations. Identify the current
   version. If below `0.8.22`, the auto-unchecked loop optimization is absent.
   If below `0.8.24`, transient storage requires inline assembly. If below
   `0.8.28`, other incremental optimizer improvements are missing. Note: version
   upgrades should be validated with `forge test` to confirm no regressions.

3. **Match `optimizer_runs` to expected call frequency; recommend `via_ir` for
   complex contracts.**
   For each finding, quantify the expected impact using `forge test --gas-report`
   before and after. Document the change in `foundry.toml` and the rationale.
   For `via_ir`, note the compile-time tradeoff and recommend enabling only in
   the production profile.

## Supporting Docs

Only read these files when explicitly needed — do not load all three by default:

| File | Read only when… |
|---|---|
| `resources/PATTERNS.md` | You need the break-even calculation formula or full multi-profile `foundry.toml` examples beyond what's shown above |
| `resources/CHECKLIST.md` | Producing a formal `/decipher-gas-optimizoor:analyze` report and confirming all compiler settings were reviewed |
| `resources/EXAMPLE_FINDING.md` | Generating a report and needing the exact output format for an optimizer configuration finding |
| `docs/evm-gas-reference.md` | You need EIP references or baseline opcode costs to contextualize compiler optimization impact |

## Output Format

Report each finding with: pattern ID, config key, current value, recommended
value, and estimated gas impact.

**Example finding (CO-001):**

```
CO-001 | foundry.toml | optimizer_runs = 200
  Severity : medium
  Context  : AMM swap router called ~1M times/year

  Current foundry.toml:
    [profile.default]
    optimizer = true
    optimizer_runs = 200

  Recommended:
    [profile.default]
    optimizer = true
    optimizer_runs = 1_000_000

    [profile.deploy]
    optimizer = true
    optimizer_runs = 1           # for one-shot factory deployment scripts

  Rationale: At 1M calls/year, a 5% per-call runtime saving at optimizer_runs
  = 1_000_000 vs 200 is: 1,000,000 calls × 50 gas saved × $0.0000001/gas
  ≈ meaningful cumulative savings. Deployment bytecode may grow ~5–10% but
  is a one-time cost.

  Measure:
    forge build --sizes                  # bytecode size delta
    forge test --gas-report              # per-function gas delta
```

**Example finding (CO-002):**

```
CO-002 | foundry.toml | via_ir not set (defaults to false)
  Severity : medium
  Context  : DeFi lending protocol with complex internal call chains

  Current foundry.toml:
    [profile.default]
    optimizer = true
    optimizer_runs = 200

  Recommended:
    [profile.default]
    optimizer = true
    optimizer_runs = 200
    via_ir = true

  Rationale: via_ir lowers code to Yul before optimization, enabling
  cross-function optimizations unavailable to the classic pipeline. For
  contracts with complex internal calls and tight loops, typical savings
  are 5–20% in bytecode size or runtime gas.

  Warning: via_ir increases compile time 5–50×. Enable in production
  profile; keep disabled in dev profile for fast iteration.

  Measure:
    forge build --sizes                  # compare bytecode size
    forge test --gas-report              # compare per-function gas
    forge test                           # full suite — confirm no regressions
```

**Example finding (CO-003):**

```
CO-003 | LendingPool.sol:2 | pragma solidity ^0.8.0
  Severity : low
  Gas saved : ~30 gas/loop iteration (auto-unchecked, 0.8.22+)
              + transient storage available (0.8.24+)

  Current:
    pragma solidity ^0.8.0;

  Recommended:
    pragma solidity <latest-stable>;   // check https://github.com/ethereum/solidity/releases

  Rationale: 0.8.22+ auto-unchecks simple loop counters (no manual
  unchecked{} wrapper needed). 0.8.24+ enables native tstore/tload for
  reentrancy guards (~26,900 gas saved per guarded call vs SSTORE-based
  guard). The latest stable release includes all incremental optimizer
  improvements — look up the current version before recommending.

  Action: Bump pragma to the current stable release, run forge test for
  regressions, re-verify deployment artifacts match the new compiler version.
```
