---
name: custom-errors
description: >
  Detects all require() with string messages and revert("string") calls in
  Solidity contracts and converts them to custom errors. Never allows string-based
  reverts to pass without flagging. Covers CE-001 (require with string → custom
  error), CE-002 (revert string → custom error), CE-003 (parameterless errors that
  should include typed context). Use when writing or reviewing any revert logic in
  Foundry-based Solidity 0.8.4+ projects.
allowed-tools:
  - Read
---

## 1. Purpose

Convert every string-based revert in a Solidity contract to a custom error. Custom
errors (introduced in Solidity 0.8.4) use a 4-byte selector instead of a string,
reducing bytecode size and runtime revert cost by ~15–50 gas per revert path.

## 2. When to Use This Skill

Use when:
- Claude is writing any `require(condition, "string")` statement
- Claude is writing any `revert("string literal")` statement
- The user asks Claude to review revert logic in a contract
- Claude is about to finalize any function that contains error conditions
- A contract imports OpenZeppelin or other libraries that still use string reverts

Fire on **every** `require(cond, "string")` or `revert("string")` without exception.

## 3. When NOT to Use This Skill

Do NOT use for:
- `require(condition)` with no message — no string to remove, nothing to convert
- `revert CustomError()` — already a custom error, review only for CE-003 context
- Contracts targeting Solidity < 0.8.4 — custom errors did not exist before 0.8.4
- Third-party library code you do not control (flag but do not modify)
- String-based reverts in test files where human-readable messages aid test output

## 4. Platform Detection

This skill applies when the following markers are present:

**File extensions:** `*.sol`
**Project markers:** `foundry.toml` or `hardhat.config.ts` in project root
**Language markers:**
- `pragma solidity ^0.8.x;` (must be 0.8.4 or higher)
- `contract`, `library`, or `interface` declarations
- `require(`, `revert(` usage in function bodies

Do not apply to Vyper (`.vy`) or non-EVM languages.

## 5. Quick Reference

| Pattern | Fix | Gas Saving |
|---------|-----|------------|
| `require(cond, "string")` | `if (!cond) revert CustomError()` | ~15–50 gas runtime + bytecode reduction |
| `revert("string")` | `revert CustomError()` | ~15–50 gas runtime + bytecode reduction |
| `revert CustomError()` with no context | Add typed params if useful | Better debugging, minimal cost |

**Decision rule:** If a quote mark appears inside a `require()` or `revert()`, this
skill fires. No exceptions.

## 6. Workflow

### Step 1: Scan for require(cond, "string") — CE-001

- [ ] Search entire file for `require(` calls
- [ ] Flag every `require` that has a string literal as its second argument
- [ ] For each: define a named custom error at contract scope
- [ ] Replace `require(cond, "msg")` with `if (!cond) revert CustomError()`
- [ ] If the same string appears at multiple call sites, declare the error once

### Step 2: Scan for revert("string") — CE-002

- [ ] Search entire file for standalone `revert("` calls
- [ ] Flag every bare string revert
- [ ] For each: define or reuse a named custom error
- [ ] Replace `revert("msg")` with `revert CustomError()`

### Step 3: Review existing custom errors for typed context — CE-003

- [ ] Identify custom errors that fire with no parameters
- [ ] Determine whether the revert site has useful runtime values (amounts, addresses, indices)
- [ ] If yes, add typed parameters: `error InsufficientBalance(uint256 needed, uint256 available)`
- [ ] Update the revert site to pass the values
- [ ] Skip if no useful context exists (e.g., `NotOwner()` — address is implicit in `msg.sender`)

## 7. Output Format

When a gas issue is identified, report using this format:

---
**[MEDIUM] String revert in require — replace with custom error (CE-001)**
**File:** src/Token.sol, line 34
**Estimated saving:** ~24 gas per revert (runtime) + ~200 gas at deployment (bytecode)

**Current code:**
```solidity
require(msg.sender == owner, "Only owner");
```

**Optimized code:**
```solidity
error NotOwner();
// ...
if (msg.sender != owner) revert NotOwner();
```

**Why:** `require(cond, "string")` ABI-encodes the string as `Error(string)` return
data on every revert (4 + 32 + 32 + padded string bytes = ~96 bytes). A custom error
encodes only its 4-byte selector. The string is also stored in contract bytecode at
200 gas/byte, increasing deployment cost.

---

## 8. Supporting Docs

- Need conversion patterns for all three CE variants? → Read: `resources/PATTERNS.md`
- Unsure what a complete finding looks like for a full contract? → Read: `resources/EXAMPLE_FINDING.md`
