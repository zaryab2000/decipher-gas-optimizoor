# Storage Layout Review Checklist

Run before marking any storage-layout review complete.

- [ ] Every struct has fields ordered large → small (SL-001)
- [ ] Each struct's slot count verified with `forge inspect <Contract> storageLayout --json`
- [ ] Any `address` field checked for `uint96` pairing opportunity (SL-002)
- [ ] Functions reading the same storage var >1 time have a local cache (SL-003)
- [ ] Reentrancy guard uses TSTORE if Solidity ≥0.8.24 + EVM cancun (SL-005)
- [ ] No `keccak256("literal")` in function bodies — precomputed as `constant` (SL-009)
- [ ] Arrays used for key-based lookup flagged and replaced with mappings (SL-010)
- [ ] Upgradeable contracts: no existing fields reordered — new fields appended only
- [ ] `forge snapshot --diff` run after layout changes to confirm gas reduction
