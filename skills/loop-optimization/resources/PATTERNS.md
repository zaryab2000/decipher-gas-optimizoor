# Loop Optimization Patterns

Six loop gas patterns derived from the knowledge base. Priority order: LO-002 > LO-001 > LO-003 >
LO-004 > LO-005 > LO-006.

---

## LO-001: Cache array length before loop condition

**EVM mechanic:** A storage array's `.length` property reads from a storage slot on every evaluation.
On the first loop iteration the slot is cold (2,100 gas SLOAD). On every subsequent iteration the
slot is warm (100 gas SLOAD). A local `uint256` cache replaces warm SLOADs with MLOADs (3 gas each).

**Saving:** (N−1) × 97 gas where N = number of iterations. For 100 iterations: 9,603 gas.

**When applies:** Any `for` or `while` loop whose condition expression directly references
`storageArray.length`.

**When not:** Memory arrays (`.length` is already an MLOAD). Loops where the array length changes
inside the body via `push()` or `pop()`.

### Anti-pattern

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Distributor {
    address[] public recipients;

    function distribute(uint256 amount) external {
        for (uint256 i = 0; i < recipients.length; i++) {
            // recipients.length: SLOAD on every iteration (100 gas warm after first)
            payable(recipients[i]).transfer(amount);
        }
    }
}
```

### Optimized

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Distributor {
    address[] public recipients;

    function distribute(uint256 amount) external {
        uint256 len = recipients.length;  // SLOAD once (2,100 gas cold)
        for (uint256 i = 0; i < len;) {  // len: MLOAD (3 gas per iteration)
            payable(recipients[i]).transfer(amount);
            unchecked { ++i; }
        }
    }
}
```

---

## LO-002: Cache storage variable reads used inside loop body

**EVM mechanic:** Every state variable reference inside a loop body executes one SLOAD per iteration.
Even warm SLOADs cost 100 gas. An MLOAD costs 3 gas. A loop-invariant storage variable (one whose
value is unchanged during the loop) should be read into a local variable before the loop starts.

**Saving:** (N−1) × 97 gas per cached variable (warm path). For a variable read 50 times: 4,753 gas.
If the slot is cold on entry: N × 2,097 gas (cold SLOAD 2,100 vs MLOAD 3, minus first read cost).

**When applies:** Any state variable referenced inside a loop body whose value does not change between
iterations (loop-invariant).

**When not:** Variables whose values are updated inside the loop (e.g., a running total being written
back to storage). Variables accessed via a different key on every iteration (e.g., `mapping[i]` where
each key is distinct — each read hits a different slot and cannot be cached as one value).

### Anti-pattern

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RewardCalculator {
    uint256 public rewardRate;   // storage slot — loop invariant
    uint256[] public balances;

    function totalRewards() external view returns (uint256 total) {
        for (uint256 i = 0; i < balances.length; i++) {
            total += balances[i] * rewardRate;  // rewardRate: SLOAD on every iteration
        }
    }
}
```

### Optimized

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RewardCalculator {
    uint256 public rewardRate;
    uint256[] public balances;

    function totalRewards() external view returns (uint256 total) {
        uint256 _rewardRate = rewardRate;   // SLOAD once before loop
        uint256 len = balances.length;      // SLOAD once before loop (LO-001)
        for (uint256 i = 0; i < len;) {
            total += balances[i] * _rewardRate;  // MLOAD: 3 gas
            unchecked { ++i; }
        }
    }
}
```

---

## LO-003: Wrap loop counter increment in `unchecked {}` block

**EVM mechanic:** Solidity 0.8+ wraps every arithmetic operation with overflow/underflow guard opcodes
(ISZERO + REVERT sequence). A loop counter bounded by an array length or constant can never overflow
`uint256` in practice. The overflow check is provably unnecessary but still executes on every
iteration, costing approximately 30 gas per iteration.

**Saving:** ~30 gas per iteration. For 1,000 iterations: 30,000 gas.

**When applies:** Any loop with a `uint256` counter bounded by an array length or a known constant.

**When not:** Solidity 0.8.22+ may auto-skip overflow checks for simple counters (manual `unchecked`
is then harmless but redundant). Downward-counting loops using `i--` where underflow is possible.
Loops where the bound can reach `type(uint256).max` via external input.

### Anti-pattern

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Processor {
    uint256[] public items;

    function processAll() external {
        uint256 len = items.length;
        for (uint256 i = 0; i < len; i++) {  // i++ triggers overflow check (~30 gas wasted)
            _process(items[i]);
        }
    }

    function _process(uint256 item) internal pure returns (uint256) { return item * 2; }
}
```

### Optimized

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Processor {
    uint256[] public items;

    function processAll() external {
        uint256 len = items.length;
        for (uint256 i = 0; i < len;) {
            _process(items[i]);
            unchecked { ++i; }  // no overflow check; ++i preferred (LO-004)
        }
    }

    function _process(uint256 item) internal pure returns (uint256) { return item * 2; }
}
```

---

## LO-004: Use pre-increment `++i` instead of post-increment `i++`

**EVM mechanic:** `i++` evaluates to the original value of `i` before incrementing. The compiler must
preserve the original value (DUP opcode) before overwriting it. `++i` increments `i` and returns the
new value in one step with no temporary. In the for loop increment position, the return value is
discarded, making `i++`'s two-phase evaluation pure overhead.

**Saving:** ~5 gas per iteration. May be eliminated by the optimizer — measure before relying on this.

**When applies:** Any loop counter that uses `i++` in the increment position (for loop third clause or
standalone statement).

**When not:** When the Solidity optimizer already eliminates the difference (use `forge snapshot --diff`
to confirm). This is a micro-optimization; apply only after addressing LO-001 through LO-003.

### Anti-pattern

```solidity
function sum(uint256[] calldata values) external pure returns (uint256 total) {
    uint256 len = values.length;
    for (uint256 i = 0; i < len; i++) {   // i++ — DUP overhead per iteration
        total += values[i];
    }
}
```

### Optimized

```solidity
function sum(uint256[] calldata values) external pure returns (uint256 total) {
    uint256 len = values.length;
    for (uint256 i = 0; i < len;) {
        total += values[i];
        unchecked { ++i; }   // pre-increment inside unchecked — no DUP, no overflow check
    }
}
```

---

## LO-005: Use do-while loop when at least one iteration is guaranteed

**EVM mechanic:** A `for` loop evaluates the condition before the first iteration. If the loop body is
guaranteed to execute at least once (e.g., the function reverts on empty input), that initial
condition check (comparison + JUMPI, ~13 gas) is wasted. A `do-while` loop executes the body first
and checks the condition after.

**Saving:** ~10–20 gas one-time (one initial condition evaluation eliminated).

**When applies:** Functions that validate non-empty input before the loop (e.g., `require(len > 0)`),
or where the loop bound is a compile-time constant ≥ 1.

**When not:** When the array or range could be zero-length — a `do-while` always runs the body at
least once, which would cause an out-of-bounds revert or incorrect behavior. Only use when the
non-empty invariant is explicitly enforced and tested.

### Anti-pattern

```solidity
function processItems(uint256[] calldata items) external {
    require(items.length > 0, "Empty");
    uint256 len = items.length;
    for (uint256 i = 0; i < len; ++i) {  // initial i < len check is redundant (len > 0 guaranteed)
        _process(items[i]);
    }
}
```

### Optimized

```solidity
function processItems(uint256[] calldata items) external {
    require(items.length > 0, "Empty");
    uint256 len = items.length;
    uint256 i;
    do {
        _process(items[i]);
        unchecked { ++i; }
    } while (i < len);  // condition checked after first iteration — initial check eliminated
}
```

---

## LO-006: Order boolean conditions cheapest-first for short-circuit savings

**EVM mechanic:** Solidity short-circuit evaluates `&&` and `||`: in `A && B`, if `A` is false, `B`
is never evaluated. When `A` is cheap (e.g., a local variable comparison, 3 gas) and `B` is
expensive (e.g., a storage read SLOAD, 2,100 gas cold), placing `A` first avoids `B`'s cost on
every call where `A` short-circuits.

**Saving:** Variable. Full cost of the expensive condition on every call where the cheap condition
short-circuits. A saved cold SLOAD = 2,100 gas; a saved warm SLOAD = 100 gas.

**When applies:** Any `if`, `require`, or loop condition using `&&` or `||` where one sub-expression
is clearly cheaper than another and one is more likely to resolve the expression (fail fast for `&&`,
succeed fast for `||`).

**When not:** When both conditions are equally cheap (both local variable comparisons). When the
short-circuit frequency is unknown — only reorder when the probability distribution justifies it.

### Anti-pattern

```solidity
contract AccessGate {
    mapping(address => bool) public isWhitelisted;

    function execute(address user) external {
        // isWhitelisted SLOAD (2,100 gas cold) evaluated before cheap msg.sender check
        if (isWhitelisted[user] && user == msg.sender) {
            _doWork();
        }
    }
}
```

### Optimized

```solidity
contract AccessGate {
    mapping(address => bool) public isWhitelisted;

    function execute(address user) external {
        // Cheap comparison first — if user != msg.sender, skip SLOAD entirely
        if (user == msg.sender && isWhitelisted[user]) {
            _doWork();
        }
    }
}
```
