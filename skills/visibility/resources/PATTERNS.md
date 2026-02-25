# Visibility Patterns — Quick Reference

## VI-001: public → external (no internal callers)

```solidity
// BEFORE: public generates two entry points (external + internal ABI)
function transfer(address to, uint256 amount) public { ... }
function batchTransfer(uint256[] memory ids, address to) public { ... }

// AFTER: external + calldata (combine with CD-001 for reference params)
function transfer(address to, uint256 amount) external { ... }
function batchTransfer(uint256[] calldata ids, address to) external { ... }
// ~24 gas saved (simple params) | thousands saved (array params via calldata)
```

**Confirm no internal callers before changing:**
```bash
rg "transfer\(" --type sol  # no bare calls inside same contract
```

**Must stay public when:**
- Called internally as `functionName(args)` (bare call = internal dispatch)
- Called as `this.functionName(args)` — this is an external call but must stay public
- Required by an interface that specifies `public`

## VI-002: Remove duplicate manual getters

```solidity
// BEFORE: manual getter duplicates auto-generated one
address public owner;  // Solidity already generates owner() getter

function getOwner() external view returns (address) {
    return owner;  // VI-002: redundant — callers can call owner() directly
}

// AFTER: delete getOwner() entirely
// Callers use auto-generated owner() getter at no extra cost
```

Applies when: a `view` function's entire body is `return stateVar` or `return mapping[param]`
and the state variable is already `public`.

## Gas savings

| Scenario | Saving |
|---|---|
| `external` over `public`, simple params | ~24 gas/call |
| `external` + `calldata` for 10-element array | ~960 gas/call |
| `external` + `calldata` for 7-field struct | ~672 gas/call |
| Remove duplicate getter | Bytecode reduction only (one-time) |
