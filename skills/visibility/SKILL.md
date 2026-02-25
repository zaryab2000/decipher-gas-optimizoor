---
name: visibility
description: >
  Detects public functions that could be external and explicit getters that
  duplicate auto-generated Solidity getters. external functions skip the internal
  entry point and enable calldata for array/struct parameters, saving ~24+ gas per
  call for simple types and thousands for arrays. Covers VI-001 (public → external
  when no internal calls) and VI-002 (remove duplicate manual getters). Use when
  writing or reviewing function declarations in Foundry-based Solidity projects.
allowed-tools:
  - Read
---

## 1. Purpose

Identify functions declared `public` that are never called internally and remove
manual getter functions that duplicate Solidity's auto-generated getters. Both
changes reduce unnecessary bytecode and enable downstream optimizations.

`public` functions generate two ABI dispatch entry points: one for external calls
(reads from calldata) and one for internal calls (parameters on stack/memory).
`external` eliminates the internal entry point, enabling `calldata` for reference
parameters.

---

## 2. When to Use This Skill

- Writing or reviewing any Solidity function declaration
- Code review of contracts with many `public` functions
- Pre-audit cleanup of a Foundry-based Solidity project
- After adding new external entry points that do not call internal functions
- After applying VI-001: combine with CD-001 (calldata) for max impact

---

## 3. When NOT to Use This Skill

- Functions already declared `external` — already optimal
- Contracts with no `public` functions
- Interface-only files or abstract contracts where visibility is inherited
- When only reviewing test files (visibility in tests has no gas impact)
- Functions called internally via bare name (`_fn()`) or `this.fn()` — must stay `public`

---

## 4. Platform Detection

Trigger on any `.sol` file containing `public` function declarations or manual
`view` getter functions. No tooling prerequisites beyond `Read`.

```bash
# Find public functions
grep -n "public" src/**/*.sol | grep -v "^.*\/\/"

# Find manual getter candidates (view returns single value)
grep -n "view returns" src/**/*.sol
```

---

## 5. Quick Reference

| Situation | Action |
|---|---|
| Function called only externally? | Change to `external` (VI-001) |
| Function takes array/struct params AND is external? | Also use `calldata` (VI-001 + CD-001) |
| Manual getter for a `public` state variable? | Remove it (VI-002) |
| Function called internally (same contract, no `this.`)? | Must stay `public` or `internal` |
| Function called via `this.fn()` from inside the contract? | Must stay `public` |
| Required by interface (e.g., ERC-20 `balanceOf`)? | Keep with appropriate visibility |

---

## 6. Workflow

**Step 1 — Find all `public` functions**
- [ ] Read the contract and list every function with `public` visibility
- [ ] Exclude constructors, state variable declarations, and interface stubs

**Step 2 — Search for internal call sites**
- [ ] For each `public` function named `fnName`: scan the full contract source for
  bare `fnName(` calls (without `this.` prefix) inside other function bodies
- [ ] If no internal call sites exist: VI-001 candidate
- [ ] Also scan for explicit duplicate getters: `view` functions whose entire body is
  `return stateVar` or `return mapping[param]` where `stateVar`/`mapping` is already
  `public` (VI-002 candidate)

**Step 3 — Apply changes**
- [ ] VI-001: Change `public` to `external`. For array, struct, `bytes`, or `string`
  parameters, also change `memory` to `calldata` (combines VI-001 + CD-001)
- [ ] VI-002: Delete the manual getter entirely. Callers use the auto-generated getter
- [ ] Run `forge test --gas-report` to confirm savings; `forge test` for regressions

---

## 7. Output Format

Report each finding using this structure:

```
**[SEVERITY] Description**
**File:** path/to/Contract.sol, line N
**Technique:** VI-00X
**Estimated saving:** ~X gas per call
[before code block]
[after code block]
**Verification:** rg "fnName\(" --type sol / forge test --gas-report
```

### Concrete example finding

**[MEDIUM] `batchTransfer` is public but never called internally — change to external (VI-001)**
**File:** src/NFTMarket.sol, line 24
**Technique:** VI-001 + CD-001
**Estimated saving:** ~984 gas per call (array copy + dispatcher overhead)

Before:
```solidity
function batchTransfer(uint256[] memory ids, address to) public {
    for (uint256 i = 0; i < ids.length; ++i) {
        tokenOwner[ids[i]] = to;
    }
}
```

After:
```solidity
function batchTransfer(uint256[] calldata ids, address to) external {
    uint256 len = ids.length;
    for (uint256 i = 0; i < len; ++i) {
        tokenOwner[ids[i]] = to;
    }
}
```

**Verification:** `rg "batchTransfer\(" --type sol` (confirm no internal callers) then `forge test --gas-report`

---

## 8. Supporting Docs

Only read these files when explicitly needed — do not load all three by default:

| File | Read only when… |
|---|---|
| `resources/PATTERNS.md` | You need VI-001 gas savings for large array parameters (>10 elements) or the VI-002 inheritance edge case |
| `resources/CHECKLIST.md` | Producing a formal `/gas:analyze` report and confirming all public functions were audited |
| `resources/EXAMPLE_FINDING.md` | Generating a report and needing the exact output format for a multi-function NFT contract finding |
