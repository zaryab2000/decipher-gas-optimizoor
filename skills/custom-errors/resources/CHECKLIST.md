# Custom Errors Skill — Pre-completion Checklist

Run this before marking a custom errors review complete.

## CE-001: require(cond, "string")

- [ ] All `require(` calls in the contract scanned
- [ ] Every `require` with a string literal second argument flagged
- [ ] For each flagged require: a named custom error defined at contract scope
- [ ] Replacement: `if (!cond) revert CustomError()` used consistently
- [ ] Errors shared across multiple revert sites use a single definition
- [ ] Error names are descriptive (e.g., `InsufficientBalance`, not `Error1`)

## CE-002: revert("string")

- [ ] All standalone `revert("` calls scanned
- [ ] Each bare string revert replaced with a named custom error
- [ ] No string literals remain inside `revert()` calls

## CE-003: parameterless errors with useful context

- [ ] All custom errors reviewed for missing runtime context
- [ ] Errors where useful values exist (amounts, addresses, indices) updated:
  `error InsufficientBalance(uint256 needed, uint256 available);`
- [ ] Revert sites updated to pass values:
  `revert InsufficientBalance(amount, balances[msg.sender]);`
- [ ] Errors where no useful context exists left as-is (e.g., `NotOwner()`)

## Scope check

- [ ] Solidity version is `^0.8.4` or later (custom errors require 0.8.4+)
- [ ] Test files excluded from CE-001/CE-002 (string reverts in tests are acceptable)
- [ ] Third-party library code flagged but not modified

## Verification

- [ ] `forge build` — no compilation errors
- [ ] `forge test` — all tests pass (revert message changes may break tests that
  check for specific revert strings; update test expectations)
- [ ] `forge build --sizes` — bytecode smaller after removing string literals
