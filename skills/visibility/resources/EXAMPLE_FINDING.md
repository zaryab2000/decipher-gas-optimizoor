# Example Finding: NFTMarket

**Contract:** `src/NFTMarket.sol`
**Findings:** VI-001 + CD-001 (batchTransfer) + VI-002 (duplicate getter)

---

## Before

```solidity
contract NFTMarket {
    address public owner;
    mapping(uint256 => address) public tokenOwner;

    function batchTransfer(uint256[] memory ids, address to) public {
        for (uint256 i = 0; i < ids.length; ++i) {
            tokenOwner[ids[i]] = to;
        }
    }

    function getOwner() external view returns (address) {
        return owner;  // duplicates auto-generated owner() getter
    }
}
```

## After

```solidity
contract NFTMarket {
    address public owner;
    mapping(uint256 => address) public tokenOwner;

    // VI-001 + CD-001: public→external, memory→calldata
    function batchTransfer(uint256[] calldata ids, address to) external {
        uint256 len = ids.length;
        for (uint256 i = 0; i < len;) {
            tokenOwner[ids[i]] = to;
            unchecked { ++i; }
        }
    }
    // getOwner() deleted — callers use owner() auto-getter (VI-002)
}
```

## Findings Summary

| ID | Finding | Saving |
|----|---------|--------|
| VI-001 + CD-001 | `batchTransfer`: public+memory → external+calldata | ~984 gas/call (10 IDs) |
| VI-002 | `getOwner()` deleted (duplicate of `owner()`) | Bytecode reduction |

**Verify:** `rg "batchTransfer\|getOwner" --type sol` to confirm no internal callers, then `forge test --gas-report`
