# Calldata Patterns — Quick Reference

## CD-001: Array/bytes/string parameter — memory → calldata

```solidity
// BEFORE: CALLDATACOPY on every call (3 gas/byte + memory expansion)
function verify(bytes32[] memory proof) external { ... }

// AFTER: direct calldata reads — no copy
function verify(bytes32[] calldata proof) external { ... }
// 10-element proof = 320 bytes × 3 gas = ~960 gas saved per call
// Propagate calldata to any internal function this is passed to
```

## CD-002: Struct parameter — memory → calldata

```solidity
// BEFORE: entire struct copied from calldata to memory
function fill(Order memory order) external { ... }

// AFTER: reads directly from calldata
function fill(Order calldata order) external { ... }
// 224-byte Order struct = ~672 gas saved per call
```

## CD-003: Small type param in computation — use uint256

```solidity
// BEFORE: AND 0xFF mask on every arithmetic op (~10–22 gas each)
function calculateFee(uint8 bips) external pure returns (uint256) {
    return bips * BASE_AMOUNT;  // AND masking applied to bips
}

// AFTER: no masking
function calculateFee(uint256 bips) external pure returns (uint256) {
    return bips * BASE_AMOUNT;
}
// Exception: keep uint8 if it IS stored in a packed struct
```

## CD-004: Multiple bool params — consider uint256 bitmap (3+ bools only)

```solidity
// BEFORE: 3 separate bool params (each padded to 32 bytes in ABI)
function update(bool flag1, bool flag2, bool flag3) external { ... }

// AFTER: single uint256 bitmap
uint256 constant FLAG1 = 1;
uint256 constant FLAG2 = 2;
uint256 constant FLAG3 = 4;
function update(uint256 flags) external {
    if (flags & FLAG1 != 0) { ... }
}
// ~140×(N−1) gas saved per call in calldata encoding
```

## Key constraint

`calldata` requires `external`. If function is `public`, apply VI-001 first, then CD-001/CD-002.
Calldata parameters are immutable — if any element is written, `memory` is required.
