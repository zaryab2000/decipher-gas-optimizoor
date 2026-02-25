# Storage Layout Patterns — Quick Reference

## SL-001: Pack struct fields (large → small)

```solidity
// BEFORE: 5 slots (bool alone, address alone)
struct Position { bool active; uint256 value; address owner; uint128 a; uint128 b; }

// AFTER: 3 slots — save 44,200 gas per first write
struct Position { uint256 value; uint128 a; uint128 b; address owner; bool active; }
// slot 0: value | slot 1: a+b | slot 2: owner+active
```

Rule: `uint256`/`bytes32` first (full slot), then descending size, pack smalls last.

## SL-002: address + uint96 perfect fill

```solidity
// BEFORE: 2 slots
address owner;   // slot 0, 20 bytes, 12 wasted
uint96  amount;  // slot 1, 12 bytes, 20 wasted

// AFTER: 1 slot (20 + 12 = 32 bytes exactly)
address owner;   // slot N, bytes 0–19
uint96  amount;  // slot N, bytes 20–31
```

## SL-003: Cache storage variable inside a function (multiple reads)

```solidity
// BEFORE: 3 SLOADs (100 gas warm each after first)
function calc() external view returns (uint256) {
    return balances[a] * rate + balances[b] * rate; // rate: 2 warm SLOADs
}

// AFTER: 1 SLOAD + 2 MLOADs (3 gas each)
function calc() external view returns (uint256) {
    uint256 _rate = rate;
    return balances[a] * _rate + balances[b] * _rate;
}
```

## SL-004: Zero out storage slots with `delete` to claim gas refund

Use `delete` on mappings or storage variables when their value is no longer needed,
triggering the EVM refund for zeroing a slot.

**Gas impact:** ~4,800 gas refund per zeroed slot (EIP-3529), capped at 20% of total tx gas.

```solidity
// BEFORE: manual zeroing — gas-equivalent but intent is unclear
function cancelOrder(uint256 orderId) external {
    require(orderOwner[orderId] == msg.sender);
    orderOwner[orderId] = address(0);   // SSTORE nonzero→zero: 5,000 gas + 4,800 refund
    orderAmount[orderId] = 0;           // SSTORE nonzero→zero: 5,000 gas + 4,800 refund
}

// AFTER: explicit delete — same gas, clearer intent, triggers refund
function cancelOrder(uint256 orderId) external {
    require(orderOwner[orderId] == msg.sender);
    delete orderOwner[orderId];    // SSTORE nonzero→zero: 5,000 gas + 4,800 refund
    delete orderAmount[orderId];   // SSTORE nonzero→zero: 5,000 gas + 4,800 refund
    // Net effective cost per slot: ~200 gas after refund (in sufficiently large tx)
}
```

**When NOT to apply:**
- Small transactions where total gas < 24,000: the 20% refund cap prevents full realization.
- Never `delete` a packed struct field mid-function if sibling fields in the same slot are
  still in use — `delete` zeroes the entire slot, corrupting co-located variables.
- Pre-London refund strategies (15,000 gas/slot, 50% cap) no longer apply post-EIP-3529.

**Verification:**
```bash
forge test --match-test testCancelOrder -vvvv   # trace SSTORE opcodes and refund
forge test --gas-report
```

## SL-005: Transient storage for reentrancy guard (requires Solidity 0.8.24+, EVM cancun)

```solidity
// BEFORE: SSTORE lock costs 22,100 gas (cold), 2,900 gas (warm unlock)
uint256 private _locked;
modifier nonReentrant() { require(_locked == 0); _locked = 1; _; _locked = 0; }

// AFTER: TSTORE/TLOAD costs 100 gas each — saves ~26,900 gas per guarded call
modifier nonReentrant() {
    assembly { if tload(0) { revert(0, 0) } tstore(0, 1) }
    _;
    assembly { tstore(0, 0) }
}
```

## SL-007: SSTORE2 for large static data (read-many, write-once)

Use when storing > 64 bytes that never changes after deployment.
Deploy data as contract bytecode; read via `EXTCODECOPY`. Avoids 22,100 gas/slot
for each 32-byte chunk. Implementation: `SSTORE2.write(data)` returns an address;
read with `SSTORE2.read(addr)`.

## SL-008: Batch state variable mutations — write storage exactly once per function

Cache a storage variable in a local memory variable, accumulate all mutations locally,
then write back to storage exactly once at the end of the function.

**Gas impact:** (N−1) × 2,900 gas saved per function, where N is the number of writes to
the same slot. Each eliminated warm SSTORE (nonzero→nonzero) saves 2,900 gas.

```solidity
// BEFORE: 3 writes to count — pays 2,900 gas for each intermediate warm SSTORE
function processThree() external {
    count += 1;   // SSTORE 1 (cold: 22,100 gas or warm: 2,900 gas)
    // ... work A ...
    count += 1;   // SSTORE 2 (warm nonzero→nonzero: 2,900 gas — wasted)
    // ... work B ...
    count += 1;   // SSTORE 3 (warm nonzero→nonzero: 2,900 gas — wasted)
}

// AFTER: 1 SLOAD + all mutations in memory + 1 SSTORE — saves 2 × 2,900 = 5,800 gas
function processThree() external {
    uint256 _count = count;   // SLOAD once (2,100 gas cold or 100 gas warm)
    // ... work A ...
    // ... work B ...
    count = _count + 3;       // SSTORE once (22,100 gas cold or 2,900 gas warm)
}
```

**When NOT to apply:**
- If the variable is only written once in the function: no batching benefit.
- If intermediate state must be observable by re-entrant calls — this is rare and a
  design smell. Contracts with reentrancy guards can safely batch writes.
- Naturally combines with SL-003 (cache reads): always cache before mutating.
- When the variable is inside a loop, see LO-002 for the loop-scoped variant.

**Verification:**
```bash
forge test --match-test testProcess -vvvv   # count SSTORE opcodes in trace
forge snapshot --diff
```

## SL-009: Precompute keccak256 as constant

```solidity
// BEFORE: 30 + 6 gas per word on every call
bytes32 role = keccak256("ADMIN_ROLE");

// AFTER: 0 gas (compiler inlines the value)
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
```

## SL-010: Prefer mapping over array for key-based lookup

Arrays with linear search = O(n) SLOADs. `mapping(key => value)` = O(1) single SLOAD.
Use arrays only when iteration over all elements is genuinely needed on-chain.
