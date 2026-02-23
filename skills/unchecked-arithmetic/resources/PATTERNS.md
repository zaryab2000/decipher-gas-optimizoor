# Unchecked Arithmetic — Patterns Reference

## Pattern: UA-001 — general unchecked arithmetic with proven bounds

**Anti-pattern (pays ~30 gas overhead per operation for a check that can never trigger):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract VestingSchedule {
    uint256 public constant TOTAL_PERIODS = 12;

    // elapsed is guaranteed <= TOTAL_PERIODS by all callers — but Solidity still
    // emits ISZERO + JUMPI after the SUB opcode to check for underflow
    function remainingPeriods(uint256 elapsed) external pure returns (uint256) {
        // BAD: underflow check fires ~30 gas even though elapsed <= 12 always
        return TOTAL_PERIODS - elapsed;
    }
}
```

**Optimized (~30 gas saved per call — invariant documented; check removed):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract VestingSchedule {
    uint256 public constant TOTAL_PERIODS = 12;

    function remainingPeriods(uint256 elapsed) external pure returns (uint256) {
        // INVARIANT: all callers validate elapsed <= TOTAL_PERIODS before this call;
        //            underflow is impossible because TOTAL_PERIODS >= elapsed always
        unchecked {
            return TOTAL_PERIODS - elapsed;
        }
    }
}
```

**The EVM mechanic:** Solidity 0.8+ emits an ISZERO + conditional JUMPI after each
arithmetic opcode to detect overflow/underflow. Each check costs approximately 30 gas.
When the invariant is externally proven (caller validates `elapsed <= TOTAL_PERIODS`),
the check is dead code. `unchecked {}` removes the ISZERO + JUMPI, saving ~30 gas per
operation.

**When this applies:** Arithmetic where the invariant is proven by:
- The surrounding loop condition (i < length → i++ cannot overflow)
- A prior explicit check in the same function
- Type bounds that make overflow impossible (e.g., adding two `uint128` values stored
  in a struct guarantees the result fits in uint256)
- A constant that acts as a ceiling (TOTAL_PERIODS is 12 — `uint256 - 12` cannot
  underflow unless the minuend is below 12, which must be proven elsewhere)

**Invariant comment requirement:** Always add an inline comment immediately before the
`unchecked {}` block. The comment must state:
1. What property makes overflow/underflow impossible
2. Where that property is established (loop condition, prior require, type constraint)

**When it doesn't apply:**
- Caller is external/public and has not validated inputs — user-controlled inputs require
  a bounds check in the same function before `unchecked` can be applied
- The invariant depends on an external state change that could be modified by a
  re-entrant call between the proof and the arithmetic
- Compound expressions where intermediate values could overflow even if the final result
  fits — trace every intermediate value separately

---

## Pattern: UA-002 — post-comparison unchecked subtraction

**Anti-pattern (pays ~30 gas for a subtraction underflow check that the prior require already made impossible):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Escrow {
    mapping(address => uint256) public deposits;

    function withdraw(uint256 amount) external {
        require(deposits[msg.sender] >= amount, "Insufficient deposit");
        // BAD: Solidity still emits ISZERO after the subtraction even though
        //      the require above makes deposits[msg.sender] < amount impossible
        deposits[msg.sender] -= amount;   // ~30 gas wasted on dead underflow check
    }
}
```

**Optimized (~30 gas saved per withdraw() call; also applies CE-001 and SL-008):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Escrow {
    error InsufficientDeposit();
    mapping(address => uint256) public deposits;

    function withdraw(uint256 amount) external {
        uint256 deposit = deposits[msg.sender];   // cache SLOAD (SL-003)
        if (deposit < amount) revert InsufficientDeposit();  // CE-001: custom error
        // INVARIANT: deposit >= amount proven by the check immediately above;
        //            no re-entrancy possible (no external calls between check and write)
        unchecked {
            deposits[msg.sender] = deposit - amount;  // underflow impossible
        }
    }
}
```

**The EVM mechanic:** Same as UA-001. The require/if check above the subtraction already
guarantees `a >= b`. The Solidity underflow guard on `a - b` is redundant dead code.
Removing it with `unchecked {}` saves ~30 gas.

**When this applies:** The specific pattern is:
```
[require(a >= b) OR if (a < b) revert()]
// ... no external calls that can modify a or b ...
a - b
```
All three conditions must hold:
1. The check immediately precedes the subtraction (same scope, no interleaved code that
   could modify the variables)
2. The check operates on the *same* variables as the subtraction (not proxies or aliases)
3. No re-entrant external call exists between the check and the subtraction

**Re-entrancy safety check:** Before applying UA-002 to a function that contains external
calls, verify that:
- The subtraction happens *before* any external call (checks-effects-interactions), OR
- A reentrancy guard (`nonReentrant` modifier or transient lock) prevents state changes
  between the check and the subtraction

**When it doesn't apply:**
- When state can change between the check and the subtraction via re-entrancy and no
  guard is present — the check value may be stale by the time the subtraction executes
- When the check and the subtraction operate on different variables
  (e.g., `require(a >= c)` then `a - b` — the check proves nothing about `a - b`)
- For signed integer subtraction — underflow behavior differs; verify separately

**Required fuzz test pattern:**
```solidity
// test/Escrow.t.sol
function testWithdrawFuzz(uint256 amount) external {
    // seed: deposit a known amount
    uint256 seeded = 1_000 ether;
    vm.prank(user);
    escrow.deposit(seeded);

    // boundary: amount > seeded should revert
    if (amount > seeded) {
        vm.expectRevert(Escrow.InsufficientDeposit.selector);
    }
    vm.prank(user);
    escrow.withdraw(amount > seeded ? amount : amount);  // both branches covered

    // verify: balance exactly decremented
    if (amount <= seeded) {
        assertEq(escrow.deposits(user), seeded - amount);
    }
}
```
