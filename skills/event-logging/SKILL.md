---
name: event-logging
description: >
  Detects storage writes used for off-chain-only historical data and recommends
  replacing them with event emission. Also identifies events missing indexed
  parameters on filterable fields. LOG1 costs ~375 gas vs cold SSTORE 22,100 gas
  for off-chain data. Covers EV-001 (storage → events for historical data) and
  EV-002 (indexed parameter selection for filterable events). Use when writing
  storage arrays for historical records or event declarations in Foundry-based
  Solidity projects.
allowed-tools: Read
---

## Purpose

Identify storage arrays used solely for off-chain historical data and replace
the writes with event emission. Also audit event declarations for missing
`indexed` parameters on fields that callers will filter by.

## When to Use

- Writing or reviewing functions that push to storage arrays
- Adding new events to a contract
- Pre-audit review of data retention patterns
- Reviewing any contract that stores audit trails, price history, or action logs

## When NOT to Use

- When storage data must be read by on-chain code (another contract or the
  same contract reads the array on-chain)
- When historical data must survive contract replacement and be directly
  accessible via `eth_getStorageAt` without indexer infrastructure
- When reviewing contracts with no storage arrays and no events

## Rationalizations to Reject

| Rationalization | Why It's Wrong | Required Action |
|---|---|---|
| "We might need to read this on-chain later" | Speculation is not a reason to pay 22,100 gas per push today; if on-chain read is genuinely needed, design for it explicitly | Confirm on-chain read requirement before keeping storage |
| "Events can be lost or missed" | Events are part of the transaction receipt, permanent on-chain once included; off-chain indexers (The Graph, Etherscan) reliably capture them | Use events for historical data; storage only for current state |
| "It's just one array" | One array pushed once per user action at 1,000 users/day = 22,100,000 gas/day wasted | Estimate the volume, not the per-instance cost |
| "Removing storage might break existing callers" | Before removing, verify no external contract reads the array via `eth_getStorageAt` or ABI calls; confirm off-chain-only access | Audit callers, don't assume |

## Platform Detection

Trigger on any `.sol` file containing storage array `push()` calls or `event`
declarations without `indexed` parameters on address/uint256/bytes32 fields.

## Quick Reference

| Data type | On-chain access needed? | Recommendation |
|---|---|---|
| Historical array pushes | No (only off-chain) | Replace with `emit Event()` |
| Current state value | Yes | Keep in storage |
| Event `address`/`uint256`/`bytes32` fields used for filtering | — | Add `indexed` |
| More than 3 filterable fields | — | Index the 3 most important |
| `string`/`bytes` event field | — | Do NOT index (hashes value, loses original) |

## Workflow

1. **Find storage arrays written but never read on-chain.**
   Search the contract for `storageArray.push(...)` calls. For each array,
   search the entire contract for any read access: `storageArray[i]`,
   `storageArray.length`, or passing `storageArray` to an internal function.
   If the array is only pushed to and never read on-chain, it is an EV-001
   candidate. Confirm the data is only needed off-chain (historical record,
   analytics, audit trail).

2. **Replace `push()` with `emit` for write-only arrays.**
   Define an event that captures the same fields as the struct or value being
   pushed. Replace `array.push(value)` with `emit EventName(fields...)`.
   Remove the storage array declaration if it has no remaining readers.
   Keep any storage variable that holds the current/latest value — only the
   historical log is moved to events.

3. **Review all event declarations for `indexed` coverage.**
   For each `event` declaration, identify fields that callers will filter by:
   addresses (sender, recipient, owner), IDs (tokenId, orderId), and key
   amounts. Add `indexed` to up to 3 such fields per event. Do not index
   `string`, `bytes`, or dynamic arrays (indexing hashes them, making the
   original value unrecoverable from the topic). Do not index fields that are
   never used as filter criteria in off-chain queries.

## Supporting Docs

Only read these files when explicitly needed — do not load all three by default:

| File | Read only when… |
|---|---|
| `resources/PATTERNS.md` | You need EV-002 indexed topic cost calculations or The Graph query impact examples |
| `resources/CHECKLIST.md` | Producing a formal `/gas:analyze` report and confirming all storage arrays were audited |
| `resources/EXAMPLE_FINDING.md` | Generating a report and needing the exact output format for a history-array finding |
| `docs/evm-gas-reference.md` | You need LOG opcode costs or the SSTORE vs event gas comparison table |

## Output Format

Report each finding with: pattern ID, storage variable or event name, file and
line reference, gas estimate, and the exact change required.

**Example finding (EV-001):**

```
EV-001 | PriceOracle.sol:8 | priceHistory[]
  Severity : high
  Gas saved : ~21,094 gas per updatePrice() call
              (LOG2 ~1,006 gas vs cold SSTORE 22,100 gas per history entry)

  Before:
    uint256[] public priceHistory;

    function updatePrice(uint256 newPrice) external {
        priceHistory.push(currentPrice);   // SSTORE ~22,100 gas cold
        currentPrice = newPrice;
    }

  After:
    event PriceUpdated(
        uint256 indexed timestamp,
        uint256 oldPrice,
        uint256 newPrice
    );

    function updatePrice(uint256 newPrice) external {
        uint256 old = currentPrice;
        currentPrice = newPrice;
        emit PriceUpdated(block.timestamp, old, newPrice);   // LOG2 ~1,006 gas
    }

  Reason: priceHistory is never read on-chain. Off-chain indexers (The Graph,
  Etherscan) capture PriceUpdated events. Storage array eliminated entirely.

  Verify:
    forge test --match-test testUpdatePrice -vvvv   # LOG opcode not SSTORE
    forge test --gas-report
```

**Example finding (EV-002):**

```
EV-002 | NFTMarket.sol:6 | Sale event missing indexed fields
  Severity : low
  Gas saved : off-chain filtering ~O(1) vs O(n) scan; on-chain emit
              costs +375 gas per indexed topic added

  Before:
    event Sale(address seller, address buyer, uint256 tokenId, uint256 price);

  After:
    event Sale(
        address indexed seller,
        address indexed buyer,
        uint256 indexed tokenId,
        uint256 price             // non-indexed: price not a filter field
    );

  Reason: seller, buyer, and tokenId are the primary filter keys for
  querying sales history. Ethereum bloom filters enable O(1) topic-based
  filtering. price is rarely used as a filter key and is retrieved from
  the data field.

  Verify:
    forge test --match-test testBuy -vvvv   # LOG4 (3 indexed + event sig topic)
```
