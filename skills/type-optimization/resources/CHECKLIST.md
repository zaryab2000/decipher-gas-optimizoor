# Type Optimization Checklist

Run before marking any type-optimization review complete.

- [ ] Small-type (uint8/16/32/64) local vars and params in arithmetic changed to uint256 (TY-001)
- [ ] Exemption confirmed: small types in packed storage structs are NOT changed (SL-001 applies there)
- [ ] Short `string` state variables (≤31 bytes) replaced with `bytes32 constant` (TY-002)
- [ ] 3+ standalone `bool` state variables consolidated into `uint256` bitmap (TY-003)
- [ ] Unnecessary intermediate downcasts in hot-path arithmetic removed (TY-004)
- [ ] `forge inspect <Contract> storageLayout --json` confirms expected slot reduction
- [ ] `forge test` passes — no type mismatch regressions
