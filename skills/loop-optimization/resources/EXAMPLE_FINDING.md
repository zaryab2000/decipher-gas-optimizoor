# Loop Optimization — Example Finding: Reward Distributor

## Contract Under Review

`src/RewardDistributor.sol` — A reward distribution contract iterating over a storage array of
recipients and applying a configurable reward rate. Three separate loop gas issues are present.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RewardDistributor {
    address[] public recipients;
    mapping(address => uint256) public balances;
    mapping(address => bool) public isApprovedClaimer;
    uint256 public rewardRate;

    // BEFORE OPTIMIZATION — 3 loop issues on lines 45, 23
    function distribute() external {
        for (uint256 i = 0; i < recipients.length; i++) {
            // LO-001: recipients.length SLOAD every iteration (warm: 100 gas each)
            // LO-002: rewardRate SLOAD every iteration (warm: 100 gas each)
            // LO-003: i++ triggers Solidity overflow check (~30 gas each)
            balances[recipients[i]] += rewardRate;
        }
    }

    function claimFor(address user, uint256 amount) external {
        // LO-006: expensive SLOAD (2,100 gas) evaluated before cheap msg.sender check (3 gas)
        if (isApprovedClaimer[user] && msg.sender == user) {
            _claim(user, amount);
        }
    }

    function _claim(address user, uint256 amount) internal {}
}
```

## Findings

### Finding 1 — LO-001 + LO-002 + LO-003: Three Loop Issues Combined (HIGH)

**File:** src/RewardDistributor.sol, line 45
**Estimated saving:** ~230 gas/iteration × 100 iterations = ~23,000 gas per call

Per-iteration cost breakdown (before optimization):

| Source | Gas per iteration | Type |
|---|---|---|
| `recipients.length` SLOAD (warm) | 100 gas | LO-001 |
| `rewardRate` SLOAD (warm) | 100 gas | LO-002 |
| `i++` overflow check | ~30 gas | LO-003 |
| Total wasted per iteration | ~230 gas | — |

For 100 iterations: ~23,000 gas in pure loop scaffolding overhead.

**Current code (line 45):**
```solidity
function distribute() external {
    for (uint256 i = 0; i < recipients.length; i++) {
        balances[recipients[i]] += rewardRate;
    }
}
```

**Optimized code:**
```solidity
function distribute() external {
    uint256 len         = recipients.length;  // LO-001: SLOAD once (2,100 gas cold)
    uint256 _rewardRate = rewardRate;         // LO-002: SLOAD once (2,100 gas cold)
    for (uint256 i = 0; i < len;) {
        balances[recipients[i]] += _rewardRate;  // MLOAD: 3 gas (was 100 gas warm SLOAD)
        unchecked { ++i; }                       // LO-003 + LO-004: no overflow check
    }
}
```

**Optimized cost (100 iterations):**

| Source | Gas (optimized) |
|---|---|
| Length SLOAD (once) | 2,100 gas |
| Rate SLOAD (once) | 2,100 gas |
| Counter (100 × MLOAD) | ~300 gas |
| Total loop overhead | ~4,500 gas |

**Saving: ~22,500 gas per call** (vs ~27,000 gas before). For 100 recipients: (99 × 97) + (99 × 97) + (100 × 30) = 9,603 + 9,603 + 3,000 = **22,206 gas saved**.

---

### Finding 2 — LO-006: Expensive Condition Before Cheap Condition (LOW)

**File:** src/RewardDistributor.sol, line 23
**Estimated saving:** ~2,100 gas per rejected call (cold SLOAD skipped when msg.sender != user)

The `isApprovedClaimer[user]` mapping lookup (cold SLOAD: 2,100 gas) appears before the cheap
`msg.sender == user` comparison (~3 gas). When `msg.sender != user` — the common case for
unauthorized callers — the SLOAD is paid unnecessarily. Swapping the order short-circuits on the
cheap check first.

**Current code:**
```solidity
function claimFor(address user, uint256 amount) external {
    // SLOAD (2,100 gas cold) evaluated before cheap identity check (3 gas)
    if (isApprovedClaimer[user] && msg.sender == user) {
        _claim(user, amount);
    }
}
```

**Optimized code:**
```solidity
function claimFor(address user, uint256 amount) external {
    // Identity check first (3 gas) — SLOAD skipped when caller is not the user
    if (msg.sender == user && isApprovedClaimer[user]) {
        _claim(user, amount);
    }
}
```

---

## Combined Optimized Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RewardDistributor {
    address[] public recipients;
    mapping(address => uint256) public balances;
    mapping(address => bool) public isApprovedClaimer;
    uint256 public rewardRate;

    function distribute() external {
        uint256 len         = recipients.length;  // LO-001
        uint256 _rewardRate = rewardRate;         // LO-002
        for (uint256 i = 0; i < len;) {
            balances[recipients[i]] += _rewardRate;
            unchecked { ++i; }                    // LO-003 + LO-004
        }
    }

    function claimFor(address user, uint256 amount) external {
        if (msg.sender == user && isApprovedClaimer[user]) {  // LO-006
            _claim(user, amount);
        }
    }

    function _claim(address user, uint256 amount) internal {}
}
```

---

## Summary

| Finding | Technique | Severity | Estimated Saving |
|---|---|---|---|
| 3 loop issues combined | LO-001, LO-002, LO-003 | HIGH | ~22,206 gas per 100-recipient call |
| Expensive condition order | LO-006 | LOW | ~2,100 gas per rejected `claimFor()` call |

## Verification

```bash
forge test --match-test testDistribute --gas-report
forge test --match-test testDistribute -vvvv | grep -E "SLOAD|MLOAD"
forge snapshot --diff
```
