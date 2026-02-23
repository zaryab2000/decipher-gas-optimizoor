# Storage Layout — Example Finding: DeFi Vault

## Contract Under Review

`src/LendingVault.sol` — A lending vault tracking user positions, protocol fees, and configuration.

## Findings

### Finding 1 — SL-001: Unpacked Position Struct (HIGH)

**File:** src/LendingVault.sol, line 12
**Estimated saving:** ~44,200 gas per position created (2 eliminated cold SSTOREs)

**Current storage layout (5 slots):**
```solidity
struct Position {
    address owner;      // slot 0, bytes 0-19 (12 bytes wasted)
    uint256 principal;  // slot 1 (full slot)
    uint128 amount;     // slot 2, bytes 0-15 (16 bytes wasted)
    uint128 reward;     // slot 3, bytes 0-15 (16 bytes wasted)
    bool active;        // slot 4, byte 0 (31 bytes wasted)
}
// Total: 5 SSTOREs per new position = 110,500 gas cold
```

**Optimized layout (3 slots):**
```solidity
struct Position {
    uint256 principal;  // slot 0 (full slot)
    uint128 amount;     // slot 1, bytes 0-15
    uint128 reward;     // slot 1, bytes 16-31
    address owner;      // slot 2, bytes 0-19
    bool active;        // slot 2, byte 20
}
// Total: 3 SSTOREs per new position = 66,300 gas cold (saves 44,200 gas)
```

**Verification:**
```bash
forge inspect LendingVault storageLayout --json  # confirm slot count drops 5→3
forge snapshot --diff                            # measure gas delta on position creation
```

---

### Finding 2 — SL-003: Repeated SLOAD for `feeRate` in Distribution Loop (HIGH)

**File:** src/LendingVault.sol, line 67
**Estimated saving:** (N−1) × 97 gas per call (100-iteration loop = 9,603 gas)

**Current code:**
```solidity
function distributeRewards(address[] calldata users) external {
    for (uint256 i = 0; i < users.length; i++) {
        // feeRate SLOAD on every iteration (warm: 100 gas × N)
        positions[users[i]].reward += positions[users[i]].amount * feeRate / 1e18;
    }
}
```

**Optimized code:**
```solidity
function distributeRewards(address[] calldata users) external {
    uint256 _feeRate = feeRate;          // SL-003: SLOAD once (cold: 2,100)
    uint256 len = users.length;          // LO-001: cache array length
    for (uint256 i = 0; i < len;) {
        positions[users[i]].reward += positions[users[i]].amount * _feeRate / 1e18;
        unchecked { ++i; }              // LO-003: unchecked counter
    }
}
```

---

### Finding 3 — SL-005: SSTORE-Based Reentrancy Guard (HIGH)

**File:** src/LendingVault.sol, line 44
**Estimated saving:** ~26,900 gas per call (TSTORE vs cold SSTORE for guard)

**Current code:**
```solidity
uint256 private _locked;  // storage slot — 22,100 gas to set

modifier nonReentrant() {
    require(_locked != 1, "reentrant");
    _locked = 1;   // SSTORE cold: 22,100 gas
    _;
    _locked = 0;   // SSTORE warm: 2,900 gas
}
```

**Optimized code (Solidity 0.8.24+, EVM cancun):**
```solidity
modifier nonReentrant() {
    assembly { if tload(0) { revert(0, 0) } tstore(0, 1) }
    _;
    assembly { tstore(0, 0) }
    // TSTORE: 100 gas to set, cleared automatically at tx end
}
```

**Prerequisite:** `pragma solidity 0.8.24;` and `evm_version = "cancun"` in `foundry.toml`.

---

## Summary

| Finding | Technique | Severity | Estimated Saving |
|---|---|---|---|
| Position struct unpacked | SL-001 | HIGH | 44,200 gas/position |
| feeRate SLOAD in loop | SL-003 | HIGH | 9,603 gas/100-user call |
| SSTORE reentrancy guard | SL-005 | HIGH | 26,900 gas/guarded call |

**Total on a 100-user distribute call:** ~80,703 gas
