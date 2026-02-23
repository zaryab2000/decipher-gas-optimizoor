# Custom Errors — Example Finding

## Contract Under Review

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleToken {
    address public owner;
    bool    public paused;
    uint256 public maxSupply;
    uint256 public totalSupply;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    constructor(uint256 _maxSupply) {
        owner     = msg.sender;
        maxSupply = _maxSupply;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Only owner");          // CE-001
        require(!paused, "Contract is paused");              // CE-001
        require(totalSupply + amount <= maxSupply, "Exceeds max supply");  // CE-001
        balances[to] += amount;
        totalSupply  += amount;
    }

    function transfer(address to, uint256 amount) external {
        require(!paused, "Contract is paused");              // CE-001 (duplicate string)
        require(balances[msg.sender] >= amount, "Insufficient balance");  // CE-001
        if (to == address(0)) revert("Cannot transfer to zero address");  // CE-002
        balances[msg.sender] -= amount;
        balances[to]         += amount;
    }

    function approve(address spender, uint256 amount) external {
        require(!paused, "Contract is paused");              // CE-001 (duplicate string)
        allowances[msg.sender][spender] = amount;
    }

    function setPaused(bool _paused) external {
        require(msg.sender == owner, "Only owner");          // CE-001 (duplicate string)
        paused = _paused;
    }
}
```

---

## Analysis

**Total string reverts found:** 7 (across 4 unique strings + 1 bare revert string)
**Distinct error declarations needed:** 4 custom errors
**Estimated bytecode reduction:** ~160 bytes (strings removed from bytecode)
**Estimated deployment gas saving:** ~32,000 gas (160 bytes × 200 gas/byte)
**Estimated runtime saving:** ~15–50 gas per revert path triggered

---

## Findings

### [MEDIUM] CE-001 — require("Only owner") at 4 call sites

**Files:** src/SimpleToken.sol, lines 20, 36 (mint, setPaused)
**Estimated saving:** ~24 gas per revert + deployment bytecode reduction

"Only owner" (10 bytes) appears in bytecode once per `require` site. With 2 sites, the
string consumes ~192 bytes of deployment bytecode (including ABI encoding padding).

```solidity
// BEFORE — string stored per require, ~96 bytes of revert data per revert
require(msg.sender == owner, "Only owner");

// AFTER — one declaration, 4-byte selector reused at all sites
error NotOwner();
if (msg.sender != owner) revert NotOwner();
```

---

### [MEDIUM] CE-001 — require("Contract is paused") at 3 call sites

**Files:** src/SimpleToken.sol, lines 21, 30, 37
**Estimated saving:** ~24 gas per revert + deployment bytecode reduction

"Contract is paused" (18 bytes) appears at 3 require sites. Removing all 3 saves
approximately 3 × 160 bytes = 480 bytes of bytecode.

```solidity
// BEFORE — string stored three times in bytecode
require(!paused, "Contract is paused");

// AFTER — one declaration at contract scope
error ContractPaused();
if (paused) revert ContractPaused();
```

---

### [MEDIUM] CE-001 — require("Exceeds max supply")

**File:** src/SimpleToken.sol, line 22
**Estimated saving:** ~24 gas per revert + deployment bytecode reduction

This error has useful context: how much was requested and what the cap is.
Apply CE-003 — add typed parameters.

```solidity
// BEFORE — no context on how much was attempted vs what's available
require(totalSupply + amount <= maxSupply, "Exceeds max supply");

// AFTER — typed context makes the revert decodable by off-chain tooling
error ExceedsMaxSupply(uint256 requested, uint256 available);
uint256 remaining = maxSupply - totalSupply;
if (amount > remaining) revert ExceedsMaxSupply(amount, remaining);
```

---

### [MEDIUM] CE-001 + CE-003 — require("Insufficient balance")

**File:** src/SimpleToken.sol, line 31
**Estimated saving:** ~24 gas per revert + better debugging context

This error has directly useful context: the amount requested and the balance available.

```solidity
// BEFORE — no numbers visible in the revert
require(balances[msg.sender] >= amount, "Insufficient balance");

// AFTER — needed and available both included
error InsufficientBalance(uint256 needed, uint256 available);
uint256 balance = balances[msg.sender];
if (balance < amount) revert InsufficientBalance(amount, balance);
```

---

### [MEDIUM] CE-002 — revert("Cannot transfer to zero address")

**File:** src/SimpleToken.sol, line 33
**Estimated saving:** ~24 gas per revert + ~160 bytes bytecode

"Cannot transfer to zero address" (32 bytes) is a bare string revert. Convert to a
parameterless custom error — the zero address itself is the context (implicit from the
failed condition).

```solidity
// BEFORE — 32-byte string stored in bytecode, ~128 bytes ABI revert data
if (to == address(0)) revert("Cannot transfer to zero address");

// AFTER — 4-byte selector only
error ZeroAddress();
if (to == address(0)) revert ZeroAddress();
```

---

## Optimized Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SimpleToken {
    // Custom errors — declared once, reused at every call site
    error NotOwner();
    error ContractPaused();
    error ExceedsMaxSupply(uint256 requested, uint256 available);
    error InsufficientBalance(uint256 needed, uint256 available);
    error ZeroAddress();

    address public owner;
    bool    public paused;
    uint256 public maxSupply;
    uint256 public totalSupply;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    constructor(uint256 _maxSupply) {
        owner     = msg.sender;
        maxSupply = _maxSupply;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != owner) revert NotOwner();
        if (paused) revert ContractPaused();
        uint256 remaining = maxSupply - totalSupply;
        if (amount > remaining) revert ExceedsMaxSupply(amount, remaining);
        balances[to] += amount;
        totalSupply  += amount;
    }

    function transfer(address to, uint256 amount) external {
        if (paused) revert ContractPaused();
        uint256 balance = balances[msg.sender];
        if (balance < amount) revert InsufficientBalance(amount, balance);
        if (to == address(0)) revert ZeroAddress();
        balances[msg.sender] = balance - amount;
        balances[to]        += amount;
    }

    function approve(address spender, uint256 amount) external {
        if (paused) revert ContractPaused();
        allowances[msg.sender][spender] = amount;
    }

    function setPaused(bool _paused) external {
        if (msg.sender != owner) revert NotOwner();
        paused = _paused;
    }
}
```

## Total Gas Savings Summary

| Finding | Runtime saving | Bytecode saving |
|---------|---------------|-----------------|
| CE-001: NotOwner (×2 sites) | ~24 gas/revert | ~384 bytes |
| CE-001: ContractPaused (×3 sites) | ~24 gas/revert | ~576 bytes |
| CE-001+CE-003: ExceedsMaxSupply | ~24 gas/revert | ~192 bytes |
| CE-001+CE-003: InsufficientBalance | ~24 gas/revert | ~192 bytes |
| CE-002: ZeroAddress | ~24 gas/revert | ~320 bytes |
| **Total** | **~24 gas per revert path** | **~1,664 bytes → ~332,800 gas deployment** |

Note: bytecode deployment saving is approximate. Use `forge inspect SimpleToken bytecodeSize`
before and after to measure actual reduction.

## Verification

```bash
forge build                                     # confirm contract compiles
forge inspect SimpleToken bytecodeSize          # compare before/after
forge test --gas-report                         # verify revert path gas
```
