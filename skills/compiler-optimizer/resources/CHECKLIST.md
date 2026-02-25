# Compiler Optimizer Checklist

Run before marking any compiler-optimizer review complete.

- [ ] `foundry.toml` has `optimizer = true` in all profiles
- [ ] `optimizer_runs` matches contract call frequency (1M for DeFi, 1 for factories, 200 for general)
- [ ] Production profile has `via_ir = true` for complex contracts
- [ ] Dev profile keeps `via_ir = false` for fast iteration
- [ ] `pragma solidity` is exact version pin, not a floating range (`^`)
- [ ] Solidity version is ≥0.8.22 for auto-unchecked loops
- [ ] Solidity version is ≥0.8.24 if transient storage (SL-005) is used
- [ ] `forge test` passes after any version bump
- [ ] `forge build --sizes` and `forge test --gas-report` run to measure actual impact
