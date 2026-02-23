# Example Finding: DEX Order Processor

**Contract:** `src/OrderProcessor.sol`
**Description:** A DEX order-matching contract that takes large Order structs, Merkle proof arrays,
and signature bytes as external function parameters.
**Findings:** 3 (CD-002, CD-001, CD-003)
**Combined saving:** ~1,350 gas per `fillOrder()` call + ~6 gas per `calculateFee()` call

---

## Contract Under Review

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract OrderProcessor {
    struct Order {
        address maker;    // 20 bytes
        address taker;    // 20 bytes
        address token;    // 20 bytes
        uint256 amount;   // 32 bytes
        uint256 price;    // 32 bytes
        uint256 expiry;   // 32 bytes
        bytes32 salt;     // 32 bytes
        // Total: 7 fields, 224 bytes ABI-encoded
    }

    bytes32 public merkleRoot;

    // BEFORE OPTIMIZATION

    // CD-002: 224-byte Order struct + 65-byte signature both copied from calldata to memory
    function fillOrder(Order memory order, bytes memory signature) external {
        _validate(order, signature);
        _settle(order);
    }

    // CD-001: 320-byte proof array copied from calldata to memory (10-element bytes32[])
    function claimReward(
        uint256 amount,
        bytes32[] memory proof
    ) external {
        require(_verifyProof(proof, merkleRoot, keccak256(abi.encode(msg.sender, amount))));
        _distributeReward(msg.sender, amount);
    }

    // CD-003: uint8 params trigger AND masking on every arithmetic op
    function calculateFee(uint8 bips, uint8 tierMultiplier) external pure returns (uint256) {
        return bips * tierMultiplier * 1e14;
    }

    function _validate(Order memory o, bytes memory sig) internal pure {}
    function _settle(Order memory o) internal {}
    function _verifyProof(bytes32[] memory proof, bytes32 root, bytes32 leaf)
        internal pure returns (bool) { return true; }
    function _distributeReward(address to, uint256 amount) internal {}
}
```

---

## Finding 1 of 3 — CD-002: Struct Parameter Declared `memory` in External Function

**Severity:** HIGH
**File:** src/OrderProcessor.sol, line 24
**Function:** `fillOrder(Order memory order, bytes memory signature)`

The 7-field `Order` struct (224 bytes ABI-encoded) and the 65-byte signature are both copied from
calldata into memory at function entry. CALLDATACOPY costs 3 gas + 3 gas/word. For the struct:
224 bytes = 7 words → 3 + 7 × 3 = 24 gas base + memory expansion. For the signature: 65 bytes =
3 words → 3 + 3 × 3 = 12 gas base. Total estimated copy cost with expansion overhead: ~1,200 gas.

Declaring both parameters `calldata` eliminates these copies. Field values are read on demand via
CALLDATALOAD (3 gas per 32-byte field access). If only a subset of fields is accessed, the saving
is even greater than the full copy cost.

**Estimated saving:** ~672 gas (Order copy) + ~195 gas (signature copy) + ~477 gas (memory
expansion overhead) = **~1,344 gas per `fillOrder()` call.**

Before:
```solidity
function fillOrder(Order memory order, bytes memory signature) external {
    _validate(order, signature);
    _settle(order);
}

function _validate(Order memory o, bytes memory sig) internal pure {}
function _settle(Order memory o) internal {}
```

After:
```solidity
// calldata propagated to every internal function that receives this data
function fillOrder(Order calldata order, bytes calldata signature) external {
    _validate(order, signature);
    _settle(order);
}

function _validate(Order calldata o, bytes calldata sig) internal pure {}
function _settle(Order calldata o) internal {}
```

Important: `calldata` must be propagated to `_validate` and `_settle`. Internal functions that
receive a `calldata` value must also declare the parameter `calldata` — the compiler will emit an
error if there is a location mismatch.

---

## Finding 2 of 3 — CD-001: Array Parameter Declared `memory` in External Function

**Severity:** HIGH
**File:** src/OrderProcessor.sol, line 29
**Function:** `claimReward(uint256, bytes32[] memory proof)`

A 10-element `bytes32[]` Merkle proof array (320 bytes) is copied from calldata into memory at
every call. This is pure overhead — `_verifyProof` only reads elements, never writes to them.

**Estimated saving:** 320 bytes × 3 gas/byte = **~960 gas per `claimReward()` call.**

Before:
```solidity
function claimReward(
    uint256 amount,
    bytes32[] memory proof      // 320 bytes copied from calldata to memory
) external {
    require(_verifyProof(proof, merkleRoot, keccak256(abi.encode(msg.sender, amount))));
    _distributeReward(msg.sender, amount);
}

function _verifyProof(bytes32[] memory proof, bytes32 root, bytes32 leaf)
    internal pure returns (bool) { return true; }
```

After:
```solidity
function claimReward(
    uint256 amount,
    bytes32[] calldata proof    // direct calldata read — no copy
) external {
    require(_verifyProof(proof, merkleRoot, keccak256(abi.encode(msg.sender, amount))));
    _distributeReward(msg.sender, amount);
}

function _verifyProof(bytes32[] calldata proof, bytes32 root, bytes32 leaf)
    internal pure returns (bool) { return true; }
```

---

## Finding 3 of 3 — CD-003: Small-Type Parameters with Masking Overhead

**Severity:** LOW
**File:** src/OrderProcessor.sol, line 36
**Function:** `calculateFee(uint8 bips, uint8 tierMultiplier)`

`uint8` parameters cause the compiler to emit AND masking opcodes after arithmetic to enforce the
8-bit range. Since `bips` and `tierMultiplier` are used only in computation (never stored in a
packed struct), `uint256` eliminates the masking overhead with no semantic change.

**Estimated saving:** ~3–6 gas per call (2 masking ops eliminated). Measure with optimizer enabled
— the saving may be zero with high optimizer runs.

Before:
```solidity
function calculateFee(uint8 bips, uint8 tierMultiplier) external pure returns (uint256) {
    return bips * tierMultiplier * 1e14;  // MUL + AND 0xFF + MUL + AND 0xFF
}
```

After:
```solidity
function calculateFee(uint256 bips, uint256 tierMultiplier) external pure returns (uint256) {
    return bips * tierMultiplier * 1e14;  // MUL + MUL — no masking
}
```

---

## Combined Fix: Optimized Contract

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

    bytes32 public merkleRoot;

    // CD-002: calldata struct + calldata bytes
    function fillOrder(Order calldata order, bytes calldata signature) external {
        _validate(order, signature);
        _settle(order);
    }

    // CD-001: calldata array
    function claimReward(
        uint256 amount,
        bytes32[] calldata proof
    ) external {
        require(_verifyProof(proof, merkleRoot, keccak256(abi.encode(msg.sender, amount))));
        _distributeReward(msg.sender, amount);
    }

    // CD-003: uint256 params
    function calculateFee(uint256 bips, uint256 tierMultiplier) external pure returns (uint256) {
        return bips * tierMultiplier * 1e14;
    }

    function _validate(Order calldata o, bytes calldata sig) internal pure {}
    function _settle(Order calldata o) internal {}
    function _verifyProof(bytes32[] calldata proof, bytes32 root, bytes32 leaf)
        internal pure returns (bool) { return true; }
    function _distributeReward(address to, uint256 amount) internal {}
}
```

---

## Gas Summary

| Finding | Technique | Severity | Estimated Saving per Call |
|---|---|---|---|
| Order struct + signature memory→calldata | CD-002 | HIGH | ~1,344 gas per `fillOrder()` |
| Proof array memory→calldata | CD-001 | HIGH | ~960 gas per `claimReward()` |
| uint8 params → uint256 | CD-003 | LOW | ~6 gas per `calculateFee()` |

**Priority:** Fix CD-001 and CD-002 first. These are one-word source changes with no logic impact
and measurable per-call savings that scale with call volume.

For a DEX processing 1,000 `fillOrder()` calls per day at 30 gwei and ETH at $3,000:
- Saving: 1,344 gas × 1,000 × 30 × 10^-9 ETH × $3,000/ETH ≈ **$0.12/day → ~$44/year**
- All from a two-word keyword change.

---

## Verification Commands

```bash
# Gas report for all three functions
forge test --gas-report

# Trace CALLDATACOPY presence (before: should appear; after: should not)
forge test --match-test testFillOrder -vvvv | grep CALLDATACOPY
forge test --match-test testClaimReward -vvvv | grep CALLDATACOPY

# Snapshot comparison
forge snapshot --diff
```
