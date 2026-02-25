# Unchecked Arithmetic Patterns — Quick Reference

## UA-001: Loop counter (most common case)

```solidity
// BEFORE: overflow check on every ++i (~30 gas/iter wasted)
for (uint256 i = 0; i < items.length; i++) { ... }

// AFTER: loop condition proves i < length → i+1 cannot overflow uint256
for (uint256 i = 0; i < items.length;) {
    // ... loop body ...
    // INVARIANT: i < items.length from loop condition; i+1 <= type(uint256).max
    unchecked { ++i; }
}
```

## UA-002: Subtraction after bounds check

```solidity
// BEFORE: underflow check fires ~30 gas even though it cannot trigger
require(balance >= amount, "Insufficient");
balance -= amount;

// AFTER: require above proves balance >= amount; underflow impossible
require(balance >= amount, "Insufficient");
// INVARIANT: balance >= amount proven by require above
unchecked { balance -= amount; }
```

Or using custom errors (preferred with CE-001):
```solidity
if (balance < amount) revert InsufficientBalance();
// INVARIANT: balance >= amount proven by check above
unchecked { balance -= amount; }
```

## UA-001 general: arithmetic on proven-bounded values

```solidity
// BEFORE: multiplication of two bounded values pays ~30 gas check
uint256 TOTAL_PERIODS = 12;
function remaining(uint256 elapsed) external pure returns (uint256) {
    return TOTAL_PERIODS - elapsed;  // checked, but caller always validates elapsed <= 12
}

// AFTER: invariant documented and proven at call sites
function remaining(uint256 elapsed) external pure returns (uint256) {
    // INVARIANT: all callers validate elapsed <= TOTAL_PERIODS
    unchecked { return TOTAL_PERIODS - elapsed; }
}
```

## Safety rules (non-negotiable)

1. Always write an `// INVARIANT:` comment inside or immediately before the `unchecked {}` block
2. Only wrap the specific operation proven safe — never wrap entire function bodies
3. For business-critical arithmetic (token balances, prices): require fuzz test before applying
4. Re-entrancy: check that no external calls occur between the bounds proof and the unchecked op
