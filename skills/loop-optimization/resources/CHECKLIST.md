# Loop Optimization Pre-Completion Checklist

Run this checklist on every function containing a `for` or `while` loop before marking the
optimization complete. Check each item; leave unchecked items with a justification comment.

---

## Per-Loop Items

Work through each loop in the contract in order.

### LO-001: Array Length Caching

- [ ] Every loop's bound expression has been inspected — confirm whether it references a storage
  array's `.length` directly in the condition.
- [ ] If `storageArray.length` appears in the loop condition, confirm the array length is not
  modified inside the loop body (no `push()` or `pop()` calls on that array).
- [ ] A local `uint256 len = storageArray.length;` variable is declared before the loop and used
  in the condition instead of `storageArray.length`.

### LO-002: Loop Body Storage Caching

- [ ] Every loop body has been scanned for state variable references (identifiers that refer to
  contract-level `storage` variables, not local or calldata variables).
- [ ] For each state variable found: confirmed it is loop-invariant (its value does not change
  between iterations — no writes to it inside the loop body, no external calls inside the loop
  that could modify it).
- [ ] Each loop-invariant storage read is cached in a local variable before the loop starts
  (e.g., `uint256 _rate = rewardRate;`).
- [ ] The local cache variable is used inside the loop body instead of the storage variable.

### LO-003: Unchecked Counter Increment

- [ ] The loop counter increment is wrapped in an `unchecked {}` block
  (e.g., `unchecked { ++i; }`).
- [ ] Confirmed the counter cannot overflow `uint256` given its loop bound (the bound is either
  an array length, a known constant, or an externally validated value ≤ `type(uint256).max`).
- [ ] The increment has been moved out of the for loop's third clause and into an explicit
  `unchecked { ++i; }` at the end of the loop body.

### LO-004: Pre-Increment Style

- [ ] `++i` is used instead of `i++` inside the `unchecked` block.
- [ ] If the optimizer is enabled, verified with `forge snapshot --diff` that this change produces
  a measurable difference (may be zero with optimization on — acceptable either way).

### LO-005: do-while Opportunity

- [ ] Checked whether the loop body is guaranteed to execute at least once (e.g., the function
  has a `require(arr.length > 0)` guard earlier, or the loop bound is a compile-time constant ≥ 1).
- [ ] If the non-empty invariant is enforced and tested, considered converting to `do-while`.
- [ ] If converted to `do-while`, confirmed a corresponding test covers the empty-input revert
  path so the invariant is actually enforced.

### LO-006: Boolean Short-Circuit Ordering

- [ ] Every `if`, `require`, and loop condition using `&&` or `||` in or near the loop has been
  inspected for sub-expression cost ordering.
- [ ] In each `&&` expression, the cheaper sub-expression (local variable comparison, calldata
  read, arithmetic) appears to the left of the more expensive one (storage read, external call).
- [ ] In each `||` expression, the cheaper sub-expression that is most likely to be `true`
  appears to the left.

---

## Final Verification

- [ ] Gas estimate provided for the combined saving:
  `savings = (N iterations) × (gas per iteration saved)` for LO-001, LO-002, LO-003 separately,
  then summed.
- [ ] `forge test --gas-report` run before and after — gas reduction confirmed for affected
  functions.
- [ ] `forge test` passes with no new failures — behavior is unchanged.
- [ ] No loop-invariant caching applied to variables that could change due to re-entrant external
  calls inside the loop body.
