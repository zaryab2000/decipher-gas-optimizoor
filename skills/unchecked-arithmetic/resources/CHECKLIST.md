# Unchecked Arithmetic — Safety Verification Checklist

Run this checklist for **every** proposed `unchecked {}` block before including it in a
finding. A single failed gate disqualifies the application of `unchecked`. Do not apply
`unchecked` if any item cannot be confirmed.

---

## Pre-Application Checklist

- [ ] **Invariant is explicitly stated as an inline comment**
  The comment must appear immediately before the `unchecked {}` block. It must state
  *what* property makes overflow/underflow impossible and *where* that property is
  established (loop condition, preceding require, type bound, constant).
  Example: `// INVARIANT: i < length from loop condition; i + 1 <= max uint256`

- [ ] **The bounds proof comes from the same function scope**
  The invariant must be provable by reading only the current function body. Do not
  rely on external assumptions, caller documentation, or off-chain guarantees.
  If the proof requires reading another function or an external contract, the invariant
  is not established in scope — do not apply `unchecked`.

- [ ] **For subtraction: an if/require proving a >= b immediately precedes a - b**
  "Immediately precedes" means: no interleaved statements that could modify `a` or `b`
  between the check and the subtraction. The check and the subtraction must be in the
  same execution scope with no branches or external calls between them.

- [ ] **Fuzz test exists covering boundary values**
  A fuzz test must:
  - Exercise `amount = 0` (minimum input)
  - Exercise `amount = balance` (exactly equal — no underflow, edge case)
  - Exercise `amount > balance` (should revert, not wrap around)
  - Exercise random values in the full `uint256` range
  If no fuzz test exists, state the required test in the finding before recommending
  `unchecked`. Do not approve `unchecked` arithmetic that is untested at boundaries.

- [ ] **No user-controlled inputs reach the unchecked block without prior bounds validation**
  Any value that originates from `msg.sender`, calldata, or an external contract is
  user-controlled. User-controlled values MUST pass through a `require` or `if`+revert
  check that establishes their bounds before they enter an `unchecked {}` block.
  Example of a DISQUALIFYING pattern:
  ```solidity
  // amount is user-controlled; no check precedes this → UNSAFE
  unchecked { balances[msg.sender] -= amount; }
  ```

- [ ] **Re-entrancy cannot modify the bounded variable between the check and the arithmetic**
  For functions that perform external calls: confirm either
  (a) the `unchecked` subtraction appears before any external call
      (checks-effects-interactions pattern), OR
  (b) a reentrancy guard is active (nonReentrant modifier or transient lock)
  A re-entrant call that modifies the variable invalidates the check's guarantee.
  Example of a DISQUALIFYING pattern:
  ```solidity
  require(balance >= amount);
  externalToken.safeTransferFrom(...);  // re-entrant call can modify balance here
  unchecked { balance -= amount; }      // UNSAFE: balance may have changed
  ```

---

## Post-Application Verification

After applying `unchecked`, run these commands to confirm correctness:

```bash
# Run the specific fuzz test targeting the unchecked block
forge fuzz --match-test <testFunctionName>

# Run all tests to confirm no regressions
forge test

# Confirm gas saving is measurable
forge snapshot --diff
```

---

## Disqualification Reference

If any of the following are true, do NOT apply `unchecked`:

| Condition | Reason |
|-----------|--------|
| Invariant stated only in comments outside the function | Out-of-scope proof — not enforced |
| Only test coverage is happy-path unit tests | Boundary violations untested |
| External call between bounds check and subtraction, no reentrancy guard | Re-entrant invalidation possible |
| User input reaches subtraction without a same-function bounds check | Unvalidated user-controlled data |
| Multiple arithmetic operations wrapped in one `unchecked` block | Each operation needs its own proof |
| Signed integer arithmetic (`int256`) | Underflow semantics differ; verify separately |
