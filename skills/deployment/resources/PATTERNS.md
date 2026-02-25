# Deployment Patterns — Quick Reference

## DP-001: ERC-1167 minimal proxy (clone factory)

```solidity
// BEFORE: deploys full bytecode per user (~500,000 gas each)
function createVault() external returns (address) {
    return address(new Vault(msg.sender));
}

// AFTER: clones share implementation, each clone costs ~41,000 gas
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

address public immutable IMPLEMENTATION;
constructor() { IMPLEMENTATION = address(new VaultImpl()); }

function createVault() external returns (address) {
    address clone = Clones.clone(IMPLEMENTATION);
    VaultImpl(clone).initialize(msg.sender);
    return clone;
}
// Refactor: constructor → initialize() with _initialized guard
// Add _disableInitializers() in VaultImpl constructor
```

Break-even: ERC-1167 saves ~(full_size × 200 − 41,000) gas per instance.

## DP-002: payable admin functions (~24 gas/call)

```solidity
// BEFORE: non-payable adds implicit `require(msg.value == 0)` check
function setConfig(uint256 v) external onlyOwner { ... }

// AFTER: check removed — saves ~24 gas per call
function setConfig(uint256 v) external payable onlyOwner { ... }
// Warning: only safe if contract has ETH recovery or admin is trusted
```

## DP-003: Remove dead code (200 gas/byte of bytecode)

```solidity
// Remove: constant-false branches, unused internal/private functions
bool public constant IS_PRESALE = false;
function buy() external {
    if (IS_PRESALE) { _applyDiscount(); }  // dead — remove this block
    _process();
}
function _applyDiscount() internal pure { ... }  // unreachable — remove entirely
```

Measure: `forge build --sizes` before and after.

## DP-004: Vanity address via CREATE2 (ultra-high-frequency only)

Each leading zero byte in a contract address saves ~12 gas per CALL to that address
(EIP-2929 access list lookup). Worthwhile only for contracts with millions of calls/day.
Use `cast create2` or a dedicated miner to find a salt that produces the desired prefix.
