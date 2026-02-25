---
name: unchecked-arithmetic
description: >
  Identifies arithmetic operations in Solidity where overflow or underflow is
  provably impossible and wraps them in unchecked {} blocks to eliminate Solidity
  0.8+ overflow guard opcodes (~30 gas per operation). Covers UA-001 (general
  unchecked arithmetic with proven bounds) and UA-002 (post-comparison unchecked
  subtraction). Never recommends unchecked without explicit proof of safety.
  Use when reviewing bounded arithmetic or subtraction that follows a bounds check
  in Foundry-based Solidity 0.8+ projects.
allowed-tools: Read
---

## Purpose

Identify arithmetic operations where the overflow/underflow invariant is provable from
the surrounding code logic, then wrap those operations in `unchecked {}` to skip
Solidity 0.8+'s automatic overflow guards (~30 gas per operation). Always require an
explicit inline comment documenting the invariant. Never recommend `unchecked` without
proof.

## When to Use This Skill

Use when:
- Claude reviews a subtraction operation that is immediately preceded by a check
  proving the minuend is greater than or equal to the subtrahend
- Claude writes loop counter increments where the bound is proven by a `for` condition
- Claude reviews arithmetic on values proven bounded by type constraints or prior
  validation (e.g., a `uint8` counter that cannot exceed 255)
- The user asks whether a specific arithmetic expression is safe to wrap in `unchecked`

## When NOT to Use This Skill

Do NOT use for:
- Any arithmetic where the overflow/underflow condition is not explicitly proven in the
  same function scope — "it looks safe" is not proof; document the invariant in a comment
  or do not apply
- User-controlled inputs that have not been validated by a prior bounds check
- Business-critical arithmetic (token balances, prices, collateral ratios) unless fuzz
  test coverage specifically targeting boundary values is confirmed to exist — always
  document the fuzz test name in the finding
- Operations inside re-entrant paths where state can change between the check and the
  arithmetic (confirm reentrancy guard present or CEI pattern followed before applying)
- Solidity versions before 0.8.0 — those have no overflow checks to remove
- When uncertain about overflow safety: state "Cannot confirm bounds — do not apply
  unchecked without fuzz test proving safety" rather than guessing

## Rationalizations to Reject

| Rationalization | Why It's Wrong | Required Action |
|-----------------|----------------|-----------------|
| "This looks safe" | Looking safe is not proof of safety — only bounds proven by code logic count | Document the invariant in an inline comment before applying `unchecked` |
| "The tests pass" | Tests only cover cases you thought of; `unchecked` wraps silently on overflow | Add fuzz tests that specifically target boundary conditions |
| "It's a small number" | Small input does not mean overflow-safe — compound expressions can overflow | Trace the maximum possible value through every arithmetic operation |
| "The compiler would catch it" | The compiler does not catch logical overflow errors — it only removes the runtime check | Prove the invariant in code and in comments |

## Platform Detection

This skill applies when the following markers are present:

**File extensions:** `*.sol`
**Project markers:** `foundry.toml` or `hardhat.config.ts` in project root
**Language markers:**
- `pragma solidity ^0.8.x;` (must be 0.8.0 or higher — overflow checks exist here)
- `contract`, `library` declarations
- Arithmetic operators: `+`, `-`, `*`, `/`, `**` in function bodies

Do not apply to Solidity < 0.8.0 (no overflow checks present to remove) or to Vyper.

## Quick Reference

**Decision tree — apply in order for each arithmetic operation:**

```
Is the operation in a loop counter increment bounded by the loop condition?
  YES → wrap in unchecked {}; add comment; verify with fuzz test (UA-001)
  NO  ↓
Is the operation a subtraction (a - b)?
  YES ↓
    Does an immediately preceding if/require prove a >= b in this scope?
      YES → wrap in unchecked {}; add comment citing the check (UA-002)
      NO  → do NOT apply unchecked
  NO  ↓
Is the operation on values with provable upper/lower bounds from type or constant?
  YES → document the invariant; wrap in unchecked {}; add fuzz test (UA-001)
  NO  → do NOT apply unchecked
```

| Pattern | Rule | Gas saving |
|---------|------|-----------|
| Loop counter `i++` bounded by `length` | UA-001 | ~30 gas/iteration |
| `a - b` where prior check proves `a >= b` | UA-002 | ~30 gas/subtraction |
| Arithmetic on values bounded by type/constant | UA-001 | ~30 gas/operation |

## Workflow

### Step 1: Identify arithmetic operations

- [ ] List every `+`, `-`, `*`, `**` expression in the function under review
- [ ] Note whether the operands are user-controlled, constants, or validated values

### Step 2: Determine if bounds are provably established

- [ ] For subtraction `a - b`: look for `require(a >= b)` or `if (a < b) revert()`
  immediately before the operation in the same scope
- [ ] For addition/multiplication: determine the maximum possible value of each operand
  — is the result provably within `type(uint256).max`?
- [ ] For loop counters: the loop condition itself (`i < length`) proves the counter
  cannot overflow if `length` is a `uint256` (bounded by type)
- [ ] If bounds cannot be proven from code in the same function → stop; do not apply

### Step 3: Document the invariant as a comment

- [ ] Write an inline comment immediately before the `unchecked {}` block stating
  exactly why overflow/underflow is impossible
- [ ] Example: `// INVARIANT: balance >= amount proven by check above`
- [ ] Example: `// INVARIANT: i < length from loop condition; i + 1 <= type(uint256).max`

### Step 4: Wrap in unchecked {} and verify

- [ ] Wrap only the specific operation(s) with proven safety — do not wrap entire
  function bodies
- [ ] Confirm with a fuzz test that exercises boundary values (amount = 0,
  amount = max, amount = balance)
- [ ] Run `forge fuzz` to validate no unexpected overflow path exists

## Output Format

When a safe unchecked opportunity is identified, report using this format:

---
**[MEDIUM] Redundant underflow check after bounds proof — use unchecked subtraction (UA-002)**
**File:** src/Escrow.sol, line 18
**Estimated saving:** ~30 gas per call to withdraw()

**Current code:**
```solidity
require(deposits[msg.sender] >= amount, "Insufficient deposit");
deposits[msg.sender] -= amount;   // underflow check redundant — already proven above
```

**Optimized code:**
```solidity
uint256 deposit = deposits[msg.sender];
if (deposit < amount) revert InsufficientDeposit();
// INVARIANT: deposit >= amount proven by check above; underflow impossible
unchecked {
    deposits[msg.sender] = deposit - amount;
}
```

**Why:** Solidity 0.8+ emits an ISZERO + JUMPI sequence after every subtraction to
detect underflow, costing ~30 gas. The `require` above already proves that
`deposits[msg.sender] >= amount`. The underflow check on the subtraction is therefore
unreachable dead code. Wrapping in `unchecked {}` removes it.

**Required before applying:** Confirm no re-entrancy between the check and the
subtraction (reentrancy guard present or CEI pattern followed). Add fuzz test:
`testWithdrawFuzz(uint256 amount)` covering `amount > deposits[caller]`.

## Supporting Docs

Only read these files when explicitly needed — do not load all three by default:

| File | Read only when… |
|---|---|
| `resources/PATTERNS.md` | You need a UA-001 edge case (multiplication overflow proof, compound expression bounds) not covered by the Quick Reference |
| `resources/CHECKLIST.md` | Producing a formal `/gas:analyze` report and confirming safety checks are complete |
| `resources/EXAMPLE_FINDING.md` | Generating a report and needing the exact format for an unchecked finding |
| `docs/evm-gas-reference.md` | You need the arithmetic opcode cost table (checked vs unchecked ADD/SUB/MUL) to back a gas estimate |
