# Storage Layout Patterns — SL-001 through SL-010

Gas constants used throughout (EIP-2929, EIP-1153, EIP-3529):
- Cold SLOAD: 2,100 gas
- Warm SLOAD: 100 gas
- MLOAD: 3 gas
- Cold SSTORE zero→nonzero: 22,100 gas
- Cold SSTORE nonzero→nonzero: 5,000 gas (+ 2,900 warm)
- SSTORE nonzero→zero: 5,000 gas (+ 4,800 refund post-EIP-3529)
- TSTORE: 100 gas
- TLOAD: 100 gas
- KECCAK256: 30 gas + 6 gas per 32-byte word

---

## Pattern: SL-001 — Pack struct fields to minimize slots

**Anti-pattern (costs up to 110,500 gas for 5 slots first write):**
```solidity
pragma solidity ^0.8.20;

contract TokenVault {
    struct Position {
        uint128 amount;    // slot 0 (16 bytes used, 16 bytes wasted)
        uint256 principal; // slot 1 (uint256 cannot share a slot)
        uint128 reward;    // slot 2 (16 bytes used, 16 bytes wasted)
        address owner;     // slot 3 (20 bytes used, 12 bytes wasted)
        bool active;       // slot 4 (1 byte used, 31 bytes wasted)
    }
    // 5 slots — 5 × 22,100 = 110,500 gas on first write

    mapping(uint256 => Position) public positions;
}
```

**Optimized (saves ~44,200 gas per write — 2 fewer slots):**
```solidity
pragma solidity ^0.8.20;

contract TokenVault {
    struct Position {
        uint256 principal; // slot 0 (full 32 bytes, must be alone)
        uint128 amount;    // slot 1, bytes 0-15
        uint128 reward;    // slot 1, bytes 16-31
        address owner;     // slot 2, bytes 0-19
        bool active;       // slot 2, byte 20
    }
    // 3 slots — 3 × 22,100 = 66,300 gas on first write

    mapping(uint256 => Position) public positions;
}
```

**The EVM mechanic:** Solidity packs consecutive fields into a slot only if they fit
without crossing a 32-byte boundary; placing a `uint256` after a `uint128` forces a new
slot because `uint256` requires 32-byte alignment.

**When this applies:** Any struct with fields of mixed sizes where total bytes < 32 × N
(i.e., there are gaps that could be eliminated by reordering).

**When it doesn't apply:** Upgradeable proxy contracts where storage layout is frozen;
structs where fields are always accessed in isolation (packing adds mask overhead).

---

## Pattern: SL-002 — Pack address + uint96 for a perfect 32-byte slot

**Anti-pattern (costs 44,200 gas — 2 cold SSTOREs to write config):**
```solidity
pragma solidity ^0.8.20;

contract FeeRegistry {
    struct PoolConfig {
        address token;   // slot 0 (20 bytes, 12 bytes wasted)
        uint256 feeBps;  // slot 1 (uint256 won't fit in remaining 12 bytes)
    }
    // 2 slots: co-read costs 4,200 gas cold (2 SLOADs)

    mapping(address => PoolConfig) public configs;
}
```

**Optimized (saves ~22,100 gas per write, ~2,100 gas per co-read):**
```solidity
pragma solidity ^0.8.20;

contract FeeRegistry {
    struct PoolConfig {
        address token;  // slot 0, bytes 0-19
        uint96 feeBps;  // slot 0, bytes 20-31 (20 + 12 = 32, perfect fill)
    }
    // 1 slot: co-read costs 2,100 gas cold (1 SLOAD)

    mapping(address => PoolConfig) public configs;
}
```

**The EVM mechanic:** `address` is 20 bytes and `uint96` is 12 bytes; together they sum
to exactly 32 bytes, filling one slot with zero wasted space.

**When this applies:** Any struct with an `address` field alongside a numeric field
whose value range fits in 96 bits (max ~7.9 × 10²⁸ — sufficient for fees, timestamps,
balances in most protocols).

**When it doesn't apply:** If the numeric field's actual value can exceed `2^96 - 1`,
downcasting to `uint96` will silently overflow; verify the value range first.

---

## Pattern: SL-003 — Cache storage variables in memory before repeated use

**Anti-pattern (costs 2 × 2,100 = 4,200 gas for 2 cold SLOADs of same variable):**
```solidity
pragma solidity ^0.8.20;

contract StakingPool {
    uint256 public totalStaked;
    uint256 public rewardRate;

    function computeReward(uint256 userStake) external view returns (uint256) {
        if (userStake > totalStaked) revert();          // SLOAD 1: 2,100 gas cold
        return (userStake * rewardRate) / totalStaked;  // SLOAD 2: 100 gas warm
    }
}
```

**Optimized (saves 97 gas per avoided warm SLOAD, up to 2,097 per avoided cold SLOAD):**
```solidity
pragma solidity ^0.8.20;

contract StakingPool {
    uint256 public totalStaked;
    uint256 public rewardRate;

    function computeReward(uint256 userStake) external view returns (uint256) {
        uint256 _totalStaked = totalStaked; // SLOAD once: 2,100 gas cold
        uint256 _rewardRate  = rewardRate;  // SLOAD once: 2,100 gas cold

        if (userStake > _totalStaked) revert();
        return (userStake * _rewardRate) / _totalStaked; // 2 MLOADs: 3 gas each
    }
}
```

**The EVM mechanic:** After the first SLOAD, the slot is warm (100 gas); but even a warm
SLOAD at 100 gas is 33× more expensive than MLOAD at 3 gas. A variable read N times saves
(N-1) × 97 gas minimum.

**When this applies:** Any function that reads the same state variable more than once.
Savings compound inside loops (see LO-002).

**When it doesn't apply:** Functions where a re-entrant external call between reads could
modify the storage variable — caching would give a stale value. Only cache in
non-reentrant contexts or provably stable scopes.

---

## Pattern: SL-004 — Zero out storage slots with `delete` to claim gas refund

**Anti-pattern (leaves stale data; same gas as delete but intent is unclear):**
```solidity
pragma solidity ^0.8.20;

contract OrderBook {
    mapping(uint256 => address) public orderOwner;
    mapping(uint256 => uint256) public orderAmount;

    function cancelOrder(uint256 orderId) external {
        require(orderOwner[orderId] == msg.sender);
        orderOwner[orderId]  = address(0); // nonzero→zero SSTORE: 5,000 gas
        orderAmount[orderId] = 0;          // nonzero→zero SSTORE: 5,000 gas
        // No EVM difference — but intent is ambiguous
    }
}
```

**Optimized (explicit delete; each slot earns 4,800 gas refund post-EIP-3529):**
```solidity
pragma solidity ^0.8.20;

contract OrderBook {
    mapping(uint256 => address) public orderOwner;
    mapping(uint256 => uint256) public orderAmount;

    function cancelOrder(uint256 orderId) external {
        require(orderOwner[orderId] == msg.sender);
        delete orderOwner[orderId];  // nonzero→zero SSTORE + 4,800 gas refund
        delete orderAmount[orderId]; // nonzero→zero SSTORE + 4,800 gas refund
        // Net cost: ~200 gas per slot inside a sufficiently large transaction
    }
}
```

**The EVM mechanic:** EIP-3529 (London) grants a 4,800 gas refund per slot zeroed
(nonzero→zero SSTORE), capped at 20% of total transaction gas.

**When this applies:** Functions that logically remove a record (cancel, close, expire)
but previously left nonzero values in storage.

**When it doesn't apply:** Transactions with total gas < 24,000 (refund cap prevents full
recovery); never `delete` a packed struct field mid-function while co-located fields in
the same slot are still in use — this zeroes the entire slot.

---

## Pattern: SL-005 — Replace SSTORE reentrancy guard with transient storage

**Anti-pattern (costs ~27,100 gas per guarded call):**
```solidity
pragma solidity ^0.8.20;

contract Vault {
    uint256 private _locked; // persistent slot

    modifier nonReentrant() {
        require(_locked == 0);  // SLOAD: 2,100 gas cold
        _locked = 1;             // SSTORE zero→nonzero: 22,100 gas
        _;
        _locked = 0;             // SSTORE nonzero→zero: 5,000 gas (+4,800 refund)
    }

    function withdraw(uint256 amount) external nonReentrant { /* ... */ }
}
```

**Optimized (costs ~300 gas per guarded call — saves ~26,800 gas):**
```solidity
pragma solidity ^0.8.24; // minimum version for transient storage

contract Vault {
    // Transient slot: auto-cleared at transaction end, no persistent state used
    bytes32 private constant LOCK_SLOT = keccak256("vault.reentrancy.lock");

    modifier nonReentrant() {
        assembly {
            if tload(LOCK_SLOT) { revert(0, 0) } // TLOAD: 100 gas
            tstore(LOCK_SLOT, 1)                   // TSTORE: 100 gas
        }
        _;
        assembly {
            tstore(LOCK_SLOT, 0)                   // TSTORE: 100 gas
        }
    }

    function withdraw(uint256 amount) external nonReentrant { /* ... */ }
}
```

**The EVM mechanic:** EIP-1153 (Cancun) transient storage is always zero at transaction
start and cleared automatically at transaction end; TSTORE/TLOAD cost 100 gas regardless
of access history (no cold/warm distinction).

**When this applies:** Reentrancy guards using a `uint256` or `bool` persistent storage
lock, on contracts targeting Solidity 0.8.24+ and a Cancun-compatible EVM.

**When it doesn't apply:** Chains without EIP-1153 support; proxy patterns using
delegatecall where transient storage is shared across delegates (requires careful design).

---

## Pattern: SL-006 — Use transient storage for flash-loan approvals

**Anti-pattern (costs ~29,200 gas for the approval lifecycle):**
```solidity
pragma solidity ^0.8.20;

contract FlashLender {
    mapping(address => bool) private _approvedCallbacks; // persistent

    function flashLoan(address borrower, uint256 amount) external {
        _approvedCallbacks[borrower] = true;              // cold SSTORE: 22,100 gas
        IBorrower(borrower).onFlashLoan(amount);
        require(!_approvedCallbacks[borrower], "Not repaid"); // SLOAD: 2,100 gas
    }

    function signalRepayment(address borrower) external {
        _approvedCallbacks[borrower] = false;             // SSTORE nonzero→zero: 5,000 gas
    }
}
```

**Optimized (costs ~300 gas for the approval lifecycle — saves ~28,900 gas):**
```solidity
pragma solidity ^0.8.24;

contract FlashLender {
    function _approvalSlot(address borrower) private pure returns (bytes32) {
        return keccak256(abi.encode("flashloan.approved", borrower));
    }

    function flashLoan(address borrower, uint256 amount) external {
        bytes32 slot = _approvalSlot(borrower);
        assembly { tstore(slot, 1) }               // TSTORE: 100 gas
        IBorrower(borrower).onFlashLoan(amount);
        uint256 approved;
        assembly { approved := tload(slot) }       // TLOAD: 100 gas
        require(approved == 0, "Not repaid");
    }

    function signalRepayment(address borrower) external {
        bytes32 slot = _approvalSlot(borrower);
        assembly { tstore(slot, 0) }               // TSTORE: 100 gas
    }
}
```

**The EVM mechanic:** Transient storage persists through subcalls within a transaction but
is discarded at transaction end, making it ideal for within-transaction coordination flags.

**When this applies:** Any pattern that sets a flag before a callback and clears it
after — flash loans, vault entry checks, multicall guards.

**When it doesn't apply:** State that must persist across multiple transactions; chains
or compilers without EIP-1153 support.

---

## Pattern: SL-007 — SSTORE2 for large read-heavy static data

**Anti-pattern (costs 22,100 gas per element write; 2,100 gas cold SLOAD per element read):**
```solidity
pragma solidity ^0.8.20;

contract MerkleVerifier {
    bytes32[] public merkleTree; // each element = 1 storage slot

    constructor(bytes32[] memory tree) {
        for (uint256 i; i < tree.length; ++i) {
            merkleTree.push(tree[i]); // 22,100 gas cold SSTORE per element
        }
    }

    function getNode(uint256 index) external view returns (bytes32) {
        return merkleTree[index]; // 2,100 gas cold SLOAD per element
    }
}
```

**Optimized (one-time CREATE write; ~700 gas warm EXTCODECOPY per read — saves ~1,400+ gas/read):**
```solidity
pragma solidity ^0.8.20;

import {SSTORE2} from "solmate/utils/SSTORE2.sol";

contract MerkleVerifier {
    address private immutable _dataPointer; // immutable: free to read (PUSH32)

    constructor(bytes memory packedTree) {
        _dataPointer = SSTORE2.write(packedTree); // deploy data as contract bytecode
    }

    function getNode(uint256 index) external view returns (bytes32) {
        bytes memory chunk = SSTORE2.read(_dataPointer, index * 32, (index + 1) * 32);
        return bytes32(chunk); // EXTCODECOPY: ~700 gas warm vs 2,100 gas cold SLOAD
    }
}
```

**The EVM mechanic:** `EXTCODECOPY` reads from contract bytecode, which is cheaper than
storage SLOADs for bulk data: approximately 700 gas for a warm contract plus 3 gas/word,
versus 2,100 gas per 32-byte storage slot cold.

**When this applies:** Data written once at deployment and read frequently — lookup
tables, Merkle trees, SVG data, encoded configuration. Break-even is typically 2–3 reads
for payloads over 64 bytes.

**When it doesn't apply:** Mutable data (bytecode is immutable); very small data
(<64 bytes) where the CREATE overhead exceeds storage cost; cold contract access adds
2,600 gas — use `immutable` for the pointer to keep it warm.

---

## Pattern: SL-008 — Batch mutations: read once, accumulate locally, write once

**Anti-pattern (costs 22,100 + 2 × 2,900 = 27,900 gas for 3 writes to same slot):**
```solidity
pragma solidity ^0.8.20;

contract Counter {
    uint256 public count;

    function processThree() external {
        count += 1; // SSTORE: 22,100 gas cold (or 2,900 warm)
        // ... work A ...
        count += 1; // SSTORE warm nonzero→nonzero: 2,900 gas
        // ... work B ...
        count += 1; // SSTORE warm nonzero→nonzero: 2,900 gas
    }
}
```

**Optimized (saves 2 × 2,900 = 5,800 gas by eliminating 2 intermediate SSTOREs):**
```solidity
pragma solidity ^0.8.20;

contract Counter {
    uint256 public count;

    function processThree() external {
        uint256 _count = count; // SLOAD once: 2,100 gas cold
        // ... work A ...
        // ... work B ...
        count = _count + 3;     // SSTORE once: 22,100 gas cold (or 2,900 warm)
    }
}
```

**The EVM mechanic:** A warm SSTORE (nonzero→nonzero) costs 2,900 gas; accumulating
changes in a local `uint256` uses only MLOAD/MSTORE at 3 gas each.

**When this applies:** Any function that writes the same storage variable N > 1 times
within a single execution — counters, balances, accumulators.

**When it doesn't apply:** When intermediate state must be observable by re-entrant calls
(rare in well-guarded contracts). If the variable is only written once, no benefit.

---

## Pattern: SL-009 — Precompute keccak256 of string literals as constant

**Anti-pattern (costs 30 + 6 gas/word runtime KECCAK256 on every call):**
```solidity
pragma solidity ^0.8.20;

contract AccessControl {
    mapping(bytes32 => mapping(address => bool)) private _roles;

    function hasAdminRole(address account) external view returns (bool) {
        return _roles[keccak256("ADMIN_ROLE")][account]; // KECCAK256 every call: ~36 gas
    }

    function hasOperatorRole(address account) external view returns (bool) {
        return _roles[keccak256("OPERATOR_ROLE")][account]; // KECCAK256 every call: ~42 gas
    }
}
```

**Optimized (0 gas runtime — compiler inlines the bytes32 value as a PUSH32):**
```solidity
pragma solidity ^0.8.20;

contract AccessControl {
    bytes32 public constant ADMIN_ROLE    = keccak256("ADMIN_ROLE");    // compile-time
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE"); // compile-time

    mapping(bytes32 => mapping(address => bool)) private _roles;

    function hasAdminRole(address account) external view returns (bool) {
        return _roles[ADMIN_ROLE][account]; // PUSH32 of constant: ~0 gas overhead
    }

    function hasOperatorRole(address account) external view returns (bool) {
        return _roles[OPERATOR_ROLE][account];
    }
}
```

**The EVM mechanic:** The Solidity compiler evaluates `keccak256` of string literals at
compile time when assigned to a `constant`, eliminating the runtime KECCAK256 opcode and
memory copy entirely.

**When this applies:** Any `keccak256("hardcoded string")` call in a function body that
is not already a contract-level constant.

**When it doesn't apply:** Strings that depend on runtime inputs (cannot precompute);
hashes used only once where the single-call saving is negligible.

---

## Pattern: SL-010 — Prefer mapping over array for key-value lookups

**Anti-pattern (costs 2 SSTOREs per insert: ~44,200 gas cold; 2 SLOADs per lookup):**
```solidity
pragma solidity ^0.8.20;

contract Registry {
    struct UserInfo { uint256 balance; bool active; }

    UserInfo[] public users;
    mapping(address => uint256) public userIndex; // index needed for O(1) access

    function register(address user, uint256 balance) external {
        userIndex[user] = users.length;      // SLOAD length + SSTORE index
        users.push(UserInfo(balance, true)); // SSTORE element + SSTORE length
        // 2 SSTOREs cold = ~44,200 gas
    }

    function getBalance(address user) external view returns (uint256) {
        return users[userIndex[user]].balance; // 2 SLOADs cold = ~4,200 gas
    }
}
```

**Optimized (1 SSTORE per insert: ~22,100 gas cold; 1 SLOAD per lookup):**
```solidity
pragma solidity ^0.8.20;

contract Registry {
    struct UserInfo { uint256 balance; bool active; }

    mapping(address => UserInfo) public users; // direct key-value, no length overhead

    function register(address user, uint256 balance) external {
        users[user] = UserInfo(balance, true); // 1 SSTORE cold = ~22,100 gas
    }

    function getBalance(address user) external view returns (uint256) {
        return users[user].balance; // 1 SLOAD cold = ~2,100 gas
    }
}
```

**The EVM mechanic:** Dynamic arrays maintain a length variable in a separate storage
slot; `push()` writes two slots (element + length). A `mapping` has no length slot — the
element slot is derived purely from the key hash and is zero until written.

**When this applies:** Any contract using a dynamic array as the primary store for
records that are accessed by key (address, uint256 ID), without a requirement for
ordered iteration or enumeration.

**When it doesn't apply:** When ordered iteration over all entries is required — mappings
cannot be iterated. Use `mapping` + parallel `address[]` for both lookup and enumeration.
When total count is needed: add a separate `uint256` counter.
