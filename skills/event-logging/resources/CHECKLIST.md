# Event Logging Skill — Pre-completion Checklist

Run this before marking an event logging review complete.

## EV-001: storage arrays → events for off-chain data

- [ ] All storage array `push()` calls identified in the contract
- [ ] For each array: searched the entire contract for any on-chain read access
  (`array[i]`, `array.length`, `array` passed to internal functions)
- [ ] Confirmed: array is write-only from on-chain perspective (push but never read)
- [ ] Confirmed: data only needed off-chain (historical record, audit trail, analytics)
- [ ] Replacement event defined with matching fields plus `indexed` params (EV-002)
- [ ] `array.push(value)` replaced with `emit EventName(fields...)`
- [ ] Storage array declaration removed (if no remaining readers)
- [ ] On-chain indexer infrastructure confirmed available (The Graph, Etherscan, etc.)

## EV-002: indexed parameter coverage

- [ ] All `event` declarations in the contract scanned
- [ ] For each event: identified fields used as filter keys (addresses, IDs, amounts)
- [ ] Up to 3 most important filter fields marked `indexed`
- [ ] `string`, `bytes`, and dynamic array fields NOT indexed (indexing hashes them)
- [ ] Fields rarely used as filters NOT indexed (emit cost increase not justified)
- [ ] ERC-standard events follow their defined indexed parameters (e.g., ERC-20
  `Transfer` has `from indexed`, `to indexed`, `value` non-indexed)

## Verification

- [ ] `forge test --match-test testEventFunction -vvvv` — LOG opcode (not SSTORE)
  appears in trace for replaced storage writes
- [ ] `forge test --gas-report` — function gas reduced after storage→event replacement
- [ ] `forge test` — no regressions
- [ ] Off-chain query tested (confirm events are queryable via The Graph or eth_getLogs)
