# Immutable and Constant Patterns — Quick Reference

## IC-001: Compile-time literal → constant

```solidity
// BEFORE: storage slot allocated, SLOAD on every read
uint256 public maxSupply = 10_000;
bytes32 public ADMIN_ROLE = keccak256("ADMIN");

// AFTER: inlined by compiler — zero runtime cost, no storage slot
uint256 public constant MAX_SUPPLY = 10_000;
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
```

Applies to: numeric literals, `keccak256("string")`, `type(uint256).max`, ETH amounts.

## IC-002: Constructor-set-once address/value → immutable

```solidity
// BEFORE: 3 storage slots, 2,100 gas cold SLOAD each read
address public owner;
address public feeToken;
address public treasury;
constructor(address o, address f, address t) { owner = o; feeToken = f; treasury = t; }

// AFTER: baked into bytecode, ~3 gas per read
address public immutable OWNER;
address public immutable FEE_TOKEN;
address public immutable TREASURY;
constructor(address o, address f, address t) { OWNER = o; FEE_TOKEN = f; TREASURY = t; }
```

## IC-003: Hot-path modifier variable (priority case)

```solidity
// BEFORE: SLOAD on every function call guarded by onlyOwner
address public owner;
modifier onlyOwner() { require(msg.sender == owner); _; }

// AFTER: PUSH20 opcode — ~2,097 gas saved per guarded call
address public immutable OWNER;
modifier onlyOwner() { require(msg.sender == OWNER); _; }
```

Flag IC-003 at highest severity when the variable is inside a modifier called by many functions.

## Constraints

- `immutable` requires assignment in the **constructor only** — cannot be set in initializers
- `constant` requires a compile-time-evaluable expression — cannot be set from function args
- Upgradeable contracts: `immutable` lives in implementation bytecode, not proxy storage — safe to use
- Do not apply to variables that must change after deployment
