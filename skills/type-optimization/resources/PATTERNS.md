# Type Optimization Patterns — Quick Reference

## TY-001: Small integer types in computation → uint256

```solidity
// BEFORE: AND 0xFF mask on every arithmetic op (~10–22 gas each)
function scale(uint8 bips) external pure returns (uint256) {
    return bips * 1e14;  // EVM masks bips to 8 bits on every operation
}

// AFTER: no masking — EVM native word size
function scale(uint256 bips) external pure returns (uint256) {
    return bips * 1e14;
}
// Exception: uint8/uint16 in packed storage structs — keep smaller types there (SL-001)
```

## TY-002: Short string state variable → bytes32

```solidity
// BEFORE: dynamic-length string uses 2 storage slots + SLOAD on every read
string public symbol;
constructor() { symbol = "USDC"; }

// AFTER: fits in 1 slot; as constant — zero storage, zero SLOAD
bytes32 public constant SYMBOL = "USDC";
// ERC-20 getter if needed:
function symbol() external pure returns (string memory) {
    return string(abi.encodePacked(SYMBOL));
}
```

Applies to strings ≤31 bytes. Strings that vary or exceed 31 bytes: keep as `string`.

## TY-003: Multiple standalone bool state vars → uint256 bitmap

```solidity
// BEFORE: 4 storage slots (one per bool — each alone in a slot)
bool public paused;
bool public mintEnabled;
bool public burnEnabled;
bool public transferLocked;

// AFTER: 1 storage slot
uint256 private constant FLAG_PAUSED        = 1;
uint256 private constant FLAG_MINT_ENABLED  = 2;
uint256 private constant FLAG_BURN_ENABLED  = 4;
uint256 private constant FLAG_TRANSFER_LOCK = 8;
uint256 private _flags;

function isPaused() external view returns (bool) { return _flags & FLAG_PAUSED != 0; }
function pause()   external onlyOwner { _flags |= FLAG_PAUSED; }
// Cold write savings: 3 × 22,100 = 66,300 gas
```

## TY-004: Remove unnecessary intermediate downcast

```solidity
// BEFORE: uint128 cast → AND mask applied, then widened back to uint256
uint256 result = uint128(x) * uint256(y);

// AFTER: operate on uint256 directly
uint256 result = x * y;
// Only valid if x's value fits within the intended range (add explicit check if needed)
```
