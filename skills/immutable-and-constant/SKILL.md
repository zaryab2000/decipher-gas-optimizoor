---
name: immutable-and-constant
description: >
  Detects state variables that should be declared constant or immutable in Solidity
  contracts. Constant for compile-time-known values (inlined by compiler, zero
  runtime cost), immutable for constructor-set-once values (baked into bytecode,
  ~3 gas per read vs 2100 gas cold SLOAD). Covers IC-001 (constant for literal
  assignments), IC-002 (immutable for constructor-set values), IC-003 (immutable
  for frequently-read address variables). Use when writing constructors or
  reviewing state variable declarations in Foundry-based Solidity projects.
allowed-tools:
  - Read
---

## 1. Purpose

Identify state variables that are assigned a fixed value and never modified, then
promote them to `constant` (compile-time-known values) or `immutable`
(constructor-set-once values). Both eliminate storage slots entirely: `constant`
values are inlined as bytecode literals (zero runtime read cost); `immutable` values
are baked into deployed bytecode and read via PUSH opcode (~3 gas vs 2,100 gas cold
SLOAD).

## 2. When to Use This Skill

Use when:
- Claude is writing state variable declarations at contract scope
- Claude is writing or reviewing a constructor body
- The user asks about gas costs of state variable reads
- Claude reviews a contract where `owner`, token addresses, or config values are
  stored as regular `address` or `uint256` state variables but never reassigned
- A modifier reads a state variable on every call (e.g., `onlyOwner`)

## 3. When NOT to Use This Skill

Do NOT use for:
- Variables that are reassigned in any function after the constructor — those require
  regular storage; `immutable` is disqualified if reassigned outside the constructor
- Variables set in an `initialize()` function in upgradeable contracts — `immutable`
  requires assignment in the constructor only; initializer patterns use storage
- `immutable` in proxy implementation contracts — the value lives in the
  implementation's bytecode, not the proxy's storage; use with care
- Variables that must be updatable (e.g., a transferable owner address) — use regular
  storage with appropriate access control

## 4. Platform Detection

This skill applies when the following markers are present:

**File extensions:** `*.sol`
**Project markers:** `foundry.toml` or `hardhat.config.ts` in project root
**Language markers:**
- `pragma solidity ^0.8.x;`
- `contract` declarations with state variable sections
- `constructor(` present or state variables with initializers

Do not apply to Vyper (`.vy`) or non-EVM languages.

## 5. Quick Reference

**Decision tree — apply in order for each state variable:**

```
Is the value known at compile time (literal or constant expression)?
  YES → constant (~0 gas per read, no storage slot)
  NO  ↓
Is the value set exactly once in the constructor and never reassigned?
  YES → immutable (~3 gas per read, no storage slot)
  NO  ↓
Is it an address set in the constructor, read in hot paths (modifiers, frequent calls)?
  YES → immutable — IC-003 priority case (savings apply on every guarded call)
  NO  ↓
Value must change after deployment → regular storage (necessary cost)
```

| Modifier | Read cost | Slot allocated | Set location |
|----------|-----------|----------------|--------------|
| (none) | ~2,100 gas cold SLOAD | Yes | Anywhere |
| `immutable` | ~3 gas (PUSH32) | No | Constructor only |
| `constant` | ~0 gas (inlined) | No | Declaration only |

## 6. Workflow

### Step 1: Scan all state variable declarations

- [ ] List every state variable at contract scope with its type and current modifier
- [ ] For each: check if the value is a compile-time literal or constant expression
  - Examples: `uint256 MAX = 10_000`, `bytes32 ROLE = keccak256("ADMIN")`,
    `uint256 FEE = 0.01 ether`
  - If yes → flag as IC-001 (should be `constant`)

### Step 2: Scan the constructor for set-once assignments

- [ ] Identify which state variables are assigned in the constructor
- [ ] For each: verify no other function reassigns the same variable
  - Search for the variable name in all function bodies outside the constructor
  - If no reassignment found → flag as IC-002 or IC-003
- [ ] IC-003 priority: `address` variables read in modifiers or high-frequency
  functions get the highest priority label

### Step 3: Identify hot-path variables (IC-003 priority)

- [ ] Scan all `modifier` bodies for storage variable reads
- [ ] Scan frequently-called external functions for repeated state variable reads
- [ ] Prioritize these in the report — they save gas on every single call

## 7. Output Format

When a gas issue is identified, report using this format:

---
**[HIGH] Constructor-set address stored in regular storage — use immutable (IC-003)**
**File:** src/ProtocolVault.sol, lines 8–10
**Estimated saving:** ~2,097 gas per `onlyOwner` call (cold SLOAD → PUSH20)

**Current code:**
```solidity
address public owner;       // SLOAD on every onlyOwner check (2,100 gas cold)
address public feeToken;    // SLOAD on every fee calculation
address public treasury;    // SLOAD on every fee transfer

constructor(address _owner, address _feeToken, address _treasury) {
    owner    = _owner;
    feeToken = _feeToken;
    treasury = _treasury;
}
```

**Optimized code:**
```solidity
address public immutable OWNER;
address public immutable FEE_TOKEN;
address public immutable TREASURY;

constructor(address owner, address feeToken, address treasury) {
    OWNER     = owner;
    FEE_TOKEN = feeToken;
    TREASURY  = treasury;
}
```

**Why:** `immutable` values are embedded in deployed bytecode. Each read uses a PUSH20
opcode (~3 gas) rather than SLOAD (2,100 gas cold). For a contract with 5 guarded
functions called 200 times per day, declaring `owner` immutable saves
1,000 × 2,097 gas = 2,097,000 gas per day from this single change.

---

## 8. Supporting Docs

Only read these files when explicitly needed — do not load both by default:

| File | Read only when… |
|---|---|
| `resources/PATTERNS.md` | You need IC-003 hot-path examples or edge cases (e.g., immutable in library vs contract) not in the Quick Reference |
| `resources/CHECKLIST.md` | Producing a formal `/gas:analyze` report and confirming completeness |
| `resources/EXAMPLE_FINDING.md` | Generating a report and needing the exact format for a multi-variable vault finding |
| `docs/evm-gas-reference.md` | You need SLOAD cold/warm costs vs PUSH opcode cost to quantify immutable savings |
