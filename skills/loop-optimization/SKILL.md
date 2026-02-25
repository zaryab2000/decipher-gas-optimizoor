---
name: loop-optimization
description: >
  Detects loop gas inefficiencies in Solidity contracts: uncached array length in
  loop conditions, storage variable reads inside loop bodies, unprotected loop
  counters without unchecked, post-increment usage, do-while opportunities, and
  short-circuit ordering. Use when writing or reviewing for/while loops in
  Foundry-based Solidity projects. Covers LO-001 through LO-006: length caching,
  body storage caching, unchecked counters, pre-increment, do-while patterns,
  and boolean short-circuit evaluation.
allowed-tools: Read Bash
---

## Purpose

Find and fix gas inefficiencies in Solidity loop constructs. Every per-iteration
cost multiplies linearly — 100 iterations × 100 gas = 10,000 gas. Loop bodies are
the highest-leverage location for gas optimization in Solidity contracts.

## When to Use

- Writing or reviewing any `for` or `while` loop in a Solidity contract
- Auditing contracts for gas efficiency before deployment
- Responding to gas reports showing high per-call cost on functions with loops
- Reviewing contract code in Foundry-based projects (`forge test --gas-report`)

## When NOT to Use

- **Memory arrays:** `.length` on a memory array is an MLOAD — already cheap; no caching needed
- **Single-iteration loops:** constant overhead savings (LO-003/LO-004) are not worth the noise
- **Loops with external calls that modify state:** caching storage before such a loop risks stale values
- **Loops that modify the array length:** never cache `.length` if the loop body calls `push()` or `pop()`
- **Solidity 0.8.22+ with simple counters:** the compiler auto-skips overflow checks; LO-003 is redundant
  (but harmless — apply anyway for version-agnostic code)

## Rationalizations to Reject

| Claim | Why it is wrong | Correct action |
|---|---|---|
| "The loop is small" | Per-iteration costs multiply linearly — 100 iterations × 100 gas = 10,000 gas | Apply all loop optimizations regardless of loop size |
| "The compiler handles caching" | Solidity does not cache storage reads across iterations; each loop iteration pays SLOAD cost | Explicitly cache all loop-invariant storage reads before the loop |
| "It already has unchecked" | unchecked on the counter does not cache the length or body storage reads | Apply LO-001 + LO-002 + LO-003 together; they are independent savings |

## Platform Detection

```bash
# Confirm Foundry is available
forge --version

# Run gas report to find expensive loop functions
forge test --gas-report

# Trace SLOAD count in a specific loop function
forge test --match-test <testName> -vvvv | grep SLOAD
```

## Quick Reference

| Loop Pattern | Gas Impact | Fix | Example Saving (100 iters) |
|---|---|---|---|
| `i < arr.length` in condition | Medium — 97 gas/iter (warm SLOAD) | Cache to `uint256 len = arr.length` before loop | 9,603 gas |
| Storage var read in body | High — 97–2,097 gas/iter per var | Cache to local var before loop | 9,700–209,700 gas |
| `i++` without `unchecked` | Medium — ~30 gas/iter | `unchecked { ++i; }` | ~3,000 gas |
| `i++` vs `++i` | Low — ~5 gas/iter | Use `++i` inside unchecked block | ~500 gas |
| `for` when body always runs | Low — ~13 gas one-time | `do { ... } while (...)` | 13 gas flat |
| Expensive condition first in `&&` | Variable | Reorder: cheapest condition first | Up to 2,100 gas on each short-circuit |

**Priority order:** LO-002 (body caching) > LO-001 (length caching) > LO-003 (unchecked) > LO-004 (pre-increment) > LO-005 (do-while) > LO-006 (short-circuit)

## Workflow

- [ ] **Step 1 — Identify all loops.** Read the contract and list every `for` and `while` loop by
  function name and line number. Note the loop bound expression for each.

- [ ] **Step 2 — Check loop bounds (is length cached?).** For each loop, inspect the condition
  expression. If it references `storageArray.length` directly (not via a local `uint256`), flag as
  LO-001. Check that the flagged array's length is not modified inside the loop body before caching.

- [ ] **Step 3 — Check loop body (are storage reads inside?).** For each loop body, identify every
  state variable reference. If a state variable is read inside the body and its value does not change
  between iterations (i.e., it is loop-invariant), flag as LO-002. Cache it before the loop.

- [ ] **Step 4 — Check counter increment (unchecked? pre-increment?).** For each loop counter,
  verify: (a) the increment is wrapped in `unchecked {}` (LO-003); (b) `++i` is used rather than
  `i++` inside the unchecked block (LO-004). If the loop body provably runs at least once, consider
  converting to `do-while` (LO-005). If any `if`/`require` in or around the loop uses `&&` with an
  expensive left-hand condition, flag as LO-006.

## Supporting Docs

Only read these files when explicitly needed — do not load all three by default:

| File | Read only when… |
|---|---|
| `resources/PATTERNS.md` | Encountering an LO-004/LO-005/LO-006 edge case not covered by the Quick Reference above |
| `resources/CHECKLIST.md` | Producing a formal `/gas:analyze` report and confirming completeness |
| `resources/EXAMPLE_FINDING.md` | Generating a report and needing the exact format for a multi-pattern loop finding |
| `docs/evm-gas-reference.md` | You need authoritative SLOAD/MLOAD costs or unchecked arithmetic savings to back a gas estimate |

## Output Format

For each finding, produce:

```
[SEVERITY] <pattern title> — <brief description>
File: <path>, line <N>
Loop: <exact loop signature>
Estimated saving: <formula> (e.g., ~97 gas × N iterations)

Before:
<solidity code showing the anti-pattern>

After:
<solidity code showing the fix>
```

**Concrete example finding:**

---

**[HIGH] Storage variable read inside loop — not cached**
**File:** src/RewardDistributor.sol, line 45
**Loop:** `for (uint256 i = 0; i < recipients.length; i++)`
**Estimated saving:** ~97 gas × N iterations (warm SLOAD → MLOAD per iteration) + 97 gas × N for
uncached length + ~30 gas × N for checked counter. For 50 recipients: ~11,200 gas per call.

Before:
```solidity
function distribute() external {
    for (uint256 i = 0; i < recipients.length; i++) {
        uint256 reward = balances[recipients[i]] * rewardRate; // rewardRate: SLOAD each iter
        _pay(recipients[i], reward);
    }
}
```

After:
```solidity
function distribute() external {
    uint256 _rewardRate = rewardRate;         // SLOAD once before loop
    uint256 len = recipients.length;          // SLOAD once before loop
    for (uint256 i = 0; i < len;) {
        uint256 reward = balances[recipients[i]] * _rewardRate; // MLOAD: 3 gas
        _pay(recipients[i], reward);
        unchecked { ++i; }
    }
}
```

Gas breakdown for 50 recipients:
- LO-001 (length): 49 × 97 = 4,753 gas
- LO-002 (rewardRate): 49 × 97 = 4,753 gas
- LO-003 (unchecked): 50 × 30 = 1,500 gas
- **Total: ~11,006 gas saved per call**

---
