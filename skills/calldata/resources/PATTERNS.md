# Calldata Optimization Patterns

Four calldata gas patterns derived from the knowledge base. CD-001 and CD-002 are the
highest-impact changes; CD-003 and CD-004 are lower-impact micro-optimizations.

---

## CD-001: Use `calldata` instead of `memory` for external function array parameters

**EVM mechanic:** When an `external` function parameter is declared `memory`, Solidity emits a
CALLDATACOPY instruction at function entry, copying the entire array into a new memory allocation.
CALLDATACOPY costs 3 gas + 3 gas per 32-byte word, plus memory expansion overhead (quadratic for
large allocations). Declaring the parameter `calldata` skips this copy entirely — the EVM reads
elements via CALLDATALOAD (3 gas per 32-byte read) directly from the immutable calldata region.

**Saving:** ~3 gas per byte of array data (copy cost avoided). For a 10-element `bytes32[]` proof
(320 bytes): ~960 gas + memory expansion overhead. Scales with array size.

**When applies:** Any `external` function with an array, `bytes`, or `string` parameter declared
`memory` that the function body only reads (never writes to elements).

**When not:** If the function writes to array elements (`arr[i] = x`), `calldata` is read-only.
For `public` functions, `calldata` is not allowed — apply VI-001 first. For `internal` and
`private` functions, `calldata` is not available.

### Anti-pattern

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MerkleDropper {
    bytes32 public merkleRoot;

    // BAD: memory parameter triggers CALLDATACOPY of entire proof array (~960 gas for 10 elements)
    function verifyAndClaim(
        uint256 amount,
        bytes32[] memory proof
    ) external {
        require(_verify(proof, merkleRoot, keccak256(abi.encode(msg.sender, amount))));
        _claim(msg.sender, amount);
    }

    function _verify(bytes32[] memory proof, bytes32 root, bytes32 leaf)
        internal pure returns (bool) { return true; }

    function _claim(address to, uint256 amount) internal {}
}
```

### Optimized

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MerkleDropper {
    bytes32 public merkleRoot;

    // GOOD: calldata — no copy; each element read via CALLDATALOAD (3 gas) on access
    function verifyAndClaim(
        uint256 amount,
        bytes32[] calldata proof
    ) external {
        require(_verify(proof, merkleRoot, keccak256(abi.encode(msg.sender, amount))));
        _claim(msg.sender, amount);
    }

    // Internal helper must also accept calldata when receiving this value
    function _verify(bytes32[] calldata proof, bytes32 root, bytes32 leaf)
        internal pure returns (bool) { return true; }

    function _claim(address to, uint256 amount) internal {}
}
```

**Verification:**
```bash
forge test --gas-report
forge test --match-test testVerifyAndClaim -vvvv  # confirm no CALLDATACOPY in trace
```

---

## CD-002: Use `calldata` instead of `memory` for external function struct parameters

**EVM mechanic:** Identical to CD-001 — a `memory` struct parameter triggers CALLDATACOPY of the
entire struct into memory at function entry. A `calldata` struct is read field-by-field via
CALLDATALOAD on access, paying only for fields actually used. A 7-field Order struct (224 bytes)
costs ~672 gas to copy to memory; `calldata` eliminates this.

CD-002 is listed separately from CD-001 because the trigger differs (struct vs array) and some
developers apply `calldata` for arrays but miss structs.

**Saving:** ~3 gas per byte of struct size (copy avoided). A 224-byte struct saves ~672 gas per
call. A 4-field struct (128 bytes) saves ~384 gas per call.

**When applies:** Any `external` function with a user-defined struct parameter declared `memory`
where the function only reads struct fields (no `param.field = x` assignments).

**When not:** If the function modifies any struct field, `calldata` is read-only. For nested
dynamic types inside the struct (e.g., `bytes[] memory items`), test carefully — ABI encoding
constraints may apply. For `public` functions, apply VI-001 first.

### Anti-pattern

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract OrderProcessor {
    struct Order {
        address maker;   // 20 bytes
        address taker;   // 20 bytes
        address token;   // 20 bytes
        uint256 amount;  // 32 bytes
        uint256 price;   // 32 bytes
        uint256 expiry;  // 32 bytes
        bytes32 salt;    // 32 bytes
        // Total ABI-encoded: 224 bytes
    }

    // BAD: 224-byte Order struct and 65-byte signature both copied from calldata to memory
    function fillOrder(Order memory order, bytes memory signature) external {
        _validate(order, signature);
        _execute(order);
    }

    function _validate(Order memory o, bytes memory sig) internal pure {}
    function _execute(Order memory o) internal {}
}
```

### Optimized

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract OrderProcessor {
    struct Order {
        address maker;
        address taker;
        address token;
        uint256 amount;
        uint256 price;
        uint256 expiry;
        bytes32 salt;
    }

    // GOOD: calldata — no copy; fields read on access via CALLDATALOAD
    function fillOrder(Order calldata order, bytes calldata signature) external {
        _validate(order, signature);
        _execute(order);
    }

    // Propagate calldata through the internal call chain
    function _validate(Order calldata o, bytes calldata sig) internal pure {}
    function _execute(Order calldata o) internal {}
}
```

**Verification:**
```bash
forge test --gas-report
forge test --match-test testFillOrder -vvvv  # verify struct fields read via CALLDATALOAD
```

---

## CD-003: Use `uint256` instead of smaller types for non-storage parameters

**EVM mechanic:** The EVM operates natively on 256-bit (32-byte) words. When a smaller integer type
(`uint8`, `uint16`, `uint32`, `uint64`) is used in computation, the compiler emits AND masking
opcodes after arithmetic operations to enforce the declared range (e.g., `AND 0xFF` for `uint8`).
Each mask costs 3–22 gas. For function parameters and local variables that are never packed into a
storage slot, smaller types provide no benefit — only masking overhead.

**Saving:** ~10–22 gas per arithmetic operation on a small-type variable. The optimizer may reduce
this to zero — measure with `forge snapshot --diff` before applying.

**When applies:** `uint8`, `uint16`, `uint32`, or `uint64` function parameters, return values, or
local variables used only in arithmetic — never stored in a packed struct field.

**When not:** Storage struct fields — smaller types ARE the optimization there (SL-001). Values that
must semantically wrap at a smaller boundary (range enforcement is the intent). When the optimizer
already eliminates the difference.

### Anti-pattern

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ScoreCalculator {
    // BAD: uint8 params — AND 0xFF masking emitted after each arithmetic op
    function computeScore(uint8 a, uint8 b, uint8 weight) external pure returns (uint8) {
        uint8 sum    = a + b;        // ADD + AND 0xFF
        uint8 result = sum * weight; // MUL + AND 0xFF
        return result;
    }
}
```

### Optimized

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ScoreCalculator {
    // GOOD: uint256 — native EVM word size; no masking
    function computeScore(uint256 a, uint256 b, uint256 weight) external pure returns (uint256) {
        uint256 sum    = a + b;        // ADD only
        uint256 result = sum * weight; // MUL only
        return result;
    }
}
```

**Key rule:** Use `uint256` everywhere except packed storage struct fields.

**Verification:**
```bash
forge snapshot --diff  # measure saving; may be 0 with optimizer enabled
```

---

## CD-004: Encode multiple boolean flags as a `uint256` bitmap in calldata

**EVM mechanic:** Each `bool` parameter is ABI-encoded as a full 32-byte word in calldata (31 zero
bytes + 1 non-zero byte). Zero calldata bytes cost 4 gas each; non-zero bytes cost 16 gas each.
A `bool true` parameter therefore costs 31 × 4 + 1 × 16 = 140 gas. A `uint256` bitmap packs N
flags into one 32-byte word — same 140 gas base cost regardless of flag count. For N flags,
savings = (N−1) × ~140 gas per call.

**Saving:** ~140 × (N−1) gas per call. For 4 flags: ~420 gas per call.

**When applies:** Any function signature with 3 or more `bool` parameters that are logically option
flags for a single operation.

**When not:** 1–2 `bool` parameters (readability cost outweighs saving). When individual booleans
carry semantically distinct meanings (e.g., `isOwner`, `isExpired`). When the ABI must remain
human-readable for Etherscan or frontend tooling.

### Anti-pattern

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FeatureRouter {
    // BAD: 4 bool params — 4 × 140 gas = 560 gas in calldata
    function execute(
        address target,
        uint256 value,
        bool delegateCall,
        bool revertOnFail,
        bool trackGas,
        bool emitEvent
    ) external { }
}
```

### Optimized

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FeatureRouter {
    uint256 constant FLAG_DELEGATE_CALL  = 1;  // bit 0
    uint256 constant FLAG_REVERT_ON_FAIL = 2;  // bit 1
    uint256 constant FLAG_TRACK_GAS      = 4;  // bit 2
    uint256 constant FLAG_EMIT_EVENT     = 8;  // bit 3

    // GOOD: 4 flags in 1 uint256 — 140 gas vs 560 gas for 4 bools
    function execute(
        address target,
        uint256 value,
        uint256 flags
    ) external {
        bool delegateCall  = flags & FLAG_DELEGATE_CALL  != 0;
        bool revertOnFail  = flags & FLAG_REVERT_ON_FAIL != 0;
        bool trackGas      = flags & FLAG_TRACK_GAS      != 0;
        bool emitEvent     = flags & FLAG_EMIT_EVENT     != 0;
    }
}
```

**Verification:**
```bash
forge test --gas-report  # compare total call gas with and without bitmap
```

---

## Calldata byte cost reference

| Byte type | Cost | Notes |
|---|---|---|
| Zero byte | 4 gas | Zero-padding in ABI-encoded params |
| Non-zero byte | 16 gas | Value bytes |
| `bool true` ABI-encoded | 31 × 4 + 1 × 16 = 140 gas | 32-byte padded word |
| `bool false` ABI-encoded | 32 × 4 = 128 gas | 32 zero bytes |
| `bytes32` all non-zero | 32 × 16 = 512 gas | Worst case |
| `uint256` non-zero | 16 + 31 × 4 = 140 gas | 1 non-zero byte + 31 zero bytes |
