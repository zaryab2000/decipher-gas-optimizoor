# Event Logging — Example Finding

## Contract Under Review

`StakingRewards.sol` — a staking contract storing reward history in a storage
array and emitting events without indexed fields.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract StakingRewards {
    struct RewardRecord {
        address staker;
        uint256 amount;
        uint256 timestamp;
    }

    // Issue 1 (EV-001): reward history stored on-chain, never read on-chain
    RewardRecord[] public rewardHistory;

    // Issue 2 (EV-002): no indexed fields — cannot filter by staker or epoch
    event RewardClaimed(address staker, uint256 amount, uint256 epoch);

    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public pendingRewards;

    function claimReward() external {
        uint256 reward = pendingRewards[msg.sender];
        require(reward > 0, "No rewards");

        pendingRewards[msg.sender] = 0;

        // BAD: stores historical record on-chain (3 SSTORE cold = 3 × 22,100 gas)
        rewardHistory.push(RewardRecord(msg.sender, reward, block.timestamp));

        emit RewardClaimed(msg.sender, reward, block.timestamp);
        _transfer(msg.sender, reward);
    }

    function _transfer(address to, uint256 amount) internal {}
}
```

## Finding 1 — EV-001: `rewardHistory[]` stores off-chain-only data

**File:** `StakingRewards.sol:17` (`rewardHistory.push`)
**Severity:** high
**Gas saved:** ~64,837 gas per `claimReward()` call
(3 cold SSTOREs at 22,100 gas each = 66,300 gas vs LOG2 ~1,463 gas)

`rewardHistory` is pushed on every claim but never read by any on-chain
function. Off-chain dashboards querying reward history should use events.

**Before:**
```solidity
RewardRecord[] public rewardHistory;

function claimReward() external {
    uint256 reward = pendingRewards[msg.sender];
    require(reward > 0, "No rewards");
    pendingRewards[msg.sender] = 0;

    // 3 cold SSTOREs: staker address + amount + timestamp
    rewardHistory.push(RewardRecord(msg.sender, reward, block.timestamp));

    emit RewardClaimed(msg.sender, reward, block.timestamp);
    _transfer(msg.sender, reward);
}
```

**After:**
```solidity
// rewardHistory storage array removed entirely

function claimReward() external {
    uint256 reward = pendingRewards[msg.sender];
    require(reward > 0, "No rewards");
    pendingRewards[msg.sender] = 0;

    // RewardClaimed event carries the full record — no SSTORE needed
    emit RewardClaimed(msg.sender, reward, block.timestamp);
    _transfer(msg.sender, reward);
}
```

Off-chain indexers (The Graph, Etherscan event logs) capture `RewardClaimed`
events and make them queryable by staker address, amount, or time range.

## Finding 2 — EV-002: `RewardClaimed` missing `indexed` fields

**File:** `StakingRewards.sol:14` (event declaration)
**Severity:** low
**Gas impact:** +375 gas per indexed field at emit; off-chain filtering O(1) vs O(n)

`staker` and `epoch` are the primary filter keys for reward queries.
Off-chain code querying "all rewards for staker 0xabc" or "all rewards in
epoch 5" requires topic-based filtering for efficiency.

**Before:**
```solidity
event RewardClaimed(address staker, uint256 amount, uint256 epoch);
```

**After:**
```solidity
event RewardClaimed(
    address indexed staker,   // topic 1: filter by staker address
    uint256 indexed epoch,    // topic 2: filter by reward epoch
    uint256 amount            // data field: amount retrieved alongside filter results
);
```

`amount` is left non-indexed because it is not a filter key — callers always
retrieve it as part of the result, not as a search criterion.

## Combined Fixed Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract StakingRewards {
    event RewardClaimed(
        address indexed staker,
        uint256 indexed epoch,
        uint256 amount
    );

    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public pendingRewards;

    function claimReward() external {
        uint256 reward = pendingRewards[msg.sender];
        require(reward > 0, "No rewards");
        pendingRewards[msg.sender] = 0;

        emit RewardClaimed(msg.sender, block.timestamp, reward);
        _transfer(msg.sender, reward);
    }

    function _transfer(address to, uint256 amount) internal {}
}
```

## Summary

| Finding | Location | Gas Impact |
|---|---|---|
| EV-001: remove `rewardHistory[]` | line 8–9, 17 | ~64,837 gas/claim saved |
| EV-002: add `indexed` to `staker`, `epoch` | line 14 | +750 gas/emit; O(1) filter |

## Verification

```bash
forge test --match-test testClaimReward -vvvv
# Trace should show LOG3 (2 indexed + event sig) NOT SSTORE for the history write

forge test --gas-report
# claimReward gas should drop by ~64,837 gas after removing rewardHistory push
```
