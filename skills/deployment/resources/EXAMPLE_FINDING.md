# Example Finding: VaultFactory

**Contract:** `src/VaultFactory.sol`
**Finding:** DP-001 (minimal proxy factory)

---

## Before

```solidity
contract VaultFactory {
    address[] public vaults;

    function createVault() external returns (address) {
        Vault vault = new Vault(msg.sender);  // ~532,000 gas per user
        vaults.push(address(vault));
        return address(vault);
    }
}
```

## After

```solidity
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract VaultFactory {
    address public immutable IMPLEMENTATION;
    address[] public vaults;

    constructor() {
        IMPLEMENTATION = address(new VaultImpl());  // deployed once
    }

    function createVault() external returns (address) {
        address clone = Clones.clone(IMPLEMENTATION);  // ~41,000 gas
        VaultImpl(clone).initialize(msg.sender);
        vaults.push(clone);
        return clone;
    }
}
```

## Finding Summary

| ID | Finding | Saving |
|----|---------|--------|
| DP-001 | `new Vault()` → ERC-1167 clone | ~491,000 gas per vault created |

**Migration note:** Refactor `Vault` constructor to `initialize()` with an `_initialized` guard.
Add `constructor() { _disableInitializers(); }` to `VaultImpl`.

**Verify:** `forge test --match-test testCreateVault --gas-report`
