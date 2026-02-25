# Example Finding: RewardDistributor

**Contract:** `src/RewardDistributor.sol`
**Findings:** LO-001 + LO-002 + LO-003 (combined loop fix)

---

## Before

```solidity
contract RewardDistributor {
    uint256 public rewardRate;
    address[] public recipients;

    function distribute() external {
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 reward = balances[recipients[i]] * rewardRate;
            _pay(recipients[i], reward);
        }
    }
}
```

## After

```solidity
function distribute() external {
    uint256 _rewardRate = rewardRate;   // LO-002: 1 SLOAD
    uint256 len = recipients.length;    // LO-001: 1 SLOAD
    for (uint256 i = 0; i < len;) {
        uint256 reward = balances[recipients[i]] * _rewardRate;
        _pay(recipients[i], reward);
        unchecked { ++i; }              // LO-003: ~30 gas/iter
    }
}
```

## Findings Summary

| ID | Finding | Saving (100 iters) |
|----|---------|-------------------|
| LO-001 | Cache `recipients.length` | ~9,600 gas |
| LO-002 | Cache `rewardRate` | ~9,600 gas |
| LO-003 | `unchecked { ++i; }` | ~3,000 gas |
| **Total** | | **~22,200 gas/call** |

**Verify:** `forge test --gas-report` before and after
