# Event Logging — Patterns Reference

## EV-001: Replace Storage Writes with Event Emission for Off-Chain Data

### Pattern ID
`EV-001`

### Core concept
LOG opcodes are dramatically cheaper than SSTORE for data that only needs
to be readable off-chain. A LOG1 event costs ~375 gas base + 375 gas/topic +
8 gas/byte of non-indexed data. A cold SSTORE costs 22,100 gas per 32-byte
slot. For historical records, audit trails, and analytics that no on-chain
code ever reads, events are always the correct choice.

### Opcode costs (spec-accurate)
- `SSTORE` zero→nonzero (cold): **22,100 gas**
- `SSTORE` nonzero→nonzero (warm): **2,900 gas**
- `LOG1` (1 topic): 375 (base) + 375 (topic) + 8 × data_bytes gas
- `LOG2` (2 topics, e.g., indexed timestamp + event sig): ~375 + 750 + 8 × data_bytes
- Example: `LOG2` with two non-indexed uint256 fields = 375 + 750 + 8 × 64 = **1,637 gas**
- Net saving per storage write replaced: **22,100 − 1,637 ≈ 20,463 gas** (typical)

### Anti-pattern
```solidity
contract TradeLog {
    struct Trade {
        address maker;
        uint256 amount;
        uint256 price;
    }
    Trade[] public tradeHistory;   // written on every trade, never read on-chain

    function executeTrade(address maker, uint256 amount, uint256 price) external {
        tradeHistory.push(Trade(maker, amount, price));   // 3 × SSTORE cold
    }
}
```

### Optimized pattern
```solidity
contract TradeLog {
    event TradeExecuted(
        address indexed maker,
        uint256 amount,
        uint256 price
    );

    function executeTrade(address maker, uint256 amount, uint256 price) external {
        emit TradeExecuted(maker, amount, price);   // LOG2 — ~1,637 gas total
    }
}
```

### When NOT to apply
- The array is read on-chain (another function calls `tradeHistory[i]` or
  iterates `tradeHistory.length`). Events cannot be read by on-chain code.
- The data must be accessible without indexer infrastructure via
  `eth_getStorageAt`.
- The historical data must be passed as an argument to another contract's
  function.

---

## EV-002: Indexed Parameters for Filterable Events

### Pattern ID
`EV-002`

### Core concept
Indexed event parameters are stored as LOG topics and participate in
Ethereum's bloom filter. Nodes can answer `eth_getLogs` with topic filters
in O(1) without scanning all block data. Non-indexed parameters are stored
in the event's data field and require full event data decoding to filter.

### Opcode costs (spec-accurate)
- `LOG` base cost: **375 gas**
- Per topic (indexed param): **+375 gas each** (max 3 indexed params per event)
- Per byte of non-indexed data: **+8 gas**
- Adding 1 indexed param: +375 gas at emit time, but O(1) filtering off-chain
- EVM limit: **3 indexed parameters per event** (topic 0 is the event sig hash)

### Anti-pattern
```solidity
// No indexed fields — full scan required for any filter query
event Transfer(address from, address to, uint256 value);
```

### Optimized pattern
```solidity
// Canonical ERC-20 Transfer — from and to indexed for wallet-centric queries
event Transfer(address indexed from, address indexed to, uint256 value);
```

### Indexing rules
1. Index fields that callers will filter by: sender/recipient addresses,
   token IDs, order IDs, and other identity keys.
2. Do NOT index `string`, `bytes`, or dynamic arrays. Indexing hashes them
   with keccak256, making the original value unrecoverable from the topic.
   Only index fixed-size value types.
3. When more than 3 fields are filterable, choose the 3 most commonly used
   filter keys and leave the rest in the data field.
4. Do not index fields that are never queried (e.g., internal counters,
   computed intermediaries).

### Common examples
```solidity
// ERC-20 Transfer — index from and to (wallet queries); value in data
event Transfer(address indexed from, address indexed to, uint256 value);

// ERC-721 Transfer — index all three (token-centric and wallet-centric queries)
event Transfer(
    address indexed from,
    address indexed to,
    uint256 indexed tokenId
);

// DeFi swap — index pool and caller; amounts in data (not filter keys)
event Swap(
    address indexed pool,
    address indexed caller,
    uint256 amountIn,
    uint256 amountOut
);
```

### When NOT to apply
- Events emitted very rarely (constructor events, one-time admin actions):
  the filtering benefit does not justify the +375 gas/topic overhead.
- When the event has only 1 parameter and it is not a filter key.
- When all parameters are dynamic types (`string`, `bytes`): indexing them
  loses the original value. Emit non-indexed and filter by event signature
  alone.
