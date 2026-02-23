# EVM Gas Quick Reference

A standalone reference for gas costs relevant to Solidity optimization.
Numbers are based on post-EIP-2929/3529 (Berlin+) rules unless noted.

---

## Storage Opcode Costs

| Opcode | Condition | Gas Cost |
| ------ | --------- | -------- |
| SLOAD | Cold (first access in tx, EIP-2929) | 2,100 gas |
| SLOAD | Warm (subsequent access in tx) | 100 gas |
| MLOAD | Memory read | 3 gas |
| SSTORE | Cold zero→nonzero (first write to empty slot) | 22,100 gas |
| SSTORE | Nonzero→nonzero (overwrite existing value) | 2,900 gas (warm) |
| SSTORE | Nonzero→zero (zeroing a slot) | 5,000 gas (+ 4,800 refund, EIP-3529) |
| TSTORE | Transient storage write (EIP-1153, Cancun) | 100 gas |
| TLOAD | Transient storage read (EIP-1153, Cancun) | 100 gas |

**Key takeaway:** A cold SLOAD costs 21× more than a warm SLOAD. Caching storage reads in memory variables within a function is one of the highest-ROI optimizations available.

---

## Arithmetic Opcode Costs

| Operation | Gas (checked, Solidity 0.8+) | Gas (unchecked) |
| --------- | ----------------------------- | --------------- |
| ADD/SUB | ~8 gas (3 + ISZERO 3 + JUMPI 10 — with optimizer) | ~3 gas |
| MUL | ~8 gas checked | ~5 gas |
| DIV/MOD | ~8 gas checked | ~5 gas |
| Saving per unchecked op | — | ~30 gas (community verified) |

The overhead for checked arithmetic comes from the ISZERO + JUMPI pair the compiler inserts for overflow detection. In tight loops, this compounds: a loop running 1,000 iterations saves ~30,000 gas by wrapping only the provably safe counter increment in `unchecked`.

---

## Error Handling Cost Comparison

| Error type | Runtime cost | Bytecode cost |
| ---------- | ------------ | ------------- |
| `require(cond, "10-char string")` | ~50+ gas encoding | ~200+ gas/byte in bytecode |
| `revert("10-char string")` | Same as require | Same |
| `if (!cond) revert CustomError()` | ~4 bytes (selector only) | ~4 bytes in bytecode |
| Custom error with 2 params | 4 + 32 + 32 = 68 bytes returned | Minimal |

String revert messages are ABI-encoded at runtime and stored as bytecode. Every character in the string costs gas both at deployment (bytecode size) and at revert time (encoding). Custom errors pay only a 4-byte selector, regardless of how many parameters they carry.

---

## Transaction Baseline Costs

| Item | Cost |
| ---- | ---- |
| Base transaction cost | 21,000 gas |
| Contract creation (CREATE) | 32,000 gas + 200 gas/byte bytecode |
| ERC-1167 minimal proxy deploy | ~41,000 gas (45-byte proxy) |
| Full 2,500-byte contract deploy | ~532,000 gas |
| DELEGATECALL overhead | ~100 gas (warm) |

For factory patterns deploying many instances, ERC-1167 minimal proxies reduce per-instance deploy cost by 10–20× compared to deploying the full implementation each time. The tradeoff is a DELEGATECALL overhead on every function call (~100 gas warm).

---

## Calldata Byte Costs

| Byte type | Cost |
| --------- | ---- |
| Non-zero byte | 16 gas |
| Zero byte | 4 gas |
| `bool` parameter (ABI padded) | ~140 gas (31 zero bytes + 1 non-zero) |
| `address` parameter (20 bytes) | ~304 gas (12 zero bytes + 20 non-zero, worst case) |
| Leading zero byte in address | Saves 12 gas (16→4 gas per zero byte) |

ABI encoding pads all values to 32-byte words. A single `bool true` occupies 32 bytes of calldata: 31 zero bytes (4 gas each = 124 gas) plus 1 non-zero byte (16 gas) = 140 gas total. Batch functions that accept arrays amortize calldata overhead across many operations.

---

## Slot Packing Rules

Every storage slot is exactly 32 bytes. Types smaller than 32 bytes can share a slot if their combined size fits. The compiler packs consecutive declarations automatically — but only if they are declared consecutively. Non-consecutive declarations are never packed across the gap.

| Type | Bytes | Can pack with |
| ---- | ----- | ------------- |
| bool | 1 | address(20), uint64(8), uint32(4), uint96(12) |
| uint8 | 1 | Many; up to 31 per slot |
| uint32 | 4 | address(20) + uint64(8) = 32 bytes |
| uint64 | 8 | address(20) + uint32(4) = 32 bytes |
| uint96 | 12 | address(20) = 32 bytes (perfect fit) |
| uint128 | 16 | Another uint128 = 32 bytes (perfect fit) |
| address | 20 | uint96(12) or bool(1)+uint88(11) |
| uint192 | 24 | uint64(8) |
| uint256 | 32 | Never (full slot alone) |
| bytes32 | 32 | Never (full slot alone) |

**Canonical packing rule:** Place `uint256`/`bytes32` first (they fill a slot alone and gain nothing from grouping). Then group remaining types in descending size order, filling each slot before starting the next.

**Example — 3 slots reduced to 2:**
```solidity
// Before: 3 slots (address fills slot 0 with 12 bytes wasted;
//         bool fills slot 2 with 31 bytes wasted)
address owner;    // slot 0: 20/32 bytes used
uint256 balance;  // slot 1: 32/32 bytes used
bool paused;      // slot 2: 1/32 bytes used

// After: 2 slots
uint256 balance;  // slot 0: 32/32 bytes used
address owner;    // slot 1: 20 bytes
bool paused;      // slot 1: 1 byte — packed with owner (21/32 bytes used)
```

**Verification command:**
```bash
forge inspect <ContractName> storageLayout --json
```

Run this before finalizing any struct or contract-level state variable layout. The compiler output is the ground truth — visual inspection is unreliable.

---

## LOG Opcode Costs

| Opcode | Base | Per topic | Per data byte |
| ------ | ---- | --------- | ------------- |
| LOG0 | 375 gas | — | 8 gas |
| LOG1 | 375 gas | 375 gas | 8 gas |
| LOG2 | 375 gas | 750 gas | 8 gas |
| LOG3 | 375 gas | 1,125 gas | 8 gas |
| LOG4 | 375 gas | 1,500 gas | 8 gas |

**Cost comparison — events vs storage for historical data:**

| Operation | Gas cost |
| --------- | -------- |
| 1 cold SSTORE (zero→nonzero) | 22,100 gas |
| LOG1 with 32 bytes of data | 375 (base) + 375 (topic) + 256 (32 bytes × 8) = 1,006 gas |

Events are approximately **21× cheaper** than storage for data that only needs to be read off-chain. Use events for historical records, audit trails, and indexing. Use storage only when the data must be readable on-chain.

---

## Key EIP References

| EIP | Name | Key change |
| --- | ---- | ---------- |
| EIP-2929 | Cold/warm access | SLOAD cold=2,100, warm=100; cold address access=2,600 |
| EIP-3529 | Refund cap | Max refund capped at 20% of tx gas; per-slot refund 4,800 gas |
| EIP-1153 | Transient storage | TSTORE/TLOAD at 100 gas each; storage cleared at end of transaction |
| ERC-1167 | Minimal proxy | 45-byte DELEGATECALL proxy standard for cheap contract cloning |

**EIP-2929 (Berlin, April 2021):** Introduced the cold/warm distinction. Before this EIP, all SLOADs cost 800 gas. After, the first access to a slot in a transaction costs 2,100 gas (cold), and subsequent accesses within the same transaction cost 100 gas (warm). This is why caching a storage variable into a local memory variable on its first read is so impactful.

**EIP-3529 (London, August 2021):** Reduced the gas refund cap from 50% to 20% of the transaction gas limit and eliminated the SELFDESTRUCT refund. The SSTORE zero-refund of 4,800 gas per slot still applies but is now bounded by the 20% cap.

**EIP-1153 (Cancun, March 2024):** Transient storage (`TSTORE`/`TLOAD`) operates like regular storage within a transaction but is automatically cleared at the end. Cost is 100 gas for both reads and writes — matching warm storage access. Useful for reentrancy guards and intra-transaction state that does not need to persist.
