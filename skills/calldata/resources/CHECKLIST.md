# Calldata Review Checklist

Run before marking any calldata review complete.

- [ ] Every `external` function with array/bytes/string/struct params uses `calldata` unless the param is mutated
- [ ] `calldata` propagated to all internal helpers that receive the same param
- [ ] Functions with ≥3 bool params evaluated for bitmap encoding (CD-004)
- [ ] Small-type params (uint8/16/32/64) in computation-only positions changed to uint256 (CD-003)
- [ ] `public` functions with no internal callers changed to `external` first (VI-001)
- [ ] `forge test` run after changes to confirm no calldata/memory mismatch errors
