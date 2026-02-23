# Deployment Skill — Pre-completion Checklist

Run this before marking a deployment review complete.

## DP-001: ERC-1167 minimal proxy

- [ ] All `new ContractName(...)` in factory loops or repeated factory functions identified
- [ ] Confirmed: instances need the same logic (only storage differs)
- [ ] Confirmed: instances do NOT need to be upgradeable
- [ ] Implementation contract uses `initialize()` instead of constructor
- [ ] `_disableInitializers()` called in implementation constructor
- [ ] OpenZeppelin `Clones.clone()` or Solady `LibClone` used
- [ ] Implementation address stored as `immutable` in factory (IC-002)
- [ ] `forge test --gas-report` confirms per-instance deployment cost reduction

## DP-002: payable admin functions

- [ ] All access-controlled (onlyOwner, onlyAdmin) non-ETH functions identified
- [ ] Confirmed: contract has a withdrawal mechanism for accidentally sent ETH
- [ ] Confirmed: function is in a hot path (called frequently)
- [ ] Confirmed: function never intentionally receives ETH from callers
- [ ] `payable` added; inline comment documents why it is safe

## DP-003: dead code removal

- [ ] `forge build --sizes` run; large contracts checked for dead code
- [ ] `if (CONSTANT_FALSE)` branches identified and removed
- [ ] Unused `internal`/`private` functions (no callers) removed
- [ ] `forge test` passes after removal (no breakage from removed code)

## DP-004: vanity address (if applicable)

- [ ] Contract is expected to be called millions of times per day
- [ ] Contract address is passed as calldata to external callers
- [ ] CREATE2 deployment planned
- [ ] Brute-force computation feasibility assessed (each leading zero ≈ 256× more compute)

## Verification

- [ ] `forge build --sizes` — confirm bytecode size reduction where applicable
- [ ] `forge test` — no regressions from any change
- [ ] `forge test --gas-report` — per-function gas matches expectations
