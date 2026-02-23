# Deployment Skill — Example Finding: Token Vault Factory

## Contract Under Review

`src/VaultFactory.sol` — A factory that deploys individual user vault contracts,
each requiring a separate deployment transaction.

## Findings

### Finding 1 — DP-001: Full Deployment in Factory Loop (CRITICAL)

**File:** src/VaultFactory.sol, line 18
**Estimated saving:** ~491,000 gas per vault created

**Current code:**
```solidity
contract VaultFactory {
    address[] public vaults;

    function createVault() external returns (address vault) {
        vault = address(new UserVault(msg.sender));  // 32,000 + 200×bytecodeSize gas
        vaults.push(vault);
        emit VaultCreated(msg.sender, vault);
    }
}

contract UserVault {
    address public owner;
    // 200 functions... ~2,500 bytes of bytecode
    constructor(address _owner) { owner = _owner; }
}
```

**Cost:** deploying `UserVault` (2,500 bytes) = 32,000 + 200 × 2,500 = **532,000 gas per vault**

**Optimized code:**
```solidity
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract VaultFactory {
    address public immutable IMPLEMENTATION;
    address[] public vaults;

    constructor() {
        IMPLEMENTATION = address(new UserVaultImpl());
        UserVaultImpl(IMPLEMENTATION).initialize(address(0));
    }

    function createVault() external returns (address vault) {
        vault = Clones.clone(IMPLEMENTATION);       // 32,000 + 200×45 = 41,000 gas
        UserVaultImpl(vault).initialize(msg.sender);
        vaults.push(vault);
        emit VaultCreated(msg.sender, vault);
    }
}

contract UserVaultImpl {
    address public owner;
    bool private _initialized;

    function initialize(address _owner) external {
        require(!_initialized);
        _initialized = true;
        owner = _owner;
    }
    // 200 functions... same logic
}
```

**Savings per vault:** 532,000 − 41,000 = **491,000 gas** (~12× cheaper)
For 1,000 vaults: **491,000,000 gas saved**

---

### Finding 2 — DP-003: Dead Code Inflating Bytecode (LOW)

**File:** src/UserVault.sol, line 120
**Estimated saving:** ~6,000 gas at deployment (30 dead function bytes × 200 gas/byte)

**Current code:**
```solidity
bool public constant FEATURE_ENABLED = false;

function _applyFeature(uint256 amount) internal pure returns (uint256) {
    // Dead function — FEATURE_ENABLED is false; this function is never called
    return amount * 95 / 100;
}
```

**Optimized code:**
```solidity
// Removed: _applyFeature and FEATURE_ENABLED constant
// Bytecode shrinks; deployment gas decreases proportionally
```

---

## Summary

| Finding | Technique | Severity | Estimated Saving |
|---|---|---|---|
| Full deployment per vault | DP-001 | CRITICAL | 491,000 gas/vault |
| Dead presale code | DP-003 | LOW | ~6,000 gas at deployment |

**Priority:** DP-001 dominates — 491,000 gas × vault count is the primary target.
