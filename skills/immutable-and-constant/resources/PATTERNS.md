# Immutable and Constant — Patterns Reference

## Pattern: IC-001 — compile-time literal → constant

**Anti-pattern (costs ~2,100 gas cold SLOAD per read; wastes a storage slot):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TokenConfig {
    // BAD: literal values that never change but occupy storage slots
    uint256 public MAX_SUPPLY  = 10_000;         // SLOAD to read (2,100 gas cold)
    uint256 public MINT_PRICE  = 0.01 ether;     // SLOAD to read (2,100 gas cold)
    bytes32 public ROLE_ADMIN  = keccak256("ADMIN_ROLE");  // SLOAD to read

    function mint(uint256 quantity) external payable {
        require(msg.value >= MINT_PRICE * quantity);   // SLOAD (2,100 gas cold)
        require(totalSupply + quantity <= MAX_SUPPLY);  // SLOAD (2,100 gas cold)
    }
}
```

**Optimized (zero runtime read cost; no storage slot allocated):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TokenConfig {
    // GOOD: values inlined by compiler — PUSH literal, ~0 gas, no slot
    uint256 public constant MAX_SUPPLY  = 10_000;
    uint256 public constant MINT_PRICE  = 0.01 ether;
    bytes32 public constant ROLE_ADMIN  = keccak256("ADMIN_ROLE");  // compile-time hash

    function mint(uint256 quantity) external payable {
        require(msg.value >= MINT_PRICE * quantity);   // PUSH literal (~3 gas)
        require(totalSupply + quantity <= MAX_SUPPLY);  // PUSH literal (~3 gas)
    }
}
```

**The EVM mechanic:** `constant` variables have no storage slot. The compiler inlines
their value as a literal PUSH opcode wherever the variable is referenced. The cold SLOAD
cost (2,100 gas) is eliminated entirely. `keccak256` of a string literal is evaluated at
compile time when assigned to a `constant`.

**When this applies:** State variable has a compile-time-known value (literal number,
ether suffix, fixed keccak256 of a string, arithmetic on other constants) and is never
reassigned anywhere in the contract.

**When it doesn't apply:** Values computed from constructor arguments or runtime
data — these cannot be `constant` because they are not known at compile time. Use
`immutable` instead (IC-002).

---

## Pattern: IC-002 — constructor-set value → immutable

**Anti-pattern (costs ~22,100 gas at deployment SSTORE + ~2,100 gas cold SLOAD per read):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Staking {
    // BAD: set once in constructor — stored in regular storage slots
    address public rewardToken;  // cold SSTORE (22,100 gas) at deploy; SLOAD per read
    uint256 public lockPeriod;   // cold SSTORE (22,100 gas) at deploy; SLOAD per read
    uint256 public minStake;     // cold SSTORE (22,100 gas) at deploy; SLOAD per read

    constructor(address token, uint256 period, uint256 minimum) {
        rewardToken = token;
        lockPeriod  = period;
        minStake    = minimum;
    }

    function isUnlocked(uint256 depositTime) external view returns (bool) {
        return block.timestamp >= depositTime + lockPeriod;  // SLOAD every call (2,100 gas)
    }

    function canStake(uint256 amount) external view returns (bool) {
        return amount >= minStake;  // SLOAD every call (2,100 gas)
    }
}
```

**Optimized (~22,100 gas saved at deployment per variable + ~2,097 gas saved per read):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Staking {
    // GOOD: baked into bytecode at deployment — read via PUSH32 (~3 gas)
    address public immutable REWARD_TOKEN;
    uint256 public immutable LOCK_PERIOD;
    uint256 public immutable MIN_STAKE;

    constructor(address token, uint256 period, uint256 minimum) {
        REWARD_TOKEN = token;
        LOCK_PERIOD  = period;
        MIN_STAKE    = minimum;
    }

    function isUnlocked(uint256 depositTime) external view returns (bool) {
        return block.timestamp >= depositTime + LOCK_PERIOD;  // PUSH32 (~3 gas)
    }

    function canStake(uint256 amount) external view returns (bool) {
        return amount >= MIN_STAKE;  // PUSH32 (~3 gas)
    }
}
```

**The EVM mechanic:** `immutable` variables are recorded during construction and written
into the contract's deployed bytecode (not into storage). The EVM reads them via code
access opcodes, not SLOAD. Each read costs ~3 gas instead of 2,100 gas (cold) or 100
gas (warm). The storage slot SSTORE at deployment is also eliminated (~22,100 gas saved
per variable).

**When this applies:** State variable is assigned exactly once in the constructor and
never reassigned in any other function (including modifiers, `initialize()`, or any
external/public function).

**When it doesn't apply:**
- Variable reassigned in any function outside the constructor
- Upgradeable proxy patterns where `initialize()` replaces the constructor
- Variables whose value depends on multiple constructor calls (not possible with
  `immutable` — assignment must be a single expression in constructor body)

---

## Pattern: IC-003 — constructor-set address in hot path → immutable (priority case)

**Anti-pattern (SLOAD on every access-controlled call — 2,100 gas cold per transaction):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ProtocolVault {
    // BAD: frequently read addresses in regular storage
    address public owner;        // SLOAD on every onlyOwner check
    address public feeToken;     // SLOAD on every fee calculation
    address public treasury;     // SLOAD on every fee transfer

    constructor(address _owner, address _feeToken, address _treasury) {
        owner    = _owner;
        feeToken = _feeToken;
        treasury = _treasury;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);  // cold SLOAD (2,100 gas) per transaction
        _;
    }

    function deposit(uint256 amount) external onlyOwner {
        // IERC20(feeToken).transferFrom(...)  — another SLOAD for feeToken
    }
}
```

**Optimized (~2,097 gas saved per guarded call per address variable):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ProtocolVault {
    // GOOD: addresses in bytecode — PUSH20 (~3 gas) instead of SLOAD (2,100 gas cold)
    address public immutable OWNER;
    address public immutable FEE_TOKEN;
    address public immutable TREASURY;

    constructor(address owner, address feeToken, address treasury) {
        OWNER     = owner;
        FEE_TOKEN = feeToken;
        TREASURY  = treasury;
    }

    modifier onlyOwner() {
        require(msg.sender == OWNER);  // PUSH20 (~3 gas) — no SLOAD
        _;
    }

    function deposit(uint256 amount) external onlyOwner {
        // IERC20(FEE_TOKEN).transferFrom(...)  — PUSH20, no SLOAD for address
    }
}
```

**The EVM mechanic:** Same as IC-002, but specifically applied to `address` variables
used in modifiers and hot-path functions. The key difference is frequency: every call to
every `onlyOwner`-guarded function pays the SLOAD cost. With `immutable`, that SLOAD
becomes a PUSH20 and the savings compound across every guarded call.

**When this applies:** `address` state variable assigned in constructor, read in
modifiers or functions called with high frequency. Always flag as IC-003 (higher
priority than IC-002 due to call-frequency multiplier).

**When it doesn't apply:**
- Owner address is transferable (`transferOwnership()`) — `immutable` cannot be changed.
  Use Ownable2Step pattern with regular storage.
- Upgradeable proxy implementations — `immutable` in an implementation is embedded in
  implementation bytecode, not the proxy's storage. The proxy delegates to the
  implementation but reads its own storage for state. Use with caution.
