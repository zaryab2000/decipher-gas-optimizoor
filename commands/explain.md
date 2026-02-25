# /gas:explain <pattern>

Explain the EVM mechanic behind a specific gas optimization pattern with exact cost
numbers, before/after code, and when NOT to apply it.

## Accepted patterns

`cold-sload` | `slot-packing` | `unchecked` | `custom-errors` | `calldata` |
`external-vs-public` | `immutable` | `loop-caching` | `unbounded-loop`

If the user supplies an unknown pattern, respond:

> Unknown pattern "[X]". Accepted patterns:
> cold-sload, slot-packing, unchecked, custom-errors, calldata,
> external-vs-public, immutable, loop-caching, unbounded-loop

---

## Output format (use for every pattern)

Produce exactly five sections:

1. **What it is** — one sentence.
2. **The EVM mechanic** — why the naive code is expensive at the opcode level.
3. **Gas cost difference** — exact numbers in a table.
4. **Before / after example** — minimal Solidity snippets.
5. **When NOT to apply** — concrete conditions.

---

## Pattern stubs

Use these as anchors; fill in from your knowledge of EVM gas mechanics.

| Pattern | Core mechanic | Key numbers |
|---|---|---|
| `cold-sload` | First SLOAD in a tx costs 2,100 gas (EIP-2929); warm = 100; MLOAD = 3 | Cache to local var: 2,100 → 3 gas per subsequent read |
| `slot-packing` | Each 32-byte storage slot = one SSTORE/SLOAD; fields share a slot if they fit | Cold SSTORE 22,100 gas/slot; saving 1 slot = 22,100 gas on first write |
| `unchecked` | Solidity 0.8+ emits ISZERO+JUMPI after every arithmetic op | ~30 gas/op; safe only when overflow is provably impossible |
| `custom-errors` | `require(c,"str")` ABI-encodes full string; custom error = 4-byte selector | ~15–50 gas/revert + ~200 gas × string_bytes at deployment |
| `calldata` | `memory` param triggers CALLDATACOPY (3 gas/byte); `calldata` reads directly | ~3 gas/byte saved; for 10-element bytes32[] = ~960 gas |
| `external-vs-public` | `public` generates internal+external entry points; `external` skips internal | ~24 gas/call (scalar); thousands for array params via calldata |
| `immutable` | Immutable values baked into deployed bytecode as PUSH32 | ~3 gas/read vs 2,100 gas cold SLOAD; use when set once in constructor |
| `loop-caching` | Storage reads inside loops pay 100 gas (warm) per iteration | Cache before loop: 2,100 gas once + 3 gas × N vs 100 gas × N |
| `unbounded-loop` | Block gas limit ~30M; cold-storage loop: max ~14,285 iterations before DoS | Not a per-call saving — a correctness risk; fix with pagination or pull pattern |
