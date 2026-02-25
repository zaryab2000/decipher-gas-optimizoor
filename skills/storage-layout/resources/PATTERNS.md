# Storage Layout Patterns — Quick Reference

## SL-001: Pack struct fields (large → small)

```solidity
// BEFORE: 5 slots (bool alone, address alone)
struct Position { bool active; uint256 value; address owner; uint128 a; uint128 b; }

// AFTER: 3 slots — save 44,200 gas per first write
struct Position { uint256 value; uint128 a; uint128 b; address owner; bool active; }
// slot 0: value | slot 1: a+b | slot 2: owner+active
```

Rule: `uint256`/`bytes32` first (full slot), then descending size, pack smalls last.

## SL-002: address + uint96 perfect fill

```solidity
// BEFORE: 2 slots
address owner;   // slot 0, 20 bytes, 12 wasted
uint96  amount;  // slot 1, 12 bytes, 20 wasted

// AFTER: 1 slot (20 + 12 = 32 bytes exactly)
address owner;   // slot N, bytes 0–19
uint96  amount;  // slot N, bytes 20–31
```

## SL-003: Cache storage variable inside a function (multiple reads)

```solidity
// BEFORE: 3 SLOADs (100 gas warm each after first)
function calc() external view returns (uint256) {
    return balances[a] * rate + balances[b] * rate; // rate: 2 warm SLOADs
}

// AFTER: 1 SLOAD + 2 MLOADs (3 gas each)
function calc() external view returns (uint256) {
    uint256 _rate = rate;
    return balances[a] * _rate + balances[b] * _rate;
}
```

## SL-005: Transient storage for reentrancy guard (requires Solidity 0.8.24+, EVM cancun)

```solidity
// BEFORE: SSTORE lock costs 22,100 gas (cold), 2,900 gas (warm unlock)
uint256 private _locked;
modifier nonReentrant() { require(_locked == 0); _locked = 1; _; _locked = 0; }

// AFTER: TSTORE/TLOAD costs 100 gas each — saves ~26,900 gas per guarded call
modifier nonReentrant() {
    assembly { if tload(0) { revert(0, 0) } tstore(0, 1) }
    _;
    assembly { tstore(0, 0) }
}
```

## SL-007: SSTORE2 for large static data (read-many, write-once)

Use when storing > 64 bytes that never changes after deployment.
Deploy data as contract bytecode; read via `EXTCODECOPY`. Avoids 22,100 gas/slot
for each 32-byte chunk. Implementation: `SSTORE2.write(data)` returns an address;
read with `SSTORE2.read(addr)`.

## SL-009: Precompute keccak256 as constant

```solidity
// BEFORE: 30 + 6 gas per word on every call
bytes32 role = keccak256("ADMIN_ROLE");

// AFTER: 0 gas (compiler inlines the value)
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
```

## SL-010: Prefer mapping over array for key-based lookup

Arrays with linear search = O(n) SLOADs. `mapping(key => value)` = O(1) single SLOAD.
Use arrays only when iteration over all elements is genuinely needed on-chain.
