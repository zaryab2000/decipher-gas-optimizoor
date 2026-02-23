# Type Optimization — Patterns Reference

## TY-001: Use uint256 for Local Variables and Loop Counters

### Pattern ID
`TY-001`

### Core concept
The EVM operates natively on 256-bit (32-byte) words. When the compiler sees
an operation on a value declared as `uint8`, `uint16`, `uint32`, or `uint64`,
it emits an AND masking opcode after each arithmetic result to enforce the
declared type's range. These masks cost ~3 gas each and serve no purpose for
values that are never stored in a packed struct.

The rule: **use `uint256` everywhere except packed storage structs.**

### Anti-pattern
```solidity
// BAD: uint8 loop counter — AND 0xFF mask after each increment
for (uint8 i = 0; i < 100; ++i) {
    // ... ~3 gas masking overhead per iteration
}

// BAD: uint32 parameters in arithmetic-heavy function
function compute(uint32 a, uint32 b) external pure returns (uint32) {
    return (a * b) / 100;   // multiple AND 0xFFFFFFFF masks
}
```

### Optimized pattern
```solidity
// GOOD: uint256 — EVM native word size, no masking
for (uint256 i = 0; i < 100; ++i) {
    // no masking overhead
}

function compute(uint256 a, uint256 b) external pure returns (uint256) {
    return (a * b) / 100;   // native 256-bit arithmetic, no masking
}
```

### Exception: packed struct fields
```solidity
// This is CORRECT — uint128 in a struct SAVES gas by packing into fewer slots
struct Position {
    uint128 amount;    // packed with reward in slot 0
    uint128 reward;    // packed with amount in slot 0
    address owner;     // packed with active in slot 1
    bool active;       // packed with owner in slot 1
}
```

---

## TY-002: bytes32 Instead of string for Fixed Short Identifiers

### Pattern ID
`TY-002`

### Core concept
Dynamic `string` in Solidity uses a length prefix and ABI encoding overhead.
Short strings (≤31 bytes) stored as `string` use one storage slot for the
length-prefixed data, but the encoding and decoding overhead is higher than
`bytes32`. A `bytes32` value is a fixed-size type: one SLOAD reads the entire
value, one SSTORE writes it, and ABI encoding is a single 32-byte push.

Combined with `constant`, `bytes32` values are inlined at compile time —
zero storage slots, zero SLOADs per read.

### Anti-pattern
```solidity
// BAD: dynamic string for a fixed short identifier
string public symbol;
string public name;
string public version;

constructor() {
    symbol  = "ETH";         // SSTORE (dynamic string encoding)
    name    = "Ethereum";    // SSTORE
    version = "1";           // SSTORE
}
```

### Optimized pattern
```solidity
// GOOD: bytes32 constant — zero storage, zero runtime cost
bytes32 public constant SYMBOL  = "ETH";
bytes32 public constant NAME    = "Ethereum";
bytes32 public constant VERSION = "1";

// For ERC-20 compatibility (name/symbol must return string):
function symbol() external pure returns (string memory) {
    return string(abi.encodePacked(SYMBOL));
}
function name() external pure returns (string memory) {
    return string(abi.encodePacked(NAME));
}
```

### When NOT to apply
- Strings that can exceed 31 bytes at runtime: `bytes32` silently truncates.
  Use `string` for variable-length data.
- When the return type must be `string` to satisfy an interface and the
  callers cannot handle `bytes32`: use the wrapper pattern shown above.

---

## TY-003: uint256 Bitmap for Multiple Bool State Variables

### Pattern ID
`TY-003`

### Core concept
Each standalone `bool` state variable occupies one full 32-byte storage slot.
Solidity does NOT automatically pack standalone state variables — only
consecutive fields within a `struct`. Three `bool` declarations = three slots
= up to 3 × 22,100 = 66,300 gas on first write.

A `uint256` bitmap stores 256 boolean flags in a single storage slot. N bools
→ 1 uint256 eliminates (N−1) slots.

### Anti-pattern
```solidity
// BAD: 4 storage slots for 4 bools
bool public paused;       // slot 0: 22,100 gas cold write
bool public mintEnabled;  // slot 1: 22,100 gas cold write
bool public burnEnabled;  // slot 2: 22,100 gas cold write
bool public transferFee;  // slot 3: 22,100 gas cold write
```

### Optimized pattern
```solidity
// GOOD: 1 storage slot for all flags
uint256 private constant FLAG_PAUSED       = 1;   // bit 0
uint256 private constant FLAG_MINT_ENABLED = 2;   // bit 1
uint256 private constant FLAG_BURN_ENABLED = 4;   // bit 2
uint256 private constant FLAG_TRANSFER_FEE = 8;   // bit 3

uint256 private _flags;   // 1 slot: 22,100 gas cold write (first flag set)

// Setters
function pause()       external { _flags |= FLAG_PAUSED; }
function enableMint()  external { _flags |= FLAG_MINT_ENABLED; }

// Getters
function isPaused()       external view returns (bool) { return _flags & FLAG_PAUSED != 0; }
function isMintEnabled()  external view returns (bool) { return _flags & FLAG_MINT_ENABLED != 0; }
```

### Gas math
- 4 standalone bools: 4 cold SSTOREs = 4 × 22,100 = 88,400 gas
- 1 bitmap: 1 cold SSTORE = 22,100 gas (subsequent flag sets cost 2,900 warm)
- Savings: 66,300 gas on first writes; 3 × 2,100 = 6,300 gas per co-read

---

## TY-004: Avoid Unnecessary Downcasts in Hot Paths

### Pattern ID
`TY-004`

### Core concept
An explicit downcast (e.g., `uint128(x)`) emits an AND masking opcode to
truncate the value to the target type's range. If the result is immediately
used in arithmetic that widens back to `uint256`, the mask provides no
benefit — only overhead (~3 gas per cast).

### Anti-pattern
```solidity
// BAD: downcast to uint128 then immediately widen back — pure masking waste
function getPrice(uint256 liquidity) external view returns (uint256) {
    uint128 sqrtP = uint128(sqrtPrice);             // AND mask (~3 gas)
    return uint256(sqrtP) * uint256(sqrtP) / liquidity;
}
```

### Optimized pattern
```solidity
// GOOD: work directly in uint256
function getPrice(uint256 liquidity) external view returns (uint256) {
    return sqrtPrice * sqrtPrice / liquidity;       // no masking
}
```

### When NOT to apply
- The downcast is required to store into a packed struct field: the AND mask
  prevents overwriting adjacent packed variables.
- The downcast is required for interface compatibility (function parameter
  type, return type, or external call argument).
- Always measure with `forge snapshot --diff` first — the optimizer may have
  already eliminated the redundant cast.
