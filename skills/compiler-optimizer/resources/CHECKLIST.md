# Compiler Optimizer Skill — Pre-completion Checklist

Run this before marking a compiler optimizer review complete.

## CO-001: optimizer_runs tuning

- [ ] `foundry.toml` located and read
- [ ] `optimizer = true` confirmed (never deploy with optimizer disabled)
- [ ] Contract type identified: DeFi hot-path / factory / general / library
- [ ] `optimizer_runs` current value noted
- [ ] `optimizer_runs` compared against recommended table:
  - DeFi hot path → `1_000_000`
  - Factory / deployer → `1`
  - General purpose → `200`
  - Library → `1_000_000`
- [ ] Separate `[profile.deploy]` profile for factory contracts noted
- [ ] `forge test --gas-report` baseline captured before changes

## CO-002: via_ir

- [ ] Contract complexity assessed (complex internal calls, heavy loops, structs)
- [ ] `via_ir` current setting checked in `foundry.toml`
- [ ] For complex DeFi contracts: `via_ir = true` recommended for production profile
- [ ] Warning: compile time increase (5–50×) documented for development profile
- [ ] `forge build --sizes` baseline captured

## CO-003: Solidity version

- [ ] `pragma solidity` version checked in all key contract files
- [ ] Version pinned to exact version, not floating (`0.8.28`, not `^0.8.0`)
- [ ] Version < 0.8.22: auto-unchecked loop optimization missing (flag it)
- [ ] Version < 0.8.24: transient storage keyword missing (flag it)
- [ ] Upgrade path: `forge test` run after pragma bump to catch regressions
- [ ] Security audit implications noted for version bumps

## Verification

- [ ] `forge build` — no compilation errors after config changes
- [ ] `forge test` — full suite passes
- [ ] `forge build --sizes` — bytecode sizes recorded (before and after)
- [ ] `forge test --gas-report` — per-function gas recorded (before and after)
