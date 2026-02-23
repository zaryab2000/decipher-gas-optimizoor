# Unchecked Arithmetic — Example Finding

## Contract Under Review

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SimpleEscrow — holds deposits and allows guarded withdrawals
contract SimpleEscrow is ReentrancyGuard {
    error InsufficientDeposit();
    error ZeroAmount();

    mapping(address => uint256) public deposits;
    uint256 public totalDeposited;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        deposits[msg.sender] += amount;
        totalDeposited       += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        // BAD: Solidity 0.8+ underflow check on this subtraction is redundant
        require(deposits[msg.sender] >= amount, "Insufficient deposit");
        deposits[msg.sender] -= amount;    // ~30 gas wasted on dead check (UA-002)
        totalDeposited       -= amount;    // ~30 gas wasted on dead check (UA-002)
        emit Withdrawn(msg.sender, amount);
    }
}
```

---

## Analysis

**Pattern found:** UA-002 — subtraction after bounds check in `withdraw()`
**Operations eligible for unchecked:** 2 (both subtractions in `withdraw()`)
**Estimated saving per call:** ~60 gas (2 × ~30 gas)
**Re-entrancy safety:** confirmed — `nonReentrant` guard prevents state changes between
  the check and the subtractions
**Fuzz test required:** yes — must be added before shipping

---

## Finding

### [MEDIUM] UA-002 — Redundant underflow check on two subtractions in withdraw()

**File:** src/SimpleEscrow.sol, lines 27–28
**Estimated saving:** ~60 gas per `withdraw()` call (2 subtractions × ~30 gas each)

The `require(deposits[msg.sender] >= amount)` check on line 26 proves that
`deposits[msg.sender] >= amount`. Since `totalDeposited >= deposits[msg.sender]` is
always true (invariant: `totalDeposited` is the sum of all individual deposits),
`totalDeposited >= amount` is also proven. Both subtractions cannot underflow.
Solidity's overflow guard on each subtraction (~30 gas each) is dead code.

The `nonReentrant` modifier guarantees no external call can modify `deposits` or
`totalDeposited` between the require check and the subtractions.

**Current code:**
```solidity
require(deposits[msg.sender] >= amount, "Insufficient deposit");
deposits[msg.sender] -= amount;    // Solidity emits ISZERO+JUMPI here — redundant
totalDeposited       -= amount;    // Solidity emits ISZERO+JUMPI here — redundant
```

**Optimized code:**
```solidity
uint256 deposit = deposits[msg.sender];   // cache SLOAD (SL-003)
if (deposit < amount) revert InsufficientDeposit();   // CE-001: custom error

// INVARIANT: deposit >= amount proven by the check above.
// INVARIANT: totalDeposited >= deposit is maintained by the deposit() function invariant,
//            therefore totalDeposited >= amount also holds.
// INVARIANT: nonReentrant guard ensures no state change between check and writes.
unchecked {
    deposits[msg.sender] = deposit - amount;
    totalDeposited       = totalDeposited - amount;
}
```

**Why it is safe:**
1. `deposit >= amount` — established by `if (deposit < amount) revert()` immediately above
2. `totalDeposited >= deposit` — class invariant maintained by `deposit()`: every call to
   `deposit()` increments both `deposits[user]` and `totalDeposited` by the same amount,
   so `totalDeposited` is always the sum of all `deposits[user]` values
3. No re-entrancy — `nonReentrant` is active for the full duration of `withdraw()`

**Required fuzz test (must exist before shipping):**
```solidity
// test/SimpleEscrow.t.sol
contract SimpleEscrowTest is Test {
    SimpleEscrow escrow;
    address user = address(0xBEEF);

    function setUp() public {
        escrow = new SimpleEscrow();
    }

    function testWithdrawFuzz(uint256 depositAmount, uint256 withdrawAmount) public {
        // Bound deposit to prevent test overflow
        depositAmount = bound(depositAmount, 1, type(uint128).max);

        // Setup: user deposits
        vm.startPrank(user);
        escrow.deposit(depositAmount);

        // Case 1: withdraw more than deposited — must revert
        if (withdrawAmount > depositAmount) {
            vm.expectRevert(SimpleEscrow.InsufficientDeposit.selector);
            escrow.withdraw(withdrawAmount);
        } else if (withdrawAmount > 0) {
            // Case 2: valid withdrawal — must succeed and deduct exactly
            escrow.withdraw(withdrawAmount);
            assertEq(escrow.deposits(user), depositAmount - withdrawAmount);
            assertEq(escrow.totalDeposited(), depositAmount - withdrawAmount);
        }
        vm.stopPrank();
    }

    function testWithdrawExactBalance() public {
        // Edge case: withdraw exactly the deposited amount (balance = 0 after)
        vm.startPrank(user);
        escrow.deposit(1_000 ether);
        escrow.withdraw(1_000 ether);
        assertEq(escrow.deposits(user), 0);
        assertEq(escrow.totalDeposited(), 0);
        vm.stopPrank();
    }
}
```

---

## Optimized Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SimpleEscrow is ReentrancyGuard {
    error InsufficientDeposit();
    error ZeroAmount();

    mapping(address => uint256) public deposits;
    uint256 public totalDeposited;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        // Note: overflow of deposits[user] + amount is theoretical only (uint256 max ~1.1e77)
        deposits[msg.sender] += amount;
        totalDeposited       += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        uint256 deposit = deposits[msg.sender];  // single SLOAD cached in memory
        if (deposit < amount) revert InsufficientDeposit();

        // INVARIANT: deposit >= amount proven by check above.
        // INVARIANT: totalDeposited >= deposit (class invariant: totalDeposited is the
        //            running sum of all deposits[user] values via deposit()).
        // INVARIANT: nonReentrant prevents state changes between check and writes.
        unchecked {
            deposits[msg.sender] = deposit - amount;
            totalDeposited       = totalDeposited - amount;
        }
        emit Withdrawn(msg.sender, amount);
    }
}
```

## Gas Savings Summary

| Location | Before | After | Saving |
|----------|--------|-------|--------|
| `deposits[msg.sender] -= amount` | ~30 gas overhead | 0 | ~30 gas |
| `totalDeposited -= amount` | ~30 gas overhead | 0 | ~30 gas |
| `require(...)` → `if` + custom error | string ABI overhead | 4-byte selector | ~24 gas |
| Storage cache (SL-003) | 2nd SLOAD for deposit | MLOAD | ~97 gas warm |
| **Total per withdraw() call** | | | **~181 gas** |

## Verification

```bash
# Run the fuzz test
forge test --match-test testWithdrawFuzz -v

# Confirm boundary edge case
forge test --match-test testWithdrawExactBalance -v

# Measure gas delta
forge snapshot --diff

# Verify no ISZERO overhead in optimized path
forge test --match-test testWithdrawFuzz -vvvv  # inspect trace for overflow check opcodes
```
