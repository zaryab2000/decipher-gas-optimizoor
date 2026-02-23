# /gas:explain <pattern>

Explain the EVM mechanic behind a specific gas optimization pattern with exact cost
numbers, before/after code, and guidance on when not to apply it.

## Accepted patterns

`cold-sload` | `slot-packing` | `unchecked` | `custom-errors` | `calldata` |
`external-vs-public` | `immutable` | `loop-caching` | `unbounded-loop`

If the user supplies a pattern not in this list, respond:

> Unknown pattern "[X]". Accepted patterns:
> cold-sload, slot-packing, unchecked, custom-errors, calldata,
> external-vs-public, immutable, loop-caching, unbounded-loop

---

## Output format for every pattern

Produce five sections in this order:

1. **What it is** — one sentence defining the pattern.
2. **The EVM mechanic** — why the naive code is expensive at the opcode level.
3. **Gas cost difference** — exact numbers for both approaches.
4. **Before / after example** — minimal Solidity snippets showing the transformation.
5. **When NOT to apply** — concrete conditions where the optimization is wrong or unsafe.

---

## Pattern: cold-sload

**What it is:** A cold SLOAD is the first read of a storage slot within a transaction;
it costs 2,100 gas (EIP-2929). Subsequent reads of the same slot in the same transaction
are warm and cost 100 gas. Reading from memory costs 3 gas (MLOAD).

**The EVM mechanic:** EIP-2929 (Berlin) introduced access lists to distinguish cold vs
warm storage slots. A slot is cold at transaction start. The first SLOAD marks it warm in
the transaction's access set; all subsequent SLOADs within the same transaction use the
warm cost. MLOAD reads from the EVM's memory region, which has no cold/warm distinction.

**Gas cost difference:**

| Operation | Cost |
| --------- | ---- |
| SLOAD (cold, first access) | 2,100 gas |
| SLOAD (warm, subsequent accesses) | 100 gas |
| MLOAD (memory read) | 3 gas |

Caching to a local variable converts every access after the first from 100 gas to 3 gas,
saving 97 gas per avoided warm SLOAD.

**Before / after:**

```solidity
// Before: two SLOADs (1 cold + 1 warm = 2,200 gas total for this variable)
function bad() external view returns (uint256) {
    if (totalSupply == 0) revert();      // SLOAD cold: 2,100 gas
    return userBalance / totalSupply;    // SLOAD warm: 100 gas
}

// After: one SLOAD + one MLOAD (2,100 + 3 gas = 2,103 gas total)
function good() external view returns (uint256) {
    uint256 supply = totalSupply;        // SLOAD cold: 2,100 gas (one time)
    if (supply == 0) revert();
    return userBalance / supply;         // MLOAD: 3 gas
}
```

**When NOT to apply:** If a re-entrant call between the two reads could change the
storage value, caching produces a stale view. Only cache in non-reentrant contexts where
the value is stable for the function's duration.

---

## Pattern: slot-packing

**What it is:** Solidity packs struct fields into 32-byte storage slots from left to
right; reordering fields to group smaller types together reduces the number of slots used
and therefore the number of SSTOREs and SLOADs required.

**The EVM mechanic:** The EVM storage model allocates one 32-byte slot per distinct slot
number. A cold SSTORE (zero → nonzero) costs 22,100 gas per slot. If a struct uses 5
slots when 3 would suffice, every first-write pays 2 unnecessary cold SSTOREs (44,200
gas wasted). On subsequent writes, each avoidable warm SSTORE costs 2,900 gas.

**Gas cost difference:**

| Operation | Cost per slot |
| --------- | ------------- |
| SSTORE cold (zero → nonzero) | 22,100 gas |
| SSTORE warm (nonzero → nonzero) | 2,900 gas |
| SLOAD cold | 2,100 gas |
| SLOAD warm | 100 gas |

Eliminating one slot saves 22,100 gas on first write and 2,100 gas on first read.

**Type byte sizes for packing decisions:**

| Type | Bytes |
| ---- | ----- |
| `bool` | 1 |
| `uint8` / `int8` | 1 |
| `uint16` / `int16` | 2 |
| `uint32` / `int32` | 4 |
| `uint64` / `int64` | 8 |
| `uint96` / `int96` | 12 |
| `uint128` / `int128` | 16 |
| `address` | 20 |
| `uint256` / `int256` | 32 (always its own slot) |

Verify with: `forge inspect <ContractName> storageLayout --json`

**Before / after:**

```solidity
// Before: 4 slots (uint128 alone, address alone, bool alone, uint256 alone)
struct Config {
    uint128 amount;   // slot 0 (16 bytes, 16 bytes wasted)
    address owner;    // slot 1 (20 bytes, 12 bytes wasted)
    bool active;      // slot 2 (1 byte, 31 bytes wasted)
    uint256 value;    // slot 3 (32 bytes, full slot)
}

// After: 2 slots (address+uint96 share slot 0; uint128+bool share slot 1; uint256 alone)
struct Config {
    uint256 value;    // slot 0 (32 bytes, alone)
    uint128 amount;   // slot 1, bytes 0-15
    bool active;      // slot 1, byte 16 — packed with amount
    address owner;    // slot 2, bytes 0-19  [note: bool+address fit if active moved]
}
// Optimal: value(slot0), owner+active(slot1: 20+1=21 bytes), amount(slot2)
```

**When NOT to apply:** Never reorder storage variables in an upgradeable (proxy) contract
— slot positions are fixed across upgrades and reordering causes storage collisions. Only
pack when fields are frequently accessed together; packing fields accessed in isolation
adds masking overhead.

---

## Pattern: unchecked

**What it is:** Wrapping arithmetic in `unchecked { ... }` disables Solidity 0.8+'s
automatic overflow/underflow checks, saving approximately 30 gas per arithmetic
operation.

**The EVM mechanic:** Solidity 0.8+ inserts additional opcodes around every `+`, `-`,
`*`, and `**` operation to check for overflow/underflow and revert if detected. The EVM
itself performs arithmetic with silent wrap-around (like uint256 modular arithmetic);
the overflow check is synthesized by the compiler. Removing these checks when the
operation is provably safe eliminates those extra opcodes.

**Gas cost difference:**

| Arithmetic | Approximate cost |
| ---------- | ---------------- |
| `a + b` with overflow check (Solidity 0.8+ default) | ~35 gas |
| `a + b` in `unchecked` block | ~5 gas |
| Saving per operation | ~30 gas |

**Before / after:**

```solidity
// Before: loop counter increments with overflow check (~30 gas wasted per iteration)
for (uint256 i = 0; i < arr.length; i++) {
    // i can never overflow: arr.length <= 2^256-1 and i < arr.length always
    process(arr[i]);
}

// After: unchecked increment saves ~30 gas per iteration
uint256 len = arr.length; // cache length
for (uint256 i = 0; i < len;) {
    process(arr[i]);
    unchecked { i++; } // safe: i < len < 2^256
}
```

**When NOT to apply:** Only use `unchecked` when overflow is provably impossible — either
by type constraints, prior bounds checks, or mathematical proof. Never apply to user-
supplied values without bounds validation. Do not apply to subtraction where the
subtrahend could exceed the minuend.

---

## Pattern: custom-errors

**What it is:** Custom errors (`error MyError()` + `revert MyError()`) use a 4-byte
ABI selector instead of ABI-encoding an entire error string, reducing both runtime gas
and deployment bytecode size.

**The EVM mechanic:** `require(condition, "string")` encodes the revert reason as
`Error(string)`: 4 bytes selector + 32 bytes ABI offset + 32 bytes string length +
ceil(len/32) * 32 bytes string data. Every byte of error string is stored in contract
bytecode at deployment (200 gas/byte) and returned as calldata on revert. A custom error
uses only its 4-byte selector; no string is stored or encoded.

**Gas cost difference:**

For a 10-character string like "Not owner":

| Approach | Bytecode added | Revert data returned |
| -------- | -------------- | --------------------|
| `require(cond, "Not owner")` | ~200 bytes × 200 gas = ~40,000 deploy gas | ~96 bytes |
| `if (!cond) revert NotOwner()` | ~4 bytes | 4 bytes |

Runtime savings: ~15–50 gas per revert (varies with string length).

**Before / after:**

```solidity
// Before: string stored in bytecode and ABI-encoded on every revert
require(msg.sender == owner, "Not owner");

// After: 4-byte selector only
error NotOwner();
if (msg.sender != owner) revert NotOwner();
```

**When NOT to apply:** When the error string carries variable runtime context that cannot
be expressed as typed custom error parameters, and human-readable strings are critical
for consumer tooling. Also unnecessary if already on a custom error.

---

## Pattern: calldata

**What it is:** Declaring external function parameters as `calldata` instead of `memory`
avoids copying the ABI-decoded input into memory, saving 3 gas per byte of input data
plus the memory expansion cost.

**The EVM mechanic:** `memory` parameters cause the EVM to copy the calldata into the
memory region (CALLDATACOPY at 3 gas/byte + memory expansion). `calldata` parameters are
read directly from the transaction input without copying (CALLDATALOAD at 3 gas per 32
bytes read). For large arrays or structs, the difference scales linearly with data size.

**Gas cost difference:**

| Approach | Cost for 1KB input |
| -------- | ------------------ |
| `memory` param | ~3,072 gas (copy) + memory expansion |
| `calldata` param | ~96 gas (direct CALLDATALOAD reads only) |

For small inputs (1–2 params): ~50–100 gas saved. For large arrays: thousands of gas
saved.

**Before / after:**

```solidity
// Before: input array copied into memory on every call
function sum(uint256[] memory values) public returns (uint256 total) {
    for (uint256 i = 0; i < values.length; i++) total += values[i];
}

// After: reads directly from calldata — no copy
function sum(uint256[] calldata values) external returns (uint256 total) {
    for (uint256 i = 0; i < values.length; i++) total += values[i];
}
```

**When NOT to apply:** `calldata` is only valid for `external` functions — internal or
`public` functions called internally must use `memory`. If the function modifies the
array, `memory` is required (`calldata` is read-only).

---

## Pattern: external-vs-public

**What it is:** `public` functions that are never called internally should be declared
`external` to avoid the Solidity dispatcher's overhead of copying reference-type
arguments from calldata into memory.

**The EVM mechanic:** For `public` functions with reference-type parameters (arrays,
structs, bytes), Solidity copies the calldata arguments into memory so the function can
be called both externally (with calldata) and internally (which requires memory). This
copy is unnecessary when the function is only called externally. `external` functions
read reference-type parameters directly from calldata.

**Gas cost difference:**

| Scenario | Cost |
| -------- | ---- |
| `public` with array param | calldata copy: 3 gas/byte + memory expansion |
| `external` with array param | no copy; direct calldata reads |

For scalar parameters (uint256, address, bool): no difference — both are passed by value
and the dispatcher overhead is negligible.

**Before / after:**

```solidity
// Before: public copies array into memory even for external-only callers
function process(bytes memory data) public returns (bytes32) {
    return keccak256(data); // never called internally
}

// After: external + calldata avoids the memory copy entirely
function process(bytes calldata data) external returns (bytes32) {
    return keccak256(data);
}
```

**When NOT to apply:** If the function is called internally (from another function in the
same contract or a derived contract), it must remain `public` — `external` functions
cannot be called internally.

---

## Pattern: immutable

**What it is:** Variables declared `immutable` are set once in the constructor and
embedded in contract bytecode at deployment; reading them costs a PUSH32 opcode (3 gas)
instead of a SLOAD (2,100 gas cold or 100 gas warm).

**The EVM mechanic:** `constant` variables are inlined by the compiler as literal values
in bytecode — zero runtime cost. `immutable` variables are also inlined in bytecode but
their values are set in the constructor rather than at compile time. In both cases, the
runtime read is a PUSH32 (or smaller PUSH) — a bytecode operation with no storage
access. Contrast with a regular state variable, which the EVM must fetch from the
storage trie via SLOAD.

**Gas cost difference:**

| Storage type | Read cost |
| ------------ | --------- |
| Regular state variable (cold) | 2,100 gas (SLOAD) |
| Regular state variable (warm) | 100 gas (SLOAD) |
| `immutable` | 3 gas (PUSH32) |
| `constant` | 3 gas (PUSH32) or inlined literal |

**Before / after:**

```solidity
// Before: owner read from storage on every privileged call (2,100 gas cold)
contract Ownable {
    address public owner;
    constructor() { owner = msg.sender; }
    modifier onlyOwner() { require(msg.sender == owner); _; }
}

// After: owner embedded in bytecode (3 gas PUSH32)
contract Ownable {
    address public immutable owner;
    constructor() { owner = msg.sender; }
    modifier onlyOwner() { require(msg.sender == owner); _; }
}
```

**When NOT to apply:** If the variable must change after deployment (e.g., an owner that
can be transferred), `immutable` is wrong — use a regular state variable with a setter.
For values known at compile time (not set in constructor), prefer `constant` over
`immutable`.

---

## Pattern: loop-caching

**What it is:** Reading a storage variable into a local variable before a loop, and
caching `array.length` in a local variable, eliminates repeated SLOADs on every loop
iteration.

**The EVM mechanic:** Each SLOAD inside a loop executes once per iteration. A warm SLOAD
costs 100 gas vs 3 gas for MLOAD. For a 100-iteration loop reading one storage variable
per iteration, the warm-SLOAD cost is 100 × 100 = 10,000 gas vs 100 × 3 = 300 gas with
a local cache — a saving of 9,700 gas. Array `.length` on a storage array also issues a
SLOAD on every evaluation if the array is in storage.

**Gas cost difference:**

| Pattern | Cost for N iterations |
| ------- | --------------------- |
| Storage read per iteration | N × 100 gas (warm SLOAD) |
| Cached local read per iteration | 2,100 gas (1 cold SLOAD) + N × 3 gas (MLOAD) |
| Break-even | N > 21 iterations |

For N = 100: uncached = 10,000 gas, cached = 2,400 gas. Saving: 7,600 gas.

**Before / after:**

```solidity
// Before: rewardRate SLOAD on every iteration; array.length SLOAD in condition
for (uint256 i = 0; i < stakes.length; i++) {
    total += stakes[i] * rewardRate; // SLOAD rewardRate per iteration
}

// After: both cached before loop
uint256 _rewardRate = rewardRate;  // 1 SLOAD
uint256 len = stakes.length;       // 1 SLOAD (if stakes is storage array)
for (uint256 i = 0; i < len;) {
    total += stakes[i] * _rewardRate; // MLOAD per iteration
    unchecked { i++; }
}
```

**When NOT to apply:** If the storage variable can be modified by a re-entrant call or
external call made inside the loop body, caching gives a stale value for subsequent
iterations. If the array is in memory (not storage), `.length` is already an MLOAD — no
caching benefit for the length.

---

## Pattern: unbounded-loop

**What it is:** A loop that iterates over a user-controlled or ever-growing storage
collection without a bound can exceed the block gas limit, making the function
permanently unexecutable and creating a denial-of-service vulnerability.

**The EVM mechanic:** Every EVM block has a gas limit (typically ~30M gas on Ethereum
mainnet). A loop over N storage elements costs at minimum N × 2,100 gas (cold SLOADs).
At 30M gas, the maximum loop iterations over cold storage is ~14,285. If the collection
can grow beyond this point — either by user action or natural accumulation — the
transaction will always run out of gas, bricking the function.

**Gas cost difference:** Not applicable as a per-call optimization. The risk is
correctness failure, not efficiency.

**Before / after:**

```solidity
// Before: unbounded loop — bricked if users.length > ~14,000
function distributeRewards() external {
    for (uint256 i = 0; i < users.length; i++) {
        _pay(users[i], rewards[users[i]]);
    }
}

// After option 1: pagination — caller controls batch size
function distributeRewards(uint256 start, uint256 end) external {
    uint256 len = users.length;
    if (end > len) end = len;
    for (uint256 i = start; i < end;) {
        _pay(users[i], rewards[users[i]]);
        unchecked { i++; }
    }
}

// After option 2: pull pattern — each user claims individually
function claimReward() external {
    uint256 amount = rewards[msg.sender];
    if (amount == 0) revert NoReward();
    delete rewards[msg.sender];
    _pay(msg.sender, amount);
}
```

**When NOT to apply:** If the collection is demonstrably bounded at a small constant
(e.g., always exactly 5 signers in a multisig), the loop is safe. If the data lives in
memory (not storage), the gas cost is lower and the same block limit still applies but
is harder to hit. Pagination is always the correct mitigation for storage-based
iteration over unbounded sets.
