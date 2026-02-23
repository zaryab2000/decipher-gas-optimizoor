# Visibility Skill — Example Finding: NFT Marketplace

## Contract Under Review

`src/RoyaltyNFT.sol` — An NFT contract with minting, batch transfer, and royalty
distribution functions.

## Findings

### Finding 1 — VI-001 + CD-001: `batchTransfer` public with array param (HIGH)

**File:** src/RoyaltyNFT.sol, line 31
**Estimated saving:** ~1,920 gas per call (20-element batch: 640 bytes × 3 gas/byte + dispatcher)

**Before:**
```solidity
function batchTransfer(uint256[] memory ids, address to) public {
    for (uint256 i = 0; i < ids.length; i++) {
        require(_isApprovedOrOwner(msg.sender, ids[i]), "Not approved");
        _transfer(ownerOf(ids[i]), to, ids[i]);
    }
}
```

**After:**
```solidity
function batchTransfer(uint256[] calldata ids, address to) external {
    uint256 len = ids.length;
    for (uint256 i = 0; i < len;) {
        if (!_isApprovedOrOwner(msg.sender, ids[i])) revert NotApproved();
        _transfer(ownerOf(ids[i]), to, ids[i]);
        unchecked { ++i; }
    }
}
```

**Verification:** `rg "batchTransfer\(" --type sol` → 0 internal callers confirmed

---

### Finding 2 — VI-001: `mint` public, simple params (LOW)

**File:** src/RoyaltyNFT.sol, line 18
**Estimated saving:** ~24 gas per mint call

**Before:**
```solidity
function mint(address to, uint256 tokenId) public onlyOwner { ... }
```

**After:**
```solidity
function mint(address to, uint256 tokenId) external onlyOwner { ... }
```

---

### Finding 3 — VI-001: KEEP `_burnInternal` public (informational)

**File:** src/RoyaltyNFT.sol, line 62

```solidity
// KEEP public: called by both burn() and emergencyBurn() in this contract
function _burnInternal(uint256 tokenId) public { ... }
```

`_burnInternal` is called by `burn()` and `emergencyBurn()` as bare internal calls.
Changing to `external` would break these call sites. Leave as `public`.

---

### Finding 4 — VI-002: `getOwner` duplicates auto-getter (LOW)

**File:** src/RoyaltyNFT.sol, line 78
**Estimated saving:** ~300 gas at deployment (bytecode reduced)

**Before:**
```solidity
mapping(uint256 => address) public tokenOwner;

function getOwner(uint256 tokenId) public view returns (address) {
    return tokenOwner[tokenId];  // duplicate of tokenOwner(uint256) auto-getter
}
```

**After:**
```solidity
mapping(uint256 => address) public tokenOwner;
// getOwner removed — callers use tokenOwner(tokenId) directly
```

---

## Summary

| Finding | Technique | Severity | Estimated Saving |
|---|---|---|---|
| batchTransfer memory→calldata + external | VI-001 + CD-001 | HIGH | ~1,920 gas/20-batch call |
| mint → external | VI-001 | LOW | ~24 gas/call |
| _burnInternal: KEEP public | — | Informational | — |
| getOwner duplicate removed | VI-002 | LOW | ~300 gas at deployment |

**Priority:** Finding 1 dominates — fix batchTransfer first.
