# Example Finding: GovernanceToken

**Contract:** `src/GovernanceToken.sol`
**Findings:** TY-003 (bool bitmap) + TY-001 (loop counter type)

---

## Before

```solidity
contract GovernanceToken {
    bool public paused;          // slot 0
    bool public mintEnabled;     // slot 1
    bool public burnEnabled;     // slot 2
    bool public transferLocked;  // slot 3

    function batchMint(address[] calldata recipients, uint8 amount) external {
        for (uint8 i = 0; i < recipients.length; ++i) {  // TY-001: uint8 counter
            _mint(recipients[i], amount);
        }
    }
}
```

## After

```solidity
contract GovernanceToken {
    uint256 private constant FLAG_PAUSED        = 1;   // bit 0
    uint256 private constant FLAG_MINT_ENABLED  = 2;   // bit 1
    uint256 private constant FLAG_BURN_ENABLED  = 4;   // bit 2
    uint256 private constant FLAG_TRANSFER_LOCK = 8;   // bit 3
    uint256 private _flags;                             // 1 slot total

    function isPaused() external view returns (bool) { return _flags & FLAG_PAUSED != 0; }
    function pause()    external onlyOwner { _flags |= FLAG_PAUSED; }

    function batchMint(address[] calldata recipients, uint256 amount) external {
        uint256 len = recipients.length;
        for (uint256 i = 0; i < len;) {  // TY-001: uint256 counter
            _mint(recipients[i], amount);
            unchecked { ++i; }
        }
    }
}
```

## Findings Summary

| ID | Finding | Saving |
|----|---------|--------|
| TY-003 | 4 bools → 1 bitmap | ~66,300 gas (3 slots eliminated) |
| TY-001 | `uint8 i` → `uint256 i` | ~10–22 gas/iter (masking eliminated) |

**Verify:** `forge inspect GovernanceToken storageLayout --json` (1 slot, not 4)
