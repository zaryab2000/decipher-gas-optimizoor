# Example Finding: Escrow

**Contract:** `src/Escrow.sol`
**Findings:** UA-002 (post-check subtraction) + UA-001 (loop counter)

---

## Before

```solidity
contract Escrow {
    mapping(address => uint256) public deposits;

    function withdraw(uint256 amount) external {
        require(deposits[msg.sender] >= amount, "Insufficient");
        deposits[msg.sender] -= amount;  // UA-002: underflow check redundant
    }

    function batchRelease(address[] calldata users) external {
        for (uint256 i = 0; i < users.length; i++) {  // UA-001: checked counter
            delete deposits[users[i]];
        }
    }
}
```

## After

```solidity
contract Escrow {
    mapping(address => uint256) public deposits;

    error InsufficientDeposit();

    function withdraw(uint256 amount) external {
        uint256 dep = deposits[msg.sender];
        if (dep < amount) revert InsufficientDeposit();
        // INVARIANT: dep >= amount proven by check above; underflow impossible
        unchecked { deposits[msg.sender] = dep - amount; }
    }

    function batchRelease(address[] calldata users) external {
        uint256 len = users.length;
        for (uint256 i = 0; i < len;) {
            delete deposits[users[i]];
            // INVARIANT: i < len from loop condition; i+1 <= type(uint256).max
            unchecked { ++i; }
        }
    }
}
```

## Findings Summary

| ID | Finding | Saving |
|----|---------|--------|
| UA-002 | Subtraction in `withdraw()` | ~30 gas/call |
| UA-001 | Loop counter in `batchRelease()` | ~30 gas × N users |

**Verify:** `forge test --match-test testWithdrawFuzz` (boundary values: 0, max, exact balance)
