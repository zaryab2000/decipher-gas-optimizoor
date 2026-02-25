# Custom Errors Patterns — Quick Reference

## CE-001: require(cond, "string") → custom error

```solidity
// BEFORE: ABI-encodes string on every revert + stores string in bytecode (200 gas/byte)
require(amount > 0, "Amount must be positive");
require(msg.sender == owner, "Not owner");

// AFTER: 4-byte selector only — smaller bytecode, cheaper revert
error ZeroAmount();
error NotOwner();
// ...
if (amount == 0) revert ZeroAmount();
if (msg.sender != owner) revert NotOwner();
```

Saving: ~15–50 gas per revert + deployment bytecode reduction.

## CE-002: revert("string") → custom error

```solidity
// BEFORE
revert("Transfer failed");

// AFTER
error TransferFailed();
// ...
revert TransferFailed();
```

## CE-003: Add typed context to parameterless errors (when useful)

```solidity
// BEFORE: no context — debugger must reconstruct from state
error InsufficientBalance();
revert InsufficientBalance();

// AFTER: error includes runtime values for debugger/monitoring
error InsufficientBalance(uint256 needed, uint256 available);
revert InsufficientBalance(amount, balances[msg.sender]);
// Skip if no useful runtime values exist (e.g., NotOwner — msg.sender is implicit)
```

## Naming convention

- Use descriptive PascalCase: `NotOwner`, `InsufficientBalance`, `DeadlineExpired`
- Declare errors at contract scope (not inside functions)
- Reuse the same error across multiple call sites if the meaning is identical
- Don't add CE-003 context for every error — only where the values aid debugging
