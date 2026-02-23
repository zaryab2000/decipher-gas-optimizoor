# Visibility Skill — Pattern Reference

## VI-001: public → external (no internal callers)

**Trigger:** `public` function never called from within the same contract body.

**Before (simple params):**
```solidity
// ~24 gas wasted per call on ABI dispatcher internal entry point
function mint(address to, uint256 tokenId) public {
    tokenOwner[tokenId] = to;
}
```

**After:**
```solidity
// external: no internal entry point generated
function mint(address to, uint256 tokenId) external {
    tokenOwner[tokenId] = to;
}
```
**Gas saving:** ~24 gas per call (dispatcher overhead eliminated).

---

## VI-001 + CD-001: Always apply together for reference-type parameters

**Before (array params):**
```solidity
// public + memory: copies entire array from calldata to memory (~3 gas/byte)
function batchTransfer(uint256[] memory ids, address to) public {
    for (uint256 i = 0; i < ids.length; ++i) {
        tokenOwner[ids[i]] = to;
    }
}
```

**After:**
```solidity
// external + calldata: no copy, reads directly from calldata
function batchTransfer(uint256[] calldata ids, address to) external {
    uint256 len = ids.length;
    for (uint256 i = 0; i < len; ++i) {
        tokenOwner[ids[i]] = to;
    }
}
```
**Gas saving:** ~24 gas (dispatcher) + ~3 gas/byte of array (copy eliminated).
For a 30-element `uint256[]` (960 bytes): ~2,904 gas saved per call.

---

## VI-002: Remove duplicate manual getter

**Trigger:** `view` function whose entire body is `return stateVar[param]` or
`return stateVar` where `stateVar` is already declared `public`.

**Before:**
```solidity
mapping(address => uint256) public balances;  // auto-generates balances(address) getter

// Duplicate: same ABI as the auto-getter, but adds bytecode
function getBalance(address user) public view returns (uint256) {
    return balances[user];
}
```

**After:**
```solidity
mapping(address => uint256) public balances;
// No getBalance — callers use balances(user) directly
```
**Gas saving:** ~200–1,000 gas at deployment (bytecode reduced); zero runtime impact.

---

## Exception patterns — do NOT remove manual getters when:

```solidity
// KEEP: adds access control the auto-getter lacks
function getBalance(address user) external view onlyOwner returns (uint256) {
    return balances[user];
}

// KEEP: converts the type
function getBalance(address user) external view returns (uint128) {
    return uint128(balances[user]);
}

// KEEP: interface requires a different name (ERC-20 balanceOf vs storage balances)
function balanceOf(address user) external view returns (uint256) {
    return balances[user];
}
```

---

## Reference: public vs external dispatch

| Visibility | Calldata behavior | Internal call | Bytecode |
|---|---|---|---|
| `public` | Copies ref-types to memory | Yes | Larger (2 entry points) |
| `external` | Reads directly from calldata | No | Smaller (1 entry point) |
