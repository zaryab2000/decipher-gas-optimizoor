---
name: deployment
description: >
  Detects deployment cost inefficiencies in Solidity: factory patterns that deploy
  full contracts when ERC-1167 minimal proxies would suffice, non-payable admin
  functions with unnecessary ETH check overhead, dead code paths inflating bytecode,
  and opportunities for vanity addresses via CREATE2 for high-frequency contracts.
  Covers DP-001 (minimal proxy factories), DP-002 (payable admin functions),
  DP-003 (dead code removal), DP-004 (vanity addresses). Use when writing
  constructors, factory contracts, or reviewing bytecode size.
allowed-tools:
  - Read
  - Bash
---

## Purpose

Identify deployment cost inefficiencies: factory patterns deploying full
contracts instead of minimal proxies, dead code inflating bytecode, and
configuration-level savings (payable admin functions, vanity addresses for
ultra-high-frequency protocols). Deployment cost is 200 gas/byte of bytecode
and is paid once per instance — reducing it compounds at factory scale.

## When to Use

- Writing or reviewing factory contracts
- Reviewing constructors and `new ContractName()` patterns
- Pre-deployment review of bytecode size
- Reviewing contracts with known dead or conditional code paths
- Reviewing admin functions in high-frequency DeFi protocols

## When NOT to Use

- Contracts that are already using proxies (ERC-1967, UUPS, Beacon)
- Singleton contracts deployed once with no factory pattern
- When dead code was intentionally preserved for a future activation

## Platform Detection

Trigger fires when:
- A factory function uses `new ContractName()` to deploy multiple instances
- `Bash` is available to run `forge build --sizes` for bytecode measurement

## Quick Reference

- Factory deploying `new ContractName()` for each user? → ERC-1167 minimal
  proxy (DP-001, ~491,000 gas saved per clone)
- Admin function called thousands of times? → `payable` removes ~24 gas/call
  ETH check (DP-002)
- Dead `if(CONSTANT_FALSE)` branch or unused `internal`/`private` function?
  → remove it (DP-003, 200 gas/byte)
- CREATE2 factory for ultra-high-frequency protocol (millions of calls/day)?
  → consider vanity address (DP-004, ~12 gas/call/leading-zero-byte)

## Workflow

1. **Find factory patterns — does it use `new ContractName()`?**
   Search the contract for `new ` keywords. For each `new` deployment, ask:
   (a) Are multiple instances of this contract expected? (b) Do all instances
   share the same logic (same bytecode)? (c) Do instances only differ in their
   initial storage state (set via constructor arguments)?
   If yes to all three, the factory is an ERC-1167 minimal proxy candidate
   (DP-001). Estimate savings: (full_bytecode_size × 200 gas − 41,000 gas) per
   instance. The implementation must be refactored to use `initialize()` instead
   of a constructor.

2. **Find dead code — constant-false branches, unreachable code, unused
   private/internal functions.**
   Look for `if (CONSTANT)` where the constant is provably false; `internal`
   or `private` functions with no call sites in the contract; functions
   explicitly marked deprecated with no callers. Removing dead code saves
   200 gas per byte at deployment — measure with `forge build --sizes` before
   and after. Also flag any code path that the optimizer does not eliminate
   (some patterns require explicit removal).

3. **Find non-payable admin functions — would `payable` save meaningful gas?**
   For functions with explicit access control (onlyOwner, onlyAdmin) called
   frequently, consider whether the ~24 gas/call saving from removing the
   `msg.value == 0` check justifies the risk. This is a micro-optimization —
   apply only after storage, loop, calldata, and struct optimizations are done.
   Note: adding `payable` to a function in a contract with no ETH withdrawal
   mechanism risks permanently locking any accidentally sent ETH.

## Output Format

Report each finding with: pattern ID, contract/function, file and line
reference, gas estimate, and the exact change required.

**Example finding (DP-001):**

```
DP-001 | VaultFactory.sol:12 | VaultFactory.createVault()
  Severity : critical
  Gas saved : ~491,000 gas per vault deployment
              (full Vault ~532,000 gas vs ERC-1167 clone ~41,000 gas)

  Before:
    function createVault() external returns (address) {
        Vault vault = new Vault(msg.sender);   // 500,000+ gas per user
        vaults.push(address(vault));
        return address(vault);
    }

  After:
    import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

    address public immutable IMPLEMENTATION;

    constructor() {
        IMPLEMENTATION = address(new VaultImpl());   // deployed once
    }

    function createVault() external returns (address) {
        address clone = Clones.clone(IMPLEMENTATION);   // ~41,000 gas
        VaultImpl(clone).initialize(msg.sender);
        vaults.push(clone);
        return clone;
    }

  Migration: Refactor Vault constructor to initialize() with _initialized
  guard. Add _disableInitializers() in VaultImpl constructor (OpenZeppelin
  pattern) to prevent initializing the implementation contract itself.

  Verify:
    forge test --match-test testCreateVault --gas-report
    forge test -vvvv   # DELEGATECALL visible in clone function calls
```

**Example finding (DP-003):**

```
DP-003 | TokenSale.sol:14 | dead _applyPresaleDiscount() branch
  Severity : low
  Gas saved : 200 gas/byte × bytecode removed (measure with forge build --sizes)

  Issue:
    bool public constant IS_PRESALE = false;
    function buy(uint256 amount) external payable {
        if (IS_PRESALE) {
            _applyPresaleDiscount(amount);   // dead — IS_PRESALE is false
        }
        _processPurchase(amount);
    }
    function _applyPresaleDiscount(uint256 amount) internal pure returns (uint256) {
        return amount * 80 / 100;   // unreachable internal function
    }

  Fix: Remove the if (IS_PRESALE) block and _applyPresaleDiscount entirely.
  The optimizer may eliminate some dead code — measure before and after.

  Verify:
    forge build --sizes   # bytecode size before vs after
```

## Supporting Docs

Only read these files when explicitly needed — do not load all three by default:

| File | Read only when… |
|---|---|
| `resources/PATTERNS.md` | You need DP-004 (vanity address via CREATE2) details or full ERC-1167 clone implementation not shown above |
| `resources/CHECKLIST.md` | Producing a formal `/gas:analyze` report and confirming all deployment patterns were checked |
| `resources/EXAMPLE_FINDING.md` | Generating a report and needing the exact output format for a factory optimization finding |

**Example finding (DP-002):**

```
DP-002 | AdminControl.sol:22 | setConfig() non-payable admin function
  Severity : low
  Gas saved : ~24 gas per call
  Context  : admin function called ~1,000 times/year — marginal impact

  Before:
    function setConfig(uint256 value) external {
        require(msg.sender == ADMIN);
        // ...
    }

  After:
    function setConfig(uint256 value) external payable {
        require(msg.sender == ADMIN);
        // ...
    }

  Warning: Only safe if the contract has a mechanism to recover accidentally
  sent ETH, or if the admin is trusted not to send ETH accidentally. Apply
  only after all higher-priority optimizations are addressed.

  Verify:
    forge snapshot --diff   # ~24 gas reduction per call
```
