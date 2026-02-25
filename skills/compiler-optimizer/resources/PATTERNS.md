# Compiler Optimizer Patterns — Quick Reference

## CO-001: optimizer_runs by contract type

| Contract type | `optimizer_runs` | Rationale |
|---|---|---|
| AMM router / lending pool (high-frequency DeFi) | `1_000_000` | Runtime savings outweigh larger bytecode |
| Factory / deployer (called once per deploy) | `1` | Minimize deployment cost; runtime cost negligible |
| General purpose / default | `200` | Foundry default — balanced |
| Library deployed once, called by many | `1_000_000` | Amortized deployment cost is negligible |

**Break-even formula:**
`extra_deployment_bytes × 200 = per_call_savings × total_calls`
For 1M calls/year, even 1 gas/call saving justifies 5,000 extra bytes.

```toml
# Production DeFi profile
[profile.default]
optimizer = true
optimizer_runs = 1_000_000

# One-shot factory deploy profile
[profile.deploy]
optimizer = true
optimizer_runs = 1

# Dev — fast iteration
[profile.dev]
optimizer = true
optimizer_runs = 200
```

## CO-002: via_ir for complex contracts

```toml
# Production profile only — via_ir is 5–50× slower to compile
[profile.default]
optimizer = true
via_ir = true

# Dev profile — keep fast
[profile.dev]
optimizer = true
via_ir = false
```

Enables Yul-level cross-function optimization. Typical savings: 5–20% bytecode/gas
for contracts with tight loops, complex internal calls, or many structs.

## CO-003: Solidity version milestones

| Version | Key gain |
|---|---|
| `0.8.22+` | Auto-unchecked simple loop counters (~30 gas/iter, no manual `unchecked` needed) |
| `0.8.24+` | Native `tstore`/`tload` syntax for transient storage (SL-005, SL-006) |
| `0.8.28` | Latest stable — all incremental optimizer improvements |

Always use exact version pins: `pragma solidity 0.8.28;` not `^0.8.0`.
After bumping version, run `forge test` to catch any breaking changes.
