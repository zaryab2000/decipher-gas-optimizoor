# Example Finding: MerkleDropper

**Contract:** `src/MerkleDropper.sol`
**Findings:** CD-001 (array calldata) + CD-002 (struct calldata)

---

## Before

```solidity
contract MerkleDropper {
    struct Claim { address user; uint256 amount; bytes32 salt; }

    function claimBatch(
        Claim memory claim,           // CD-002: 96-byte struct copied to memory
        bytes32[] memory proof        // CD-001: 10-element proof copied to memory
    ) external {
        require(_verify(proof, merkleRoot, keccak256(abi.encode(claim))));
        _distribute(claim.user, claim.amount);
    }

    function _verify(bytes32[] memory proof, bytes32 root, bytes32 leaf)
        internal pure returns (bool) { /* ... */ }
}
```

## After

```solidity
contract MerkleDropper {
    struct Claim { address user; uint256 amount; bytes32 salt; }

    function claimBatch(
        Claim calldata claim,          // CD-002: direct calldata read
        bytes32[] calldata proof       // CD-001: direct calldata read
    ) external {
        require(_verify(proof, merkleRoot, keccak256(abi.encode(claim))));
        _distribute(claim.user, claim.amount);
    }

    function _verify(bytes32[] calldata proof, bytes32 root, bytes32 leaf)
        internal pure returns (bool) { /* ... */ }  // calldata propagated
}
```

## Findings Summary

| ID | Finding | Saving |
|----|---------|--------|
| CD-002 | `Claim` struct: memory → calldata | ~288 gas (96 bytes × 3) |
| CD-001 | `bytes32[]` proof: memory → calldata | ~960 gas (320 bytes × 3) |
| **Total** | | **~1,248 gas/call** |

**Verify:** `forge test` (no mismatch errors) then `forge test --gas-report`
