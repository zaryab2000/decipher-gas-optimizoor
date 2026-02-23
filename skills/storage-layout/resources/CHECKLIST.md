# Storage Layout Review Checklist

Run this checklist before marking any storage-layout review complete.
Every unchecked item is a potential missed gas saving or a missed constraint that
could cause a recommendation to be incorrect.

---

## Struct Packing (SL-001, SL-002)

- [ ] Every struct in scope has had packing check applied — not just the largest or most
      obvious one
- [ ] `forge inspect <ContractName> storageLayout --json` output reviewed for slot
      assignments (skip and note if forge is unavailable)
- [ ] All wasted slots identified — not just the first one encountered
- [ ] Each finding reports the before and after slot count with byte-level justification
- [ ] `address` + `uint96` perfect-pair opportunity checked for every struct with an
      `address` field (SL-002)
- [ ] No struct fields have been reordered in an upgradeable contract — if the contract
      uses `UUPSUpgradeable`, `Initializable`, or storage gaps, note the constraint and
      skip reordering

## Gas Estimates (all techniques)

- [ ] Gas estimate provided for each finding — minimum 1 concrete number per finding
      (e.g., "~44,200 gas per write" not just "saves gas")
- [ ] Gas numbers are derived from the knowledge base constants (cold SSTORE 22,100,
      warm SSTORE 2,900, cold SLOAD 2,100, warm SLOAD 100, TSTORE/TLOAD 100 each)
- [ ] No gas numbers invented — if uncertain, state the range rather than a precise figure

## Code Examples

- [ ] At least 1 optimized code example provided per finding (before + after Solidity
      blocks with inline slot comments)
- [ ] Slot annotations added to optimized structs: `// slot 0`, `// slot 1, bytes 0-15`

## Constraint Checks

- [ ] "When NOT to apply" checked for each technique — no recommendations made for:
      - Frozen/deployed non-upgradeable contracts (SL-001, SL-002)
      - Upgradeable proxies for reordering (SL-001, SL-002)
      - Data that changes post-deployment for SSTORE2 (SL-007)
      - Separately accessed fields that don't co-load for packing (SL-001)

## Transient Storage (SL-005, SL-006)

- [ ] Transient storage techniques checked — only recommend if ALL of:
      - Solidity version is `^0.8.24` or higher (check `pragma solidity` in file)
      - EVM target is `cancun` or later (check `evm_version` in `foundry.toml`)
      - Target chain is confirmed to support EIP-1153 (Mainnet, Base post-Dencun, etc.)
- [ ] If conditions are not met, note the constraint explicitly and skip SL-005/SL-006

## Access Pattern Analysis (SL-003, SL-008)

- [ ] Mapping vs array decision reviewed for all key-based access patterns — is there
      a dynamic array used as a key-value store? (SL-010)
- [ ] Batch mutation opportunities identified for functions with multiple writes to the
      same variable (SL-008)
- [ ] Storage caching opportunities identified for functions with multiple reads of the
      same variable (SL-003); loop bodies checked separately

## Compile-Time Optimization (SL-009)

- [ ] All `keccak256("string literal")` calls in function bodies checked — any that are
      not already contract-level `constant` declarations are flagged (SL-009)

## Verification Commands

- [ ] `forge inspect` command included in each struct-packing finding
- [ ] `forge snapshot --diff` command included for all findings where a gas delta can
      be measured
- [ ] `forge test --gas-report` referenced where function-level gas comparison is useful

---

**All items checked? The storage-layout review is complete.**
If any item is left unchecked, document the reason (e.g., "forge not available",
"upgradeable contract — reordering skipped", "Solidity 0.8.20 — transient storage N/A").
