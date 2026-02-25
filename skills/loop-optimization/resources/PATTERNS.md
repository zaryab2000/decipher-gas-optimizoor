# Loop Optimization Patterns — Quick Reference

## LO-001 + LO-002 + LO-003: Combined (most common fix)

```solidity
// BEFORE: length SLOAD each iter + rewardRate SLOAD each iter + checked counter
for (uint256 i = 0; i < recipients.length; i++) {
    _pay(recipients[i], balances[recipients[i]] * rewardRate);
}

// AFTER: 3 optimizations applied together
uint256 len = recipients.length;   // LO-001: cache length (1 SLOAD)
uint256 rate = rewardRate;         // LO-002: cache storage var (1 SLOAD)
for (uint256 i = 0; i < len;) {
    _pay(recipients[i], balances[recipients[i]] * rate);
    unchecked { ++i; }             // LO-003: remove overflow check (~30 gas/iter)
}
// 100-iter saving: LO-001 ~9,600 + LO-002 ~9,600 + LO-003 ~3,000 = ~22,200 gas
```

## LO-004: Pre-increment saves ~5 gas/iter

```solidity
i++   →   ++i   // inside unchecked block — eliminates temporary value creation
```

## LO-005: do-while saves ~13 gas when body always runs

```solidity
// Use only when loop body is guaranteed to execute at least once
uint256 i;
do {
    process(items[i]);
    unchecked { ++i; }
} while (i < items.length);
```

## LO-006: Short-circuit reordering

```solidity
// Put cheapest condition first — if it fails, expensive condition never runs
// BEFORE: SLOAD (expensive) evaluated even when local check (cheap) fails
if (balances[user] > 0 && isEligible(user)) { ... }

// AFTER: local/cheap check first
if (isEligible(user) && balances[user] > 0) { ... }
```

## Edge cases

- Never cache `.length` if the loop body calls `push()` or `pop()` on the same array
- Never cache a storage variable if the loop body writes to it (stale value risk)
- On Solidity 0.8.22+, simple loop counters are auto-unchecked — LO-003 still harmless
