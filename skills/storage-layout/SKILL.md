---
name: storage-layout
description: >
  Detects storage slot inefficiencies in Solidity contracts: struct packing gaps,
  suboptimal field ordering, mapping-vs-array tradeoffs, SSTORE2 for large static
  data, transient storage for within-transaction state, and batch mutation patterns.
  Use when writing or reviewing struct definitions, state variable declarations, or
  storage-heavy contract logic in Foundry-based Solidity projects. Covers SL-001
  through SL-010: slot packing, address+uint96 pairing, storage caching, delete
  refunds, transient reentrancy guards, flash-loan flags, SSTORE2, batch writes,
  keccak constant precomputation, and mapping-vs-array decisions.
allowed-tools: Read Bash
---

## Purpose

Identify storage slot inefficiencies in Solidity contracts and recommend layout changes
that reduce SSTORE and SLOAD costs. Storage operations are the most expensive EVM
instructions: a cold SSTORE costs 22,100 gas and a cold SLOAD costs 2,100 gas. Every
eliminated slot and every avoided redundant storage access compounds across all callers
for the life of the contract.

This skill covers 10 techniques (SL-001 through SL-010) derived from the gas
optimization knowledge base. It does not invent new rules.

---

## When to Use This Skill

- Writing or reviewing a `struct` definition with mixed-size fields
- Reviewing state variable declarations at the contract level
- Auditing functions that read or write the same storage variable multiple times
- Reviewing reentrancy guards (check for SSTORE-based lock patterns)
- Reviewing flash-loan or callback patterns that use persistent storage flags
- Reviewing constructors that push static data into storage arrays
- Reviewing contracts that use arrays for key-based lookup instead of mappings

---

## When NOT to Use This Skill

- **Upgradeable contracts (proxy pattern):** Never reorder existing state variables.
  Storage layout is immutable across upgrades. Only append at the end, using gaps.
- **Frozen/deployed contracts:** If the contract is already deployed and not upgradeable,
  storage layout cannot be changed. Report findings as informational only.
- **Separately accessed fields:** If struct fields are always read in separate transactions,
  packing into shared slots adds masking overhead without reducing SLOAD count.
- **Chains without Cancun support:** Do not recommend transient storage (SL-005, SL-006)
  on chains that do not yet support EIP-1153 (e.g., some L2s before their Cancun upgrade).
- **Mutable large data:** Do not recommend SSTORE2 (SL-007) for data that changes
  after deployment — bytecode is immutable.

---

## Rationalizations to Reject

| Rationalization | Why It's Wrong | Required Action |
|---|---|---|
| "The struct looks fine as-is" | Unpacked slots cost 22,100 gas per write, silently | Run the packing check regardless of visual appearance |
| "It's only one extra slot" | At 10,000 tx/day, 1 extra slot = 221M gas/day wasted | Eliminate every eliminable slot |
| "I'll optimize later" | Storage layout cannot be changed after deployment without a migration | Fix during development, not after |
| "The compiler handles this" | Solidity packs within consecutive declarations only; cross-declaration gaps are not packed | Always verify with forge inspect |

---

## Platform Detection

Before applying any recommendation, verify the environment:

```bash
# Solidity files present?
ls src/**/*.sol 2>/dev/null || echo "No .sol files found"

# Foundry project?
test -f foundry.toml && echo "Foundry detected" || echo "No foundry.toml"

# Hardhat project?
test -f hardhat.config.ts || test -f hardhat.config.js && echo "Hardhat detected"

# Solidity version (check pragma for transient storage eligibility)
grep -r "pragma solidity" src/ | head -5

# EVM target (for transient storage: requires cancun or later)
grep "evm_version" foundry.toml 2>/dev/null

# Inspect slot layout (requires forge)
forge inspect <ContractName> storageLayout --json 2>/dev/null
```

Transient storage (SL-005, SL-006) requires: Solidity `^0.8.24` and EVM target `cancun`.
If either condition is unmet, skip those techniques and note the constraint.

---

## Quick Reference

### Variable size table

| Type | Bytes | Packs With |
|---|---|---|
| `bool` | 1 | `uint8`, other bools, bytes1 |
| `uint8` / `int8` | 1 | Other small types |
| `uint16` / `int16` | 2 | Other small types |
| `uint32` / `int32` | 4 | Other small types |
| `uint64` / `int64` | 8 | Other small types |
| `uint96` / `int96` | 12 | `address` (perfect 32-byte fill) |
| `uint128` / `int128` | 16 | Another `uint128` |
| `address` | 20 | `uint96` or smaller |
| `uint256` / `int256` | 32 | Nothing — takes a full slot alone |
| `bytes32` | 32 | Nothing — takes a full slot alone |

### Decision tree

```
Is the data written once and read many times (>2 reads)?
  YES → Is it large (>64 bytes)?
          YES → SL-007: SSTORE2
          NO  → SL-009: constant if literal hash
  NO  → Is the state only needed within one transaction?
          YES → SL-005 or SL-006: transient storage
          NO  → Does a function read/write the same slot N>1 times?
                  YES → SL-003 (cache) + SL-008 (batch write)
                  NO  → Are struct fields sorted large→small?
                          NO  → SL-001: repack struct
                          YES → Does address + field fill exactly 32 bytes?
                                  NO  → Check for uint96 pairing: SL-002
```

---

## Workflow

**Step 1 — Identify variables**
- [ ] List all `struct` definitions and state variable declarations in scope
- [ ] Note each field's type and byte size using the table in §6
- [ ] Flag any struct where fields are not ordered large-first

**Step 2 — Calculate current slot usage**
- [ ] Count the number of storage slots each struct occupies
- [ ] Run `forge inspect <Contract> storageLayout --json` if forge is available
- [ ] Identify wasted bytes within each slot (slot bytes used vs. 32)

**Step 3 — Compute optimal layout**
- [ ] Reorder fields: `uint256`/`bytes32` first, then descending size, small types last
- [ ] Check for `address` + `uint96` perfect-pair opportunities (SL-002)
- [ ] Identify functions with multiple reads of the same variable (SL-003)
- [ ] Identify functions with multiple writes to the same variable (SL-008)
- [ ] Check reentrancy guards: are they using a storage slot? (SL-005)
- [ ] Check for within-transaction flags: could they use transient storage? (SL-006)
- [ ] Check for `keccak256("literal")` calls in function bodies (SL-009)
- [ ] Check for arrays used as key-based stores instead of mappings (SL-010)

**Step 4 — Apply and annotate**
- [ ] Apply struct reordering; add inline slot comments (`// slot 0`, `// slot 1, bytes 0-15`)
- [ ] Add `// SL-001: packed` or equivalent comment to each modified struct
- [ ] Verify with `forge inspect` after changes — confirm expected slot count
- [ ] Run `forge snapshot --diff` to measure the gas delta

---

## Output Format

Report each finding using this structure:

```
**[SEVERITY] Description — N wasted slots / savings summary**
**File:** path/to/Contract.sol, line N
**Technique:** SL-00X
**Estimated saving:** ~X gas per [write/read/call]
[before code block]
[after code block]
**Verification:** forge inspect / forge snapshot --diff
```

### Concrete example finding

**[HIGH] Unpacked storage struct — 2 wasted slots**
**File:** src/Vault.sol, line 14
**Technique:** SL-001
**Estimated saving:** ~44,200 gas per write (2 eliminated cold SSTOREs)

Before:
```solidity
struct Position {
    uint128 amount;    // slot 0 (wastes 16 bytes)
    uint256 principal; // slot 1 (forces new slot)
    uint128 reward;    // slot 2 (wastes 16 bytes)
    address owner;     // slot 3 (wastes 12 bytes)
    bool active;       // slot 4 (wastes 31 bytes)
}
// 5 slots — 5 SSTOREs on first write
```

After:
```solidity
struct Position {
    uint256 principal; // slot 0
    uint128 amount;    // slot 1, bytes 0-15
    uint128 reward;    // slot 1, bytes 16-31
    address owner;     // slot 2, bytes 0-19
    bool active;       // slot 2, byte 20
}
// 3 slots — 3 SSTOREs on first write (saves 44,200 gas cold)
```

**Verification:** `forge inspect Vault storageLayout --json` then `forge snapshot --diff`

---

## Anti-Hallucination / Stability Rules

- All gas figures in this skill are derived from `docs/evm-gas-reference.md` and
  `resources/PATTERNS.md`. Do not invent new numbers or cite figures not present in
  those files.
- Do not recommend transient storage on chains or compiler versions that do not support
  EIP-1153. Always check §5 Platform Detection first.
- Do not recommend SSTORE2 for mutable data. Bytecode is immutable.
- Do not reorder struct fields in upgradeable proxy contracts — state this constraint
  explicitly if the contract uses `UUPSUpgradeable`, `Initializable`, or storage gaps.
- If `forge` is not available, skip `forge inspect` steps and note the limitation.
- Report only findings that are present in the code under review. Do not add speculative
  "consider also..." findings outside the scope of the 10 techniques.

---

## Supporting Docs

Only read these files when explicitly needed — do not load all three by default:

| File | Read only when… |
|---|---|
| `resources/PATTERNS.md` | You encounter an SL pattern (SL-004 through SL-010) not covered by the Quick Reference above, or need to verify an edge case |
| `resources/CHECKLIST.md` | Producing a formal `/gas:analyze` report and need to confirm completeness |
| `resources/EXAMPLE_FINDING.md` | Generating a report and need the exact output format for a multi-finding DeFi vault example |
| `docs/evm-gas-reference.md` | You need authoritative opcode costs (SSTORE, SLOAD, TSTORE) or slot packing rules to back a gas estimate |
