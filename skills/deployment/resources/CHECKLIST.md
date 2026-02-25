# Deployment Review Checklist

Run before marking any deployment review complete.

- [ ] Factory `new ContractName()` patterns evaluated for ERC-1167 minimal proxy (DP-001)
- [ ] Clone factory uses `initialize()` with `_initialized` guard (not constructor)
- [ ] `_disableInitializers()` called in implementation constructor
- [ ] Frequently-called admin functions evaluated for `payable` optimization (DP-002)
- [ ] `payable` only added if ETH recovery mechanism exists or admin is trusted
- [ ] Dead code (constant-false branches, no-caller internals) removed (DP-003)
- [ ] `forge build --sizes` run before and after to confirm bytecode reduction
