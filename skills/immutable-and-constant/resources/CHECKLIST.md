# Immutable and Constant Skill — Pre-completion Checklist

Run this before marking an immutable/constant review complete.

## IC-001: constant for compile-time values

- [ ] All state variable declarations at contract scope scanned
- [ ] Variables with literal initializers identified: `uint256 MAX = 10_000`,
  `bytes32 ROLE = keccak256("ADMIN")`, `uint256 FEE = 0.01 ether`
- [ ] For each: confirmed no reassignment in any function body
- [ ] Changed to `constant` — compiler inlines the value, zero runtime cost
- [ ] Naming convention: `SCREAMING_SNAKE_CASE` for constants

## IC-002: immutable for constructor-set values

- [ ] All variables assigned in the constructor but not `constant` identified
- [ ] For each: confirmed no function outside the constructor reassigns it
- [ ] Changed to `immutable` — value baked into bytecode (~3 gas to read)
- [ ] Naming convention: `SCREAMING_SNAKE_CASE` for immutables also (optional but
  consistent with IC-001)

## IC-003: hot-path address variables (priority)

- [ ] All `modifier` bodies checked for storage variable reads
- [ ] High-frequency `external` functions checked for repeated address reads
  (e.g., `owner`, `treasury`, `feeToken` read on every guarded call)
- [ ] Confirmed: address set in constructor and never reassigned
- [ ] Changed to `immutable` — saves 2,097 gas per call (cold SLOAD → PUSH20)

## Scope check

- [ ] Upgradeable contracts (proxy pattern): do NOT use `immutable` for variables
  that should be in initializer-set storage. Flag but do not apply.
- [ ] `initialize()` function pattern: `immutable` requires constructor assignment;
  initializer patterns use regular storage.
- [ ] Proxy implementation contracts: understand that `immutable` values live in
  the implementation's bytecode, not the proxy's storage.

## Verification

- [ ] `forge inspect <Contract> storageLayout --json` — constants/immutables
  do NOT appear in storage layout
- [ ] `forge test --gas-report` — calls to guarded functions show gas reduction
- [ ] `forge snapshot --diff` — net positive saving confirmed
- [ ] `forge test` — no regressions
