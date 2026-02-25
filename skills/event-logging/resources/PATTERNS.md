# Event Logging Patterns — Quick Reference

## EV-001: Replace write-only storage array with event

```solidity
// BEFORE: push to storage array that is never read on-chain
uint256[] public priceHistory;
function updatePrice(uint256 newPrice) external {
    priceHistory.push(currentPrice);  // ~22,100 gas cold SSTORE
    currentPrice = newPrice;
}

// AFTER: emit event — indexers capture it, no storage cost
event PriceUpdated(uint256 indexed timestamp, uint256 oldPrice, uint256 newPrice);
function updatePrice(uint256 newPrice) external {
    uint256 old = currentPrice;
    currentPrice = newPrice;
    emit PriceUpdated(block.timestamp, old, newPrice);  // ~1,006 gas (LOG2)
}
// Saving: ~21,094 gas per call
// Remove the priceHistory array declaration entirely
```

**Before removing the array:** confirm it has zero on-chain readers anywhere in the contract
(no `priceHistory[i]`, no `priceHistory.length`, not passed to internal functions).

## EV-002: Add indexed parameters to filterable fields

```solidity
// BEFORE: no indexed fields — O(n) scan required to find events by sender/token
event Sale(address seller, address buyer, uint256 tokenId, uint256 price);

// AFTER: index the 3 most-filtered fields
event Sale(
    address indexed seller,
    address indexed buyer,
    uint256 indexed tokenId,
    uint256 price          // non-indexed: price is rarely a filter key
);
// Cost: +375 gas per indexed topic (each indexed field = 1 extra LOG topic)
```

**Indexing rules:**
- Index: `address` (sender, recipient, owner), IDs (tokenId, orderId), key enums
- Do NOT index: `string`, `bytes`, dynamic arrays — indexing hashes them, original value lost
- Maximum 3 indexed params per event
- Do not index fields never used as filter criteria in off-chain queries
