---
name: type-optimization
description: >
  Detects type-related gas inefficiencies in Solidity: small integer types with
  masking overhead for computation-only variables (use uint256 instead), string
  state variables that should be bytes32 for fixed short identifiers, multiple
  standalone bool state variables that should be a uint256 bitmap, and unnecessary
  type downcasts in hot paths. Covers TY-001 through TY-004. Use when writing
  variable declarations or reviewing arithmetic-heavy functions in Foundry-based
  Solidity projects.
allowed-tools: Read
---

## Purpose

Identify variable declarations and arithmetic expressions where type choices
add masking overhead or consume unnecessary storage slots. The EVM operates
natively on 256-bit words; types smaller than 256 bits add AND masking opcodes
in computation contexts and waste storage slots when used as standalone
state variables.

## When to Use

- Writing or reviewing state variable declarations
- Reviewing function signatures with small integer types
- Reviewing arithmetic-heavy functions or loop bodies
- Pre-audit cleanup of variable declarations

## When NOT to Use

- Variables inside packed storage structs: smaller types ARE the optimization
  in that context (they reduce slot count). TY-001 and SL-001 apply in
  opposite contexts.
- When a smaller type is required for interface compatibility (e.g., ERC-20
  `decimals()` returns `uint8`, ERC-2981 `royaltyInfo` returns `uint96`)
- When semantic range enforcement is the intent (a value that must wrap at 255)

## Platform Detection

Trigger on any `.sol` file containing:
- `uint8`, `uint16`, `uint32`, or `uint64` local variables, parameters, or
  return types used in computation outside of a packed struct (TY-001)
- `string` state variable assigned a short literal or fixed value (TY-002)
- Three or more standalone `bool` state variable declarations (TY-003)
- An explicit downcast immediately followed by widening in arithmetic (TY-004)

## Quick Reference

| Context | Pattern | Fix |
|---|---|---|
| Local variable / return / param NOT in packed struct | `uint8`/`uint16`/`uint32`/`uint64` in arithmetic | `uint256` (no masking) |
| Short fixed string (≤31 bytes) as state var | `string public symbol` | `bytes32` (one slot, no length) |
| 3+ standalone `bool` state vars | `bool a; bool b; bool c;` | `uint256` bitmap |
| Downcast then widen in same expression | `uint128(x) * uint256(y)` | `uint256(x) * uint256(y)` |
| Bool in packed struct alongside address | OK — keeps slot full | No change needed |

## Workflow

1. **Scan state variables: standalone bools (TY-003) and string-as-bytes32
   (TY-002).**
   List all state variable declarations at the contract level. Count
   consecutive or standalone `bool` declarations not inside a struct. If three
   or more exist, flag for TY-003 bitmap conversion. For each `string` state
   variable, check its assigned value: is it a short identifier (symbol, name,
   version string) of ≤31 bytes? If so, flag for TY-002 replacement with
   `bytes32`.

2. **Scan function signatures and local vars: small types in computation
   contexts (TY-001).**
   For each function, check parameter types and local variable declarations.
   Identify any `uint8`, `uint16`, `uint32`, or `uint64` values that are used
   in arithmetic operations and are NOT being stored in a packed struct field.
   These incur AND masking opcodes on every arithmetic operation. Flag for
   TY-001 upgrade to `uint256`.

3. **Scan hot-path arithmetic: unnecessary downcasts followed by widening
   (TY-004).**
   In functions marked as hot paths (called frequently, inside loops, or
   performance-critical), search for explicit downcast expressions of the form
   `uint128(x)` or `uint64(x)` where the cast result is immediately used in
   an expression that widens back to `uint256`. This cast pays an AND masking
   cost with no benefit. Flag for TY-004 removal of the intermediate cast.

## Output Format

Report each finding with: pattern ID, variable name or expression, file and
line reference, gas estimate, and the exact change required.

**Example finding (TY-003 — bitmap for 4 bool state vars):**

```
TY-003 | GovernanceToken.sol:8–11 | 4 standalone bool state variables
  Severity : high
  Gas saved : 3 storage slots eliminated
              Cold write savings: 3 × 22,100 = 66,300 gas
              Cold read savings : 3 × 2,100  = 6,300 gas per co-access

  Before:
    bool public paused;          // slot 0
    bool public mintEnabled;     // slot 1
    bool public burnEnabled;     // slot 2
    bool public transferLocked;  // slot 3

  After:
    uint256 private constant FLAG_PAUSED         = 1;   // bit 0
    uint256 private constant FLAG_MINT_ENABLED   = 2;   // bit 1
    uint256 private constant FLAG_BURN_ENABLED   = 4;   // bit 2
    uint256 private constant FLAG_TRANSFER_LOCK  = 8;   // bit 3

    uint256 private _flags;   // single storage slot for all 4 flags

    function isPaused() external view returns (bool) {
        return _flags & FLAG_PAUSED != 0;
    }
    function pause() external onlyOwner {
        _flags |= FLAG_PAUSED;
    }

  Verify:
    forge inspect GovernanceToken storageLayout --json  # 1 slot not 4
    forge snapshot --diff
```

**Example finding (TY-002 — bytes32 for string symbol):**

```
TY-002 | ERC20Token.sol:6 | string public symbol
  Severity : medium
  Gas saved : ~22,100 gas deployment (slot eliminated) + ~500 gas per write

  Before:
    string public symbol;
    constructor() { symbol = "USDC"; }

  After:
    bytes32 public constant SYMBOL = "USDC";
    // ERC-20 interface: return string from bytes32 in getter if needed
    function symbol() external pure returns (string memory) {
        return string(abi.encodePacked(SYMBOL));
    }

  Reason: "USDC" is 4 bytes — fits in bytes32 with no truncation risk.
  As constant, the compiler inlines the value: zero storage slots, zero
  SLOADs per read.
```

## Supporting Docs

Only read these files when explicitly needed — do not load all three by default:

| File | Read only when… |
|---|---|
| `resources/PATTERNS.md` | You need TY-004 (redundant downcast) edge cases or a TY-003 bitmap encoding example beyond what's shown above |
| `resources/CHECKLIST.md` | Producing a formal `/gas:analyze` report and confirming all type patterns were checked |
| `resources/EXAMPLE_FINDING.md` | Generating a report and needing the exact output format for a multi-type finding |
| `docs/evm-gas-reference.md` | You need slot packing rules or SSTORE costs to back a TY-002/TY-003 storage slot estimate |

**Example finding (TY-001 — uint256 for loop counter):**

```
TY-001 | BatchProcessor.sol:34 | uint8 i in loop
  Severity : low
  Gas saved : ~10–22 gas per loop iteration (AND 0xFF masking eliminated)

  Before:
    for (uint8 i = 0; i < items.length; ++i) {

  After:
    for (uint256 i = 0; i < items.length; ++i) {

  Reason: i is used only as a counter and index — never stored in a packed
  struct. uint8 triggers AND 0xFF masking after each ++i. uint256 is the
  EVM native word size; no masking needed.
```
