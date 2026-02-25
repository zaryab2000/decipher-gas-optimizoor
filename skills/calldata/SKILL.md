---
name: calldata
description: >
  Detects calldata inefficiencies in Solidity external functions: memory instead
  of calldata for array and struct parameters, smaller types with masking overhead
  for computation-only parameters, and multiple bool parameters that could be
  packed into a bitmap. Use when writing or reviewing external function signatures
  in Foundry-based Solidity projects. Covers CD-001 through CD-004: calldata
  arrays, calldata structs, uint256 for computation parameters, and bool bitmap
  encoding.
allowed-tools:
  - Read
---

## Purpose

Find and fix gas waste caused by unnecessary data copies at external function boundaries. When an
`external` function parameter is declared `memory`, Solidity copies the entire calldata payload into
a new memory allocation via CALLDATACOPY (3 gas + 3 gas/word + memory expansion overhead). Declaring
it `calldata` eliminates this copy entirely — the EVM reads data directly from the immutable
calldata region. For large arrays or structs, this is a one-word source change with measurable
per-call savings.

## When to Use

- Writing or reviewing any `external` function with array, `bytes`, `string`, or struct parameters
- Auditing a contract's function signatures for calldata efficiency
- After changing a function from `public` to `external` (VI-001) — `calldata` is now available
- Reviewing functions with 3 or more `bool` parameters (CD-004 candidate)

## When NOT to Use

- **`public` functions:** `calldata` parameters are not permitted on `public` functions. Apply
  VI-001 (change to `external`) first, then apply calldata optimizations.
- **`internal` and `private` functions:** `calldata` is not available for internal calls.
- **Functions that modify the array or struct:** `calldata` is immutable. If the function writes to
  array elements (`param[i] = x`) or struct fields (`param.field = y`), `memory` is required.
- **1–2 bool parameters:** bitmap encoding (CD-004) is not worth the readability cost for so few
  flags.
- **Storage struct fields:** CD-003 (prefer `uint256`) explicitly does NOT apply to storage struct
  fields — smaller types ARE the optimization there (SL-001).

## Platform Detection

```bash
# Confirm Foundry project
test -f foundry.toml && echo "Foundry detected"

# Find external functions with memory arrays/structs — CD-001, CD-002 candidates
grep -rn "external" src/ | grep "memory"

# Find small-type parameters — CD-003 candidates
grep -rn "uint8\|uint16\|uint32\|uint64" src/

# Find functions with multiple bool parameters — CD-004 candidates
grep -rn "bool.*bool" src/
```

## Quick Reference

Decision tree for each external function parameter:

```
Is the parameter an array, bytes, or string?
├─ YES, declared memory → Does the function modify any elements?
│   ├─ NO  → [CD-001] Change to calldata — save ~3 gas/byte
│   └─ YES → Leave as memory (mutation required)
└─ NO → Is the parameter a user-defined struct?
    ├─ YES, declared memory → Does the function modify any struct fields?
    │   ├─ NO  → [CD-002] Change to calldata — save ~3 gas/byte of struct
    │   └─ YES → Leave as memory
    └─ NO → Is it uint8/uint16/uint32/uint64 used only in computation?
        ├─ YES → [CD-003] Change to uint256 — save ~10–22 gas per arithmetic op
        └─ NO → Does the function have 3+ bool parameters?
            ├─ YES → [CD-004] Consider bitmap — save ~140×(N−1) gas per call
            └─ NO → No calldata optimization needed

Is the function marked public with no internal callers?
└─ YES → [VI-001 first] Change to external, then apply calldata optimizations
```

## Workflow

- [ ] **Step 1 — Identify all external functions with reference-type parameters.** Scan for every
  `external` function. List parameters whose type is: array (`T[]`), `bytes`, `string`, or a
  user-defined struct and that are declared `memory`. Also list any function with 3+ `bool`
  parameters.

- [ ] **Step 2 — Check each flagged parameter: can `memory` become `calldata`?** For each `memory`
  array or struct parameter, confirm the function body never assigns to elements or fields. If no
  mutations, change `memory` to `calldata` (CD-001 for arrays/bytes/string; CD-002 for structs).
  Propagate `calldata` to any internal functions this value is passed to — they must also accept
  `calldata`.

- [ ] **Step 3 — Check for multiple bool params and small-type computation params.** For each
  function with 3 or more `bool` parameters, evaluate bitmap encoding (CD-004). For each
  `uint8`/`uint16`/`uint32`/`uint64` parameter used only in arithmetic (never stored in a packed
  struct), change to `uint256` (CD-003).

## Supporting Docs

Only read these files when explicitly needed — do not load all three by default:

| File | Read only when… |
|---|---|
| `resources/PATTERNS.md` | You need CD-003 bitmap encoding details or a CD-004 edge case not in the Quick Reference |
| `resources/CHECKLIST.md` | Producing a formal `/gas:analyze` report and confirming completeness |
| `resources/EXAMPLE_FINDING.md` | Generating a report and needing the exact format for a multi-param struct/array finding |

## Output Format

For each finding, produce:

```
[SEVERITY] <pattern title> — <brief description>
File: <path>, line <N>
Function: <signature>
Estimated saving: <formula>

Before:
<solidity code showing the anti-pattern>

After:
<solidity code showing the fix>
```

**Concrete example finding:**

---

**[HIGH] Array parameter declared `memory` in external function — copy unnecessary (CD-001)**
**File:** src/MerkleDropper.sol, line 18
**Function:** `verifyAndClaim(uint256, bytes32[] memory)`
**Estimated saving:** ~960 gas per call (10-element proof = 320 bytes × 3 gas/byte copy avoided)

Before:
```solidity
function verifyAndClaim(
    uint256 amount,
    bytes32[] memory proof    // CALLDATACOPY: 320 bytes → ~960 gas at function entry
) external {
    require(_verify(proof, merkleRoot, keccak256(abi.encode(msg.sender, amount))));
    _claim(msg.sender, amount);
}

function _verify(bytes32[] memory proof, bytes32 root, bytes32 leaf)
    internal pure returns (bool) { /* ... */ }
```

After:
```solidity
function verifyAndClaim(
    uint256 amount,
    bytes32[] calldata proof  // direct calldata read — no copy, no memory allocation
) external {
    require(_verify(proof, merkleRoot, keccak256(abi.encode(msg.sender, amount))));
    _claim(msg.sender, amount);
}

// calldata propagated to internal helper — must match
function _verify(bytes32[] calldata proof, bytes32 root, bytes32 leaf)
    internal pure returns (bool) { /* ... */ }
```

`forge test --gas-report` to confirm; `forge test` to verify no calldata/memory mismatch errors.

---
