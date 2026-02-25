# Example Finding: LendingVault

**Contract:** `src/LendingVault.sol`
**Findings:** SL-001 (struct packing), SL-003 (storage cache)

---

## Before

```solidity
contract LendingVault {
    struct Position {
        bool active;         // slot 0 — wastes 31 bytes
        uint256 principal;   // slot 1
        address owner;       // slot 2 — wastes 12 bytes
        uint128 amount;      // slot 3, bytes 0–15
        uint128 reward;      // slot 3, bytes 16–31
    }
    // 4 slots used — optimal layout uses 3

    uint256 public feeRate;

    function accrue(address[] calldata users) external {
        for (uint256 i = 0; i < users.length; ++i) {
            positions[users[i]].reward += positions[users[i]].principal * feeRate;
            // feeRate: warm SLOAD on every iteration
        }
    }
}
```

## After

```solidity
contract LendingVault {
    struct Position {
        uint256 principal;   // slot 0
        uint128 amount;      // slot 1, bytes 0–15
        uint128 reward;      // slot 1, bytes 16–31
        address owner;       // slot 2, bytes 0–19
        bool active;         // slot 2, byte 20
    }
    // 3 slots — saves 22,100 gas per first write (SL-001)

    uint256 public feeRate;

    function accrue(address[] calldata users) external {
        uint256 _feeRate = feeRate;  // cache: 1 SLOAD (SL-003)
        uint256 len = users.length;
        for (uint256 i = 0; i < len;) {
            positions[users[i]].reward += positions[users[i]].principal * _feeRate;
            unchecked { ++i; }
        }
    }
}
```

## Findings Summary

| ID | Finding | Saving |
|----|---------|--------|
| SL-001 | Position struct: 4 → 3 slots | ~22,100 gas per first write |
| SL-003 | `feeRate` cached before loop | ~97 gas × N iterations |

**Verify:** `forge inspect LendingVault storageLayout --json` then `forge snapshot --diff`
