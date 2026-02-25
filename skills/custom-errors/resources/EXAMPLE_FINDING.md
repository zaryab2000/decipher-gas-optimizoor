# Example Finding: Token

**Contract:** `src/Token.sol`
**Findings:** CE-001 (require → custom error) + CE-003 (typed context)

---

## Before

```solidity
contract Token {
    mapping(address => uint256) public balances;

    function transfer(address to, uint256 amount) external {
        require(to != address(0), "Zero address");
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }
}
```

## After

```solidity
contract Token {
    mapping(address => uint256) public balances;

    error ZeroAddress();
    error InsufficientBalance(uint256 needed, uint256 available);

    function transfer(address to, uint256 amount) external {
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = balances[msg.sender];
        if (bal < amount) revert InsufficientBalance(amount, bal);
        unchecked { balances[msg.sender] = bal - amount; }  // UA-002 bonus
        balances[to] += amount;
    }
}
```

## Findings Summary

| ID | Finding | Saving |
|----|---------|--------|
| CE-001 | `"Zero address"` → `ZeroAddress()` | ~24 gas/revert + bytecode reduction |
| CE-001 | `"Insufficient balance"` → `InsufficientBalance` | ~50 gas/revert + bytecode |
| CE-003 | Added `needed`/`available` context | Better debuggability at no extra cost |

**Verify:** `forge test` — update `vm.expectRevert` calls in test files to use selector-based matching
