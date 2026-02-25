# Example Finding: PriceOracle

**Contract:** `src/PriceOracle.sol`
**Findings:** EV-001 (storage → event) + EV-002 (indexed fields)

---

## Before

```solidity
contract PriceOracle {
    uint256[] public priceHistory;  // never read on-chain
    uint256 public currentPrice;

    event PriceSet(uint256 price);  // no indexed fields

    function updatePrice(uint256 newPrice) external {
        priceHistory.push(currentPrice);  // ~22,100 gas cold SSTORE
        currentPrice = newPrice;
        emit PriceSet(newPrice);
    }
}
```

## After

```solidity
contract PriceOracle {
    // priceHistory removed — never needed on-chain
    uint256 public currentPrice;

    event PriceUpdated(
        uint256 indexed timestamp,  // EV-002: indexed for time-range queries
        uint256 oldPrice,
        uint256 newPrice
    );

    function updatePrice(uint256 newPrice) external {
        uint256 old = currentPrice;
        currentPrice = newPrice;
        emit PriceUpdated(block.timestamp, old, newPrice);  // ~1,006 gas LOG2
    }
}
```

## Findings Summary

| ID | Finding | Saving |
|----|---------|--------|
| EV-001 | `priceHistory[]` removed, `push` → `emit` | ~21,094 gas/call |
| EV-002 | `timestamp` indexed on `PriceUpdated` | Off-chain O(1) filtering |

**Verify:** `forge test --match-test testUpdatePrice -vvvv` — LOG2 opcode in trace, not SSTORE
