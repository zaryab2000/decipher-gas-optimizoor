# Example Finding: YieldVault

**Contract:** `src/YieldVault.sol`
**Findings:** IC-001 (constants), IC-002/IC-003 (immutables)

---

## Before

```solidity
contract YieldVault {
    uint256 public MAX_DEPOSIT    = 100_000 ether;  // compile-time literal
    uint256 public WITHDRAWAL_FEE = 50;             // compile-time literal

    address public owner;        // set in constructor, read in onlyOwner
    address public rewardToken;  // set in constructor, never changed
    address public treasury;     // set in constructor, never changed

    constructor(address o, address r, address t) {
        owner = o; rewardToken = r; treasury = t;
    }
    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }
}
```

## After

```solidity
contract YieldVault {
    uint256 public constant MAX_DEPOSIT    = 100_000 ether;  // IC-001
    uint256 public constant WITHDRAWAL_FEE = 50;             // IC-001

    address public immutable OWNER;         // IC-003 (in modifier — highest priority)
    address public immutable REWARD_TOKEN;  // IC-002
    address public immutable TREASURY;      // IC-002

    constructor(address o, address r, address t) {
        OWNER = o; REWARD_TOKEN = r; TREASURY = t;
    }
    modifier onlyOwner() { if (msg.sender != OWNER) revert NotOwner(); _; }
}
```

## Findings Summary

| ID | Variable | Saving |
|----|----------|--------|
| IC-001 | `MAX_DEPOSIT` | ~2,100 gas/read (slot eliminated) |
| IC-001 | `WITHDRAWAL_FEE` | ~2,100 gas/read |
| IC-003 | `owner` → `OWNER` | ~2,097 gas per `onlyOwner` call |
| IC-002 | `rewardToken`, `treasury` | ~2,097 gas/read each |

**Verify:** `forge snapshot --diff`
